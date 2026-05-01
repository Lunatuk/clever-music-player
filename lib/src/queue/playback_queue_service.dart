import 'dart:async';
import 'dart:math';

import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';
import '../player/player_service.dart';
import '../player/player_state.dart';
import '../recommendation/recommendation_service.dart';
import 'queue_state.dart';

const Object _unsetFeedbackValue = Object();
const int recommendationSelectionPoolLimit = 10;
const double negativeScoreSelectionTolerance = 10.0;
const double _maxSelectionWeightBoost = 12;

List<RecommendationResult> buildWeightedSelectionPool(
  List<RecommendationResult> recommendations, {
  int limit = recommendationSelectionPoolLimit,
}) {
  return buildWeightedSelectionPoolResult(
    recommendations,
    limit: limit,
  ).candidates;
}

WeightedSelectionPoolResult buildWeightedSelectionPoolResult(
  List<RecommendationResult> recommendations, {
  int limit = recommendationSelectionPoolLimit,
  double negativeScoreTolerance = negativeScoreSelectionTolerance,
}) {
  final preferred = recommendations
      .where((recommendation) => _safeScore(recommendation.score) >= 1)
      .toList(growable: false);
  if (preferred.isNotEmpty) {
    return WeightedSelectionPoolResult(
      candidates: preferred.take(limit).toList(growable: false),
    );
  }

  if (recommendations.isEmpty) {
    return WeightedSelectionPoolResult(candidates: const []);
  }

  final bestScore = recommendations
      .map((recommendation) => _safeScore(recommendation.score))
      .reduce(max);
  final minimumAllowedScore = bestScore - negativeScoreTolerance;
  final cutoffCandidates = recommendations
      .where(
        (recommendation) =>
            _safeScore(recommendation.score) >= minimumAllowedScore,
      )
      .toList(growable: false);
  final source = cutoffCandidates.isEmpty ? recommendations : cutoffCandidates;
  final cutoffApplied = cutoffCandidates.isNotEmpty &&
      cutoffCandidates.length < recommendations.length;

  return WeightedSelectionPoolResult(
    candidates: source.take(limit).toList(growable: false),
    message: cutoffApplied
        ? 'Negative score cutoff active: showing candidates within '
            '${negativeScoreTolerance.toStringAsFixed(1)} points of best '
            'available score.'
        : null,
  );
}

List<double> selectionWeightsForRecommendations(
  List<RecommendationResult> recommendations,
) {
  if (recommendations.isEmpty) {
    return const [];
  }

  final scores = [
    for (final recommendation in recommendations)
      _safeScore(recommendation.score),
  ];
  final minScore = scores.reduce(min);
  final maxScore = scores.reduce(max);

  return [
    for (final score in scores)
      selectionWeightForScore(
        score,
        minScore: minScore,
        maxScore: maxScore,
      ),
  ];
}

double selectionWeightForScore(
  double score, {
  required double minScore,
  required double maxScore,
}) {
  final safeScore = _safeScore(score);
  final safeMinScore = _safeScore(minScore);
  final safeMaxScore = _safeScore(maxScore);
  final scoreRange = safeMaxScore - safeMinScore;
  if (scoreRange <= 0) {
    return 1;
  }

  final normalized = ((safeScore - safeMinScore) / scoreRange).clamp(0.0, 1.0);
  return 1 + (_maxSelectionWeightBoost * normalized);
}

double _safeScore(double score) {
  return score.isFinite ? score : 0;
}

final class WeightedSelectionPoolResult {
  WeightedSelectionPoolResult({
    required Iterable<RecommendationResult> candidates,
    this.message,
  }) : candidates = List.unmodifiable(candidates);

  final List<RecommendationResult> candidates;
  final String? message;
}

