import 'dart:io';

import 'package:clever_music_player/src/android/android_audio_metadata.dart';
import 'package:clever_music_player/src/android/android_folder_bookmarks.dart';
import 'package:clever_music_player/src/android/android_import_controller.dart';
import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/android/drift_android_folder_library.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/track_repository.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/metadata_enrichment.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/test_audio_folders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('untagged SAF display name supplies artist/title without extension', () {
    final result = mergeAudioDocumentMetadata(const AudioDocumentMetadata(
        name: 'BOOKER — Пора завязывать.mp3', duration: Duration(minutes: 3)));
    expect(result.title, 'Пора завязывать');
    expect(result.artist, 'BOOKER');
    expect(result.source, MetadataSource.filename);
    expect(result.confidence, 0.72);
    expect(result.duration, const Duration(minutes: 3));
  });

  test('useful embedded fields take priority over conflicting filename', () {
    final result = mergeAudioDocumentMetadata(const AudioDocumentMetadata(
        name: 'Wrong Artist - Wrong Title.mp3',
        title: 'Actual Title',
        artist: 'Actual Artist',
        album: 'Album',
        albumArtist: 'Album Artist',
        genre: 'Post-Rock'));
    expect(result.title, 'Actual Title');
    expect(result.artist, 'Actual Artist');
    expect(result.album, 'Album');
    expect(result.albumArtist, 'Album Artist');
    expect(result.genre, 'Post-Rock');
    expect(result.source, MetadataSource.embeddedTags);
    expect(result.confidence, 0.95);
  });

  test('missing embedded artist is filled without replacing embedded title',
      () {
    final result = mergeAudioDocumentMetadata(const AudioDocumentMetadata(
        name: 'Arctic Monkeys - 505.mp3', title: '505 (Live)', album: 'Live'));
    expect(result.title, '505 (Live)');
    expect(result.artist, 'Arctic Monkeys');
    expect(result.album, 'Live');
    expect(result.source, MetadataSource.embeddedTags);
  });

  test('placeholder tags and whitespace fall back to filename rules', () {
    final result = mergeAudioDocumentMetadata(const AudioDocumentMetadata(
        name: '[yayaheart] Мне 20.mp3',
        title: 'Track 01',
        artist: '<unknown>',
        album: 'Unknown Album',
        genre: 'N/A'));
    expect(result.title, 'Мне 20');
    expect(result.artist, 'yayaheart');
    expect(result.album, isNull);
    expect(result.genre, isNull);
    expect(result.source, MetadataSource.filename);
  });

  for (final name in ['scars.mp3', 'scars_on_broadway.mp3']) {
    test('ambiguous filename $name does not invent an artist', () {
      final result =
          mergeAudioDocumentMetadata(AudioDocumentMetadata(name: name));
      expect(result.artist, isNull);
      expect(result.title, isNot(contains('.mp3')));
      expect(result.confidence, lessThanOrEqualTo(0.35));
    });
  }

  test('missing display name still permits useful embedded metadata', () {
    final result = mergeAudioDocumentMetadata(
        const AudioDocumentMetadata(title: 'Oceans', artist: 'Pearl Jam'));
    expect(result.title, 'Oceans');
    expect(result.artist, 'Pearl Jam');
    expect(result.source, MetadataSource.embeddedTags);
  });

  test('nameless document uses a neutral label and low confidence', () {
    final result =
        mergeAudioDocumentMetadata(const AudioDocumentMetadata(name: ' '));
    expect(result.title, 'Без названия');
    expect(result.artist, isNull);
    expect(result.source, MetadataSource.fallback);
    expect(result.confidence, 0.2);
  });

  test('nameless generic title remains a low-confidence label', () {
    final result =
        mergeAudioDocumentMetadata(const AudioDocumentMetadata(title: 'Track'));
    expect(result.title, 'Track');
    expect(result.artist, isNull);
    expect(result.source, MetadataSource.fallback);
    expect(result.confidence, 0.2);
  });

  test('embedded strings share desktop normalization', () {
    final result = mergeAudioDocumentMetadata(const AudioDocumentMetadata(
        title: '  Моя\u0000  песня\n',
        artist: '\tИсполнитель  ',
        albumArtist: '  Автор\n альбома ',
        genre: ' Post-Rock '));
    expect(result.title, 'Моя песня');
    expect(result.artist, 'Исполнитель');
    expect(result.albumArtist, 'Автор альбома');
    expect(result.genre, 'Post-Rock');
  });

  test('Android and desktop produce the same metadata for the same input',
      () async {
    final dir = await Directory.systemTemp.createTemp('cmp_metadata_parity_');
    addTearDown(() => dir.delete(recursive: true));
    for (final title in [null, 'Embedded Title']) {
      const name = 'Исполнитель - Название.flac';
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes([0, 1]);
      final android = mergeAudioDocumentMetadata(AudioDocumentMetadata(
          name: name, title: title, album: 'Альбом', genre: 'Rock'));
      final desktop = await AudioMetadataReaderService(
          embeddedMetadataReader: (_) async => EmbeddedAudioMetadata(
              title: title, album: 'Альбом', genre: 'Rock')).read(file);
      expect(android.title, desktop.title);
      expect(android.artist, desktop.artist);
      expect(android.album, desktop.album);
      expect(android.genre, desktop.genre);
      expect(android.source, desktop.metadataSource);
      expect(android.confidence, desktop.metadataConfidence);
    }
  });

  group('real SQLite import', () {
    late _Fixture f;
    setUp(() => f = _Fixture());
    tearDown(() => f.close());

    test(
        'refresh upgrades old Android filename records without changing identity',
        () async {
      final id = await f.repo.tracks.upsertTrack(Track.fromSource(
          source: f.source,
          title: 'BOOKER - Пора завязывать.mp3',
          metadataSource: MetadataSource.filename,
          addedAt: f.now,
          updatedAt: f.now));
      await f.repo.trackUserState.upsertState(TrackUserState(
          trackId: id, isFavorite: true, playCount: 4, updatedAt: f.now));
      await f.importer.importFolder();
      final updated = (await f.repo.tracks.findById(id))!;
      expect(updated.id, id);
      expect(updated.filePath, f.source.storageValue);
      expect(updated.title, 'Пора завязывать');
      expect(updated.artist, 'BOOKER');
      expect(updated.metadataSource, MetadataSource.filename);
      expect(updated.metadataConfidence, 0.72);
      expect(updated.addedAt, f.now);
      expect(updated.libraryFolderId, f.store.folderIdFor(f.native.first));
      final state = (await f.repo.trackUserState.findByTrackId(id))!;
      expect(state.isFavorite, isTrue);
      expect(state.playCount, 4);
      expect(await f.repo.tracks.listTracks(), hasLength(1));
    });

    test('folder and individual imports share metadata and preserve ownership',
        () async {
      f.native.selection = AudioDocumentSelection([f.source]);
      await f.importer.importSelection();
      final first = (await f.repo.tracks.listTracks()).single;
      expect(first.title, 'Пора завязывать');
      expect(first.artist, 'BOOKER');
      await f.importer.importFolder();
      final folder = (await f.repo.tracks.listTracks()).single;
      expect(folder.id, first.id);
      expect(folder.title, first.title);
      expect(folder.artist, first.artist);
      expect(folder.metadataConfidence, first.metadataConfidence);
      expect(folder.libraryFolderId, isNotNull);
      await f.store.forget(f.native.first);
      expect(await f.repo.tracks.listTracks(), isEmpty);
    });

    test(
        'refresh preserves manual cleared fields, custom cover and linked data',
        () async {
      await f.importer.importFolder();
      final track = (await f.repo.tracks.listTracks()).single;
      final id = track.id!;
      await f.repo.tracks.updateTrackMetadata(TrackMetadataUpdate(
          trackId: id, title: 'Моя версия', updatedAt: f.now));
      await f.repo.tracks.updateCustomArtwork(
          trackId: id,
          path: 'private/cover.webp',
          hash: 'custom',
          mimeType: 'image/webp',
          updatedAt: f.now);
      final playlist = await f.repo.playlists.createPlaylist('Keep');
      await f.repo.playlists.addTrackToPlaylist(playlist, id);
      await f.repo.playbackEvents.addEvent(PlaybackEvent(
          trackId: id, type: PlaybackEventType.started, occurredAt: f.now));
      await f.importer.refreshSavedFolders();
      final refreshed = (await f.repo.tracks.listTracks()).single;
      expect(refreshed.id, id);
      expect(refreshed.libraryFolderId, track.libraryFolderId);
      expect(refreshed.title, 'Моя версия');
      expect(refreshed.artist, isNull);
      expect(refreshed.genre, isNull);
      expect(refreshed.metadataSource, MetadataSource.manual);
      expect(refreshed.customArtworkPath, 'private/cover.webp');
      expect(refreshed.customArtworkHash, 'custom');
      expect(await f.repo.playbackEvents.recentForTrack(id), hasLength(1));
      expect(
          (await f.repo.playlists.watchPlaylistTracks(playlist).first)
              .single
              .trackId,
          id);
    });

    test('opaque URI text never becomes a filename or inferred artist',
        () async {
      f.native.selection = AudioDocumentSelection([
        ContentUriAudioSource(
            'content://test.documents/document/BOOKER%20-%20Wrong.mp3')
      ]);
      f.native.readAction = (_) async => const AudioDocumentMetadata();
      await f.importer.importSelection();
      final row = (await f.repo.tracks.listTracks()).single;
      expect(row.title, 'Без названия');
      expect(row.artist, isNull);
      expect(row.metadataSource, MetadataSource.fallback);
    });
  });
}

final class _Fixture {
  _Fixture() {
    repo = DriftRepositories(database);
    native.count = 1;
    native.readAction = (_) async =>
        const AudioDocumentMetadata(name: 'BOOKER - Пора завязывать.mp3');
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
  final database = AppDatabase(NativeDatabase.memory());
  final native = TestAudioFolders();
  final now = DateTime(2026);
  ContentUriAudioSource get source => native.track(native.first, 0);
  late final DriftRepositories repo;
  late final AndroidFolderBookmarks store;
  late final AndroidImportController importer;
  Future<void> close() async {
    await importer.close();
    await store.close();
    importer.dispose();
    store.dispose();
    await database.close();
  }
}
