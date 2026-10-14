import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/recommendation/recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recommend returns scored local tracks with reasons', () async {
    final now = DateTime(2026);
    final service = RecommendationService(
      tracks: _FakeTrackRepository([
        _track(id: 1, title: 'Known Favorite', now: now),
        _track(id: 2, title: 'Unplayed Track', now: now),
      ]),
      trackUserState: _FakeTrackUserStateRepository({
        1: TrackUserState(
          trackId: 1,
          isFavorite: true,
          rating: 5,
          playCount: 10,
          updatedAt: now,
        ),
      }),
      playbackEvents: const _FakePlaybackEventRepository(),
    );

    final results = await service.recommend(now: now);

    expect(results, hasLength(2));
    expect(results.first.track.id, 1);
    expect(
      results.first.reasons.map((reason) => reason.code),
      containsAll(['technical_base_score', 'favorite', 'rating']),
    );
    expect(
      results.first.reasons
          .firstWhere((reason) => reason.code == 'technical_base_score')
          .weight,
      1,
    );
    expect(
      results.first.reasons
          .firstWhere((reason) => reason.code == 'favorite')
          .weight,
      2,
    );
    expect(
      results.first.reasons
          .firstWhere((reason) => reason.code == 'rating')
          .weight,
      8,
    );
    expect(
      results.first.reasons
          .firstWhere((reason) => reason.code == 'rating')
          .message,
      'Ручная оценка влияет на итоговый балл.',
    );
  });

  test('recommend excludes hidden tracks', () async {
    final now = DateTime(2026);
    final service = RecommendationService(
      tracks: _FakeTrackRepository([
        _track(id: 1, title: 'Hidden Track', now: now),
        _track(id: 2, title: 'Visible Track', now: now),
      ]),
      trackUserState: _FakeTrackUserStateRepository({
        1: TrackUserState(
          trackId: 1,
          isHidden: true,
          updatedAt: now,
        ),
      }),
      playbackEvents: const _FakePlaybackEventRepository(),
    );

    final results = await service.recommend(now: now);

    expect(results, hasLength(1));
    expect(results.single.track.id, 2);
    expect(
      results.single.reasons.map((reason) => reason.code),
      contains('no_user_state'),
    );
  });

  test('recommend excludes missing and low-rated tracks', () async {
    final now = DateTime(2026);
    final service = RecommendationService(
      tracks: _FakeTrackRepository([
        _track(id: 1, title: 'Missing Track', now: now, isMissing: true),
        _track(id: 2, title: 'Low Rated Track', now: now),
        _track(id: 3, title: 'Playable Track', now: now),
      ]),
      trackUserState: _FakeTrackUserStateRepository({
        2: TrackUserState(trackId: 2, rating: 1, updatedAt: now),
      }),
      playbackEvents: const _FakePlaybackEventRepository(),
    );

    final results = await service.recommend(now: now);

    expect(results, hasLength(1));
    expect(results.single.track.id, 3);
    expect(results.single.candidatesConsidered, 1);
  });

  test('recommend uses recent history to reduce repetition', () async {
    final now = DateTime(2026);
    final service = RecommendationService(
      tracks: _FakeTrackRepository([
        _track(id: 1, title: 'Recent Track', artist: 'Artist A', now: now),
        _track(id: 2, title: 'Same Artist', artist: 'Artist A', now: now),
        _track(id: 3, title: 'Different Artist', artist: 'Artist B', now: now),
      ]),
      trackUserState: const _FakeTrackUserStateRepository({}),
      playbackEvents: _FakePlaybackEventRepository([
        PlaybackEvent(
          trackId: 1,
          type: PlaybackEventType.started,
          occurredAt: now,
        ),
      ]),
    );

    final results = await service.recommend(
      waveMode: WaveMode.focus,
      now: now,
    );

    expect(results.first.track.id, 3);
    expect(
      results
          .firstWhere((result) => result.track.id == 2)
          .reasons
          .map((reason) => reason.code),
      contains('artist_repeat_penalty'),
    );
    expect(
      results
          .firstWhere((result) => result.track.id == 1)
          .reasons
          .map((reason) => reason.code),
      contains('recent_play_penalty'),
    );
  });

  test('favorites mode boosts liked tracks without extreme weight', () async {
    final now = DateTime(2026);
    final service = RecommendationService(
      tracks: _FakeTrackRepository([
        _track(id: 1, title: 'Favorite', now: now),
        _track(id: 2, title: 'Other', now: now),
      ]),
      trackUserState: _FakeTrackUserStateRepository({
        1: TrackUserState(
          trackId: 1,
          isFavorite: true,
          playCount: 10,
          updatedAt: now,
        ),
        2: TrackUserState(
          trackId: 2,
          playCount: 10,
          updatedAt: now,
        ),
      }),
      playbackEvents: const _FakePlaybackEventRepository(),
    );

    final results = await service.recommend(
      waveMode: WaveMode.favorites,
      now: now,
    );
    final favoriteReason = results
        .firstWhere((result) => result.track.id == 1)
        .reasons
        .firstWhere((reason) => reason.code == 'favorite');

    expect(results.first.track.id, 1);
    expect(favoriteReason.weight, 12);
  });

  test('liked track in balanced mode gets favorite boost without rating',
      () async {
    final now = DateTime(2026);
    final service = RecommendationService(
      tracks: _FakeTrackRepository([
        _track(id: 1, title: 'Liked', now: now),
        _track(id: 2, title: 'Neutral', now: now),
      ]),
      trackUserState: _FakeTrackUserStateRepository({
        1: TrackUserState(
          trackId: 1,
          isFavorite: true,
          playCount: 10,
          updatedAt: now,
        ),
        2: TrackUserState(
          trackId: 2,
          playCount: 10,
          updatedAt: now,
        ),
      }),
      playbackEvents: const _FakePlaybackEventRepository(),
    );

    final results = await service.recommend(now: now);
    final likedResult = results.firstWhere((result) => result.track.id == 1);

    expect(
      likedResult.reasons.map((reason) => reason.code),
      contains('favorite'),
    );
    expect(
      likedResult.reasons.map((reason) => reason.code),
      isNot(contains('rating')),
    );
    expect(
      likedResult.reasons
          .firstWhere((reason) => reason.code == 'favorite')
          .weight,
      2,
    );
  });

  test('liked track does not dominate a normal library in balanced mode',
      () async {
    final now = DateTime(2026);
    final tracks = [
      _track(id: 1, title: 'Liked Played Track', now: now),
      for (var id = 2; id <= 11; id++)
        _track(id: id, title: 'Unplayed $id', now: now),
    ];
    final service = RecommendationService(
      tracks: _FakeTrackRepository(tracks),
      trackUserState: _FakeTrackUserStateRepository({
        1: TrackUserState(
          trackId: 1,
          isFavorite: true,
          playCount: 20,
          updatedAt: now,
        ),
      }),
      playbackEvents: const _FakePlaybackEventRepository(),
    );

    final results = await service.recommend(now: now);

    expect(results.first.track.id, isNot(1));
    expect(
      results
          .firstWhere((result) => result.track.id == 1)
          .reasons
          .firstWhere((reason) => reason.code == 'favorite')
          .weight,
      2,
    );
  });

  test('skip penalty weakens when the last skip is old', () async {
    final now = DateTime(2026);
    final service = RecommendationService(
      tracks: _FakeTrackRepository([
        _track(id: 1, title: 'Recently Skipped', now: now),
        _track(id: 2, title: 'Old Skip', now: now),
      ]),
      trackUserState: _FakeTrackUserStateRepository({
        1: TrackUserState(
          trackId: 1,
          playCount: 5,
          skipCount: 1,
          lastSkippedAt: now.subtract(const Duration(hours: 12)),
          updatedAt: now,
        ),
        2: TrackUserState(
          trackId: 2,
          playCount: 5,
          skipCount: 1,
          lastSkippedAt: now.subtract(const Duration(days: 30)),
          updatedAt: now,
        ),
      }),
      playbackEvents: const _FakePlaybackEventRepository(),
    );

    final results = await service.recommend(now: now);
    final recentSkip = results.firstWhere((result) => result.track.id == 1);
    final oldSkip = results.firstWhere((result) => result.track.id == 2);
    final recentPenalty = recentSkip.reasons
        .firstWhere((reason) => reason.code == 'skip_penalty')
        .weight;
    final oldPenalty = oldSkip.reasons
        .firstWhere((reason) => reason.code == 'skip_penalty')
        .weight;

    expect(results.map((result) => result.track.id), containsAll([1, 2]));
    expect(recentPenalty, lessThan(oldPenalty));
    expect(oldPenalty, greaterThanOrEqualTo(-1));
  });

  test('recent play penalty comes from playback history, not permanent state',
      () async {
    final now = DateTime(2026);
    final service = RecommendationService(
      tracks: _FakeTrackRepository([
        _track(id: 1, title: 'Played In State', now: now),
      ]),
      trackUserState: _FakeTrackUserStateRepository({
        1: TrackUserState(
          trackId: 1,
          playCount: 20,
          lastPlayedAt: now,
          updatedAt: now,
        ),
      }),
      playbackEvents: const _FakePlaybackEventRepository(),
    );

    final results = await service.recommend(now: now);

    expect(results.single.track.id, 1);
    expect(
      results.single.reasons.map((reason) => reason.code),
      isNot(contains('recent_play_penalty')),
    );
  });
}

