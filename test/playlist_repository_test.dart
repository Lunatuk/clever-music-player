import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/queue/playlist_queue_actions.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('create playlist trims name and stores optional description', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);

    await fixture.repositories.playlists.createPlaylist(
      '  Road Mix  ',
      description: '  Driving songs  ',
    );

    final playlists =
        await fixture.repositories.playlists.watchPlaylists().first;

    expect(playlists, hasLength(1));
    expect(playlists.single.name, 'Road Mix');
    expect(playlists.single.description, 'Driving songs');
    expect(playlists.single.trackCount, 0);
  });

  test('rename playlist updates the stored name', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);

    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Draft');

    await fixture.repositories.playlists.renamePlaylist(
      playlistId,
      '  Favorites  ',
    );

    final playlists =
        await fixture.repositories.playlists.watchPlaylists().first;

    expect(playlists.single.name, 'Favorites');
  });

  test('delete playlist cascades entries', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final trackId = await fixture.addTrack('Track One');
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('To Delete');
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      trackId,
    );

    await fixture.repositories.playlists.deletePlaylist(playlistId);

    expect(
      await fixture.repositories.playlists.watchPlaylists().first,
      isEmpty,
    );
    expect(
      await fixture.repositories.playlists
          .watchPlaylistTracks(playlistId)
          .first,
      isEmpty,
    );
  });

  test('add track to playlist stores an ordered entry', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final trackId = await fixture.addTrack('Track One');
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Mix');

    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      trackId,
    );

    final entries = await fixture.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;

    expect(entries, hasLength(1));
    expect(entries.single.trackId, trackId);
    expect(entries.single.position, 0);
    expect(entries.single.track.title, 'Track One');
  });

  test('watch playlist tracks includes track artwork fields', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final trackId = await fixture.addTrack(
      'Covered Track',
      artworkPath: '/app/artwork/cover.png',
      artworkHash: 'cover-hash',
      artworkMimeType: 'image/png',
    );
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Mix');
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      trackId,
    );

    final entries = await fixture.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;

    expect(entries.single.track.artworkPath, '/app/artwork/cover.png');
    expect(entries.single.track.artworkHash, 'cover-hash');
    expect(entries.single.track.artworkMimeType, 'image/png');
  });

  test('track artwork fields map through repository storage', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final trackId = await fixture.addTrack(
      'Mapped Track',
      artworkPath: '/app/artwork/mapped.jpg',
      artworkHash: 'mapped-hash',
      artworkMimeType: 'image/jpeg',
    );

    final track = await fixture.repositories.tracks.findById(trackId);

    expect(track?.artworkPath, '/app/artwork/mapped.jpg');
    expect(track?.artworkHash, 'mapped-hash');
    expect(track?.artworkMimeType, 'image/jpeg');
  });

  test('adding same track twice does not duplicate it', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final trackId = await fixture.addTrack('Track One');
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Mix');

    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      trackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      trackId,
    );

    final entries = await fixture.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;

    expect(entries, hasLength(1));
  });

  test('remove track from playlist removes only that entry', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final firstTrackId = await fixture.addTrack('First');
    final secondTrackId = await fixture.addTrack('Second');
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Mix');
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      firstTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      secondTrackId,
    );

    await fixture.repositories.playlists.removeTrackFromPlaylist(
      playlistId,
      firstTrackId,
    );

    final entries = await fixture.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;

    expect(entries.map((entry) => entry.trackId), [secondTrackId]);
    expect(
      await fixture.repositories.tracks.findById(firstTrackId),
      isNotNull,
    );
  });

  test('watch playlist tracks returns tracks in playlist order', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final firstTrackId = await fixture.addTrack('First');
    final secondTrackId = await fixture.addTrack('Second');
    final thirdTrackId = await fixture.addTrack('Third');
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Ordered');

    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      secondTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      firstTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      thirdTrackId,
    );

    final entries = await fixture.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;

    expect(
      entries.map((entry) => entry.track.title),
      ['Second', 'First', 'Third'],
    );
    expect(entries.map((entry) => entry.position), [0, 1, 2]);
  });

  test('reorder playlist tracks rewrites gapless positions', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final firstTrackId = await fixture.addTrack('First');
    final secondTrackId = await fixture.addTrack('Second');
    final thirdTrackId = await fixture.addTrack('Third');
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Ordered');
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      firstTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      secondTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      thirdTrackId,
    );

    await fixture.repositories.playlists.reorderPlaylistTracks(
      playlistId: playlistId,
      trackIds: [thirdTrackId, firstTrackId, secondTrackId],
    );

    final entries = await fixture.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;

    expect(entries.map((entry) => entry.trackId), [
      thirdTrackId,
      firstTrackId,
      secondTrackId,
    ]);
    expect(entries.map((entry) => entry.position), [0, 1, 2]);
  });

  test('reordered playlist order is read back from storage', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final firstTrackId = await fixture.addTrack('First');
    final secondTrackId = await fixture.addTrack('Second');
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Persisted');
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      firstTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      secondTrackId,
    );

    await fixture.repositories.playlists.reorderPlaylistTracks(
      playlistId: playlistId,
      trackIds: [secondTrackId, firstTrackId],
    );
    final reloadedRepository = DriftPlaylistRepository(fixture.database);

    final entries =
        await reloadedRepository.watchPlaylistTracks(playlistId).first;

    expect(entries.map((entry) => entry.trackId), [
      secondTrackId,
      firstTrackId,
    ]);
  });

  test('reorder only affects the target playlist', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final firstTrackId = await fixture.addTrack('First');
    final secondTrackId = await fixture.addTrack('Second');
    final thirdTrackId = await fixture.addTrack('Third');
    final firstPlaylistId =
        await fixture.repositories.playlists.createPlaylist('First List');
    final secondPlaylistId =
        await fixture.repositories.playlists.createPlaylist('Second List');
    await fixture.repositories.playlists.addTrackToPlaylist(
      firstPlaylistId,
      firstTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      firstPlaylistId,
      secondTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      secondPlaylistId,
      secondTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      secondPlaylistId,
      thirdTrackId,
    );

    await fixture.repositories.playlists.reorderPlaylistTracks(
      playlistId: firstPlaylistId,
      trackIds: [secondTrackId, firstTrackId],
    );

    final firstEntries = await fixture.repositories.playlists
        .watchPlaylistTracks(firstPlaylistId)
        .first;
    final secondEntries = await fixture.repositories.playlists
        .watchPlaylistTracks(secondPlaylistId)
        .first;

    expect(firstEntries.map((entry) => entry.trackId), [
      secondTrackId,
      firstTrackId,
    ]);
    expect(secondEntries.map((entry) => entry.trackId), [
      secondTrackId,
      thirdTrackId,
    ]);
    expect(secondEntries.map((entry) => entry.position), [0, 1]);
  });

  test('reorder rejects entries outside the playlist without changing order',
      () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final firstTrackId = await fixture.addTrack('First');
    final secondTrackId = await fixture.addTrack('Second');
    final outsideTrackId = await fixture.addTrack('Outside');
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Safe');
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      firstTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      secondTrackId,
    );

    await expectLater(
      fixture.repositories.playlists.reorderPlaylistTracks(
        playlistId: playlistId,
        trackIds: [secondTrackId, outsideTrackId],
      ),
      throwsArgumentError,
    );
    final entries = await fixture.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;

    expect(entries.map((entry) => entry.trackId), [
      firstTrackId,
      secondTrackId,
    ]);
    expect(entries.map((entry) => entry.position), [0, 1]);
  });

  test('reorder rejects incomplete order without deleting entries', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final firstTrackId = await fixture.addTrack('First');
    final secondTrackId = await fixture.addTrack('Second');
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Complete');
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      firstTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      secondTrackId,
    );

    await expectLater(
      fixture.repositories.playlists.reorderPlaylistTracks(
        playlistId: playlistId,
        trackIds: [secondTrackId],
      ),
      throwsArgumentError,
    );
    final entries = await fixture.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;

    expect(entries.map((entry) => entry.trackId), [
      firstTrackId,
      secondTrackId,
    ]);
    expect(entries, hasLength(2));
  });

  test('reorder does not affect tracks table or audio file paths', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final firstTrackId = await fixture.addTrack(
      'First',
      filePath: '/music/original-first.flac',
    );
    final secondTrackId = await fixture.addTrack(
      'Second',
      filePath: '/music/original-second.flac',
    );
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Files');
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      firstTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      secondTrackId,
    );

    await fixture.repositories.playlists.reorderPlaylistTracks(
      playlistId: playlistId,
      trackIds: [secondTrackId, firstTrackId],
    );

    final firstTrack = await fixture.repositories.tracks.findById(firstTrackId);
    final secondTrack =
        await fixture.repositories.tracks.findById(secondTrackId);

    expect(firstTrack?.filePath, '/music/original-first.flac');
    expect(secondTrack?.filePath, '/music/original-second.flac');
  });

  test('deleting a track removes its playlist entry', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final trackId = await fixture.addTrack('Track One');
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Mix');
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      trackId,
    );

    await fixture.repositories.tracks.deleteTrack(trackId);

    expect(
      await fixture.repositories.playlists
          .watchPlaylistTracks(playlistId)
          .first,
      isEmpty,
    );
  });

  test('deleting playlist does not delete library tracks', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final trackId = await fixture.addTrack('Track One');
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Mix');
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      trackId,
    );

    await fixture.repositories.playlists.deletePlaylist(playlistId);

    expect(await fixture.repositories.tracks.findById(trackId), isNotNull);
  });

  test('missing and disabled-folder playlist tracks are unavailable', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final missingTrackId = await fixture.addTrack(
      'Missing',
      isMissing: true,
    );
    final disabledFolderId = await fixture.addFolder(
      '/music/disabled',
      isEnabled: false,
    );
    final disabledTrackId = await fixture.addTrack(
      'Disabled',
      folderId: disabledFolderId,
      filePath: '/music/disabled/disabled.flac',
    );
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Unavailable');
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      missingTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      disabledTrackId,
    );

    final entries = await fixture.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;

    expect(entries.map((entry) => entry.isPlayable), [false, false]);
    expect(
      entries.map((entry) => entry.unavailableReason),
      ['Отсутствует', 'Папка отключена'],
    );
  });

  test('adding playlist to queue queues playable tracks in playlist order',
      () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);
    final firstTrackId = await fixture.addTrack('First');
    final missingTrackId = await fixture.addTrack('Missing', isMissing: true);
    final secondTrackId = await fixture.addTrack('Second');
    final playlistId =
        await fixture.repositories.playlists.createPlaylist('Queue');
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      firstTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      missingTrackId,
    );
    await fixture.repositories.playlists.addTrackToPlaylist(
      playlistId,
      secondTrackId,
    );
    await fixture.repositories.playlists.reorderPlaylistTracks(
      playlistId: playlistId,
      trackIds: [secondTrackId, missingTrackId, firstTrackId],
    );
    final entries = await fixture.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;
    final queuedTitles = <String?>[];

    final queuedCount = await addPlaylistEntriesToQueue(
      entries: entries,
      addToQueue: (track) async {
        queuedTitles.add(track.title);
      },
    );

    expect(queuedCount, 2);
    expect(queuedTitles, ['Second', 'First']);
  });
}

