import 'dart:async';

import 'package:clever_music_player/src/android/android_import_controller.dart';
import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/track_repository.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      MethodChannel('dev.lunatuk.clever_music_player/audio_documents');
  const adapter = AndroidAudioDocuments(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final tree =
      ContentUriAudioSource('content://music.documents/tree/A%3BMusic');
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('folder channel preserves raw URI and opens/pages/closes one session',
      () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return switch (call.method) {
        'pickAudioFolder' => {'uri': tree.storageValue},
        'openAudioFolder' => 7,
        'readAudioFolderPage' => {
            'uris': ['${tree.storageValue}/document/song'],
            'visited': 1,
            'done': true
          },
        _ => null,
      };
    });
    final picked = (await adapter.pickAudioFolder())!;
    expect(picked.storageValue, tree.storageValue);
    final id = await adapter.openAudioFolder(picked);
    final page = await adapter.readAudioFolderPage(id);
    expect(page.done, isTrue);
    expect(page.visited, 1);
    await adapter.closeAudioFolder(id);
    expect(methods, [
      'pickAudioFolder',
      'openAudioFolder',
      'readAudioFolderPage',
      'closeAudioFolder'
    ]);
  });

  test(
      'folder picker cancellation and malformed tree are rejected before opening',
      () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await adapter.pickAudioFolder(), isNull);
    for (final value in [
      42,
      'https://test/tree/music',
      'content://test/document/music',
      'content://test/tree/'
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => {'uri': value});
      await expectLater(adapter.pickAudioFolder(), throwsFormatException);
    }
    await expectLater(
        adapter.openAudioFolder(
            ContentUriAudioSource('content://test/document/music')),
        throwsFormatException);
  });

  test('folder page bounds/types reject invalid native messages', () async {
    for (final payload in [
      {
        'uris': List.filled(65, 'content://test/document/a'),
        'visited': 65,
        'done': true
      },
      {
        'uris': [42],
        'visited': 1,
        'done': true
      },
      {
        'uris': ['file:///tmp/song'],
        'visited': 1,
        'done': true
      },
      {'uris': [], 'visited': -1, 'done': true},
      {'uris': [], 'visited': 100001, 'done': true},
      {'uris': [], 'visited': 0, 'done': 'yes'},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => payload);
      await expectLater(adapter.readAudioFolderPage(7), throwsFormatException);
    }
    messenger.setMockMethodCallHandler(channel, (_) async => -1);
    await expectLater(adapter.openAudioFolder(tree), throwsFormatException);
  });

  group('paged folder ownership', () {
    late _Fixture f;
    setUp(() => f = _Fixture());
    tearDown(() => f.close());

    test(
        'more than 64 files import by pages, keeping different sources with same title',
        () async {
      await f.importer.importFolder();
      expect(await f.rows(), hasLength(130));
      expect(f.documents.pageCalls, 3);
      expect(f.documents.reads, 130);
      expect(f.documents.closes, 1);
      expect(f.importer.total, 130);
      expect(f.importer.processed, 130);
      expect(f.importer.busy, isFalse);
    });

    test('repeat same folder preserves IDs, manual title and favorite',
        () async {
      await f.importer.importFolder();
      final before = await f.rows();
      final first = before.first;
      await f.repositories.tracks.upsertTrack(first.copyWith(
          title: 'My title', metadataSource: MetadataSource.manual));
      await f.repositories.trackUserState.upsertState(TrackUserState(
          trackId: first.id!, isFavorite: true, updatedAt: DateTime(2026)));
      await f.importer.importFolder();
      final after = await f.rows();
      expect({for (final t in after) t.filePath: t.id},
          {for (final t in before) t.filePath: t.id});
      expect(
          (await f.repositories.tracks.findById(first.id!))!.title, 'My title');
      expect(
          (await f.repositories.trackUserState.findByTrackId(first.id!))!
              .isFavorite,
          isTrue);
    });

    test('empty folder finishes and closes without metadata reads', () async {
      f.documents.count = 0;
      await f.importer.importFolder();
      expect(await f.rows(), isEmpty);
      expect(f.documents.reads, 0);
      expect(f.documents.closes, 1);
      expect(f.importer.message, contains('Добавлено в библиотеку: 0'));
    });

    test('picker cancellation never opens a traversal', () async {
      f.documents.pick = () async => null;
      await f.importer.importFolder();
      expect(f.documents.opens, 0);
      expect(f.importer.busy, isFalse);
    });

    test('duplicate folder/file button presses cannot overlap a picker',
        () async {
      final picked = Completer<ContentUriAudioSource?>();
      f.documents.pick = () => picked.future;
      final importing = f.importer.importFolder();
      await f.importer.importFolder();
      await f.importer.importSelection();
      expect(f.documents.picks, 1);
      expect(f.documents.filePicks, 0);
      picked.complete(null);
      await importing;
    });

    test('one unreadable audio file does not prevent following files',
        () async {
      f.documents.count = 3;
      f.documents.read = (source) async {
        if (source == f.documents.source(1)) {
          throw PlatformException(code: 'access_lost');
        }
        return const AudioDocumentMetadata(title: 'Song');
      };
      await f.importer.importFolder();
      expect(await f.rows(), hasLength(2));
      expect(f.importer.processed, 3);
      expect(f.importer.message, contains('Не добавлено: 1'));
    });

    test('cancel during metadata keeps prior page and prevents late writes',
        () async {
      final blocked = Completer<AudioDocumentMetadata>();
      f.documents.read = (_) => f.documents.reads == 65
          ? blocked.future
          : Future.value(const AudioDocumentMetadata(title: 'Song'));
      final importing = f.importer.importFolder();
      await until(() => f.documents.reads == 65);
      expect(f.importer.canCancel, isTrue);
      await f.importer.cancel();
      expect(f.importer.cancelling, isTrue);
      expect(f.importer.canCancel, isFalse);
      await f.importer.importFolder();
      expect(f.documents.opens, 1);
      blocked.complete(const AudioDocumentMetadata(title: 'Late'));
      await importing;
      expect(await f.rows(), hasLength(64));
      expect(f.documents.closes, 1);
      expect(f.documents.pageCalls, 2);
      expect(f.importer.message, startsWith('Импорт остановлен.'));
      f.documents.read = null;
      await f.importer.importFolder();
      expect(await f.rows(), hasLength(130));
    });

    test('cancel pending native page ignores late results and closes once',
        () async {
      final page = Completer<AudioFolderPage>();
      f.documents.page = (_) => page.future;
      final importing = f.importer.importFolder();
      await until(() => f.documents.pageCalls == 1);
      await f.importer.cancel();
      page.complete(
          AudioFolderPage([f.documents.source(0)], visited: 1, done: true));
      await importing;
      expect(await f.rows(), isEmpty);
      expect(f.documents.reads, 0);
      expect(f.documents.closes, 1);
    });

    test('close during open drains late session without enumerating it',
        () async {
      final opened = Completer<int>();
      f.documents.open = () => opened.future;
      final importing = f.importer.importFolder();
      await until(() => f.documents.opens == 1);
      var closed = false;
      final closing = f.importer.close().then((_) => closed = true);
      await flush();
      expect(closed, isFalse);
      opened.complete(7);
      await importing;
      await closing;
      expect(f.documents.closes, 1);
      expect(f.documents.pageCalls, 0);
    });

    test('close invalidates late tree picker without waiting for user',
        () async {
      final picked = Completer<ContentUriAudioSource?>();
      f.documents.pick = () => picked.future;
      final importing = f.importer.importFolder();
      await f.importer.close();
      picked.complete(f.documents.tree);
      await importing;
      expect(f.documents.opens, 0);
    });

    test('provider failure preserves committed tracks and closes traversal',
        () async {
      f.documents.page = (index) async {
        if (index == 2) throw PlatformException(code: 'access_lost');
        return f.documents.defaultPage(index);
      };
      await f.importer.importFolder();
      expect(await f.rows(), hasLength(64));
      expect(f.importer.message, contains('Не удалось завершить импорт'));
      expect(f.importer.message, contains('64'));
      expect(f.documents.closes, 1);
      expect(f.importer.busy, isFalse);
    });

    test('non-progressing traversal terminates instead of looping', () async {
      f.documents.page =
          (_) async => const AudioFolderPage([], visited: 0, done: false);
      await f.importer.importFolder();
      expect(f.documents.pageCalls, 1);
      expect(f.documents.closes, 1);
      expect(f.importer.message, contains('Не удалось завершить импорт'));
    });
  });

  test('folder close drains accepted DB writes and waits for cursor release',
      () async {
    final documents = _Documents()..count = 1;
    final imports = _DelayedImports();
    final released = Completer<void>();
    documents.release = () => released.future;
    final importer = AndroidImportController(
        documents: documents,
        imports: imports,
        artworkCache: const NoopArtworkCacheService());
    final importing = importer.importFolder();
    await imports.entered.future;
    var closed = false;
    final closing = importer.close().then((_) => closed = true);
    imports.committed.complete([1]);
    await flush();
    expect(closed, isFalse);
    released.complete();
    await importing;
    await closing;
    expect(documents.closes, 1);
    expect(imports.calls, 1);
    importer.dispose();
  });
}

