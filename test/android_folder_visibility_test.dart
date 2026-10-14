import 'dart:async';
import 'dart:convert';

import 'package:clever_music_player/src/android/android_folder_bookmarks.dart';
import 'package:clever_music_player/src/android/android_import_controller.dart';
import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/android/drift_android_folder_library.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/track_repository.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_audio_folders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() => f = _Fixture());
  tearDown(() => f.close());

  test('upgrade from 20 adopts granted trees without rescanning', () async {
    f.native.grants = [f.native.first];
    final id = await f.add(f.native.track(f.native.first, 0));
    await f.store.initialize();
    expect((await f.repo.tracks.findById(id))!.libraryFolderId,
        f.store.folderIdFor(f.native.first));
    expect(await f.visibleIds(), [id]);
    expect(f.native.metadataReads + f.native.opens + f.native.inspections, 0);
  });

  test('upgrade from 21 hides already forgotten trees, preserving direct files',
      () async {
    f.native.grants = [f.native.first, f.native.second];
    final forgotten = await f.add(f.native.track(f.native.first, 0));
    final active = await f.add(f.native.track(f.native.second, 0));
    final direct = await f
        .add(ContentUriAudioSource('content://test.documents/document/song0'));
    await f.saveLegacy([f.native.second]);
    await f.store.initialize();
    expect(await f.visibleIds(), unorderedEquals([active, direct]));
    final row = (await f.repo.tracks.findById(forgotten))!;
    expect(row.isMissing, isFalse);
    expect(row.libraryFolderId, isNotNull);
    expect(f.native.grantReads, 0);
    await f.reload();
    expect(await f.visibleIds(), unorderedEquals([active, direct]));
    await f.store.remember(f.native.first);
    expect(await f.visibleIds(), unorderedEquals([forgotten, active, direct]));
  });

  test('empty saved list on upgrade really produces an empty folder library',
      () async {
    await f.add(f.native.track(f.native.first, 0));
    await f.add(f.native.track(f.native.second, 0));
    await f.saveLegacy([]);
    await f.store.initialize();
    expect(await f.visibleIds(), isEmpty);
    expect(await f.repo.tracks.listTracks(includeDisabledFolders: true),
        hasLength(2));
    expect(f.native.metadataReads + f.native.opens, 0);
  });

  test('new imports have owners; removal updates an existing library stream',
      () async {
    await f.importer.importFolder();
    final before = await f.repo.tracks.listTracks();
    expect(before, hasLength(2));
    expect(before.every((t) => t.libraryFolderId != null), isTrue);
    final stream = StreamIterator(f.repo.tracks.watchAllTracks());
    addTearDown(stream.cancel);
    expect(await stream.moveNext(), isTrue);
    expect(stream.current, before);
    await f.store.forget(f.native.first);
    expect(await stream.moveNext(), isTrue);
    expect(stream.current, isEmpty);
    await f.store.remember(f.native.first);
    expect(await stream.moveNext(), isTrue);
    expect(stream.current, before);
    expect(f.native.opens, 1);
  });

  test('remove/restart/reimport retain IDs, manual tags, covers and user data',
      () async {
    final original = Track.fromSource(
        source: f.native.track(f.native.first, 0),
        title: 'Manual name',
        metadataSource: MetadataSource.manual,
        customArtworkPath: 'private/cover.webp',
        customArtworkHash: 'custom-hash',
        addedAt: f.now,
        updatedAt: f.now);
    final id = await f.repo.tracks.upsertTrack(original);
    final playlist = await f.repo.playlists.createPlaylist('Keep');
    await f.repo.playlists.addTrackToPlaylist(playlist, id);
    await f.repo.trackUserState.upsertState(TrackUserState(
        trackId: id, isFavorite: true, playCount: 7, updatedAt: f.now));
    await f.repo.playbackEvents.addEvent(PlaybackEvent(
        trackId: id, type: PlaybackEventType.started, occurredAt: f.now));
    await f.saveLegacy([f.native.first]);
    await f.store.initialize();
    final owned = (await f.repo.tracks.findById(id))!;
    await f.store.forget(f.native.first);
    await f.reload();
    expect(await f.visibleIds(), isEmpty);
    expect(await f.repo.tracks.findById(id), owned);
    expect(
        (await f.repo.playlists.watchPlaylistTracks(playlist).first)
            .single
            .trackId,
        id);
    await f.importer.importFolder();
    final restored = (await f.repo.tracks.findById(id))!;
    expect(restored.libraryFolderId, owned.libraryFolderId);
    expect(restored.title, original.title);
    expect(restored.metadataSource, MetadataSource.manual);
    expect(restored.customArtworkPath, original.customArtworkPath);
    expect(restored.customArtworkHash, original.customArtworkHash);
    expect(restored.addedAt, original.addedAt);
    final state = (await f.repo.trackUserState.findByTrackId(id))!;
    expect(state.isFavorite, isTrue);
    expect(state.playCount, 7);
    expect(await f.repo.playbackEvents.recentForTrack(id), hasLength(1));
    expect(f.native.grants, isEmpty); // No revocation or extra grant lookup.
  });

  test('tree IDs, providers and separate subfolder grants never match by name',
      () async {
    final roots = [
      ContentUriAudioSource('content://one/tree/primary%3AMusic%25_'),
      ContentUriAudioSource('content://one/tree/primary%3AMusicOther'),
      ContentUriAudioSource('content://two/tree/primary%3AMusic%25_'),
      ContentUriAudioSource('content://one/tree/primary%3AMusic%25_%2FChild'),
    ];
    final ids = [
      for (final root in roots) await f.add(f.native.track(root, 0))
    ];
    await f.saveLegacy(roots);
    await f.store.initialize();
    await f.store.forget(roots.first);
    expect(await f.visibleIds(), unorderedEquals(ids.skip(1)));
    expect(await f.repo.tracks.findById(ids.first), isNotNull);
  });

  test('percent escape spelling does not orphan an existing tree document',
      () async {
    final root = ContentUriAudioSource('content://one/tree/primary%3aMusic');
    final source = ContentUriAudioSource(
        'content://one/tree/primary%3AMusic/document/primary%3AMusic%2Fa.mp3');
    final id = await f.add(source);
    await f.saveLegacy([root]);
    await f.store.initialize();
    expect(await f.visibleIds(), [id]);
    await f.store.forget(root);
    expect(await f.visibleIds(), isEmpty);
    await f.store.remember(root);
    expect(await f.visibleIds(), [id]);
    expect(await f.repo.libraryFolders.listFolders(), hasLength(1));
  });

  test('folder adoption never steals ownership from a different source',
      () async {
    final other = await f.repo.libraryFolders.upsertFolder(LibraryFolder(
        path: '/separate/source', createdAt: f.now, updatedAt: f.now));
    final id = await f.add(f.native.track(f.native.first, 0), owner: other);
    await f.saveLegacy([f.native.first]);
    await f.store.initialize();
    await f.store.forget(f.native.first);
    expect(await f.visibleIds(), [id]);
    expect((await f.repo.tracks.findById(id))!.libraryFolderId, other);
  });

  test('failed setting write rolls visibility and saved folders back together',
      () async {
    await f.importer.importFolder();
    final before = await f.visibleIds();
    final json =
        await f.repo.settings.readString(AndroidFolderBookmarks.settingKey);
    await f.database.customStatement('''
      CREATE TRIGGER reject_folder_setting BEFORE UPDATE ON app_settings
      WHEN NEW.key = '${AndroidFolderBookmarks.settingKey}'
      BEGIN SELECT RAISE(ABORT, 'test write failure'); END
    ''');
    await expectLater(f.store.forget(f.native.first), throwsA(anything));
    expect(await f.visibleIds(), before);
    expect(f.store.folders.single.source, f.native.first);
    expect(await f.repo.settings.readString(AndroidFolderBookmarks.settingKey),
        json);
    await f.database.customStatement('DROP TRIGGER reject_folder_setting');
    await f.store.forget(f.native.first);
    expect(await f.visibleIds(), isEmpty);
  });

  test('late folder page after removal cannot create visible unowned tracks',
      () async {
    await f.saveLegacy([f.native.first]);
    await f.store.initialize();
    final entered = Completer<void>();
    final page = Completer<AudioFolderPage>();
    f.native.pageAction = (_) {
      entered.complete();
      return page.future;
    };
    final refreshing = f.importer.refreshSavedFolders();
    await entered.future;
    await f.store.forget(f.native.first);
    page.complete(AudioFolderPage([f.native.track(f.native.first, 0)],
        visited: 1, done: true));
    await refreshing;
    expect(await f.visibleIds(), isEmpty);
    expect(
        await f.repo.tracks.listTracks(includeDisabledFolders: true), isEmpty);
    expect(f.native.metadataReads, 0);
    expect(f.native.closes, 1);
  });

  test('late metadata after removal stays owned by the disabled root',
      () async {
    await f.saveLegacy([f.native.first]);
    await f.store.initialize();
    final entered = Completer<void>();
    final read = Completer<AudioDocumentMetadata>();
    f.native.count = 1;
    f.native.readAction = (_) {
      entered.complete();
      return read.future;
    };
    final refreshing = f.importer.refreshSavedFolders();
    await entered.future;
    await f.store.forget(f.native.first);
    read.complete(const AudioDocumentMetadata(title: 'Late'));
    await refreshing;
    expect(await f.visibleIds(), isEmpty);
    final all = await f.repo.tracks.listTracks(includeDisabledFolders: true);
    expect(all.single.libraryFolderId, isNotNull);
    expect(f.store.folders, isEmpty);
  });

  test('corrupt settings do not migrate or disable existing library records',
      () async {
    final id = await f.add(f.native.track(f.native.first, 0));
    await f.repo.settings
        .writeString(AndroidFolderBookmarks.settingKey, '{bad');
    await expectLater(f.store.initialize(), throwsFormatException);
    expect(await f.visibleIds(), [id]);
    expect((await f.repo.tracks.findById(id))!.libraryFolderId, isNull);
    expect(await f.repo.libraryFolders.listFolders(), isEmpty);
  });
}

