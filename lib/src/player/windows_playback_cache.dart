import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/models/track.dart';

abstract interface class PlaybackCache {
  Future<PlaybackCacheEntry> resolve(Track track, String sourcePath);
}

final class PlaybackCacheEntry {
  const PlaybackCacheEntry({
    required this.filePath,
    required this.reusedExistingFile,
  });

  final String filePath;
  final bool reusedExistingFile;
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

final class WindowsPlaybackCache implements PlaybackCache {
  WindowsPlaybackCache({
    AppSupportDirectoryProvider? appSupportDirectoryProvider,
  }) : _appSupportDirectoryProvider =
            appSupportDirectoryProvider ?? getApplicationSupportDirectory;

  final AppSupportDirectoryProvider _appSupportDirectoryProvider;

  @override
  Future<PlaybackCacheEntry> resolve(Track track, String sourcePath) async {
    final source = File(sourcePath);
    final exists = await source.exists();
    if (!exists) {
      throw PlaybackCacheException(
        'Исходный аудиофайл не существует: $sourcePath',
      );
    }

    final sourceStat = await source.stat();
    final sourceSize = sourceStat.size;
    final cacheDirectory = await _cacheDirectory();
    final cachedFile = File(
      p.join(
        cacheDirectory.path,
        _cacheFileName(
          track: track,
          sourcePath: sourcePath,
          modifiedAt: sourceStat.modified,
          fileSizeBytes: sourceSize,
        ),
      ),
    );

    if (await _isValidCachedFile(cachedFile, sourceSize)) {
      return PlaybackCacheEntry(
        filePath: cachedFile.path,
        reusedExistingFile: true,
      );
    }

    try {
      await source.copy(cachedFile.path);
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

    return PlaybackCacheEntry(
      filePath: cachedFile.path,
      reusedExistingFile: false,
    );
  }

  Future<Directory> _cacheDirectory() async {
    final appSupportDirectory = await _appSupportDirectoryProvider();
    final cacheDirectory = Directory(
      p.join(
        appSupportDirectory.path,
        'CleverMusicPlayer',
        'playback_cache',
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

  String _cacheFileName({
    required Track track,
    required String sourcePath,
    required DateTime modifiedAt,
    required int fileSizeBytes,
  }) {
    final identity = track.id?.toString() ??
        track.stableId ??
        sha256.convert(utf8.encode(sourcePath)).toString();
    final extension = _asciiExtension(sourcePath);
    final key = [
      identity,
      modifiedAt.toUtc().millisecondsSinceEpoch,
      fileSizeBytes,
      extension,
    ].join('|');
    final digest = sha256.convert(utf8.encode(key)).toString();
    return 'track_${digest.substring(0, 32)}$extension';
  }

  String _asciiExtension(String filePath) {
    final basename = filePath.split(RegExp(r'[\\/]')).last;
    final dotIndex = basename.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == basename.length - 1) {
      return '';
    }

    final extension = basename.substring(dotIndex).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)) {
      return '';
    }
    return extension;
  }
}
