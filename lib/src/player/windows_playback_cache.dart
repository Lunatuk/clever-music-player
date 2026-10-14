import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../diagnostics/diagnostics_service.dart';
import '../domain/models/track.dart';
import '../domain/models/audio_source_reference.dart';

const int windowsPlaybackCacheMaxBytes = 250 * 1024 * 1024;

abstract interface class PlaybackCache {
  Future<PlaybackCacheEntry> resolve(Track track, String sourcePath);
}

/// A decoder holds a reference until its source is stopped/disposed.
abstract interface class ProtectedPlaybackCache implements PlaybackCache {
  Future<PlaybackCacheEntry> acquire(Track track, String sourcePath);
  void release(String cachedPath);
}

final class PlaybackCacheEntry {
  const PlaybackCacheEntry({
    required this.filePath,
    required this.reusedExistingFile,
    required this.cacheSizeBeforeCleanupBytes,
    required this.cacheSizeAfterCleanupBytes,
    required this.cleanupDeletedFileCount,
    required this.cleanupDeletedPaths,
    required this.sourceSizeBytes,
  });

  final String filePath;
  final bool reusedExistingFile;
  final int cacheSizeBeforeCleanupBytes;
  final int cacheSizeAfterCleanupBytes;
  final int cleanupDeletedFileCount;
  final List<String> cleanupDeletedPaths;
  final int sourceSizeBytes;
}

final class PlaybackCacheException implements Exception {
  const PlaybackCacheException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    if (cause == null) {
      return message;
    }
    return '$message ($cause)';
  }
}

typedef AppSupportDirectoryProvider = Future<Directory> Function();
typedef PlaybackCacheClock = DateTime Function();
typedef PlaybackCacheCopy = Future<void> Function(File source, File staging);

final class WindowsPlaybackCache implements ProtectedPlaybackCache {
  WindowsPlaybackCache({
    AppSupportDirectoryProvider? appSupportDirectoryProvider,
    int maxBytes = windowsPlaybackCacheMaxBytes,
    this.diagnostics = const NoopDiagnosticsService(),
    PlaybackCacheClock? clock,
    @visibleForTesting PlaybackCacheCopy? copyFile,
  })  : assert(maxBytes > 0),
        _appSupportDirectoryProvider =
            appSupportDirectoryProvider ?? getApplicationSupportDirectory,
        _maxBytes = maxBytes,
        _clock = clock ?? DateTime.now,
        _copyFile = copyFile ?? _copySource;

  final DiagnosticsService diagnostics;
  final AppSupportDirectoryProvider _appSupportDirectoryProvider;
  final int _maxBytes;
  final PlaybackCacheClock _clock;
  final PlaybackCacheCopy _copyFile;
  static final Set<String> _activeStagingDirectories = {};

  static Future<void> _copySource(File source, File staging) async {
    await source.copy(staging.path);
  }

  final Map<String, int> _inUse = {};
  Future<void> _operations = Future<void>.value();

  @override
  Future<PlaybackCacheEntry> resolve(Track track, String sourcePath) =>
      _serialize(() => _resolve(sourcePath, forPlayback: false));

  @override
  Future<PlaybackCacheEntry> acquire(Track track, String sourcePath) =>
      _serialize(() async {
        final entry = await _resolve(sourcePath, forPlayback: true);
        final key = _normalizedEntityPath(File(entry.filePath));
        _inUse.update(key, (count) => count + 1, ifAbsent: () => 1);
        return entry;
      });

  @override
  void release(String cachedPath) {
    final key = _normalizedEntityPath(File(cachedPath));
    final count = _inUse[key] ?? 0;
    if (count <= 1) {
      _inUse.remove(key);
    } else {
      _inUse[key] = count - 1;
    }
    if (count > 0) {
      final cleanup = _operations.then((_) async {
        final directory = await _cacheDirectory();
        await _cleanupToLimit(
            cacheDirectory: directory,
            protectedFile: File(p.join(directory.path, '.unused')),
            maxBytes: _maxBytes);
      });
      _operations =
          cleanup.then<void>((_) {}, onError: (Object error, StackTrace _) {
        diagnostics.record(DiagnosticEvent.cacheFailed, error: error);
        _log('deferred cleanup failed: $error');
      });
    }
  }

  @visibleForTesting
  Future<void> waitForPendingOperations() => _operations;