final class PlaybackQueueService {
  PlaybackQueueService({
    required PlayerService playerService,
    required TrackRepository tracks,
    required TrackUserStateRepository trackUserState,
    required PlaybackEventRepository playbackEvents,
    required RecommendationService recommendationService,
    DateTime Function()? clock,
    double Function()? randomDouble,
  })  : _playerService = playerService,
        _tracks = tracks,
        _trackUserState = trackUserState,
        _playbackEvents = playbackEvents,
        _recommendationService = recommendationService,
        _clock = clock ?? DateTime.now,
        _randomDouble = randomDouble ?? Random().nextDouble {
    _playerSubscription = _playerService.stateStream.listen(_handlePlayerState);
    final currentTrack = _playerService.currentTrack;
    _emit(_state.copyWith(currentTrack: currentTrack));
    unawaited(_loadCurrentTrackUserState(currentTrack));
  }

  final PlayerService _playerService;
  final TrackRepository _tracks;
  final TrackUserStateRepository _trackUserState;
  final PlaybackEventRepository _playbackEvents;
  final RecommendationService _recommendationService;
  final DateTime Function() _clock;
  final double Function() _randomDouble;
  final StreamController<QueueState> _stateController =
      StreamController<QueueState>.broadcast();

  late final StreamSubscription<PlayerState> _playerSubscription;
  QueueState _state = QueueState();
  Object? _handledCompletionTrackKey;
  Object? _currentTrackStateKey;
  int _currentTrackStateGeneration = 0;
  bool _isDisposed = false;

  QueueState get state => _state;

  Stream<QueueState> get stateStream => _stateController.stream;

  Future<void> playTrackManually(Track track) async {
    if (_isDisposed) {
      return;
    }

    _emit(
      _state.copyWith(
        currentTrack: track,
        currentTrackUserState: null,
        upcomingTrack: null,
        lastRecommendationResult: null,
        recommendationCandidates: const [],
        repeatGuardMessage: null,
        selectionPoolMessage: null,
        lastError: null,
      ),
    );
    unawaited(_loadCurrentTrackUserState(track));

    await _playerService.playTrack(track);
    _syncPlayerError();
  }

  Future<void> playSmartNext() {
    return _playSmartNext();
  }

  Future<void> next() async {
    if (_isDisposed || _state.isChoosingNext) {
      return;
    }

    await _recordSkipIfNeeded(_playerService.state);
    await _playSmartNext();
  }

  void setWaveMode(WaveMode mode) {
    if (_isDisposed || mode == _state.selectedWaveMode) {
      return;
    }

    _emit(
      _state.copyWith(
        selectedWaveMode: mode,
        lastError: null,
      ),
    );
  }

  void enableWave() {
    if (_isDisposed || _state.isWaveEnabled) {
      return;
    }

    _emit(_state.copyWith(isWaveEnabled: true, lastError: null));
  }

  void disableWave() {
    if (_isDisposed || !_state.isWaveEnabled) {
      return;
    }

    _emit(_state.copyWith(isWaveEnabled: false, upcomingTrack: null));
  }

  Future<void> likeCurrentTrack() async {
    final track = _playerService.currentTrack ?? _state.currentTrack;
    if (track == null) {
      _emit(_state.copyWith(lastError: 'Select a track to like.'));
      return;
    }

    await toggleLike(track);
  }

  Future<void> dislikeCurrentTrack() async {
    final track = _playerService.currentTrack ?? _state.currentTrack;
    if (track == null) {
      _emit(_state.copyWith(lastError: 'Select a track to dislike.'));
      return;
    }

    await toggleDislike(track);
  }

  Future<void> toggleLike(Track track) async {
    await _updateTrackFeedback(
      track,
      update: (existing, trackId, now) {
        final isLiked = existing?.isFavorite ?? false;
        final isDisliked = _isDisliked(existing);
        return _copyUserState(
          existing,
          trackId: trackId,
          isFavorite: !(isLiked && !isDisliked),
          isHidden: false,
          rating: null,
          updatedAt: now,
        );
      },
      failurePrefix: 'Like was not saved',
    );
  }

  Future<void> toggleDislike(Track track) async {
    await _updateTrackFeedback(
      track,
      update: (existing, trackId, now) {
        final isLiked = existing?.isFavorite ?? false;
        final isDisliked = _isDisliked(existing);
        return _copyUserState(
          existing,
          trackId: trackId,
          isFavorite: false,
          isHidden: !(isDisliked && !isLiked),
          rating: null,
          updatedAt: now,
        );
      },
      failurePrefix: 'Dislike was not saved',
    );
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    await _playerSubscription.cancel();
    await _stateController.close();
  }

