import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/manual_track_metadata.dart';
import 'package:clever_music_player/src/recommendation/recommendation_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual metadata update only changes metadata fields', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final now = DateTime(2026);
    final updatedAt = DateTime(2026, 5);
    final folderId = await repositories.libraryFolders.upsertFolder(
      LibraryFolder(
        path: '/music',
        displayName: 'Music',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final trackId = await repositories.tracks.upsertTrack(
      Track(
        libraryFolderId: folderId,
        stableId: 'stable-track',
        filePath: '/music/original.mp3',
        contentHash: 'hash',
        title: 'Original title',
        artist: 'Original artist',
        album: 'Original album',
        albumArtist: 'Original album artist',
        genre: 'Original genre',
        codec: 'mp3',
        duration: const Duration(minutes: 3),
        trackNumber: 1,
        discNumber: 1,
        year: 2001,
        metadataSource: MetadataSource.embeddedTags,
        metadataConfidence: 0.95,
        fileSizeBytes: 123,
        modifiedAt: now,
        lastSeenAt: now,
        addedAt: now,
        updatedAt: now,
      ),
    );
    await repositories.trackUserState.upsertState(
      TrackUserState(
        trackId: trackId,
        isFavorite: true,
        rating: 5,
        playCount: 7,
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

    await repositories.tracks.updateTrackMetadata(
      TrackMetadataUpdate(
        trackId: trackId,
        title: 'Manual title',
        artist: 'Manual artist',
        album: 'Manual album',
        albumArtist: 'Manual album artist',
        genre: null,
        year: 2026,
        trackNumber: 4,
        discNumber: 2,
        updatedAt: updatedAt,
      ),
    );

    final updatedTrack = await repositories.tracks.findById(trackId);
    expect(updatedTrack, isNotNull);
    expect(updatedTrack!.id, trackId);
    expect(updatedTrack.libraryFolderId, folderId);
    expect(updatedTrack.stableId, 'stable-track');
    expect(updatedTrack.filePath, '/music/original.mp3');
    expect(updatedTrack.contentHash, 'hash');
    expect(updatedTrack.title, 'Manual title');
    expect(updatedTrack.artist, 'Manual artist');
    expect(updatedTrack.album, 'Manual album');
    expect(updatedTrack.albumArtist, 'Manual album artist');
    expect(updatedTrack.genre, isNull);
    expect(updatedTrack.year, 2026);
    expect(updatedTrack.trackNumber, 4);
    expect(updatedTrack.discNumber, 2);
    expect(updatedTrack.codec, 'mp3');
    expect(updatedTrack.duration, const Duration(minutes: 3));
    expect(updatedTrack.fileSizeBytes, 123);
    expect(updatedTrack.modifiedAt, now);
    expect(updatedTrack.metadataSource, MetadataSource.manual);
    expect(updatedTrack.metadataConfidence, 1.0);
    expect(updatedTrack.updatedAt, updatedAt);

    final state = await repositories.trackUserState.findByTrackId(trackId);
    expect(state?.isFavorite, isTrue);
    expect(state?.rating, 5);
    expect(state?.playCount, 7);

    final events = await repositories.playbackEvents.recentForTrack(trackId);
    expect(events, hasLength(1));
    expect(events.single.type, PlaybackEventType.started);
  });

  test('manual metadata form trims text and validates integer fields', () {
    final update = buildManualTrackMetadataUpdate(
      trackId: 1,
      updatedAt: DateTime(2026),
      title: '  Title  ',
      artist: '   ',
      album: ' Album ',
      albumArtist: '',
      genre: ' Genre ',
      year: ' 2026 ',
      trackNumber: ' 3 ',
      discNumber: ' 1 ',
    );

    expect(update.title, 'Title');
    expect(update.artist, isNull);
    expect(update.album, 'Album');
    expect(update.albumArtist, isNull);
    expect(update.genre, 'Genre');
    expect(update.year, 2026);
    expect(update.trackNumber, 3);
    expect(update.discNumber, 1);

    expect(validateManualMetadataTitle(' '), 'Title is required.');
    expect(validateOptionalMetadataYear('twenty'), 'Enter a valid year.');
    expect(
      validateOptionalPositiveMetadataInteger('0', 'Track number'),
      'Track number must be a positive integer.',
    );
    expect(
      validateOptionalPositiveMetadataInteger('-1', 'Disc number'),
      'Disc number must be a positive integer.',
    );
  });

  test('recommendation repeat guard uses manually edited artist', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final now = DateTime(2026);

    final recentTrackId = await repositories.tracks.upsertTrack(
      _track(title: 'Recent', artist: 'Old Artist', now: now),
    );
    final sameManualArtistId = await repositories.tracks.upsertTrack(
      _track(title: 'Same manual artist', artist: 'Manual Artist', now: now),
    );
    await repositories.tracks.upsertTrack(
      _track(title: 'Fresh', artist: 'Fresh Artist', now: now),
    );
    await repositories.tracks.updateTrackMetadata(
      TrackMetadataUpdate(
        trackId: recentTrackId,
        title: 'Recent',
        artist: 'Manual Artist',
        album: 'Recent Album',
        updatedAt: now,
      ),
    );
    await repositories.playbackEvents.addEvent(
      PlaybackEvent(
        trackId: recentTrackId,
        type: PlaybackEventType.started,
        occurredAt: now,
      ),
    );
    final recommendation = RecommendationService(
      tracks: repositories.tracks,
      trackUserState: repositories.trackUserState,
      playbackEvents: repositories.playbackEvents,
    );

    final results = await recommendation.recommend(
      waveMode: WaveMode.focus,
      now: now,
    );
    final sameArtist = results.firstWhere(
      (result) => result.track.id == sameManualArtistId,
    );

    expect(
      sameArtist.reasons.map((reason) => reason.code),
      contains('artist_repeat_penalty'),
    );
  });
}

Track _track({
  required String title,
  required String artist,
  required DateTime now,
}) {
  return Track(
    filePath: '/music/$title.mp3',
    title: title,
    artist: artist,
    album: 'Album',
    addedAt: now,
    updatedAt: now,
  );
}