Future<_PlaylistRepositoryFixture> _createFixture() async {
  final database = AppDatabase(NativeDatabase.memory());
  final repositories = DriftRepositories(database);
  final now = DateTime(2026, 5);
  final folderId = await repositories.libraryFolders.upsertFolder(
    LibraryFolder(
      path: '/music',
      displayName: 'Music',
      createdAt: now,
      updatedAt: now,
    ),
  );

  return _PlaylistRepositoryFixture(
    database: database,
    repositories: repositories,
    defaultFolderId: folderId,
    now: now,
  );
}

final class _PlaylistRepositoryFixture {
  const _PlaylistRepositoryFixture({
    required this.database,
    required this.repositories,
    required this.defaultFolderId,
    required this.now,
  });

  final AppDatabase database;
  final DriftRepositories repositories;
  final int defaultFolderId;
  final DateTime now;

  Future<int> addFolder(String path, {bool isEnabled = true}) {
    return repositories.libraryFolders.upsertFolder(
      LibraryFolder(
        path: path,
        displayName: path.split('/').last,
        isEnabled: isEnabled,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<int> addTrack(
    String title, {
    int? folderId,
    String? filePath,
    bool isMissing = false,
    String? artworkPath,
    String? artworkHash,
    String? artworkMimeType,
  }) {
    final normalizedTitle = title.toLowerCase().replaceAll(' ', '-');
    return repositories.tracks.upsertTrack(
      Track(
        libraryFolderId: folderId ?? defaultFolderId,
        filePath: filePath ?? '/music/$normalizedTitle.flac',
        title: title,
        artist: 'Artist',
        album: 'Album',
        artworkPath: artworkPath,
        artworkHash: artworkHash,
        artworkMimeType: artworkMimeType,
        isMissing: isMissing,
        addedAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> close() => database.close();
}