  Future<void> _playSmartNext() async {
    if (_state.isChoosingNext || _isDisposed) {
      return;
    }

    _emit(
      _state.copyWith(
        isWaveEnabled: true,
        isChoosingNext: true,
        lastError: null,
      ),
    );

    try {
      final availableTracks = await _listAvailableTracks();
      if (availableTracks.isEmpty) {
        _emit(
          _state.copyWith(
            upcomingTrack: null,
            lastRecommendationResult: null,
            recommendationCandidates: const [],
            repeatGuardMessage: null,
            selectionPoolMessage: null,
            lastError: 'No playable tracks are available in the library.',
          ),
        );
        return;
      }

      final trackIds =
          availableTracks.map((track) => track.id).whereType<int>();
      final states = await _trackUserState.findByTrackIds(trackIds);
      final recentEvents = await _playbackEvents.recentEvents(limit: 50);
      final recommendations = _recommendationService.recommendFromInput(
        RecommendationInput(
          tracks: availableTracks,
          userStates: states,
          recentEvents: recentEvents,
          waveMode: _state.selectedWaveMode,
          limit: 20,
          generatedAt: _clock(),
        ),
      );

      if (recommendations.isEmpty) {
        _emit(
          _state.copyWith(
            upcomingTrack: null,
            lastRecommendationResult: null,
            recommendationCandidates: const [],
            repeatGuardMessage: null,
            selectionPoolMessage: null,
            lastError: 'No tracks match the current wave settings.',
          ),
        );
        return;
      }

      final guarded = _applyRepeatGuard(
        recommendations: recommendations,
        recentEvents: recentEvents,
        tracks: availableTracks,
      );
      final selectionPoolResult =
          buildWeightedSelectionPoolResult(guarded.candidates);
      final selectionPool = selectionPoolResult.candidates;
      final selected = _selectWeightedRecommendation(selectionPool);
      final upcoming = _firstAlternativeTrack(selectionPool, selected.track);

      _emit(
        _state.copyWith(
          currentTrack: selected.track,
          currentTrackUserState: null,
          upcomingTrack: upcoming,
          lastRecommendationResult: selected,
          recommendationCandidates: selectionPool,
          repeatGuardMessage: guarded.message,
          selectionPoolMessage: selectionPoolResult.message,
          lastError: null,
        ),
      );
      unawaited(_loadCurrentTrackUserState(selected.track));

      await _playerService.playTrack(selected.track);
      _syncPlayerError();
    } on Object catch (error) {
      _emit(
        _state.copyWith(
          lastError:
              'Could not choose the next track: ${_describeError(error)}',
        ),
      );
    } finally {
      if (!_isDisposed) {
        _emit(_state.copyWith(isChoosingNext: false));
      }
    }
  }

  RecommendationResult _selectWeightedRecommendation(
    List<RecommendationResult> recommendations,
  ) {
    if (recommendations.length == 1) {
      return recommendations.single;
    }

    final weights = selectionWeightsForRecommendations(recommendations);
    final totalWeight = weights.fold<double>(0, (sum, weight) => sum + weight);
    if (totalWeight <= 0 || !totalWeight.isFinite) {
      return recommendations.first;
    }

    final randomValue = _randomDouble().clamp(0.0, 0.999999999).toDouble();
    var threshold = randomValue * totalWeight;
    for (var index = 0; index < recommendations.length; index++) {
      threshold -= weights[index];
      if (threshold <= 0) {
        return recommendations[index];
      }
    }

    return recommendations.last;
  }

