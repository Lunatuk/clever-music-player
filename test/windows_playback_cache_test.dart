import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/player/windows_playback_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
      'active and prepared decoder leases survive cache pressure and release independently',
      () async {
    final temp = await Directory.systemTemp.createTemp('cmp_leases_');
    addTearDown(() => temp.delete(recursive: true));
    final source = File(p.join(temp.path, 'first.mp3'));
    final other = File(p.join(temp.path, 'second.mp3'));
    await source.writeAsBytes(List.filled(10, 1));
    await other.writeAsBytes(List.filled(10, 2));
    final cache = WindowsPlaybackCache(
        maxBytes: 15,
        appSupportDirectoryProvider: () async =>
            Directory(p.join(temp.path, 'support')));
    final first =
        await cache.acquire(_track(filePath: source.path), source.path);
    final repeated =
        await cache.acquire(_track(filePath: source.path), source.path);
    expect(repeated.filePath, first.filePath);
    await expectLater(cache.resolve(_track(filePath: other.path), other.path),
        throwsA(isA<PlaybackCacheException>()));
    expect(await File(first.filePath).readAsBytes(), List.filled(10, 1));
    cache.release(first.filePath);
    await expectLater(cache.resolve(_track(filePath: other.path), other.path),
        throwsA(isA<PlaybackCacheException>()));
    cache.release(repeated.filePath);
    final next = await cache.acquire(_track(filePath: other.path), other.path);
    expect(await File(next.filePath).readAsBytes(), List.filled(10, 2));
    expect(await File(first.filePath).exists(), isFalse);
    cache.release(next.filePath);
    await cache.waitForPendingOperations();
  });

  test('simultaneous requests for one source share the completed cache file',
      () async {
    final temp = await Directory.systemTemp.createTemp('cmp_parallel_cache_');
    addTearDown(() => temp.delete(recursive: true));
    final source = File(p.join(temp.path, 'source.mp3'));
    final bytes = List.generate(65536, (index) => index % 256);
    await source.writeAsBytes(bytes);
    final cache = WindowsPlaybackCache(
        appSupportDirectoryProvider: () async =>
            Directory(p.join(temp.path, 'support')));
    final entries = await Future.wait(List.generate(
        8, (_) => cache.acquire(_track(filePath: source.path), source.path)));
    expect(entries.where((entry) => !entry.reusedExistingFile), hasLength(1));
    expect(entries.map((entry) => entry.filePath).toSet(), hasLength(1));
    expect(await File(entries.first.filePath).readAsBytes(), bytes);
    for (final entry in entries) {
      cache.release(entry.filePath);
    }
    await cache.waitForPendingOperations();
  });

  test('one large playback source may temporarily exceed the retention limit',
      () async {
    final temp = await Directory.systemTemp.createTemp('cmp_large_playback_');
    addTearDown(() => temp.delete(recursive: true));
    final source = File(p.join(temp.path, 'large.wav'));
    await source.writeAsBytes(List.filled(30, 1));
    final cache = WindowsPlaybackCache(
        maxBytes: 20,
        appSupportDirectoryProvider: () async =>
            Directory(p.join(temp.path, 'support')));
    final entry =
        await cache.acquire(_track(filePath: source.path), source.path);
    expect(await File(entry.filePath).length(), 30);
    cache.release(entry.filePath);
    await cache.waitForPendingOperations();
  });

  test('Windows playback cache production limit is 250 MB', () {
    expect(windowsPlaybackCacheMaxBytes, 250 * 1024 * 1024);
  });

  test('cache filename is ASCII-only, short, and preserves extension',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_cache_name_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final appSupportDirectory =
        Directory(p.join(tempDirectory.path, 'support'));
    final longBasename = '${'a' * 96}.mp3';
    final source = File(p.join(tempDirectory.path, 'music', longBasename));
    await source.parent.create(recursive: true);
    await source.writeAsBytes([1, 2, 3, 4]);
    final track = _track(filePath: source.path);
    final cache = WindowsPlaybackCache(
      appSupportDirectoryProvider: () async => appSupportDirectory,
    );

    final entry = await cache.resolve(track, p.normalize(source.absolute.path));
    final basename = p.basename(entry.filePath);

    expect(basename, matches(RegExp(r'^[A-Za-z0-9_.-]+$')));
    expect(basename, isNot(contains(longBasename.replaceAll('.mp3', ''))));
    expect(p.extension(entry.filePath), '.mp3');
    expect(track.filePath, source.path);
  });

  test('cache key includes source path as well as file metadata', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_cache_key_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final appSupportDirectory =
        Directory(p.join(tempDirectory.path, 'support'));
    final modifiedAt = DateTime(2026, 1, 1, 12);
    final first = File(p.join(tempDirectory.path, 'a', 'song.mp3'));
    final second = File(p.join(tempDirectory.path, 'b', 'song.mp3'));
    await first.parent.create(recursive: true);
    await second.parent.create(recursive: true);
    await first.writeAsBytes([1, 2, 3, 4]);
    await second.writeAsBytes([1, 2, 3, 4]);
    await first.setLastModified(modifiedAt);
    await second.setLastModified(modifiedAt);
    final cache = WindowsPlaybackCache(
      appSupportDirectoryProvider: () async => appSupportDirectory,
    );

    final firstEntry = await cache.resolve(
      _track(filePath: first.path),
      p.normalize(first.absolute.path),
    );
    final secondEntry = await cache.resolve(
      _track(filePath: second.path),
      p.normalize(second.absolute.path),
    );

    expect(firstEntry.filePath, isNot(secondEntry.filePath));
  });

  test('cache file is reused if valid', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_cache_reuse_direct_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final appSupportDirectory =
        Directory(p.join(tempDirectory.path, 'support'));
    final source = File(p.join(tempDirectory.path, 'song.flac'));
    await source.writeAsBytes([1, 2, 3, 4]);
    final cache = WindowsPlaybackCache(
      appSupportDirectoryProvider: () async => appSupportDirectory,
    );
    final track = _track(filePath: source.path);
    final sourcePath = p.normalize(source.absolute.path);

    final first = await cache.resolve(track, sourcePath);
    await File(first.filePath).writeAsBytes([9, 9, 9, 9]);
    final second = await cache.resolve(track, sourcePath);

    expect(second.filePath, first.filePath);
    expect(second.reusedExistingFile, isTrue);
    expect(await File(second.filePath).readAsBytes(), [9, 9, 9, 9]);
  });

  test('cache cleanup keeps total size under limit and protects selected file',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_cache_cleanup_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final appSupportDirectory =
        Directory(p.join(tempDirectory.path, 'support'));
    final source = File(p.join(tempDirectory.path, 'song.mp3'));
    await source.writeAsBytes(List<int>.filled(70, 1));
    final cache = WindowsPlaybackCache(
      appSupportDirectoryProvider: () async => appSupportDirectory,
      maxBytes: 100,
      clock: () => DateTime(2026, 1, 2),
    );
    final track = _track(filePath: source.path);
    final sourcePath = p.normalize(source.absolute.path);
    final selected = await cache.resolve(track, sourcePath);
    final oldFile =
        File(p.join(File(selected.filePath).parent.path, 'old.mp3'));
    await oldFile.writeAsBytes(List<int>.filled(80, 2));
    await oldFile.setLastModified(DateTime(2025));

    final reused = await cache.resolve(track, sourcePath);
    final cacheFiles = await File(selected.filePath)
        .parent
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    final totalSize = cacheFiles.fold<int>(
      0,
      (sum, file) => sum + file.lengthSync(),
    );

    expect(reused.filePath, selected.filePath);
    expect(await File(selected.filePath).exists(), isTrue);
    expect(await oldFile.exists(), isFalse);
    expect(totalSize, lessThanOrEqualTo(100));
    expect(reused.cacheSizeBeforeCleanupBytes, greaterThan(100));
    expect(reused.cacheSizeAfterCleanupBytes, lessThanOrEqualTo(100));
    expect(reused.cleanupDeletedFileCount, 1);
  });
}

Track _track({
  required String filePath,
}) {
  final now = DateTime(2026);
  return Track(
    id: 1,
    stableId: 'stable',
    filePath: filePath,
    title: 'Song',
    artist: 'Artist',
    duration: const Duration(minutes: 3),
    addedAt: now,
    updatedAt: now,
  );
}