  Future<PlaybackCacheEntry> _serialize(
      Future<PlaybackCacheEntry> Function() operation) {
    final result = _operations.then((_) async {
      final timer = Stopwatch()..start();
      try {
        final entry = await operation();
        diagnostics.record(DiagnosticEvent.cacheResolved, fields: {
          DiagnosticField.elapsedMs: timer.elapsedMilliseconds,
          DiagnosticField.reused: entry.reusedExistingFile,
          DiagnosticField.sourceBytes: entry.sourceSizeBytes,
          DiagnosticField.cacheBytes: entry.cacheSizeAfterCleanupBytes,
          DiagnosticField.deletedFiles: entry.cleanupDeletedFileCount,
        });
        return entry;
      } on Object catch (error) {
        diagnostics.record(DiagnosticEvent.cacheFailed,
            error:
                error is PlaybackCacheException ? error.cause ?? error : error);
        rethrow;
      }
    });
    _operations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<PlaybackCacheEntry> _resolve(String sourcePath,
      {required bool forPlayback}) async {
    // This adapter owns filesystem copies only, never provider URIs.
    FileAudioSource(sourcePath);
    final source = File(sourcePath);
    final exists = await source.exists();
    if (!exists) {
      throw PlaybackCacheException(
        'Исходный аудиофайл не существует: $sourcePath',
      );
    }

    final sourceStat = await source.stat();
    final sourceSize = sourceStat.size;
    if (sourceStat.type != FileSystemEntityType.file || sourceSize <= 0) {
      throw const PlaybackCacheException(
          'Аудиофайл пуст или не является обычным файлом.');
    }
    if (sourceSize > _maxBytes && !forPlayback) {
      throw PlaybackCacheException(
        'Аудиофайл больше лимита кэша воспроизведения Windows: '
        '$sourceSize > $_maxBytes bytes.',
      );
    }

    final cacheDirectory = await _cacheDirectory();
    await _cleanupOrphanStaging(cacheDirectory);
    final extension = _sourceExtension(sourcePath);
    final cachedFile = File(
      p.join(
        cacheDirectory.path,
        _cacheFileName(
          sourcePath: sourcePath,
          modifiedAt: sourceStat.modified,
          fileSizeBytes: sourceSize,
          extension: extension,
        ),
      ),
    );
    // The retention budget is soft only for decoder-held sources. It must not
    // forbid a long recording or evict the other deck during preloading.
    var pinnedBytes = 0;
    for (final path in _inUse.keys.toList()) {
      try {
        pinnedBytes += await File(path).length();
      } on FileSystemException {
        continue;
      }
    }
    final requiredBytes = pinnedBytes +
        (_inUse.containsKey(_normalizedEntityPath(cachedFile))
            ? 0
            : sourceSize);
    final limit =
        forPlayback && requiredBytes > _maxBytes ? requiredBytes : _maxBytes;
    final cacheSizeBeforeCleanup = await _cacheDirectorySize(cacheDirectory);
    final deletedPaths = <String>[];

    if (await _isValidCachedFile(cachedFile, sourceSize)) {
      await _markRecentlyUsed(cachedFile);
      final cleanup = await _cleanupToLimit(
        cacheDirectory: cacheDirectory,
        protectedFile: cachedFile,
        maxBytes: limit,
      );
      deletedPaths.addAll(cleanup.deletedPaths);
      if (cleanup.sizeAfterBytes > limit) {
        throw PlaybackCacheException(
          'Кэш воспроизведения Windows превышает лимит после очистки: '
          '${cleanup.sizeAfterBytes} > $limit bytes.',
        );
      }
      return PlaybackCacheEntry(
        filePath: cachedFile.path,
        reusedExistingFile: true,
        cacheSizeBeforeCleanupBytes: cacheSizeBeforeCleanup,
        cacheSizeAfterCleanupBytes: cleanup.sizeAfterBytes,
        cleanupDeletedFileCount: deletedPaths.length,
        cleanupDeletedPaths: List.unmodifiable(deletedPaths),
        sourceSizeBytes: sourceSize,
      );
    }

    await _deleteInvalidTarget(cachedFile, deletedPaths);
    final preCopyCleanup = await _cleanupToLimit(
      cacheDirectory: cacheDirectory,
      protectedFile: cachedFile,
      maxBytes: limit - sourceSize,
    );
    deletedPaths.addAll(preCopyCleanup.deletedPaths);
    if (preCopyCleanup.sizeAfterBytes > limit - sourceSize) {
      throw PlaybackCacheException(
        'Не удалось освободить место в кэше воспроизведения Windows: '
        '${preCopyCleanup.sizeAfterBytes} > ${limit - sourceSize} bytes.',
      );
    }

    try {
      await _publishCopy(source, sourceStat, cachedFile, cacheDirectory);
    } on Object catch (error) {
      throw PlaybackCacheException(
        'Не удалось скопировать аудиофайл в кэш воспроизведения Windows.',
        error,
      );
    }

    if (!await _isValidCachedFile(cachedFile, sourceSize)) {
      throw PlaybackCacheException(
        'Кэшированный аудиофайл отсутствует или имеет неожиданный размер: '
        '${cachedFile.path}',
      );
    }

    final postCopyCleanup = await _cleanupToLimit(
      cacheDirectory: cacheDirectory,
      protectedFile: cachedFile,
      maxBytes: limit,
    );
    deletedPaths.addAll(postCopyCleanup.deletedPaths);
    if (postCopyCleanup.sizeAfterBytes > limit) {
      throw PlaybackCacheException(
        'Кэш воспроизведения Windows превышает лимит после очистки: '
        '${postCopyCleanup.sizeAfterBytes} > $limit bytes.',
      );
    }

    return PlaybackCacheEntry(
      filePath: cachedFile.path,
      reusedExistingFile: false,
      cacheSizeBeforeCleanupBytes: cacheSizeBeforeCleanup,
      cacheSizeAfterCleanupBytes: postCopyCleanup.sizeAfterBytes,
      cleanupDeletedFileCount: deletedPaths.length,
      cleanupDeletedPaths: List.unmodifiable(deletedPaths),
      sourceSizeBytes: sourceSize,
    );
  }

  Future<void> _publishCopy(
      File source, FileStat original, File target, Directory directory) async {
    final staging = await directory.createTemp('.pending-');
    _activeStagingDirectories.add(staging.path);
    RandomAccessFile? lock;
    try {
      lock = await File(p.join(staging.path, 'owner.lock'))
          .open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      final temporary = File(p.join(staging.path, 'audio.tmp'));
      await _copyFile(source, temporary);
      final after = await source.stat();
      if (after.type != FileSystemEntityType.file ||
          after.size != original.size ||
          after.modified != original.modified ||
          !await _isValidCachedFile(temporary, original.size)) {
        throw const PlaybackCacheException(
            'Исходный файл изменился или копирование завершилось не полностью.');
      }
      final handle = await temporary.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      await _markRecentlyUsed(temporary);
      // Same-volume rename publishes only a complete, validated copy.
      await temporary.rename(target.path);
    } finally {
      await lock?.close();
      _activeStagingDirectories.remove(staging.path);
      try {
        await staging.delete(recursive: true);
      } on FileSystemException catch (error) {
        _log('staging cleanup failed: $error');
      }
    }
  }

  Future<void> _cleanupOrphanStaging(Directory directory) async {
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! Directory ||
          !p.basename(entity.path).startsWith('.pending-') ||
          _activeStagingDirectories.contains(entity.path)) {
        continue;
      }
      RandomAccessFile? lock;
      try {
        final stat = await entity.stat();
        if (_clock().difference(stat.modified) < const Duration(minutes: 1)) {
          continue;
        }
        final marker = File(p.join(entity.path, 'owner.lock'));
        if (!await marker.exists()) continue;
        lock = await marker.open(mode: FileMode.append);
        await lock.lock(FileLock
            .exclusive); // A live copy in another process is left alone.
        final contents = await entity.list(followLinks: false).toList();
        if (contents.any((file) =>
            !{'owner.lock', 'audio.tmp'}.contains(p.basename(file.path)))) {
          continue;
        }
        final audio = File(p.join(entity.path, 'audio.tmp'));
        if (await audio.exists()) await audio.delete();
        await lock.close();
        lock = null;
        await marker.delete();
        await entity.delete();
      } on FileSystemException {
        // Locked, removed concurrently, or inaccessible: retry on a later load.
        continue;
      } finally {
        await lock?.close();
      }
    }
  }

  Future<Directory> _cacheDirectory() async {
    final appSupportDirectory = await _appSupportDirectoryProvider();
    final cacheDirectory = Directory(
      p.join(
        appSupportDirectory.path,
        'CleverMusicPlayer',
        'pc',
      ),
    );
    return cacheDirectory.create(recursive: true);
  }

  Future<bool> _isValidCachedFile(File cachedFile, int expectedSize) async {
    try {
      final stat = await cachedFile.stat();
      return stat.type == FileSystemEntityType.file &&
          stat.size == expectedSize;
    } on Object {
      return false;
    }
  }

  Future<void> _deleteInvalidTarget(
    File cachedFile,
    List<String> deletedPaths,
  ) async {
    if (_inUse.containsKey(_normalizedEntityPath(cachedFile))) {
      throw const PlaybackCacheException(
          'Повреждённая копия ещё используется другим декодером.');
    }
    try {
      final stat = await cachedFile.stat();
      if (stat.type != FileSystemEntityType.file) {
        return;
      }
      await cachedFile.delete();
      deletedPaths.add(cachedFile.path);
      _log('deleted invalid cached file: ${cachedFile.path}');
    } on FileSystemException {
      return;
    }
  }

  Future<int> _cacheDirectorySize(Directory cacheDirectory) async {
    var total = 0;
    await for (final entity in cacheDirectory.list()) {
      if (entity is! File) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.type == FileSystemEntityType.file) {
          total += stat.size;
        }
      } on Object {
        continue;
      }
    }
    return total;
  }

  Future<_CacheCleanupResult> _cleanupToLimit({
    required Directory cacheDirectory,
    required File protectedFile,
    required int maxBytes,
  }) async {
    final protectedPath = _normalizedEntityPath(protectedFile);
    final files = <_CacheFile>[];
    var totalSize = 0;

    await for (final entity in cacheDirectory.list()) {
      if (entity is! File) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.type != FileSystemEntityType.file) {
          continue;
        }
        totalSize += stat.size;
        if (_normalizedEntityPath(entity) != protectedPath &&
            !_inUse.containsKey(_normalizedEntityPath(entity))) {
          files.add(
            _CacheFile(
              file: entity,
              size: stat.size,
              lastUsedAt: stat.modified,
            ),
          );
        }
      } on Object {
        continue;
      }
    }

    final sizeBefore = totalSize;
    final deletedPaths = <String>[];
    if (totalSize <= maxBytes) {
      _log(
        'cleanup skipped: before=$sizeBefore, after=$totalSize, '
        'limit=$maxBytes',
      );
      return _CacheCleanupResult(
        sizeAfterBytes: totalSize,
        deletedPaths: const [],
      );
    }

    files.sort((left, right) => left.lastUsedAt.compareTo(right.lastUsedAt));
    for (final cached in files) {
      if (totalSize <= maxBytes) {
        break;
      }
      try {
        await cached.file.delete();
        totalSize -= cached.size;
        deletedPaths.add(cached.file.path);
        _log(
          'cleanup deleted: path=${cached.file.path}, size=${cached.size}, '
          'remaining=$totalSize, limit=$maxBytes',
        );
      } on Object catch (error) {
        _log('cleanup failed to delete ${cached.file.path}: $error');
      }
    }

    if (totalSize > maxBytes) {
      _log(
        'cleanup could not reach limit without deleting protected file: '
        'before=$sizeBefore, after=$totalSize, limit=$maxBytes, '
        'protected=${protectedFile.path}',
      );
    } else {
      _log(
        'cleanup complete: before=$sizeBefore, after=$totalSize, '
        'limit=$maxBytes, deleted=${deletedPaths.length}',
      );
    }

    return _CacheCleanupResult(
      sizeAfterBytes: totalSize,
      deletedPaths: List.unmodifiable(deletedPaths),
    );
  }

  Future<void> _markRecentlyUsed(File cachedFile) async {
    try {
      await cachedFile.setLastModified(_clock());
    } on Object catch (error) {
      _log(
          'failed to update cached file timestamp: ${cachedFile.path}: $error');
    }
  }

  String _cacheFileName({
    required String sourcePath,
    required DateTime modifiedAt,
    required int fileSizeBytes,
    required String extension,
  }) {
    final asciiExtension = _asciiExtension(extension);
    final key = [
      sourcePath,
      fileSizeBytes,
      modifiedAt.toUtc().toIso8601String(),
      extension,
    ].join('|');
    final digest = sha256.convert(utf8.encode(key)).toString();
    return 'p_${digest.substring(0, 32)}$asciiExtension';
  }

  String _sourceExtension(String filePath) {
    final basename = filePath.split(RegExp(r'[\\/]')).last;
    return p.extension(basename).toLowerCase();
  }

  String _asciiExtension(String extension) {
    if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)) {
      return '';
    }
    return extension;
  }

  String _normalizedEntityPath(FileSystemEntity entity) {
    return p.normalize(entity.absolute.path).toLowerCase();
  }

  void _log(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('WindowsPlaybackCache: $message');
  }
}

final class _CacheFile {
  const _CacheFile({
    required this.file,
    required this.size,
    required this.lastUsedAt,
  });

  final File file;
  final int size;
  final DateTime lastUsedAt;
}

final class _CacheCleanupResult {
  const _CacheCleanupResult({
    required this.sizeAfterBytes,
    required this.deletedPaths,
  });

  final int sizeAfterBytes;
  final List<String> deletedPaths;
}
