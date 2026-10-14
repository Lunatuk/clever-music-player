import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase database;
  late DriftRepositories repositories;
  final now = DateTime(2026);
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repositories = DriftRepositories(database);
  });
  tearDown(() => database.close());
  TrackImportRepository getImporter() =>
      repositories.tracks as TrackImportRepository;
  Track track(String name) => Track(
      filePath: '/music/$name.mp3',
      title: 'Same title',
      artist: 'Embedded artist',
      album: 'Embedded album',
      genre: 'Embedded genre',
      stableId: 'shared signature',
      metadataSource: MetadataSource.embeddedTags,
      contentHash: 'file-sha256-v1:3:${'a' * 64}',
      addedAt: now,
      updatedAt: now);

  test('batch IDs follow input order and a rescan preserves linked data',
      () async {
    final prepared = [track('бета 💿'), track('alpha')];
    final ids = await getImporter().upsertScannedTracks(prepared);
    expect(ids.toSet(), hasLength(2));
    for (var i = 0; i < ids.length; i++) {
      expect((await repositories.tracks.findById(ids[i]))!.filePath,
          prepared[i].filePath);
    }
    await repositories.trackUserState.upsertState(TrackUserState(
        trackId: ids.first, playCount: 9, isFavorite: true, updatedAt: now));
    final playlist = await repositories.playlists.createPlaylist('Keep');
    await repositories.playlists.addTrackToPlaylist(playlist, ids.first);
    await repositories.playbackEvents.addEvent(PlaybackEvent(
        trackId: ids.first, type: PlaybackEventType.started, occurredAt: now));
    expect(
        await getImporter().upsertScannedTracks(
            prepared.map((t) => t.copyWith(title: 'Changed')).toList()),
        ids);
    expect(await repositories.tracks.listTracks(), hasLength(2));
    expect(
        (await repositories.trackUserState.findByTrackId(ids.first))!.playCount,
        9);
    expect(
        (await repositories.trackUserState.findByTrackId(ids.first))!
            .isFavorite,
        isTrue);
    expect(await repositories.playbackEvents.recentForTrack(ids.first),
        hasLength(1));
    expect(
        (await repositories.playlists.watchPlaylistTracks(playlist).first)
            .single
            .trackId,
        ids.first);
  });

  test('latest manual values including nulls override a stale scan snapshot',
      () async {
    final id =
        (await getImporter().upsertScannedTracks([track('manual')])).single;
    final stale = (await repositories.tracks.findById(id))!;
    final editedAt = now.add(const Duration(days: 1));
    await repositories.tracks.updateTrackMetadata(TrackMetadataUpdate(
        trackId: id,
        title: 'Manual title',
        artist: 'Manual artist',
        updatedAt: editedAt));
    await getImporter().upsertScannedTracks([
      stale.copyWith(
          fileSizeBytes: 456,
          codec: 'flac',
          duration: const Duration(seconds: 8))
    ]);
    final saved = (await repositories.tracks.findById(id))!;
    expect(saved.title, 'Manual title');
    expect(saved.artist, 'Manual artist');
    expect(saved.album, isNull);
    expect(saved.genre, isNull);
    expect(saved.metadataSource, MetadataSource.manual);
    expect(saved.metadataConfidence, 1.0);
    expect(saved.updatedAt, editedAt);
    expect(saved.fileSizeBytes, 456);
    expect(saved.codec, 'flac');
    expect(saved.duration, const Duration(seconds: 8));
  });

  test('a second manual edit and clearing a custom cover survive stale data',
      () async {
    final id =
        (await getImporter().upsertScannedTracks([track('manual')])).single;
    await repositories.tracks.updateTrackMetadata(TrackMetadataUpdate(
        trackId: id,
        title: 'First manual',
        artist: 'First artist',
        updatedAt: now));
    await repositories.tracks.updateCustomArtwork(
        trackId: id,
        path: '/cache/old.jpg',
        hash: 'old',
        mimeType: 'image/jpeg',
        updatedAt: now);
    final stale = (await repositories.tracks.findById(id))!;
    await repositories.tracks.updateTrackMetadata(TrackMetadataUpdate(
        trackId: id, title: 'Latest manual', updatedAt: now));
    await repositories.tracks.clearCustomArtwork(trackId: id, updatedAt: now);
    await getImporter().upsertScannedTracks([stale]);
    final saved = (await repositories.tracks.findById(id))!;
    expect(saved.title, 'Latest manual');
    expect(saved.artist, isNull);
    expect(saved.customArtworkPath, isNull);
    expect(saved.customArtworkHash, isNull);
    expect(saved.customArtworkMimeType, isNull);
  });

  test(
      'latest custom cover is preserved even when the snapshot contains another',
      () async {
    final id =
        (await getImporter().upsertScannedTracks([track('cover')])).single;
    final stale = (await repositories.tracks.findById(id))!.copyWith(
        customArtworkPath: '/cache/stale.jpg', customArtworkHash: 'old');
    await repositories.tracks.updateCustomArtwork(
        trackId: id,
        path: '/cache/latest.png',
        hash: 'latest',
        mimeType: 'image/png',
        updatedAt: now);
    await getImporter().upsertScannedTracks([stale]);
    final saved = (await repositories.tracks.findById(id))!;
    expect(saved.customArtworkPath, '/cache/latest.png');
    expect(saved.customArtworkHash, 'latest');
    expect(saved.customArtworkMimeType, 'image/png');
  });

  test('overlapping sources retain ownership, ID and original added time',
      () async {
    final first = await repositories.libraryFolders.upsertFolder(
        LibraryFolder(path: '/music', createdAt: now, updatedAt: now));
    final second = await repositories.libraryFolders.upsertFolder(
        LibraryFolder(path: '/music/sub', createdAt: now, updatedAt: now));
    final id = (await getImporter().upsertScannedTracks(
            [track('sub/song').copyWith(libraryFolderId: first)]))
        .single;
    final later = now.add(const Duration(days: 10));
    expect(
        await getImporter().upsertScannedTracks([
          track('sub/song').copyWith(libraryFolderId: second, addedAt: later)
        ]),
        [id]);
    final saved = (await repositories.tracks.findById(id))!;
    expect(saved.libraryFolderId, first);
    expect(saved.addedAt, now);
  });

  test('scan path identity cannot relocate an unrelated explicit ID', () async {
    final id =
        (await getImporter().upsertScannedTracks([track('original')])).single;
    final copy = (await getImporter()
            .upsertScannedTracks([track('copy').copyWith(id: id)]))
        .single;
    expect(copy, isNot(id));
    expect((await repositories.tracks.findById(id))!.filePath,
        '/music/original.mp3');
  });

  test('a failed batch rolls back both inserts and updates', () async {
    final id =
        (await getImporter().upsertScannedTracks([track('existing')])).single;
    await database
        .customStatement('CREATE TRIGGER reject_bad BEFORE INSERT ON tracks '
            "WHEN NEW.file_path = '/music/bad.mp3' BEGIN "
            "SELECT RAISE(ABORT, 'injected import failure'); END;");
    await expectLater(
        getImporter().upsertScannedTracks([
          track('existing').copyWith(title: 'Must roll back'),
          track('good'),
          track('bad')
        ]),
        throwsA(anything));
    expect(await repositories.tracks.listTracks(), hasLength(1));
    expect((await repositories.tracks.findById(id))!.title, 'Same title');
  });

  test('watchers see only the complete transaction', () async {
    final events = <int>[];
    final initial = Completer<void>();
    final completed = Completer<void>();
    final subscription = repositories.tracks.watchAllTracks().listen((rows) {
      events.add(rows.length);
      if (rows.isEmpty && !initial.isCompleted) initial.complete();
      if (rows.length == 64 && !completed.isCompleted) completed.complete();
    });
    addTearDown(subscription.cancel);
    await initial.future;
    await getImporter()
        .upsertScannedTracks(List.generate(64, (i) => track('$i')));
    await completed.future.timeout(const Duration(seconds: 5));
    expect(events, [0, 64]);
  });

  test('concurrent batches for the same paths serialize to the same IDs',
      () async {
    final prepared = [track('a'), track('b')];
    final results = await Future.wait(
        List.generate(4, (_) => getImporter().upsertScannedTracks(prepared)));
    expect(results.every((ids) => ids.toString() == results.first.toString()),
        isTrue);
    expect(await repositories.tracks.listTracks(), hasLength(2));
  });

  test('invalid or empty batch cannot partially write', () async {
    expect(await getImporter().upsertScannedTracks([]), isEmpty);
    expect(() => getImporter().upsertScannedTracks([track('a'), track('a')]),
        throwsArgumentError);
    expect(
        () => getImporter()
            .upsertScannedTracks(List.generate(65, (i) => track('$i'))),
        throwsArgumentError);
    expect(await repositories.tracks.listTracks(), isEmpty);
  });

  test('indexed count includes missing files and disabled folders', () async {
    final folder = await repositories.libraryFolders.upsertFolder(LibraryFolder(
        path: '/music', isEnabled: false, createdAt: now, updatedAt: now));
    await getImporter().upsertScannedTracks([
      track('a').copyWith(libraryFolderId: folder),
      track('b').copyWith(isMissing: true)
    ]);
    expect(
        await (repositories.tracks as TrackLibraryCountRepository)
            .watchIndexedTrackCount()
            .first,
        2);
    expect(await repositories.tracks.listTracks(), isEmpty);
    await repositories.tracks.deleteTracksByLibraryFolder(folder);
    expect(
        await (repositories.tracks as TrackLibraryCountRepository)
            .watchIndexedTrackCount()
            .first,
        1);
  });

  test('file database background connection persists IDs through reopen',
      () async {
    final root = await Directory.systemTemp.createTemp('cmp_batch_db_');
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final file = File(p.join(root.path, 'library.sqlite'));
    await database.close();
    database = AppDatabase(NativeDatabase.createInBackground(file));
    repositories = DriftRepositories(database);
    final ids =
        await getImporter().upsertScannedTracks([track('a'), track('b')]);
    await database.close();
    database = AppDatabase(NativeDatabase.createInBackground(file));
    repositories = DriftRepositories(database);
    expect(
        await getImporter().upsertScannedTracks([track('a'), track('b')]), ids);
    expect(await repositories.tracks.listTracks(), hasLength(2));
  });
}
