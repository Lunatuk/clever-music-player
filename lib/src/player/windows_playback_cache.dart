import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/models/track.dart';

const int windowsPlaybackCacheMaxBytes = 250 * 1024 * 1024;

abstract interface class PlaybackCache {
  Future<PlaybackCacheEntry> resolve(Track track, String sourcePath);
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

final class WindowsPlaybackCache implements PlaybackCache {
  WindowsPlaybackCache({
    AppSupportDirectoryProvider? appSupportDirectoryProvider,
    int maxBytes = windowsPlaybackCacheMaxBytes,
    PlaybackCacheClock? clock,
  })  : assert(maxBytes > 0),
        _appSupportDirectoryProvider =
            appSupportDirectoryProvider ?? getApplicationSupportDirectory,
        _maxBytes = maxBytes,
        _clock = clock ?? DateTime.now;

  final AppSupportDirectoryProvider _appSupportDirectoryProvider;
  final int _maxBytes;
  final PlaybackCacheClock _clock;

  @override
  Future<PlaybackCacheEntry> resolve(Track _, String sourcePath) async {
    final source = File(sourcePath);
    final exists = await source.exists();
    if (!exists) {
      throw PlaybackCacheException(
        'Исходный аудиофайл не существует: $sourcePath',
      );
    }

    final sourceStat = await source.stat();
    final sourceSize = sourceStat.size;
    if (sourceSize > _maxBytes) {
      throw PlaybackCacheException(
        'Аудиофайл больше лимита кэша воспроизведения Windows: '
        '$sourceSize > $_maxBytes bytes.',
      );
    }

    final cacheDirectory = await _cacheDirectory();
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
    final cacheSizeBeforeCleanup = await _cacheDirectorySize(cacheDirectory);
    final deletedPaths = <String>[];

    if (await _isValidCachedFile(cachedFile, sourceSize)) {
      await _markRecentlyUsed(cachedFile);
      final cleanup = await _cleanupToLimit(
        cacheDirectory: cacheDirectory,
        protectedFile: cachedFile,
        maxBytes: _maxBytes,
      );
      deletedPaths.addAll(cleanup.deletedPaths);
      if (cleanup.sizeAfterBytes > _maxBytes) {
        throw PlaybackCacheException(
          'Кэш воспроизведения Windows превышает лимит после очистки: '
          '${cleanup.sizeAfterBytes} > $_maxBytes bytes.',
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
      maxBytes: _maxBytes - sourceSize,
    );
    deletedPaths.addAll(preCopyCleanup.deletedPaths);
    if (preCopyCleanup.sizeAfterBytes > _maxBytes - sourceSize) {
      throw PlaybackCacheException(
        'Не удалось освободить место в кэше воспроизведения Windows: '
        '${preCopyCleanup.sizeAfterBytes} > ${_maxBytes - sourceSize} bytes.',
      );
    }

    try {
      await source.copy(cachedFile.path);
      await _markRecentlyUsed(cachedFile);
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
      maxBytes: _maxBytes,
    );
    deletedPaths.addAll(postCopyCleanup.deletedPaths);
    if (postCopyCleanup.sizeAfterBytes > _maxBytes) {
      throw PlaybackCacheException(
        'Кэш воспроизведения Windows превышает лимит после очистки: '
        '${postCopyCleanup.sizeAfterBytes} > $_maxBytes bytes.',
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
        if (_normalizedEntityPath(entity) != protectedPath) {
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