Future<void> flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

final class _Fixture {
  _Fixture() {
    repositories = DriftRepositories(database);
    importer = AndroidImportController(
        documents: documents,
        imports: repositories.tracks as TrackImportRepository,
        artworkCache: const NoopArtworkCacheService());
  }
  final database = AppDatabase(NativeDatabase.memory());
  final documents = _Documents();
  late final DriftRepositories repositories;
  late final AndroidImportController importer;
  Future<List<Track>> rows() => repositories.tracks.listTracks(limit: 1000);
  Future<void> close() async {
    await importer.close();
    importer.dispose();
    await database.close();
  }
}

final class _Documents implements AudioDocuments, AudioDocumentFolders {
  final tree = ContentUriAudioSource('content://music.documents/tree/Music');
  ContentUriAudioSource source(int i) => ContentUriAudioSource(
      'content://music.documents/tree/Music/document/song$i');
  int count = 130,
      picks = 0,
      filePicks = 0,
      opens = 0,
      pageCalls = 0,
      reads = 0,
      closes = 0;
  Future<ContentUriAudioSource?> Function()? pick;
  Future<int> Function()? open;
  Future<AudioFolderPage> Function(int)? page;
  Future<AudioDocumentMetadata> Function(ContentUriAudioSource)? read;
  Future<void> Function()? release;
  @override
  Future<AudioDocumentSelection?> pickAudio() async {
    filePicks++;
    return null;
  }