  _RepeatGuardResult _applyRepeatGuard({
    required List<RecommendationResult> recommendations,
    required List<PlaybackEvent> recentEvents,
    required List<Track> tracks,
  }) {
    final currentTrack = _playerService.currentTrack ?? _state.currentTrack;
    final signals = _RepeatGuardSignals.from(
      currentTrack: currentTrack,
      recentEvents: recentEvents,
      tracks: tracks,
    );

    List<RecommendationResult> filter({
      required bool allowCurrentTrack,
      required bool allowRecentTracks,
      required bool allowRecentArtistAlbum,
    }) {
      return recommendations.where((recommendation) {
        final track = recommendation.track;
        if (!allowCurrentTrack && signals.isCurrentTrack(track)) {
          return false;
        }
        if (!allowRecentTracks && signals.isRecentTrack(track)) {
          return false;
        }
        if (!allowRecentArtistAlbum &&
            (signals.isRecentArtist(track) || signals.isRecentAlbum(track))) {
          return false;
        }
        return true;
      }).toList(growable: false);
    }

    final strict = filter(
      allowCurrentTrack: false,
      allowRecentTracks: false,
      allowRecentArtistAlbum: false,
    );
    if (strict.isNotEmpty) {
      return _RepeatGuardResult(
        candidates: strict,
        filteredCount: recommendations.length - strict.length,
      );
    }

    final allowArtistAlbum = filter(
      allowCurrentTrack: false,
      allowRecentTracks: false,
      allowRecentArtistAlbum: true,
    );
    if (allowArtistAlbum.isNotEmpty) {
      return _RepeatGuardResult(
        candidates: allowArtistAlbum,
        filteredCount: recommendations.length - allowArtistAlbum.length,
      );
    }

    final allowRecentTracks = filter(
      allowCurrentTrack: false,
      allowRecentTracks: true,
      allowRecentArtistAlbum: true,
    );
    if (allowRecentTracks.isNotEmpty) {
      return _RepeatGuardResult(
        candidates: allowRecentTracks,
        filteredCount: recommendations.length - allowRecentTracks.length,
      );
    }

    return _RepeatGuardResult(
      candidates: recommendations,
      filteredCount: 0,
    );
  }

  Track? _firstAlternativeTrack(
    List<RecommendationResult> recommendations,
    Track selectedTrack,
  ) {
    for (final recommendation in recommendations) {
      if (!_isSameTrack(recommendation.track, selectedTrack)) {
        return recommendation.track;
      }
    }
    return null;
  }

  Future<List<Track>> _listAvailableTracks() async {
    const pageSize = 500;
    const maxTracks = 10000;
    final available = <Track>[];
    var offset = 0;

    while (available.length < maxTracks) {
      final page = await _tracks.listTracks(limit: pageSize, offset: offset);
      if (page.isEmpty) {
        break;
      }

      available.addAll(page.where((track) => !track.isMissing));
      if (page.length < pageSize) {
        break;
      }
      offset += page.length;
    }

    return available;
  }

  Future<void> _recordSkipIfNeeded(PlayerState playerState) async {
    final track = playerState.currentTrack;
    final trackId = track?.id;
    if (track == null ||
        trackId == null ||
        !playerState.isPlaying ||
        playerState.status == PlayerPlaybackStatus.completed) {
      return;
    }

    final duration = playerState.duration ?? track.duration;
    final position = playerState.position;
    if (duration != null && position >= duration) {
      return;
    }

    final now = _clock();
    try {
      await _playbackEvents.addEvent(
        PlaybackEvent(
          trackId: trackId,
          type: PlaybackEventType.skipped,
          occurredAt: now,
          position: position,
          trackDuration: duration,
          waveMode: _state.selectedWaveMode,
        ),
      );

      final existing = await _trackUserState.findByTrackId(trackId);
      await _trackUserState.upsertState(
        _copyUserState(
          existing,
          trackId: trackId,
          skipCount: (existing?.skipCount ?? 0) + 1,
          lastSkippedAt: now,
          updatedAt: now,
        ),
      );
    } on Object catch (error) {
      _emit(
        _state.copyWith(
          lastError: 'Skip history was not saved: ${_describeError(error)}',
        ),
      );
    }
  }

