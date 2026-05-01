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
    int recentHistoryLimit = 50,
    DateTime? now,
  }) async {
    if (limit <= 0) {
      return const [];
    }

    final generatedAt = now ?? DateTime.now();
    final candidates = await _listAllCandidateTracks();
    final trackIds = candidates.map((track) => track.id).whereType<int>();
    final states = await trackUserState.findByTrackIds(trackIds);
    final recentEvents = await playbackEvents.recentEvents(
      limit: recentHistoryLimit,
    );

    return recommendFromInput(
      RecommendationInput(
        tracks: candidates,
        userStates: states,
        recentEvents: recentEvents,
        waveMode: waveMode,
        limit: limit,
        generatedAt: generatedAt,
      ),
    );
  }

  List<RecommendationResult> recommendFromInput(RecommendationInput input) {
    if (input.limit <= 0) {
      return const [];
    }

    final candidates = input.tracks.where((track) => !track.isMissing).toList();
    final history = _RecommendationHistory.from(
      recentEvents: input.recentEvents,
      tracksById: {
        for (final track in candidates)
          if (track.id != null) track.id!: track,
      },
    );
    final results = <RecommendationResult>[];

    for (final track in candidates) {
      final state = track.id == null ? null : input.userStates[track.id];
      if (_isExcludedByUserState(state)) {
        continue;
      }

      final scored = _scoreTrack(
        track: track,
        state: state,
        history: history,
        waveMode: input.waveMode,
        generatedAt: input.generatedAt,
      );

      results.add(scored);
    }

    results.sort((left, right) => right.score.compareTo(left.score));
    final candidatesConsidered = results.length;
    return results
        .take(input.limit)
        .map(
          (result) => result.copyWith(
            candidatesConsidered: candidatesConsidered,
          ),
        )
        .toList(growable: false);
  }

  RecommendationResult _scoreTrack({
    required Track track,
    required TrackUserState? state,
    required _RecommendationHistory history,
    required WaveMode waveMode,
    required DateTime generatedAt,
  }) {
    final reasons = <RecommendationScoreReason>[
      const RecommendationScoreReason(
        code: 'technical_base_score',
        message: 'Base candidate score.',
        weight: 1,
      ),
    ];

    var score = 1.0;

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

    final trackId = track.id;
    final recentTrackRank =
        trackId == null ? null : history.recentTrackRank[trackId];
    if (recentTrackRank != null) {
      addReason(
        'recent_play_penalty',
        'Played recently; lower priority keeps the wave varied.',
        _recentTrackPenalty(recentTrackRank),
      );
    }

    final artistKey = _normalizeKey(track.artist ?? track.albumArtist);
    final recentArtistRank =
        artistKey == null ? null : history.recentArtistRank[artistKey];
    if (recentArtistRank != null && recentTrackRank != 0) {
      addReason(
        'artist_repeat_penalty',
        'Recent listening already included this artist.',
        -_repeatPenalty(waveMode, recentArtistRank, artist: true),
      );
    }

    final albumKey = _normalizeKey(track.album);
    final recentAlbumRank =
        albumKey == null ? null : history.recentAlbumRank[albumKey];
    if (recentAlbumRank != null && recentTrackRank != 0) {
      addReason(
        'album_repeat_penalty',
        'Recent listening already included this album.',
        -_repeatPenalty(waveMode, recentAlbumRank, artist: false),
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
          _favoriteWeight(waveMode),
        );
      }

      final rating = state.rating;
      if (rating != null && rating > 0) {
        addReason(
          'rating',
          'Manual rating contributes to the score.',
          (rating.clamp(0, 5).toDouble() / 5) * 8,
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
        final skipPenalty = _skipPenalty(state, generatedAt);
        if (skipPenalty != 0) {
          addReason(
            'skip_penalty',
            'Recent skip history temporarily reduces confidence.',
            skipPenalty,
          );
        }
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

  double _favoriteWeight(WaveMode waveMode) {
    return switch (waveMode) {
      WaveMode.balanced => 2,
      WaveMode.discovery => 0,
      WaveMode.focus => 2,
      WaveMode.favorites => 12,
      WaveMode.deepCuts => 2,
    };
  }

  Future<List<Track>> _listAllCandidateTracks() async {
    const pageSize = 500;
    const maxCandidates = 10000;
    final candidates = <Track>[];
    var offset = 0;

    while (candidates.length < maxCandidates) {
      final page = await tracks.listTracks(limit: pageSize, offset: offset);
      if (page.isEmpty) {
        break;
      }

      candidates.addAll(page);
      if (page.length < pageSize) {
        break;
      }
      offset += page.length;
    }

    return candidates;
  }

  bool _isExcludedByUserState(TrackUserState? state) {
    if (state == null) {
      return false;
    }
    if (state.isHidden) {
      return true;
    }

    final rating = state.rating;
    return rating != null && rating <= 1;
  }

  double _recentTrackPenalty(int rank) {
    return switch (rank) {
      0 => -100,
      <= 2 => -60,
      <= 5 => -35,
      <= 10 => -18,
      _ => -8,
    };
  }

  double _repeatPenalty(
    WaveMode waveMode,
    int rank, {
    required bool artist,
  }) {
    final basePenalty = artist ? 10.0 : 7.0;
    final recencyMultiplier = rank <= 2 ? 1.4 : 1.0;
    final modeMultiplier = switch (waveMode) {
      WaveMode.focus => 1.8,
      WaveMode.discovery => 1.25,
      WaveMode.deepCuts => 1.1,
      WaveMode.balanced => 1,
      WaveMode.favorites => 0.5,
    };

    return basePenalty * recencyMultiplier * modeMultiplier;
  }

  double _skipPenalty(TrackUserState state, DateTime generatedAt) {
    final skipCount = state.skipCount;
    if (skipCount <= 0) {
      return 0;
    }

    var penalty = -((skipCount - 1).clamp(0, 8).toDouble() * 0.5);
    penalty = penalty.clamp(-4, 0).toDouble();

    final lastSkippedAt = state.lastSkippedAt;
    if (lastSkippedAt == null) {
      return penalty;
    }

    final age = generatedAt.difference(lastSkippedAt);
    if (age <= const Duration(days: 1)) {
      return penalty - 8;
    }
    if (age <= const Duration(days: 7)) {
      return penalty - 4;
    }
    return penalty - 1;
  }
}

final class _RecommendationHistory {
  const _RecommendationHistory({
    required this.recentTrackRank,
    required this.recentArtistRank,
    required this.recentAlbumRank,
  });

  final Map<int, int> recentTrackRank;
  final Map<String, int> recentArtistRank;
  final Map<String, int> recentAlbumRank;

  static _RecommendationHistory from({
    required Iterable<PlaybackEvent> recentEvents,
    required Map<int, Track> tracksById,
  }) {
    final recentTrackRank = <int, int>{};
    final recentArtistRank = <String, int>{};
    final recentAlbumRank = <String, int>{};
    var rank = 0;

    for (final event in recentEvents) {
      if (!_countsAsRecentListening(event.type)) {
        continue;
      }

      recentTrackRank.putIfAbsent(event.trackId, () => rank);

      final track = tracksById[event.trackId];
      final artistKey = _normalizeKey(track?.artist ?? track?.albumArtist);
      if (artistKey != null) {
        recentArtistRank.putIfAbsent(artistKey, () => rank);
      }

      final albumKey = _normalizeKey(track?.album);
      if (albumKey != null) {
        recentAlbumRank.putIfAbsent(albumKey, () => rank);
      }

      rank += 1;
    }

    return _RecommendationHistory(
      recentTrackRank: recentTrackRank,
      recentArtistRank: recentArtistRank,
      recentAlbumRank: recentAlbumRank,
    );
  }

  static bool _countsAsRecentListening(PlaybackEventType type) {
    return switch (type) {
      PlaybackEventType.started ||
      PlaybackEventType.resumed ||
      PlaybackEventType.completed =>
        true,
      PlaybackEventType.paused ||
      PlaybackEventType.skipped ||
      PlaybackEventType.stopped ||
      PlaybackEventType.seeked =>
        false,
    };
  }
}

String? _normalizeKey(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}