final class _Fixture {
  _Fixture() {
    repo = DriftRepositories(database);
    _createControllers();
  }
  final database = AppDatabase(NativeDatabase.memory());
  final native = TestAudioFolders();
  final now = DateTime(2026);
  late final DriftRepositories repo;
  late AndroidFolderBookmarks store;
  late AndroidImportController importer;
  void _createControllers() {
    store = AndroidFolderBookmarks(
        settings: repo.settings,
        access: native,
        library: DriftAndroidFolderLibrary(database));
    importer = AndroidImportController(
        documents: native,
        imports: repo.tracks as TrackImportRepository,
        artworkCache: const NoopArtworkCacheService(),
        bookmarks: store);
  }

  Future<int> add(ContentUriAudioSource source, {int? owner}) =>
      repo.tracks.upsertTrack(Track.fromSource(
          source: source,
          libraryFolderId: owner,
          title: 'Same name',
          addedAt: now,
          updatedAt: now));
  Future<List<int>> visibleIds() async =>
      (await repo.tracks.listTracks(limit: 1000)).map((t) => t.id!).toList();
  Future<void> saveLegacy(List<ContentUriAudioSource> roots) =>
      repo.settings.writeString(
          AndroidFolderBookmarks.settingKey,
          jsonEncode({
            'version': 1,
            'folders': [
              for (final root in roots) {'uri': root.storageValue}
            ]
          }));
  Future<void> reload() async {
    await _closeControllers();
    _createControllers();
    await store.initialize();
  }

  Future<void> _closeControllers() async {
    await importer.close();
    await store.close();
    importer.dispose();
    store.dispose();
  }

  Future<void> close() async {
    await _closeControllers();
    await database.close();
  }
}
