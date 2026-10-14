import 'dart:async';
import 'dart:convert';

import 'package:clever_music_player/src/android/android_folder_bookmarks.dart';
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

import 'support/test_audio_folders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('folder bookmark storage', () {
    late TestFolderSettings settings;
    late TestAudioFolders native;
    late AndroidFolderBookmarks store;
    setUp(() {
      settings = TestFolderSettings();
      native = TestAudioFolders();
      store = AndroidFolderBookmarks(settings: settings, access: native);
    });
    tearDown(() async {
      await store.close();
      store.dispose();
    });

    test('package 20 tree grants bootstrap once, including duplicates',
        () async {
      native.grants = [native.first, native.second, native.first];
      await store.initialize();
      await store.initialize();
      expect(store.folders.map((f) => f.source), [native.first, native.second]);
      expect(native.grantReads, 1);
      expect(settings.writes, 1);
      expect(native.metadataReads + native.opens, 0);
    });

    test('names/timestamps reload; forgotten grant does not return at restart',
        () async {
      native.grants = [native.first];
      await store.initialize();
      await store.remember(native.first, name: 'Music');
      final when = DateTime.utc(2026, 10, 14, 12);
      await store.markCompleted(native.first, when);
      final reloaded =
          AndroidFolderBookmarks(settings: settings, access: native);
      await reloaded.initialize();
      expect(reloaded.folders.single.name, 'Music');
      expect(reloaded.folders.single.lastCompletedAt, when);
      await reloaded.forget(native.first);
      await reloaded.close();
      reloaded.dispose();
      final empty = AndroidFolderBookmarks(settings: settings, access: native);
      await empty.initialize();
      expect(empty.folders, isEmpty);
      expect(native.grantReads, 1);
      expect(native.grants, [native.first]);
      await empty.close();
      empty.dispose();
    });

    test('concurrent mutations serialize without losing roots', () async {
      await store.initialize();
      final gate = Completer<void>();
      final entered = Completer<void>();
      settings.writeAction = (_, __) {
        if (!entered.isCompleted) entered.complete();
        return gate.future;
      };
      final first = store.remember(native.first);
      await entered.future;
      final second = store.remember(native.second);
      gate.complete();
      await Future.wait([first, second]);
      expect(store.folders.map((f) => f.source), [native.first, native.second]);
      expect(
          (jsonDecode(settings.values[AndroidFolderBookmarks.settingKey]!)
              as Map)['folders'],
          hasLength(2));
    });

    test('failed write preserves current state and following mutation succeeds',
        () async {
      await store.initialize();
      final before = settings.values[AndroidFolderBookmarks.settingKey];
      settings.writeAction = (_, __) async => throw StateError('disk');
      await expectLater(store.remember(native.first), throwsStateError);
      expect(store.folders, isEmpty);
      expect(settings.values[AndroidFolderBookmarks.settingKey], before);
      settings.writeAction = null;
      await store.remember(native.second);
      expect(store.folders.single.source, native.second);
    });

    test(
        'unchanged bookmarks and absent completion markers do not rewrite settings',
        () async {
      await store.initialize();
      await store.remember(native.first, name: 'Music');
      final writes = settings.writes;
      await store.remember(native.first);
      await store.remember(native.first, name: 'Music');
      await store.markCompleted(native.second, DateTime(2026));
      expect(settings.writes, writes);
    });

    test('malformed/future/duplicate data are preserved instead of overwritten',
        () async {
      for (final value in [
        '{broken',
        jsonEncode({'version': 2, 'folders': []}),
        jsonEncode({
          'version': 1,
          'folders': [
            {'uri': 'file:///music'}
          ]
        }),
        jsonEncode({
          'version': 1,
          'folders': [
            {'uri': native.first.storageValue, 'lastCompletedAt': 'invalid'}
          ]
        }),
        jsonEncode({
          'version': 1,
          'folders': [
            {'uri': native.first.storageValue},
            {'uri': native.first.storageValue}
          ]
        }),
        jsonEncode({
          'version': 1,
          'folders': [
            {'uri': native.first.storageValue, 'name': 5}
          ]
        }),
      ]) {
        final badSettings = TestFolderSettings()
          ..values[AndroidFolderBookmarks.settingKey] = value;
        final bad =
            AndroidFolderBookmarks(settings: badSettings, access: native);
        await expectLater(bad.initialize(), throwsFormatException);
        expect(bad.loadFailed, isTrue);
        await expectLater(bad.remember(native.second), throwsFormatException);
        expect(badSettings.values[AndroidFolderBookmarks.settingKey], value);
        expect(badSettings.writes, 0);
        await bad.close();
        bad.dispose();
      }
    });

    test('count/name bounds reject mutation without corrupting saved roots',
        () async {
      await store.initialize();
      for (var i = 0; i < 128; i++) {
        await store
            .remember(ContentUriAudioSource('content://test/tree/folder$i'));
      }
      final before = settings.values[AndroidFolderBookmarks.settingKey];
      await expectLater(store.remember(native.first), throwsFormatException);
      await expectLater(
          store.remember(store.folders.first.source, name: 'x' * 257),
          throwsFormatException);
      expect(store.folders, hasLength(128));
      expect(settings.values[AndroidFolderBookmarks.settingKey], before);
    });

    test('inspection failure leaves other roots available; checks deduplicate',
        () async {
      native.grants = [native.first, native.second];
      native.inspectAction = (source) async {
        if (source == native.first) {
          throw PlatformException(code: 'access_lost');
        }
        return const AudioFolderAccess(readable: true, name: 'Other');
      };
      await store.initialize();
      final first = store.refreshAccess();
      expect(identical(first, store.refreshAccess()), isTrue);
      await first;
      expect(store.accessFor(store.folders.first)!.readable, isFalse);
      expect(store.accessFor(store.folders.last)!.readable, isTrue);
      expect(native.inspections, 2);
    });

    test('late inspection cannot resurrect a forgotten bookmark', () async {
      native.grants = [native.first];
      final info = Completer<AudioFolderAccess>();
      native.inspectAction = (_) => info.future;
      await store.initialize();
      final checking = store.refreshAccess();
      await until(() => native.inspections == 1);
      final original = store.folders.single;
      await store.forget(native.first);
      info.complete(const AudioFolderAccess(readable: true));
      await checking;
      expect(store.folders, isEmpty);
      expect(store.accessFor(original), isNull);
    });

    test(
        'close drains bootstrap and accepted queued writes without notifications',
        () async {
      await store.initialize();
      final gate = Completer<void>();
      final entered = Completer<void>();
      settings.writeAction = (_, __) {
        if (!entered.isCompleted) entered.complete();
        return gate.future;
      };
      final first = store.remember(native.first);
      await entered.future;
      final second = store.remember(native.second);
      var notifications = 0;
      store.addListener(() => notifications++);
      var closed = false;
      final closing = store.close();
      expect(identical(closing, store.close()), isTrue);
      unawaited(closing.then((_) => closed = true));
      await flush();
      expect(closed, isFalse);
      gate.complete();
      await Future.wait([first, second, closing]);
      expect(store.folders, hasLength(2));
      expect(notifications, 0);
      final writes = settings.writes;
      await store.forget(native.first);
      expect(settings.writes, writes);
    });

    test('close during legacy grant lookup waits before database can close',
        () async {
      final grants = Completer<List<ContentUriAudioSource>>();
      native.listAction = () => grants.future;
      final loading = store.initialize();
      await until(() => native.grantReads == 1);
      var closed = false;
      final closing = store.close().then((_) => closed = true);
      await flush();
      expect(closed, isFalse);
      grants.complete([native.first]);
      await loading;
      await closing;
      expect(settings.values.containsKey(AndroidFolderBookmarks.settingKey),
          isTrue);
    });
  });

  group('saved folders with real SQLite imports', () {
    late _Fixture f;
    setUp(() => f = _Fixture());
    tearDown(() => f.close());

    test(
        'refresh waits for an already accepted forget before taking its folder snapshot',
        () async {
      f.native.grants = [f.native.first, f.native.second];
      await f.bookmarks.initialize();
      final forgetting = f.bookmarks.forget(f.native.first);
      final refreshing = f.importer.refreshSavedFolders();
      await Future.wait([forgetting, refreshing]);
      expect(f.native.opened, [f.native.second]);
      expect(f.bookmarks.folders.map((folder) => folder.source),
          [f.native.second]);
    });

    test(
        'late folder metadata cannot recreate a forgotten bookmark or start its import',
        () async {
      f.native.grants = [f.native.first];
      await f.bookmarks.initialize();
      final info = Completer<AudioFolderAccess>();
      f.native.inspectAction = (_) => info.future;
      final refreshing = f.importer.refreshFolder(f.bookmarks.folders.single);
      await until(() => f.native.inspections == 1);
      await f.bookmarks.forget(f.native.first);
      info.complete(const AudioFolderAccess(readable: true, name: 'Music'));
      await refreshing;
      expect(f.bookmarks.folders, isEmpty);
      expect(f.native.opens + f.native.metadataReads, 0);
    });

    test(
        'refresh legacy root needs no picker and retains ID/manual title/favorite',
        () async {
      f.native.grants = [f.native.first];
      final original = Track.fromSource(
          source: f.native.track(f.native.first, 0),
          title: 'My title',
          metadataSource: MetadataSource.manual,
          addedAt: DateTime(2026),
          updatedAt: DateTime(2026));
      final id = await f.repositories.tracks.upsertTrack(original);
      await f.repositories.trackUserState.upsertState(TrackUserState(
          trackId: id, isFavorite: true, updatedAt: DateTime(2026)));
      await f.importer.refreshSavedFolders();
      expect(f.native.picks, 0);
      expect(await f.rows(), hasLength(2));
      expect((await f.repositories.tracks.findById(id))!.title, 'My title');
      expect(
          (await f.repositories.trackUserState.findByTrackId(id))!.isFavorite,
          isTrue);
      expect(f.bookmarks.folders.single.lastCompletedAt, isNotNull);
      f.native.count = 3;
      await f.importer.refreshSavedFolders();
      expect(await f.rows(), hasLength(3));
      expect((await f.repositories.tracks.findById(id))!.filePath,
          original.filePath);
      expect(f.native.closes, 2);
    });

    test('new selection remembers name and restart uses saved registry',
        () async {
      await f.importer.importFolder();
      expect(f.bookmarks.folders.single.name, 'Музыка');
      final restarted = AndroidFolderBookmarks(
          settings: f.repositories.settings, access: f.native);
      await restarted.initialize();
      expect(restarted.folders.single.source, f.native.first);
      expect(f.native.grantReads, 1);
      await restarted.close();
      restarted.dispose();
    });

    test('missing access and failed provider do not block remaining roots',
        () async {
      f.native.grants = [f.native.first, f.native.second];
      f.native.inaccessible.add(f.native.first);
      await f.importer.refreshSavedFolders();
      expect(f.native.opened, [f.native.second]);
      expect(await f.rows(), hasLength(2));
      expect(f.importer.message, contains('Не удалось обновить папок: 1'));
      expect(f.bookmarks.folders.first.lastCompletedAt, isNull);
      f.native.inaccessible.clear();
      f.native.broken.add(f.native.first);
      await f.importer.refreshSavedFolders();
      expect(f.native.sessions, isEmpty);
      expect(f.native.closes, 3);
      expect(await f.rows(), hasLength(2));
    });

    test('cancel first root prevents second root and completion timestamp',
        () async {
      f.native.grants = [f.native.first, f.native.second];
      final read = Completer<AudioDocumentMetadata>();
      f.native.readAction = (_) => read.future;
      final refreshing = f.importer.refreshSavedFolders();
      await until(() => f.native.metadataReads == 1);
      await f.importer.cancel();
      read.complete(const AudioDocumentMetadata(title: 'late'));
      await refreshing;
      expect(f.native.opened, [f.native.first]);
      expect(await f.rows(), isEmpty);
      expect(
          f.bookmarks.folders.every((folder) => folder.lastCompletedAt == null),
          isTrue);
    });

    test(
        'forget removes only refresh bookmark, preserving tracks/feedback/grants',
        () async {
      f.native.grants = [f.native.first];
      await f.importer.refreshSavedFolders();
      final before = await f.rows();
      final id = before.first.id!;
      await f.repositories.trackUserState.upsertState(TrackUserState(
          trackId: id, isFavorite: true, updatedAt: DateTime(2026)));
      await f.bookmarks.forget(f.native.first);
      expect(f.bookmarks.folders, isEmpty);
      expect(await f.rows(), before);
      expect(
          (await f.repositories.trackUserState.findByTrackId(id))!.isFavorite,
          isTrue);
      expect(f.native.grants, [f.native.first]);
    });

    test('restore rejects different tree, then same tree retains original IDs',
        () async {
      f.native.grants = [f.native.first];
      await f.importer.refreshSavedFolders();
      final before = await f.rows();
      final folder = f.bookmarks.folders.single;
      f.native.picked = f.native.second;
      await f.importer.restoreFolderAccess(folder);
      expect(f.importer.message, startsWith('Выбрана другая папка.'));
      expect(await f.rows(), before);
      expect(f.bookmarks.folders, hasLength(1));
      f.native.picked = f.native.first;
      await f.importer.restoreFolderAccess(folder);
      expect((await f.rows()).map((t) => t.id), before.map((t) => t.id));
    });

    test('close during access check stops before decoder/metadata/track writes',
        () async {
      f.native.grants = [f.native.first];
      final info = Completer<AudioFolderAccess>();
      f.native.inspectAction = (_) => info.future;
      final refreshing = f.importer.refreshSavedFolders();
      await until(() => f.native.inspections == 1);
      var closed = false;
      final closing = f.importer.close().then((_) => closed = true);
      await flush();
      expect(closed, isFalse);
      info.complete(const AudioFolderAccess(readable: true));
      await refreshing;
      await closing;
      expect(f.native.opens + f.native.metadataReads, 0);
      expect(await f.rows(), isEmpty);
    });

    test('bad bookmark setting cannot prevent individual document imports',
        () async {
      await f.repositories.settings
          .writeString(AndroidFolderBookmarks.settingKey, '{broken');
      await expectLater(f.bookmarks.initialize(), throwsFormatException);
      f.native.selection =
          AudioDocumentSelection([f.native.track(f.native.first, 0)]);
      await f.importer.importSelection();
      expect(await f.rows(), hasLength(1));
      expect(
          await f.repositories.settings
              .readString(AndroidFolderBookmarks.settingKey),
          '{broken');
    });
  });

  test('new native access channel preserves URI and rejects malformed data',
      () async {
    const channel =
        MethodChannel('dev.lunatuk.clever_music_player/audio_documents');
    const adapter = AndroidAudioDocuments(channel: channel);
    final native = TestAudioFolders();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listAudioFolderGrants') {
        return [native.first.storageValue, native.first.storageValue];
      }
      expect(call.arguments, {'uri': native.first.storageValue});
      return {'readable': true, 'name': ' Music '};
    });
    expect(await adapter.listAudioFolderGrants(), [native.first]);
    expect((await adapter.inspectAudioFolder(native.first)).name, 'Music');
    for (final payload in [
      null,
      {'readable': 'yes'},
      {'readable': true, 'name': 'x' * 257}
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => payload);
      await expectLater(
          adapter.inspectAudioFolder(native.first), throwsFormatException);
    }
    for (final payload in [
      null,
      ['content://test/document/song'],
      List.filled(129, native.first.storageValue)
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => payload);
      await expectLater(adapter.listAudioFolderGrants(), throwsFormatException);
    }
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
    bookmarks =
        AndroidFolderBookmarks(settings: repositories.settings, access: native);
    importer = AndroidImportController(
        documents: native,
        imports: repositories.tracks as TrackImportRepository,
        artworkCache: const NoopArtworkCacheService(),
        bookmarks: bookmarks);
  }
  final database = AppDatabase(NativeDatabase.memory());
  final native = TestAudioFolders();
  late final DriftRepositories repositories;
  late final AndroidFolderBookmarks bookmarks;
  late final AndroidImportController importer;
  Future<List<Track>> rows() => repositories.tracks.listTracks(limit: 1000);
  Future<void> close() async {
    await importer.close();
    await bookmarks.close();
    importer.dispose();
    bookmarks.dispose();
    await database.close();
  }
}