Track _track({
  required int id,
  required String title,
  String artist = 'Local Artist',
  bool isMissing = false,
  required DateTime now,
}) {
  return Track(
    id: id,
    filePath: '/music/$title.flac',
    title: title,
    artist: artist,
    isMissing: isMissing,
    addedAt: now,
    updatedAt: now,
  );
}

final class _FakeTrackRepository implements TrackRepository {
  const _FakeTrackRepository(this._tracks);

  final List<Track> _tracks;

  @override
  Future<List<Track>> listTracks({
    int limit = 100,
    int offset = 0,
    bool includeDisabledFolders = false,
  }) async {
    return _tracks.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<List<Track>> listTracksByLibraryFolder(
    int libraryFolderId, {
    bool includeMissing = true,
  }) async {
    return _tracks
        .where((track) => track.libraryFolderId == libraryFolderId)
        .where((track) => includeMissing || !track.isMissing)
        .toList(growable: false);
  }

  @override
  Future<void> deleteTrack(int id) async {}

  @override
  Future<void> deleteTracksByLibraryFolder(int libraryFolderId) async {}

  @override
  Future<Track?> findById(int id) async {
    for (final track in _tracks) {
      if (track.id == id) {
        return track;
      }
    }
    return null;
  }

  @override
  Future<Track?> findByStableId(String stableId) async {
    for (final track in _tracks) {
      if (track.stableId == stableId) {
        return track;
      }
    }
    return null;
  }

  @override
  Future<Track?> findByPath(String filePath) async {
    for (final track in _tracks) {
      if (track.filePath == filePath) {
        return track;
      }
    }
    return null;
  }

  @override
  Future<int> upsertTrack(Track track) async {
    return track.id ?? 0;
  }

  @override
  Future<void> updateTrackMetadata(TrackMetadataUpdate metadata) async {}

  @override
  Future<void> updateCustomArtwork({
    required int trackId,
    required String path,
    required String hash,
    required String? mimeType,
    required DateTime updatedAt,
  }) async {}

  @override
  Future<void> clearCustomArtwork({
    required int trackId,
    required DateTime updatedAt,
  }) async {}

  @override
  Stream<List<Track>> watchTracks({
    int limit = 100,
    bool includeDisabledFolders = false,
  }) {
    return Stream.value(_tracks.take(limit).toList(growable: false));
  }

  @override
  Stream<List<Track>> watchAllTracks({
    bool includeMissing = false,
    bool includeDisabledFolders = false,
  }) {
    return Stream.value(
      _tracks
          .where((track) => includeMissing || !track.isMissing)
          .toList(growable: false),
    );
  }
}

final class _FakeTrackUserStateRepository implements TrackUserStateRepository {
  const _FakeTrackUserStateRepository(this._states);

