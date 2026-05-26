import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('reset learning state clears only recommendation state', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_learning_reset_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final audioFile = File(p.join(tempDirectory.path, 'track.mp3'));
    await audioFile.writeAsBytes([1, 2, 3], flush: true);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final now = DateTime(2026, 5);
    final folderId = await repositories.libraryFolders.upsertFolder(
      LibraryFolder(
        path: tempDirectory.path,
        displayName: 'Library',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final trackId = await repositories.tracks.upsertTrack(
      Track(
        libraryFolderId: folderId,
        filePath: audioFile.path,
        title: 'Track',
        artist: 'Artist',
        artworkPath: '/app/artwork/cover.png',
        artworkHash: 'embedded-hash',
        artworkMimeType: 'image/png',
        customArtworkPath: '/app/custom_artwork/custom.png',
        customArtworkHash: 'custom-hash',
        customArtworkMimeType: 'image/png',
        fileSizeBytes: 3,
        modifiedAt: now,
        lastSeenAt: now,
        addedAt: now,
        updatedAt: now,
      ),
    );
    final playlistId = await repositories.playlists.createPlaylist('Mix');
    await repositories.playlists.addTrackToPlaylist(playlistId, trackId);
    await repositories.trackUserState.upsertState(
      TrackUserState(
        trackId: trackId,
        isFavorite: true,
        isHidden: true,
        rating: 1,
        playCount: 12,
        skipCount: 3,
        userScoreBoost: -5,
        updatedAt: now,
      ),
    );
    await repositories.playbackEvents.addEvent(
      PlaybackEvent(
        trackId: trackId,
        type: PlaybackEventType.started,
        occurredAt: now,
      ),
    );

    await repositories.resetLearningState();

    expect(await repositories.playbackEvents.recentEvents(), isEmpty);
    expect(await repositories.trackUserState.findByTrackId(trackId), isNull);

    final tracks = await repositories.tracks.listTracks(limit: 10);
    expect(tracks, hasLength(1));
    expect(tracks.single.id, trackId);
    expect(tracks.single.artworkPath, '/app/artwork/cover.png');
    expect(tracks.single.artworkHash, 'embedded-hash');
    expect(tracks.single.customArtworkPath, '/app/custom_artwork/custom.png');
    expect(tracks.single.customArtworkHash, 'custom-hash');

    final playlists = await repositories.playlists.watchPlaylists().first;
    expect(playlists, hasLength(1));
    expect(playlists.single.id, playlistId);
    final entries =
        await repositories.playlists.watchPlaylistTracks(playlistId).first;
    expect(entries, hasLength(1));
    expect(entries.single.trackId, trackId);
    expect(await audioFile.exists(), isTrue);
  });
}