  void _handlePlayerState(PlayerState playerState) {
    if (_isDisposed) {
      return;
    }

    final previousTrackKey = _nullableTrackKey(_state.currentTrack);
    final nextTrackKey = _nullableTrackKey(playerState.currentTrack);
    final trackChanged = previousTrackKey != nextTrackKey;
    _emit(
      playerState.hasError
          ? _state.copyWith(
              currentTrack: playerState.currentTrack,
              currentTrackUserState:
                  trackChanged ? null : _state.currentTrackUserState,
              lastError: playerState.errorMessage,
            )
          : _state.copyWith(
              currentTrack: playerState.currentTrack,
              currentTrackUserState:
                  trackChanged ? null : _state.currentTrackUserState,
            ),
    );
    if (trackChanged) {
      unawaited(_loadCurrentTrackUserState(playerState.currentTrack));
    }

    final track = playerState.currentTrack;
    if (playerState.status != PlayerPlaybackStatus.completed) {
      _handledCompletionTrackKey = null;
      return;
    }

    if (!_state.isWaveEnabled || _state.isChoosingNext || track == null) {
      return;
    }

    final completionKey = _trackKey(track);
    if (_handledCompletionTrackKey == completionKey) {
      return;
    }

    _handledCompletionTrackKey = completionKey;
    unawaited(_playSmartNext());
  }

  void _syncPlayerError() {
    final playerState = _playerService.state;
    if (!playerState.hasError) {
      return;
    }

    _emit(_state.copyWith(lastError: playerState.errorMessage));
  }

  void _emit(QueueState state) {
    if (_isDisposed || state == _state) {
      return;
    }

    _state = state;
    _stateController.add(state);
  }

  Object _trackKey(Track track) {
    return track.id ?? track.filePath;
  }

  Object? _nullableTrackKey(Track? track) {
    return track == null ? null : _trackKey(track);
  }

  bool _isSameTrack(Track left, Track right) {
    if (left.id != null && right.id != null) {
      return left.id == right.id;
    }
    return left.filePath == right.filePath;
  }

  bool _isSameCurrentTrack(Track track) {
    final currentTrack = _playerService.currentTrack ?? _state.currentTrack;
    return currentTrack != null && _isSameTrack(track, currentTrack);
  }

  Future<void> _updateTrackFeedback(
    Track track, {
    required TrackUserState Function(
      TrackUserState? existing,
      int trackId,
      DateTime now,
    ) update,
    required String failurePrefix,
  }) async {
    if (_isDisposed) {
      return;
    }

    final trackId = track.id;
    if (trackId == null) {
      _emit(_state.copyWith(lastError: 'Track feedback was not saved.'));
      return;
    }

    final now = _clock();
    try {
      final existing = await _trackUserState.findByTrackId(trackId);
      final updated = update(existing, trackId, now);
      await _trackUserState.upsertState(updated);
      if (_isSameCurrentTrack(track)) {
        _currentTrackStateGeneration += 1;
        _emit(
          _state.copyWith(
            currentTrackUserState: updated,
            lastError: null,
          ),
        );
      } else {
        _emit(_state.copyWith(lastError: null));
      }
    } on Object catch (error) {
      _emit(
        _state.copyWith(
          lastError: '$failurePrefix: ${_describeError(error)}',
        ),
      );
    }
  }

  Future<void> _loadCurrentTrackUserState(Track? track) async {
    final trackId = track?.id;
    final trackKey = _nullableTrackKey(track);
    _currentTrackStateKey = trackKey;
    final generation = ++_currentTrackStateGeneration;
    if (trackId == null || trackKey == null) {
      _emit(_state.copyWith(currentTrackUserState: null));
      return;
    }

    try {
      final state = await _trackUserState.findByTrackId(trackId);
      if (_isDisposed ||
          _currentTrackStateKey != trackKey ||
          _currentTrackStateGeneration != generation) {
        return;
      }
      _emit(_state.copyWith(currentTrackUserState: state));
    } on Object catch (error) {
      if (_isDisposed ||
          _currentTrackStateKey != trackKey ||
          _currentTrackStateGeneration != generation) {
        return;
      }
      _emit(
        _state.copyWith(
          lastError: 'Track feedback was not loaded: ${_describeError(error)}',
        ),
      );
    }
  }

