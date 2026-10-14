import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftRepositories repositories;
  final now = DateTime(2026, 10, 12);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repositories = DriftRepositories(database);
  });
  tearDown(() => database.close());

  Track track(String path, {String title = 'Same song', int? folderId}) =>
      Track(
        libraryFolderId: folderId,
        stableId: 'shared-metadata-signature',
        filePath: path,
        title: title,
        artist: 'Artist',
        album: 'Album',
        fileSizeBytes: 1234,
        duration: const Duration(minutes: 3),
        addedAt: now,
        updatedAt: now,
      );

  Future<int> folder(String path) => repositories.libraryFolders.upsertFolder(
        LibraryFolder(path: path, createdAt: now, updatedAt: now),
      );

  test('same metadata in another folder does not steal a track or its state',
      () async {
    final firstFolder = await folder('/music');
    final secondFolder = await folder('/downloads');
    final firstId = await repositories.tracks.upsertTrack(
      track('/music/song.mp3', folderId: firstFolder),
    );
    await repositories.trackUserState.upsertState(
      TrackUserState(
        trackId: firstId,
        isFavorite: true,
        playCount: 9,
        updatedAt: now,
      ),
    );
    await repositories.playbackEvents.addEvent(
      PlaybackEvent(
        trackId: firstId,
        type: PlaybackEventType.started,
        occurredAt: now,
      ),
    );
    final playlistId = await repositories.playlists.createPlaylist('Keep');
    await repositories.playlists.addTrackToPlaylist(playlistId, firstId);

    final secondId = await repositories.tracks.upsertTrack(
      track('/downloads/song.mp3', folderId: secondFolder),
    );

    expect(secondId, isNot(firstId));
    final original = (await repositories.tracks.findById(firstId))!;
    expect(original.filePath, '/music/song.mp3');
    expect(original.libraryFolderId, firstFolder);
    expect(
        (await repositories.trackUserState.findByTrackId(firstId))?.playCount,
        9);
    expect(
        (await repositories.trackUserState.findByTrackId(firstId))?.isFavorite,
        isTrue);
    expect(await repositories.playbackEvents.recentForTrack(firstId),
        hasLength(1));
    expect(await repositories.trackUserState.findByTrackId(secondId), isNull);
    final entries =
        await repositories.playlists.watchPlaylistTracks(playlistId).first;
    expect(entries.single.track.id, firstId);

    await repositories.libraryFolders.setFolderEnabled(
      secondFolder,
      isEnabled: false,
      updatedAt: now,
    );
    expect((await repositories.tracks.listTracks()).single.id, firstId);
  });

  test('metadata collisions cannot overwrite a different file', () async {
    final firstId = await repositories.tracks.upsertTrack(
      track('/music/first.mp3', title: 'Первая песня'),
    );
    final secondId = await repositories.tracks.upsertTrack(
      track('/music/second.mp3', title: 'Другая песня'),
    );

    expect(secondId, isNot(firstId));
    expect(
        (await repositories.tracks.findById(firstId))?.title, 'Первая песня');
    expect(await repositories.tracks.listTracks(), hasLength(2));
  });

  test('signature lookup returns no match when the signature is ambiguous',
      () async {
    final id = await repositories.tracks.upsertTrack(track('/music/first.mp3'));
    expect(
      (await repositories.tracks.findByStableId('shared-metadata-signature'))
          ?.id,
      id,
    );
    await repositories.tracks.upsertTrack(track('/music/copy.mp3'));

    expect(
        await repositories.tracks.findByStableId('shared-metadata-signature'),
        isNull);
    expect(await repositories.tracks.findByStableId('unknown'), isNull);
  });

  test('same path updates the existing ID even if metadata signature changes',
      () async {
    final original = track('/music/song.mp3');
    final id = await repositories.tracks.upsertTrack(original);
    final updatedId = await repositories.tracks.upsertTrack(
      original.copyWith(stableId: 'new-signature', title: 'Corrected'),
    );

    expect(updatedId, id);
    expect(await repositories.tracks.listTracks(), hasLength(1));
    expect((await repositories.tracks.findById(id))?.title, 'Corrected');
  });

  test('explicit ID permits relocation without transferring another record',
      () async {
    final original = track('/music/song.mp3');
    final id = await repositories.tracks.upsertTrack(original);
    final copyId =
        await repositories.tracks.upsertTrack(track('/music/copy.mp3'));
    final relocatedId = await repositories.tracks.upsertTrack(
      original.copyWith(id: id, filePath: '/relocated/song.mp3'),
    );

    expect(relocatedId, id);
    expect((await repositories.tracks.findById(copyId))?.filePath,
        '/music/copy.mp3');
    expect(await repositories.tracks.findByPath('/music/song.mp3'), isNull);
  });

  test(
      'concurrent upserts of one path return one ID without a constraint error',
      () async {
    final ids = await Future.wait(
      List.generate(
          8,
          (_) => repositories.tracks.upsertTrack(
                track('/music/song.mp3'),
              )),
    );

    expect(ids.toSet(), hasLength(1));
    expect(await repositories.tracks.listTracks(), hasLength(1));
  });
}
