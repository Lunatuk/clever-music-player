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
      containsAll(['base_candidate', 'favorite', 'rating']),
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
}

Track _track({
  required int id,
  required String title,
  required DateTime now,
}) {
  return Track(
    id: id,
    filePath: '/music/$title.flac',
    title: title,
    artist: 'Local Artist',
    addedAt: now,
    updatedAt: now,
  );
}

final class _FakeTrackRepository implements TrackRepository {
  const _FakeTrackRepository(this._tracks);

  final List<Track> _tracks;

  @override
  Future<List<Track>> listTracks({int limit = 100, int offset = 0}) async {
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
  Stream<List<Track>> watchTracks({int limit = 100}) {
    return Stream.value(_tracks.take(limit).toList(growable: false));
  }

  @override
  Stream<List<Track>> watchAllTracks({bool includeMissing = false}) {
    return Stream.value(
      _tracks
          .where((track) => includeMissing || !track.isMissing)
          .toList(growable: false),
    );
  }
}

final class _FakeTrackUserStateRepository
    implements TrackUserStateRepository {
  const _FakeTrackUserStateRepository(this._states);

  final Map<int, TrackUserState> _states;

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
}

final class _FakePlaybackEventRepository implements PlaybackEventRepository {
  const _FakePlaybackEventRepository();

  @override
  Future<int> addEvent(PlaybackEvent event) async {
    return event.id ?? 0;
  }

  @override
  Future<List<PlaybackEvent>> recentEvents({int limit = 100}) async {
    return const [];
  }

  @override
  Future<List<PlaybackEvent>> recentForTrack(int trackId, {int limit = 50}) {
    return Future.value(const []);
  }
}