  @override
  Future<ContentUriAudioSource?> pickAudioFolder() {
    picks++;
    return pick?.call() ?? Future.value(tree);
  }

  @override
  Future<int> openAudioFolder(ContentUriAudioSource tree) {
    opens++;
    pageCalls = 0;
    return open?.call() ?? Future.value(7);
  }

  @override
  Future<AudioFolderPage> readAudioFolderPage(int session) {
    pageCalls++;
    return page?.call(pageCalls) ?? Future.value(defaultPage(pageCalls));
  }

  AudioFolderPage defaultPage(int index) {
    final start = (index - 1) * 64;
    final end = (start + 64).clamp(0, count);
    return AudioFolderPage([for (var i = start; i < end; i++) source(i)],
        visited: end, done: end == count);
  }

  @override
  Future<void> closeAudioFolder(int session) async {
    closes++;
    await release?.call();
  }

  @override
  Future<AudioDocumentMetadata> readAudio(ContentUriAudioSource source) {
    reads++;
    return read?.call(source) ??
        Future.value(const AudioDocumentMetadata(title: 'Song'));
  }
}

final class _DelayedImports implements TrackImportRepository {
  final entered = Completer<void>();
  final committed = Completer<List<int>>();
  int calls = 0;
  @override
  Future<List<int>> upsertScannedTracks(List<Track> tracks) {
    calls++;
    entered.complete();
    return committed.future;
  }
}