  final Map<int, TrackUserState> _states;

  @override
  Future<TrackUserState> toggleFeedback(int trackId, TrackFeedback feedback,
          {required DateTime updatedAt}) =>
      throw UnsupportedError('Read-only fake');

  @override
  Future<void> deleteState(int trackId) async {}

  @override
  Future<TrackUserState?> findByTrackId(int trackId) async {
    return _states[trackId];
  }

  @override
  Future<Map<int, TrackUserState>> findByTrackIds(
    Iterable<int> trackIds,
  ) async {
    return {
      for (final id in trackIds)
        if (_states[id] != null) id: _states[id]!,
    };
  }

  @override
  Future<void> upsertState(TrackUserState state) async {}

  @override
  Stream<TrackUserState?> watchTrackState(int trackId) {
    return Stream.value(_states[trackId]);
  }

  @override
  Stream<Map<int, TrackUserState>> watchTrackStatesByTrackIds(
    Iterable<int> trackIds,
  ) {
    return Stream.value({
      for (final id in trackIds)
        if (_states[id] != null) id: _states[id]!,
    });
  }
}

final class _FakePlaybackEventRepository implements PlaybackEventRepository {
  const _FakePlaybackEventRepository([this._events = const []]);

  final List<PlaybackEvent> _events;

  @override
  Future<int> recordEvent(PlaybackEvent event) =>
      throw UnsupportedError('Read-only fake');

  @override
  Future<int> addEvent(PlaybackEvent event) async {
    return event.id ?? 0;
  }

  @override
  Future<List<PlaybackEvent>> recentEvents({int limit = 100}) async {
    return _events.reversed.take(limit).toList(growable: false);
  }

  @override
  Future<List<PlaybackEvent>> recentForTrack(int trackId, {int limit = 50}) {
    return Future.value(
      _events
          .where((event) => event.trackId == trackId)
          .take(limit)
          .toList(growable: false),
    );
  }
}
