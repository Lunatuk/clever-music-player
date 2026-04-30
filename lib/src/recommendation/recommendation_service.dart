import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';

final class RecommendationService {
  const RecommendationService({
    required this.tracks,
    required this.trackUserState,
    required this.playbackEvents,
  });

  final TrackRepository tracks;
  final TrackUserStateRepository trackUserState;
  final PlaybackEventRepository playbackEvents;

  Future<List<RecommendationResult>> recommend({
    WaveMode waveMode = WaveMode.balanced,
    int limit = 25,
    DateTime? now,
  }) async {
    if (limit <= 0) {
      return const [];
    }

    final generatedAt = now ?? DateTime.now();
    final candidates = await tracks.listTracks(limit: limit * 4);
    final trackIds = candidates.map((track) => track.id).whereType<int>();
    final states = await trackUserState.findByTrackIds(trackIds);
    final results = <RecommendationResult>[];

    for (final track in candidates) {
      final state = track.id == null ? null : states[track.id];
      if (state?.isHidden ?? false) {
        continue;
      }

      final scored = _scoreTrack(
        track: track,
        state: state,
        waveMode: waveMode,
        generatedAt: generatedAt,
      );

      results.add(scored);
    }

    results.sort((left, right) => right.score.compareTo(left.score));
    return results.take(limit).toList(growable: false);
  }

  RecommendationResult _scoreTrack({
    required Track track,
    required TrackUserState? state,
    required WaveMode waveMode,
    required DateTime generatedAt,
  }) {
    final reasons = <RecommendationScoreReason>[
      const RecommendationScoreReason(
        code: 'base_candidate',
        message: 'Track is available in the local library.',
        weight: 10,
      ),
    ];

    var score = 10.0;

    void addReason(String code, String message, double weight) {
      score += weight;
      reasons.add(
        RecommendationScoreReason(
          code: code,
          message: message,
          weight: weight,
        ),
      );
    }

    if (track.artist != null || track.album != null) {
      addReason(
        'metadata_present',
        'Track has usable metadata for future library-aware scoring.',
        2,
      );
    }

    if (state == null) {
      addReason(
        'no_user_state',
        'No listening history yet; keep it eligible for exploration.',
        _discoveryWeight(waveMode),
      );
    } else {
      if (state.isFavorite) {
        addReason(
          'favorite',
          'Marked as a favorite by the listener.',
          waveMode == WaveMode.favorites ? 45 : 25,
        );
      }

      final rating = state.rating;
      if (rating != null && rating > 0) {
        addReason(
          'rating',
          'User rating contributes to the score.',
          rating.clamp(0, 5).toDouble() * 4,
        );
      }

      if (state.playCount == 0) {
        addReason(
          'unplayed',
          'Never played locally; useful for discovery.',
          _discoveryWeight(waveMode),
        );
      }

      if (state.skipCount > 0) {
        addReason(
          'skip_penalty',
          'Recent skips reduce confidence until behavior changes.',
          -(state.skipCount.clamp(1, 10).toDouble() * 2),
        );
      }

      if (state.userScoreBoost != 0) {
        addReason(
          'manual_boost',
          'Manual preference boost from local user state.',
          state.userScoreBoost,
        );
      }

      final lastPlayedAt = state.lastPlayedAt;
      if (lastPlayedAt != null) {
        final daysSincePlayed = generatedAt.difference(lastPlayedAt).inDays;
        if (daysSincePlayed >= 14) {
          addReason(
            'not_recently_played',
            'Not played recently, so it can re-enter rotation.',
            waveMode == WaveMode.deepCuts ? 18 : 6,
          );
        } else if (waveMode == WaveMode.discovery) {
          addReason(
            'recent_play_penalty',
            'Recently played tracks are deprioritized in discovery.',
            -8,
          );
        }
      }

      if (waveMode == WaveMode.focus && state.skipCount == 0) {
        addReason(
          'focus_low_skip',
          'No skip history, suitable for a lower-friction queue.',
          8,
        );
      }

      if (waveMode == WaveMode.deepCuts &&
          state.playCount > 0 &&
          state.playCount <= 3) {
        addReason(
          'deep_cut',
          'Low play count makes it a candidate for deep cuts.',
          14,
        );
      }
    }

    return RecommendationResult(
      track: track,
      score: score,
      waveMode: waveMode,
      reasons: reasons,
      generatedAt: generatedAt,
    );
  }

  double _discoveryWeight(WaveMode waveMode) {
    return switch (waveMode) {
      WaveMode.discovery => 25,
      WaveMode.deepCuts => 12,
      WaveMode.balanced => 8,
      WaveMode.focus => 2,
      WaveMode.favorites => -5,
    };
  }
}