  TrackUserState _copyUserState(
    TrackUserState? existing, {
    required int trackId,
    bool? isFavorite,
    bool? isHidden,
    Object? rating = _unsetFeedbackValue,
    int? skipCount,
    DateTime? lastSkippedAt,
    required DateTime updatedAt,
  }) {
    return TrackUserState(
      trackId: trackId,
      isFavorite: isFavorite ?? existing?.isFavorite ?? false,
      isHidden: isHidden ?? existing?.isHidden ?? false,
      rating: identical(rating, _unsetFeedbackValue)
          ? existing?.rating
          : rating as int?,
      playCount: existing?.playCount ?? 0,
      completeCount: existing?.completeCount ?? 0,
      skipCount: skipCount ?? existing?.skipCount ?? 0,
      lastPlayedAt: existing?.lastPlayedAt,
      lastSkippedAt: lastSkippedAt ?? existing?.lastSkippedAt,
      lastCompletedAt: existing?.lastCompletedAt,
      userScoreBoost: existing?.userScoreBoost ?? 0,
      preferredWaveMode: existing?.preferredWaveMode,
      updatedAt: updatedAt,
    );
  }

  String _describeError(Object error) {
    return error.toString();
  }

  static bool _isDisliked(TrackUserState? state) {
    if (state == null) {
      return false;
    }
    return state.isHidden;
  }
}

final class _RepeatGuardResult {
  const _RepeatGuardResult({
    required this.candidates,
    required this.filteredCount,
  });

  final List<RecommendationResult> candidates;
  final int filteredCount;

  String? get message {
    if (filteredCount <= 0) {
      return null;
    }
    return 'Recent repeat guard active: $filteredCount candidate(s) avoided.';
  }
}

final class _RepeatGuardSignals {
  const _RepeatGuardSignals({
    required this.currentTrackKey,
    required this.recentTrackKeys,
    required this.recentArtistKeys,
    required this.recentAlbumKeys,
  });

  final Object? currentTrackKey;
  final Set<Object> recentTrackKeys;
  final Set<String> recentArtistKeys;
  final Set<String> recentAlbumKeys;

  static _RepeatGuardSignals from({
    required Track? currentTrack,
    required Iterable<PlaybackEvent> recentEvents,
    required Iterable<Track> tracks,
  }) {
    final tracksById = {
      for (final track in tracks)
        if (track.id != null) track.id!: track,
    };
    final recentTrackKeys = <Object>{};
    final recentArtistKeys = <String>{};
    final recentAlbumKeys = <String>{};

    void addArtistAlbum(Track? track) {
      final artistKey = _normalizedMetadataKey(track?.artist);
      if (artistKey != null && recentArtistKeys.length < 2) {
        recentArtistKeys.add(artistKey);
      }

      final albumKey = _normalizedMetadataKey(track?.album);
      if (albumKey != null && recentAlbumKeys.length < 2) {
        recentAlbumKeys.add(albumKey);
      }
    }

    addArtistAlbum(currentTrack);

    for (final event in recentEvents) {
      if (!_countsAsRecentListening(event.type)) {
        continue;
      }

      final track = tracksById[event.trackId];
      if (recentTrackKeys.length < 3) {
        recentTrackKeys.add(track == null ? event.trackId : _trackKey(track));
      }
      addArtistAlbum(track);

      if (recentTrackKeys.length >= 3 &&
          recentArtistKeys.length >= 2 &&
          recentAlbumKeys.length >= 2) {
        break;
      }
    }

    return _RepeatGuardSignals(
      currentTrackKey: currentTrack == null ? null : _trackKey(currentTrack),
      recentTrackKeys: recentTrackKeys,
      recentArtistKeys: recentArtistKeys,
      recentAlbumKeys: recentAlbumKeys,
    );
  }

  bool isCurrentTrack(Track track) {
    return currentTrackKey != null && _trackKey(track) == currentTrackKey;
  }

  bool isRecentTrack(Track track) {
    return recentTrackKeys.contains(_trackKey(track));
  }

  bool isRecentArtist(Track track) {
    final artistKey = _normalizedMetadataKey(track.artist);
    return artistKey != null && recentArtistKeys.contains(artistKey);
  }

  bool isRecentAlbum(Track track) {
    final albumKey = _normalizedMetadataKey(track.album);
    return albumKey != null && recentAlbumKeys.contains(albumKey);
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

Object _trackKey(Track track) {
  return track.id ?? track.filePath;
}

String? _normalizedMetadataKey(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}
