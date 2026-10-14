import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/track.dart';
import 'package:clever_music_player/src/player/windows_playback_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late File source;
  final bytes = List.generate(64, (index) => index);
  Track track(File file) => Track(
      filePath: file.path, addedAt: DateTime(2026), updatedAt: DateTime(2026));
  Directory root() =>
      Directory(p.join(temp.path, 'support', 'CleverMusicPlayer', 'pc'));
  WindowsPlaybackCache cache(
          {PlaybackCacheCopy? copy,
          int maxBytes = 100,
          PlaybackCacheClock? clock}) =>
      WindowsPlaybackCache(
          appSupportDirectoryProvider: () async =>
              Directory(p.join(temp.path, 'support')),
          copyFile: copy,
          maxBytes: maxBytes,
          clock: clock);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cmp_atomic_cache_');
    source = File(p.join(temp.path, 'source.wav'));
    await source.writeAsBytes(bytes);
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test(
      'failed copy publishes no partial file, cleans staging, and can be retried',
      () async {
    var fail = true;
    final c = cache(copy: (source, staging) async {
      if (fail) {
        await staging.writeAsBytes([1, 2]);
        throw const FileSystemException('disk write interrupted');
      }
      await source.copy(staging.path);
    });
    await expectLater(c.resolve(track(source), source.path),
        throwsA(isA<PlaybackCacheException>()));
    expect(await root().list().toList(), isEmpty);
    expect(await source.readAsBytes(), bytes);
    fail = false;
    final entry = await c.resolve(track(source), source.path);
    expect(await File(entry.filePath).readAsBytes(), bytes);
    expect(await root().list().toList(), hasLength(1));
  });

  test('incomplete copy reported as successful is rejected before publication',
      () async {
    final c = cache(copy: (_, staging) async {
      await staging.writeAsBytes([1]);
    });
    await expectLater(c.resolve(track(source), source.path),
        throwsA(isA<PlaybackCacheException>()));
    expect(await root().list().toList(), isEmpty);
    expect(await source.readAsBytes(), bytes);
  });

  test('changed source metadata invalidates the staged copy', () async {
    final original = await source.stat();
    final c = cache(copy: (source, staging) async {
      await source.copy(staging.path);
      await source
          .setLastModified(original.modified.add(const Duration(seconds: 5)));
    });
    await expectLater(c.resolve(track(source), source.path),
        throwsA(isA<PlaybackCacheException>()));
    expect(await root().list().toList(), isEmpty);
    expect(await source.readAsBytes(), bytes);
  });

  test(
      'pending copy is visible only as staging, never under a playback filename',
      () async {
    final begun = Completer<void>();
    final finish = Completer<void>();
    final c = cache(copy: (source, staging) async {
      await staging.writeAsBytes([1, 2]);
      begun.complete();
      await finish.future;
      await source.copy(staging.path);
    });
    final operation = c.resolve(track(source), source.path);
    await begun.future;
    final entities = await root().list().toList();
    expect(entities.whereType<File>(), isEmpty);
    expect(entities.whereType<Directory>(), hasLength(1));
    finish.complete();
    final entry = await operation;
    expect(await File(entry.filePath).readAsBytes(), bytes);
    expect((await root().list().toList()).whereType<Directory>(), isEmpty);
  });

  test(
      'two decoder-held large files can overlap; release restores the retention budget',
      () async {
    final other = File(p.join(temp.path, 'other.wav'));
    await other.writeAsBytes(bytes.reversed.toList());
    final c = cache(maxBytes: 32);
    final a = await c.acquire(track(source), source.path);
    final b = await c.acquire(track(other), other.path);
    expect(await File(a.filePath).readAsBytes(), bytes);
    expect(await File(b.filePath).readAsBytes(), bytes.reversed.toList());
    c.release(a.filePath);
    await c.waitForPendingOperations();
    expect(await File(a.filePath).exists(), isFalse);
    expect(await File(b.filePath).exists(), isTrue);
    c.release(b.filePath);
    await c.waitForPendingOperations();
    expect(await root().list().toList(), isEmpty);
    expect(await source.readAsBytes(), bytes);
  });

  test(
      'orphan staging is reclaimed but unrelated directory content is preserved',
      () async {
    await root().create(recursive: true);
    final orphan =
        await Directory(p.join(root().path, '.pending-orphan')).create();
    await File(p.join(orphan.path, 'owner.lock')).writeAsString('');
    await File(p.join(orphan.path, 'audio.tmp')).writeAsBytes([1, 2]);
    final foreign =
        await Directory(p.join(root().path, '.pending-user')).create();
    await File(p.join(foreign.path, 'owner.lock')).writeAsString('');
    final foreignFile = File(p.join(foreign.path, 'keep.txt'));
    await foreignFile.writeAsString('keep');
    final c = cache(clock: () => DateTime.now().add(const Duration(days: 2)));
    await c.resolve(track(source), source.path);
    expect(await orphan.exists(), isFalse);
    expect(await foreignFile.readAsString(), 'keep');
  });

  test('a live staged copy survives cleanup by another cache instance',
      () async {
    final begun = Completer<void>();
    final finish = Completer<void>();
    final first = cache(copy: (source, staging) async {
      await staging.writeAsBytes([1]);
      begun.complete();
      await finish.future;
      await source.copy(staging.path);
    });
    final loading = first.resolve(track(source), source.path);
    await begun.future;
    final secondSource = File(p.join(temp.path, 'second.wav'));
    await secondSource.writeAsBytes([2]);
    final second =
        cache(clock: () => DateTime.now().add(const Duration(days: 2)));
    await second.resolve(track(secondSource), secondSource.path);
    expect((await root().list().toList()).whereType<Directory>(), hasLength(1));
    finish.complete();
    final entry = await loading;
    expect(await File(entry.filePath).readAsBytes(), bytes);
  });

  test('an invalid decoder-held cache entry is not overwritten until released',
      () async {
    final c = cache();
    final entry = await c.acquire(track(source), source.path);
    await File(entry.filePath).writeAsBytes([1]);
    await expectLater(c.acquire(track(source), source.path),
        throwsA(isA<PlaybackCacheException>()));
    expect(await File(entry.filePath).readAsBytes(), [1]);
    c.release(entry.filePath);
    await c.waitForPendingOperations();
    final repaired = await c.acquire(track(source), source.path);
    expect(await File(repaired.filePath).readAsBytes(), bytes);
    c.release(repaired.filePath);
    await c.waitForPendingOperations();
  });

  test('empty source cannot become a valid cached audio file', () async {
    await source.writeAsBytes([]);
    final c = cache();
    await expectLater(c.acquire(track(source), source.path),
        throwsA(isA<PlaybackCacheException>()));
    expect(await source.length(), 0);
  });
}
