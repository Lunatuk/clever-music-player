import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/async_lifecycle.dart';
import '../diagnostics/diagnostics_service.dart';
import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';
import '../player/player_service.dart';
import '../player/playback_transitions.dart';
import '../player/player_state.dart';
import '../recommendation/recommendation_service.dart';
import 'queue_state.dart';

const int recommendationSelectionPoolLimit = 10;
const double negativeScoreSelectionTolerance = 10.0;
const double _maxSelectionWeightBoost = 12;
const Duration previousRestartThreshold = Duration(seconds: 5);

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
        ? 'Ограничение отрицательных баллов активно: показаны кандидаты '
            'в пределах ${negativeScoreTolerance.toStringAsFixed(1)} баллов '
            'от лучшего доступного.'
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
    this.diagnostics = const NoopDiagnosticsService(),
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
    final transitions = _transitions;
    if (transitions != null) {
      _transitionSubscription =
          transitions.automaticTransitionStream.listen((track) {
        if (_nextPlan?.track == track &&
            _matchesNextSelection(_nextPlanState, _state)) {
          unawaited(_advanceToNext(recordSkip: false));
        }
      });
    }
    final currentTrack = _playerService.currentTrack;
    _emit(_state.copyWith(currentTrack: currentTrack));
    unawaited(_loadCurrentTrackUserState(currentTrack));
  }

  final PlayerService _playerService;
  final DiagnosticsService diagnostics;
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
  Object? _lastStartedTrackKey;
  Object? _currentTrackStateKey;
  int _currentTrackStateGeneration = 0;
  List<int> _playlistShuffleBag = const [];
  bool _isAdvancingToNext = false;
  bool _isDisposed = false;
  final _operations = AsyncOperationTracker();
  Future<void>? _closing;

  PlaybackTransitions? get _transitions {
    final player = _playerService;
    return player is PlaybackTransitions ? player as PlaybackTransitions : null;
  }

  StreamSubscription<Track>? _transitionSubscription;
  _NextTrackPlan? _nextPlan;
  _NextSelectionSnapshot? _nextPlanState;
  int _nextPlanRevision = 0;
  bool _preparationScheduled = false;
  bool _automaticAdvance = false;
  _AutomaticRecovery? _automaticRecovery;

  /// Includes the microtask gap between failed automatic candidates. Media
  /// services must keep playback active while this coordinator can still retry.
  bool get isRecoveringAutomatically =>
      !_isDisposed &&
      (_automaticRecovery?.pending == true ||
          _recoveryScheduled ||
          (_automaticAdvance && _automaticRecovery != null));
  Completer<void>? _transitionDone;
  int _manualRequestRevision = 0;
  bool _recoveryScheduled = false;
  static const automaticRecoveryAttemptLimit = 20;
  static const waveHistoryPreviousLimit = 5;
  final _waveHistory = _WaveHistory();

  QueueState get state => _state;

  Stream<QueueState> get stateStream => _stateController.stream;

  void clearLearningStateSnapshot() {
    if (_isDisposed) return;
    _invalidateNextPreparation();
    _currentTrackStateGeneration += 1;
    _emit(
      _state.copyWith(
        currentTrackUserState: null,
        lastRecommendationResult: null,
        recommendationCandidates: const [],
        repeatGuardMessage: null,
        selectionPoolMessage: null,
        lastError: null,
      ),
    );
  }

  Future<void> playTrackManually(Track track) => _operations.run(() async {
        _cancelAutomaticRecovery();
        if (_isDisposed) {
          return;
        }

        _waveHistory.clear();
        _playlistShuffleBag = const [];
        _emit(
          _state.copyWith(
            currentTrack: track,
            currentTrackUserState: null,
            playbackContext: PlaybackContext.none(),
            activeSource: PlaybackSource.singleTrack,
            repeatMode: PlaybackRepeatMode.none,
            isPlaylistShuffleEnabled: false,
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
      });

  Future<void> playLibraryTrack({
    required Track track,
    required Iterable<Track> visibleTracks,
  }) async {
    if (_isDisposed) {
      return;
    }

    await _runNextTransition(() async {
      final context = await _buildLibraryContext(
        startTrack: track,
        visibleTracks: visibleTracks,
      );
      if (context == null) {
        return;
      }

      _playlistShuffleBag = const [];
      await _playTrackListTrackAt(
        context.currentIndex,
        context: context,
        repeatMode: PlaybackRepeatMode.none,
        isPlaylistShuffleEnabled: false,
      );
    }, userInitiated: true);
  }

  Future<void> playSmartNext() {
    return _playSmartNext();
  }

  Future<void> playPlaylist({
    required int playlistId,
    required String playlistName,
    required Iterable<PlaylistEntry> entries,
    required int startTrackId,
  }) async {
    if (_isDisposed) {
      return;
    }

    await _runNextTransition(() async {
      final context = await _buildPlaylistContext(
        playlistId: playlistId,
        playlistName: playlistName,
        entries: entries,
        startTrackId: startTrackId,
      );
      if (context == null) {
        return;
      }

      _playlistShuffleBag = const [];
      await _playPlaylistTrackAt(
        context.currentIndex,
        context: context,
        repeatMode: PlaybackRepeatMode.none,
        isPlaylistShuffleEnabled: false,
      );
    }, userInitiated: true);
  }

  Future<void> refreshPlaylistContextOrder({
    required int playlistId,
    required Iterable<PlaylistEntry> entries,
  }) =>
      _operations.run(() async {
        if (_isDisposed) {
          return;
        }

        final context = _state.playbackContext;
        if (!context.isPlaylist || context.playlistId != playlistId) {
          return;
        }

        final currentTrackId =
            (_state.currentTrack ?? context.currentTrack)?.id;
        if (currentTrackId == null) {
          return;
        }

        final playableTracks = <Track>[];
        var currentIndex = -1;
        for (final entry in _orderedPlaylistEntries(entries)) {
          if (!entry.isPlayable) {
            continue;
          }
          final playableTrack = await _resolvePlayableTrack(entry.track);
          if (playableTrack == null) {
            continue;
          }
          if (entry.trackId == currentTrackId) {
            currentIndex = playableTracks.length;
          }
          playableTracks.add(playableTrack);
        }

        if (playableTracks.isEmpty || currentIndex < 0) {
          return;
        }

        final nextContext = context.copyWith(
          tracks: playableTracks,
          currentIndex: currentIndex,
        );
        if (_state.isPlaylistShuffleEnabled) {
          _resetPlaylistShuffleBag(
            context: nextContext,
            excludeIndex: currentIndex,
          );
        }

        _emit(_state.copyWith(playbackContext: nextContext));
      });

  Future<void> addToQueue(Track track) => _operations.run(() async {
        if (_isDisposed) {
          return;
        }

        final playableTrack = await _resolvePlayableTrack(track);
        if (playableTrack == null) {
          _emit(
            _state.copyWith(
              lastError: 'Отсутствующие треки нельзя добавить в очередь.',
            ),
          );
          return;
        }

        // Queue v1 is intentionally session-local. It is not persisted across app
        // restarts until playlist or durable queue semantics are introduced.
        _emit(
          _state.copyWith(
            manualQueue: [..._state.manualQueue, playableTrack],
            lastError: null,
          ),
        );
      });

  void removeQueuedTrack(int index) {
    if (_isDisposed || index < 0 || index >= _state.manualQueue.length) {
      return;
    }

    final queue = _state.manualQueue.toList(growable: true)..removeAt(index);
    _emit(_state.copyWith(manualQueue: queue, lastError: null));
  }

  void clearQueue() {
    if (_isDisposed || _state.manualQueue.isEmpty) {
      return;
    }

    _emit(_state.copyWith(manualQueue: const [], lastError: null));
  }

  Future<void> playQueuedTrackNow(int index) async {
    if (_isDisposed || index < 0 || index >= _state.manualQueue.length) {
      return;
    }

    await _runNextTransition(() async {
      await _recordSkipIfNeeded(_playerService.state);
      await _playQueuedTrackAt(index);
    }, userInitiated: true);
  }

  Future<void> next() async {
    await _advanceToNext(recordSkip: true);
  }

  Future<void> previous() async {
    await _runNextTransition(() async {
      final playerState = _playerService.state;
      final currentTrack = playerState.currentTrack ?? _state.currentTrack;
      if (currentTrack == null) {
        return;
      }

      if (playerState.position > previousRestartThreshold) {
        await _playerService.seek(Duration.zero);
        return;
      }

      if (_state.isWaveCurrentSource) {
        // A failed new recommendation is not in history: return to the last
        // played entry before stepping further back on subsequent presses.
        final historyTrack = _waveHistory.currentTrack;
        final start =
            historyTrack != null && !_isSameTrack(currentTrack, historyTrack)
                ? _waveHistory.index
                : _waveHistory.index - 1;
        final revision = _waveHistory.revision;
        if (!await _playWaveHistoryFrom(start, -1) &&
            !_isDisposed &&
            revision == _waveHistory.revision &&
            _state.isWaveCurrentSource) {
          await _playerService.seek(Duration.zero);
        }
        return;
      }

      final context = _state.playbackContext;
      if (!context.isTrackList) {
        return;
      }

      final currentIndex = context.currentIndex;
      if (currentIndex > 0) {
        await _playTrackListTrackAt(currentIndex - 1);
        return;
      }

      if (_state.repeatMode == PlaybackRepeatMode.playlist) {
        await _playTrackListTrackAt(context.tracks.length - 1);
        return;
      }

      await _playerService.seek(Duration.zero);
    }, userInitiated: true);
  }

  void setRepeatMode(PlaybackRepeatMode mode) {
    if (_isDisposed || _state.repeatMode == mode) {
      return;
    }
    if (!_state.hasTrackListContext && mode != PlaybackRepeatMode.none) {
      return;
    }
    _emit(_state.copyWith(repeatMode: mode, lastError: null));
  }

  void cycleRepeatMode() {
    if (_isDisposed || !_state.hasTrackListContext) {
      return;
    }
    setRepeatMode(
      switch (_state.repeatMode) {
        PlaybackRepeatMode.none => PlaybackRepeatMode.playlist,
        PlaybackRepeatMode.playlist => PlaybackRepeatMode.track,
        PlaybackRepeatMode.track => PlaybackRepeatMode.none,
      },
    );
  }

  void setPlaylistShuffleEnabled(bool isEnabled) {
    if (_isDisposed || _state.isPlaylistShuffleEnabled == isEnabled) {
      return;
    }
    if (!_state.hasPlaylistContext) {
      return;
    }

    if (isEnabled) {
      _resetPlaylistShuffleBag(
        context: _state.playbackContext,
        excludeIndex: _state.playbackContext.currentIndex,
      );
    } else {
      _playlistShuffleBag = const [];
    }

    _emit(
      _state.copyWith(
        isPlaylistShuffleEnabled: isEnabled,
        lastError: null,
      ),
    );
  }

  void togglePlaylistShuffle() {
    setPlaylistShuffleEnabled(!_state.isPlaylistShuffleEnabled);
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

    _emit(
      _state.copyWith(
        isWaveEnabled: false,
      ),
    );
  }

  Future<void> likeCurrentTrack() async {
    final track = _playerService.currentTrack ?? _state.currentTrack;
    if (track == null) {
      _emit(_state.copyWith(lastError: 'Выберите трек, чтобы поставить лайк.'));
      return;
    }

    await toggleLike(track);
  }

  Future<void> dislikeCurrentTrack() async {
    final track = _playerService.currentTrack ?? _state.currentTrack;
    if (track == null) {
      _emit(
        _state.copyWith(
          lastError: 'Выберите трек, чтобы поставить дизлайк.',
        ),
      );
      return;
    }

    await toggleDislike(track);
  }

  Future<void> toggleLike(Track track) async {
    await _updateTrackFeedback(
      track,
      feedback: TrackFeedback.like,
      failurePrefix: 'Лайк не был сохранён',
    );
  }

  Future<void> toggleDislike(Track track) async {
    await _updateTrackFeedback(
      track,
      feedback: TrackFeedback.dislike,
      failurePrefix: 'Дизлайк не был сохранён',
    );
  }

  Future<void> dispose() {
    if (_closing != null) return _closing!;
    _isDisposed = true;
    _operations.closeAdmission();
    _cancelAutomaticRecovery();
    _nextPlanRevision++;
    _waveHistory.clear();
    _currentTrackStateGeneration++;
    return _closing = finishCleanup([
      () async {
        await _transitionSubscription?.cancel();
      },
      () async {
        await _transitions?.prepareNextTrack(null);
      },
      _playerSubscription.cancel,
      _operations.drain,
      _stateController.close,
    ]);
  }

  Future<void> _advanceToNext(
      {required bool recordSkip, bool recovering = false}) async {
    if (!recordSkip && !recovering && !_isAdvancingToNext && !_isDisposed) {
      _automaticRecovery = _AutomaticRecovery();
    }
    await _runNextTransition(() async {
      if (!_state.canAdvance) {
        return;
      }

      if (recordSkip) {
        await _recordSkipIfNeeded(_playerService.state);
      }
      final plan = _nextPlan;
      if (plan != null &&
          _matchesNextSelection(_nextPlanState, _state) &&
          (!(recordSkip || recovering) || !plan.repeatsCurrent)) {
        _nextPlan = null;
        _automaticAdvance = !recordSkip;
        try {
          await plan.commit();
        } finally {
          _automaticAdvance = false;
        }
        return;
      }
      _automaticAdvance = !recordSkip;

      if (_state.manualQueue.isNotEmpty) {
        await _playQueuedTrackAt(0);
        return;
      }

      if (_state.hasTrackListContext) {
        await _advanceTrackList(manualSkip: recordSkip || recovering);
        return;
      }

      if (_state.isWaveCurrentSource &&
          await _playWaveHistoryFrom(_waveHistory.index + 1, 1)) {
        return;
      }

      await _chooseAndPlaySmartNext(enableWave: false);
    }, userInitiated: recordSkip);
  }

  Future<void> _runNextTransition(
    Future<void> Function() transition, {
    bool userInitiated = false,
  }) =>
      _operations.run(() async {
        if (userInitiated) {
          final wasAutomatic = _automaticRecovery != null;
          _cancelAutomaticRecovery();
          final revision = _manualRequestRevision;
          if (wasAutomatic && _isAdvancingToNext) await _transitionDone?.future;
          if (_isDisposed || revision != _manualRequestRevision) return;
        }
        if (_isDisposed || _isAdvancingToNext || _state.isChoosingNext) {
          return;
        }

        final done = _transitionDone = Completer<void>();
        _isAdvancingToNext = true;
        _emit(_state.copyWith(isChoosingNext: true, lastError: null));
        try {
          await transition();
        } on _ObsoleteAutomaticAdvance {
          // A manual selection, pause, stop or dispose has superseded recovery.
        } on _AutomaticCandidateRejected {
          _automaticRecovery?.pending = true;
        } on _AutomaticRecoveryExhausted {
          _finishAutomaticRecovery();
        } on Object catch (error) {
          _emit(
            _state.copyWith(
              lastError:
                  'Не удалось перейти к следующему треку: ${_describeError(error)}',
            ),
          );
        } finally {
          _automaticAdvance = false;
          _isAdvancingToNext = false;
          _transitionDone = null;
          done.complete();
          if (!_isDisposed) {
            _emit(_state.copyWith(isChoosingNext: false));
            _scheduleAutomaticRecovery();
          }
        }
      });

  Future<Track?> _resolvePlayableTrack(Track track) async {
    if (_isDisposed || track.isMissing) {
      return null;
    }

    final trackId = track.id;
    if (trackId == null) {
      return track;
    }

    final latestTrack = await _tracks.findById(trackId);
    if (_isDisposed || latestTrack == null || latestTrack.isMissing) {
      return null;
    }
    return latestTrack;
  }

  Future<bool> _playQueuedTrackAt(int index) async {
    _checkAutomaticAdvance();
    if (index < 0 || index >= _state.manualQueue.length) {
      return false;
    }

    final queue = _state.manualQueue.toList(growable: true);
    final track = queue.removeAt(index);
    _waveHistory.clear();
    _emit(
      _state.copyWith(
        currentTrack: track,
        currentTrackUserState: null,
        manualQueue: queue,
        activeSource: PlaybackSource.manualQueue,
        lastRecommendationResult: null,
        repeatGuardMessage: null,
        selectionPoolMessage: null,
        lastError: null,
      ),
    );
    unawaited(_loadCurrentTrackUserState(track));

    await _playSelectedTrack(track);
    _syncPlayerError();
    return true;
  }

  Future<void> _playSmartNext() async {
    await _runNextTransition(() async {
      if (_state.hasTrackListContext || _state.isPlaylistShuffleEnabled) {
        _playlistShuffleBag = const [];
        _emit(
          _state.copyWith(
            playbackContext: PlaybackContext.none(),
            repeatMode: PlaybackRepeatMode.none,
            isPlaylistShuffleEnabled: false,
          ),
        );
      }
      await _chooseAndPlaySmartNext(enableWave: true);
    }, userInitiated: true);
  }

  Future<void> _chooseAndPlaySmartNext({required bool enableWave}) async {
    if (_isDisposed) {
      return;
    }

    if (enableWave && !_state.isWaveEnabled) {
      _emit(_state.copyWith(isWaveEnabled: true, lastError: null));
    }

    try {
      final selection = await _selectWaveTrack();
      await _playWaveSelection(selection);
    } on _ObsoleteAutomaticAdvance {
      rethrow;
    } on _AutomaticCandidateRejected {
      rethrow;
    } on _AutomaticRecoveryExhausted {
      rethrow;
    } on _NoWaveSelection catch (error) {
      if (_automaticAdvance &&
          (_automaticRecovery?.attempted.isNotEmpty ?? false)) {
        _finishAutomaticRecovery();
        return;
      }
      _emit(_state.copyWith(
        lastRecommendationResult: null,
        recommendationCandidates: const [],
        repeatGuardMessage: null,
        selectionPoolMessage: null,
        lastError: error.message,
      ));
    } on Object catch (error) {
      _emit(_state.copyWith(
        lastError:
            'Не удалось выбрать следующий трек: ${_describeError(error)}',
      ));
    }
  }

  Future<_WaveSelection> _selectWaveTrack() async {
    final availableTracks = (await _listAvailableTracks())
        .where(
          (track) =>
              !(_automaticRecovery?.failed.contains(_trackKey(track)) ?? false),
        )
        .toList();
    if (_isDisposed) throw const _ObsoleteAutomaticAdvance();
    if (availableTracks.isEmpty) {
      throw const _NoWaveSelection(
          'В библиотеке нет треков, доступных для воспроизведения.');
    }
    final states = await _trackUserState.findByTrackIds(
        availableTracks.map((track) => track.id).whereType<int>());
    if (_isDisposed) throw const _ObsoleteAutomaticAdvance();
    final recentEvents = await _playbackEvents.recentEvents(limit: 50);
    if (_isDisposed) throw const _ObsoleteAutomaticAdvance();
    final recommendations = _recommendationService.recommendFromInput(
        RecommendationInput(
            tracks: availableTracks,
            userStates: states,
            recentEvents: recentEvents,
            waveMode: _state.selectedWaveMode,
            limit: 20,
            generatedAt: _clock()));
    if (recommendations.isEmpty) {
      throw const _NoWaveSelection(
          'Нет треков, подходящих под текущие настройки волны.');
    }
    final guarded = _applyRepeatGuard(
        recommendations: recommendations,
        recentEvents: recentEvents,
        tracks: availableTracks);
    final pool = buildWeightedSelectionPoolResult(guarded.candidates);
    return _WaveSelection(_selectWeightedRecommendation(pool.candidates),
        pool.candidates, guarded.message, pool.message);
  }

  Future<void> _playWaveSelection(_WaveSelection selection) async {
    _checkAutomaticAdvance();
    final selected = selection.selected;
    final selectionPool = selection.candidates;
    final previous = _playerService.currentTrack;
    if (_waveHistory.isEmpty &&
        previous != null &&
        _playerService.state.status != PlayerPlaybackStatus.error &&
        _playerService.state.status != PlayerPlaybackStatus.loading) {
      _waveHistory.append(previous);
    }
    final historyRevision = _waveHistory.revision;
    _emit(
      _state.copyWith(
        currentTrack: selected.track,
        currentTrackUserState: null,
        playbackContext: PlaybackContext.none(),
        activeSource: PlaybackSource.wave,
        repeatMode: PlaybackRepeatMode.none,
        isPlaylistShuffleEnabled: false,
        lastRecommendationResult: selected,
        recommendationCandidates: selectionPool,
        repeatGuardMessage: selection.repeatGuardMessage,
        selectionPoolMessage: selection.poolMessage,
        lastError: null,
      ),
    );
    unawaited(_loadCurrentTrackUserState(selected.track));

    await _playSelectedTrack(selected.track);
    if (!_isDisposed &&
        _waveHistory.revision == historyRevision &&
        _state.isWaveCurrentSource &&
        _isSameCurrentTrack(selected.track) &&
        _playerService.state.status != PlayerPlaybackStatus.error) {
      _waveHistory.append(_playerService.currentTrack ?? selected.track);
    }
    _syncPlayerError();
  }

  Future<_WaveHistoryTarget?> _findWaveHistoryTarget(
      int start, int direction) async {
    final revision = _waveHistory.revision;
    for (var index = start;
        index >= 0 && index < _waveHistory.tracks.length;
        index += direction) {
      final track = await _resolvePlayableTrack(_waveHistory.tracks[index]);
      if (_isDisposed || revision != _waveHistory.revision) {
        throw const _ObsoleteAutomaticAdvance();
      }
      if (track != null) return _WaveHistoryTarget(index, track);
    }
    return null;
  }

  Future<bool> _playWaveHistoryFrom(int start, int direction) async {
    final target = await _findWaveHistoryTarget(start, direction);
    _checkAutomaticAdvance();
    if (target == null || !_state.isWaveCurrentSource) return false;
    _waveHistory.moveTo(target.index, target.track);
    _emit(_state.copyWith(
      currentTrack: target.track,
      currentTrackUserState: null,
      playbackContext: PlaybackContext.none(),
      activeSource: PlaybackSource.wave,
      repeatMode: PlaybackRepeatMode.none,
      isPlaylistShuffleEnabled: false,
      // This is a replay, not a fresh recommendation with new scores/reasons.
      lastRecommendationResult: null,
      recommendationCandidates: const [],
      repeatGuardMessage: null,
      selectionPoolMessage: null,
      lastError: null,
    ));
    unawaited(_loadCurrentTrackUserState(target.track));
    await _playSelectedTrack(target.track);
    _syncPlayerError();
    return true;
  }

  Future<PlaybackContext?> _buildPlaylistContext({
    required int playlistId,
    required String playlistName,
    required Iterable<PlaylistEntry> entries,
    required int startTrackId,
  }) async {
    final playableTracks = <Track>[];
    var startIndex = -1;

    for (final entry in _orderedPlaylistEntries(entries)) {
      if (!entry.isPlayable) {
        continue;
      }
      final playableTrack = await _resolvePlayableTrack(entry.track);
      if (playableTrack == null) {
        continue;
      }
      if (entry.trackId == startTrackId) {
        startIndex = playableTracks.length;
      }
      playableTracks.add(playableTrack);
    }

    if (playableTracks.isEmpty) {
      _emit(
        _state.copyWith(
          lastError: 'В этом плейлисте нет треков для воспроизведения.',
        ),
      );
      return null;
    }
    if (startIndex < 0) {
      _emit(
        _state.copyWith(
          lastError: 'Этот трек плейлиста недоступен для воспроизведения.',
        ),
      );
      return null;
    }

    return PlaybackContext(
      source: PlaybackSource.playlist,
      playlistId: playlistId,
      playlistName: playlistName,
      tracks: playableTracks,
      currentIndex: startIndex,
    );
  }

  Future<PlaybackContext?> _buildLibraryContext({
    required Track startTrack,
    required Iterable<Track> visibleTracks,
  }) async {
    final playableTracks = <Track>[];
    var startIndex = -1;

    for (final visibleTrack in visibleTracks) {
      if (visibleTrack.isMissing) {
        continue;
      }
      final playableTrack = await _resolvePlayableTrack(visibleTrack);
      if (playableTrack == null) {
        continue;
      }
      if (_isSameTrack(visibleTrack, startTrack) ||
          _isSameTrack(playableTrack, startTrack)) {
        startIndex = playableTracks.length;
      }
      playableTracks.add(playableTrack);
    }

    if (playableTracks.isEmpty) {
      _emit(
        _state.copyWith(
          lastError: 'В этом виде библиотеки нет треков для воспроизведения.',
        ),
      );
      return null;
    }
    if (startIndex < 0) {
      _emit(
        _state.copyWith(
          lastError: 'Этот трек библиотеки недоступен для воспроизведения.',
        ),
      );
      return null;
    }

    return PlaybackContext(
      source: PlaybackSource.library,
      tracks: playableTracks,
      currentIndex: startIndex,
    );
  }

  List<PlaylistEntry> _orderedPlaylistEntries(
    Iterable<PlaylistEntry> entries,
  ) {
    return entries.toList(growable: false)
      ..sort((left, right) {
        final positionOrder = left.position.compareTo(right.position);
        if (positionOrder != 0) {
          return positionOrder;
        }
        final addedOrder = left.addedAt.compareTo(right.addedAt);
        if (addedOrder != 0) {
          return addedOrder;
        }
        return left.trackId.compareTo(right.trackId);
      });
  }

  Future<void> _advanceTrackList({required bool manualSkip}) async {
    final context = _state.playbackContext;
    if (!context.isTrackList) {
      if (_state.isWaveEnabled) {
        await _chooseAndPlaySmartNext(enableWave: false);
      }
      return;
    }

    final isCurrentContextTrack = _state.activeSource == context.source;
    if (!manualSkip &&
        isCurrentContextTrack &&
        _state.repeatMode == PlaybackRepeatMode.track) {
      await _playTrackListTrackAt(context.currentIndex);
      return;
    }

    if (context.isPlaylist && _state.isPlaylistShuffleEnabled) {
      await _advanceShuffledPlaylist(context);
      return;
    }

    final nextIndex = context.currentIndex + 1;
    if (nextIndex < context.tracks.length) {
      await _playTrackListTrackAt(nextIndex);
      return;
    }

    if (_state.repeatMode == PlaybackRepeatMode.playlist) {
      await _playTrackListTrackAt(0);
      return;
    }

    await _finishTrackListContext();
  }

  Future<void> _advanceShuffledPlaylist(PlaybackContext context) async {
    final shuffledIndex = _takeNextShuffledPlaylistIndex(context);
    if (shuffledIndex != null) {
      await _playTrackListTrackAt(shuffledIndex);
      return;
    }

    if (_state.repeatMode == PlaybackRepeatMode.playlist) {
      _resetPlaylistShuffleBag(
        context: context,
        excludeIndex: context.currentIndex,
        includeCurrentIfOnlyTrack: true,
      );
      final repeatedIndex = _takeNextShuffledPlaylistIndex(context);
      if (repeatedIndex != null) {
        await _playTrackListTrackAt(repeatedIndex);
        return;
      }
    }

    await _finishTrackListContext();
  }

  Future<void> _finishTrackListContext() async {
    _playlistShuffleBag = const [];
    _emit(
      _state.copyWith(
        playbackContext: PlaybackContext.none(),
        activeSource: PlaybackSource.none,
        repeatMode: PlaybackRepeatMode.none,
        isPlaylistShuffleEnabled: false,
        lastRecommendationResult: null,
        repeatGuardMessage: null,
        selectionPoolMessage: null,
        lastError: null,
      ),
    );
    await _chooseAndPlaySmartNext(enableWave: true);
  }

  Future<bool> _playPlaylistTrackAt(
    int index, {
    PlaybackContext? context,
    PlaybackRepeatMode? repeatMode,
    bool? isPlaylistShuffleEnabled,
  }) async {
    return _playTrackListTrackAt(
      index,
      context: context,
      repeatMode: repeatMode,
      isPlaylistShuffleEnabled: isPlaylistShuffleEnabled,
    );
  }

  Future<bool> _playTrackListTrackAt(
    int index, {
    PlaybackContext? context,
    PlaybackRepeatMode? repeatMode,
    bool? isPlaylistShuffleEnabled,
  }) async {
    _checkAutomaticAdvance();
    final trackListContext = context ?? _state.playbackContext;
    if (!trackListContext.isTrackList ||
        index < 0 ||
        index >= trackListContext.tracks.length) {
      return false;
    }

    final track = trackListContext.tracks[index];
    final nextContext = trackListContext.copyWith(currentIndex: index);
    _waveHistory.clear();
    _emit(
      _state.copyWith(
        currentTrack: track,
        currentTrackUserState: null,
        playbackContext: nextContext,
        activeSource: nextContext.source,
        repeatMode: repeatMode ?? _state.repeatMode,
        isPlaylistShuffleEnabled: isPlaylistShuffleEnabled ??
            (nextContext.isPlaylist && _state.isPlaylistShuffleEnabled),
        lastRecommendationResult: null,
        repeatGuardMessage: null,
        selectionPoolMessage: null,
        lastError: null,
      ),
    );
    unawaited(_loadCurrentTrackUserState(track));

    await _playSelectedTrack(track);
    _syncPlayerError();
    return true;
  }

  int? _takeNextShuffledPlaylistIndex(PlaybackContext context) {
    if (!context.isPlaylist || _playlistShuffleBag.isEmpty) {
      return null;
    }

    final currentIndex = context.currentIndex;
    while (_playlistShuffleBag.isNotEmpty) {
      final index = _playlistShuffleBag.first;
      _playlistShuffleBag = _playlistShuffleBag.skip(1).toList();
      if (index < 0 || index >= context.tracks.length) {
        continue;
      }
      if (context.tracks.length > 1 && index == currentIndex) {
        continue;
      }
      return index;
    }
    return null;
  }

  void _resetPlaylistShuffleBag({
    required PlaybackContext context,
    required int excludeIndex,
    bool includeCurrentIfOnlyTrack = false,
  }) {
    if (!context.isPlaylist) {
      _playlistShuffleBag = const [];
      return;
    }

    final indices = <int>[];
    for (var index = 0; index < context.tracks.length; index++) {
      if (index == excludeIndex &&
          (context.tracks.length > 1 || !includeCurrentIfOnlyTrack)) {
        continue;
      }
      indices.add(index);
    }
    _playlistShuffleBag = _shuffleIndices(indices);
  }

  List<int> _shuffleIndices(List<int> indices) {
    final shuffled = indices.toList(growable: false);
    for (var index = shuffled.length - 1; index > 0; index--) {
      final swapIndex =
          (_randomDouble().clamp(0.0, 0.999999999).toDouble() * (index + 1))
              .floor();
      final value = shuffled[index];
      shuffled[index] = shuffled[swapIndex];
      shuffled[swapIndex] = value;
    }
    return shuffled;
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
    final effectiveCurrentTrack =
        _playerService.currentTrack ?? _state.currentTrack;
    final signals = _RepeatGuardSignals.from(
      currentTrack: effectiveCurrentTrack,
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

  Future<List<Track>> _listAvailableTracks() async {
    const pageSize = 500;
    const maxTracks = 10000;
    final available = <Track>[];
    var offset = 0;

    while (!_isDisposed && available.length < maxTracks) {
      final page = await _tracks.listTracks(limit: pageSize, offset: offset);
      if (_isDisposed) break;
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
        playerState.status != PlayerPlaybackStatus.playing) {
      return;
    }

    final duration = playerState.duration ?? track.duration;
    final position = playerState.position;
    if (duration != null && position >= duration) {
      return;
    }

    final now = _clock();
    try {
      await _playbackEvents.recordEvent(
        PlaybackEvent.recording(
          trackId: trackId,
          type: PlaybackEventType.skipped,
          occurredAt: now,
          position: position,
          trackDuration: duration,
          waveMode: _state.selectedWaveMode,
        ),
      );
    } on Object catch (error) {
      diagnostics.record(DiagnosticEvent.playbackHistoryWriteFailed,
          error: error, fields: {DiagnosticField.trackId: trackId});
      _emit(
        _state.copyWith(
          lastError:
              'История пропусков не была сохранена: ${_describeError(error)}',
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

    final recovery = _automaticRecovery;
    if (playerState.status == PlayerPlaybackStatus.stopped ||
        playerState.status == PlayerPlaybackStatus.paused) {
      _cancelAutomaticRecovery();
    } else if (recovery != null &&
        playerState.failureKind == PlayerFailureKind.source &&
        playerState.status == PlayerPlaybackStatus.error &&
        playerState.currentTrack != null &&
        recovery.selectedKey == _trackKey(playerState.currentTrack!)) {
      recovery.failed.add(recovery.selectedKey!);
      recovery.pending = true;
      _scheduleAutomaticRecovery();
    }

    final track = playerState.currentTrack;
    final trackKey = track == null ? null : _trackKey(track);
    if (playerState.status != PlayerPlaybackStatus.completed) {
      _lastStartedTrackKey = trackKey;
      _handledCompletionTrackKey = null;
      return;
    }

    if (track == null || trackKey == null) {
      return;
    }

    if (_lastStartedTrackKey != null && _lastStartedTrackKey != trackKey) {
      return;
    }

    if (_handledCompletionTrackKey == trackKey) {
      return;
    }

    _handledCompletionTrackKey = trackKey;
    unawaited(_advanceToNext(recordSkip: false));
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
    _scheduleNextPreparation();
  }

  Future<void> _playSelectedTrack(Track track) async {
    _checkAutomaticAdvance();
    final recovery = _automaticAdvance ? _automaticRecovery : null;
    if (recovery != null) {
      final key = _trackKey(track);
      if (recovery.attempts >= automaticRecoveryAttemptLimit) {
        throw const _AutomaticRecoveryExhausted();
      }
      recovery.attempts++;
      if (!recovery.attempted.add(key)) {
        throw const _AutomaticCandidateRejected();
      }
      recovery.selectedKey = key;
      final latest = await _resolvePlayableTrack(track);
      _checkAutomaticAdvance();
      if (latest == null) {
        recovery.failed.add(key);
        throw const _AutomaticCandidateRejected();
      }
      track = latest;
    }
    final transitions = _transitions;
    if (_automaticAdvance && transitions != null) {
      await transitions.playAutomatically(track);
    } else {
      await _playerService.playTrack(track);
    }
    if (recovery != null &&
        identical(recovery, _automaticRecovery) &&
        _playerService.state.status == PlayerPlaybackStatus.error &&
        _playerService.state.failureKind == PlayerFailureKind.source) {
      recovery.failed.add(_trackKey(track));
      recovery.pending = true;
    }
  }

  void _checkAutomaticAdvance() {
    if (_isDisposed || (_automaticAdvance && _automaticRecovery == null)) {
      throw const _ObsoleteAutomaticAdvance();
    }
  }

  void _cancelAutomaticRecovery() {
    _automaticRecovery = null;
    _manualRequestRevision++;
  }

  void _finishAutomaticRecovery() {
    _cancelAutomaticRecovery();
    _emit(_state.copyWith(
        currentTrack: _playerService.currentTrack,
        lastError:
            'Не удалось найти доступный трек. Проверь файлы и папки библиотеки. '
            'Автоматический поиск ограничен $automaticRecoveryAttemptLimit попытками.'));
  }

  void _scheduleAutomaticRecovery() {
    if (_isDisposed ||
        _recoveryScheduled ||
        _isAdvancingToNext ||
        !(_automaticRecovery?.pending ?? false)) {
      return;
    }
    _recoveryScheduled = true;
    scheduleMicrotask(() {
      _recoveryScheduled = false;
      final recovery = _automaticRecovery;
      if (_isDisposed ||
          _isAdvancingToNext ||
          recovery == null ||
          !recovery.pending) {
        return;
      }
      recovery.pending = false;
      if (recovery.attempts >= automaticRecoveryAttemptLimit) {
        _finishAutomaticRecovery();
      } else {
        unawaited(_advanceToNext(recordSkip: false, recovering: true));
      }
    });
  }

  bool _matchesNextSelection(
      _NextSelectionSnapshot? snapshot, QueueState next) {
    if (snapshot == null || snapshot.historyRevision != _waveHistory.revision) {
      return false;
    }
    final previous = snapshot.state;
    return previous.currentTrack == next.currentTrack &&
        previous.playbackContext == next.playbackContext &&
        previous.activeSource == next.activeSource &&
        previous.repeatMode == next.repeatMode &&
        previous.isPlaylistShuffleEnabled == next.isPlaylistShuffleEnabled &&
        previous.isWaveEnabled == next.isWaveEnabled &&
        previous.selectedWaveMode == next.selectedWaveMode &&
        listEquals(previous.manualQueue, next.manualQueue);
  }

  void _invalidateNextPreparation() {
    _nextPlanState = null;
    _nextPlan = null;
    _nextPlanRevision++;
    _scheduleNextPreparation();
  }

  void _scheduleNextPreparation() {
    if (_transitions == null || _isDisposed || _preparationScheduled) return;
    _preparationScheduled = true;
    scheduleMicrotask(() {
      _preparationScheduled = false;
      if (_isDisposed ||
          _state.isChoosingNext ||
          _isAdvancingToNext ||
          _matchesNextSelection(_nextPlanState, _state)) {
        return;
      }
      unawaited(_prepareNextSelection());
    });
  }

  Future<void> _prepareNextSelection() => _operations.run(() async {
        final transitions = _transitions!;
        final snapshot = _state;
        final selectionSnapshot =
            _NextSelectionSnapshot(snapshot, _waveHistory.revision);
        final revision = ++_nextPlanRevision;
        _nextPlanState = selectionSnapshot;
        _nextPlan = null;
        try {
          final plan = snapshot.currentTrack == null || !snapshot.canAdvance
              ? null
              : await _buildNextPlan(snapshot);
          if (_isDisposed ||
              revision != _nextPlanRevision ||
              !_matchesNextSelection(selectionSnapshot, _state)) {
            return;
          }
          _nextPlan = plan;
          await transitions.prepareNextTrack(plan?.track);
        } on Object {
          // Selection/preload failures are retried by the normal end-of-track path.
          if (!_isDisposed && revision == _nextPlanRevision) {
            await transitions.prepareNextTrack(null);
          }
        }
      });

  Future<_NextTrackPlan?> _buildNextPlan(QueueState snapshot) async {
    if (snapshot.manualQueue.isNotEmpty) {
      final track = await _resolvePlayableTrack(snapshot.manualQueue.first);
      return track == null
          ? null
          : _NextTrackPlan(track, () async {
              await _playQueuedTrackAt(0);
            });
    }
    if (snapshot.isWaveCurrentSource) {
      final target = await _findWaveHistoryTarget(_waveHistory.index + 1, 1);
      if (target != null) {
        return _NextTrackPlan(target.track, () async {
          if (!await _playWaveHistoryFrom(_waveHistory.index + 1, 1)) {
            await _chooseAndPlaySmartNext(enableWave: false);
          }
        });
      }
    }
    final context = snapshot.playbackContext;
    if (context.isTrackList) {
      if (snapshot.activeSource == context.source &&
          snapshot.repeatMode == PlaybackRepeatMode.track) {
        return _NextTrackPlan(context.tracks[context.currentIndex], () async {
          await _playTrackListTrackAt(context.currentIndex);
        }, repeatsCurrent: true);
      }
      int? index;
      var shuffled = false;
      List<int>? nextShuffleCycle;
      if (context.isPlaylist && snapshot.isPlaylistShuffleEnabled) {
        if (_playlistShuffleBag.isEmpty &&
            snapshot.repeatMode == PlaybackRepeatMode.playlist) {
          nextShuffleCycle = _shuffleIndices([
            for (var i = 0; i < context.tracks.length; i++)
              if (i != context.currentIndex || context.tracks.length == 1) i,
          ]);
        }
        for (final candidate in nextShuffleCycle ?? _playlistShuffleBag) {
          if (candidate >= 0 &&
              candidate < context.tracks.length &&
              (candidate != context.currentIndex ||
                  context.tracks.length == 1)) {
            index = candidate;
            shuffled = true;
            break;
          }
        }
      } else if (context.currentIndex + 1 < context.tracks.length) {
        index = context.currentIndex + 1;
      } else if (snapshot.repeatMode == PlaybackRepeatMode.playlist) {
        index = 0;
      }
      if (index != null) {
        final nextIndex = index;
        return _NextTrackPlan(context.tracks[nextIndex], () async {
          if (shuffled) {
            if (nextShuffleCycle != null) {
              _playlistShuffleBag = nextShuffleCycle;
            }
            _takeNextShuffledPlaylistIndex(context);
          }
          await _playTrackListTrackAt(nextIndex);
        });
      }
      // Existing behaviour: finishing a list continues with Wave.
    }
    final selection = await _selectWaveTrack();
    return _NextTrackPlan(selection.selected.track, () async {
      _playlistShuffleBag = const [];
      if (!_state.isWaveEnabled) _emit(_state.copyWith(isWaveEnabled: true));
      await _playWaveSelection(selection);
    });
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
    required TrackFeedback feedback,
    required String failurePrefix,
  }) =>
      _operations.run(() async {
        if (_isDisposed) {
          return;
        }

        final trackId = track.id;
        if (trackId == null) {
          _emit(
            _state.copyWith(lastError: 'Оценка трека не была сохранена.'),
          );
          return;
        }

        final now = _clock();
        try {
          await _trackUserState.toggleFeedback(trackId, feedback,
              updatedAt: now);
          _invalidateNextPreparation();
          _emit(_state.copyWith(lastError: null));
          if (_isSameCurrentTrack(track)) {
            // Reload with a generation guard: an older toggle may finish after a
            // newer one or after switching tracks. Never paint its stale result.
            await _loadCurrentTrackUserState(track);
          }
        } on Object catch (error) {
          diagnostics.record(DiagnosticEvent.trackFeedbackWriteFailed,
              error: error, fields: {DiagnosticField.trackId: trackId});
          _emit(
            _state.copyWith(
              lastError: '$failurePrefix: ${_describeError(error)}',
            ),
          );
        }
      });

  Future<void> _loadCurrentTrackUserState(Track? track) =>
      _operations.run(() async {
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
              lastError:
                  'Оценка трека не была загружена: ${_describeError(error)}',
            ),
          );
        }
      });

  String _describeError(Object error) {
    return error.toString();
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
    return 'Защита от повторов активна: исключено кандидатов: '
        '$filteredCount.';
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

final class _NextTrackPlan {
  const _NextTrackPlan(this.track, this.commit, {this.repeatsCurrent = false});
  final Track track;
  final Future<void> Function() commit;
  final bool repeatsCurrent;
}

final class _NextSelectionSnapshot {
  const _NextSelectionSnapshot(this.state, this.historyRevision);
  final QueueState state;
  final int historyRevision;
}

final class _WaveHistoryTarget {
  const _WaveHistoryTarget(this.index, this.track);
  final int index;
  final Track track;
}

/// A session-only timeline: five previous visits plus the current/forward
/// entries share six slots. No audio buffers or full list contexts are retained.
final class _WaveHistory {
  final tracks = <Track>[];
  int index = -1;
  int revision = 0;
  bool get isEmpty => tracks.isEmpty;
  Track? get currentTrack => isEmpty ? null : tracks[index];

  void clear() {
    if (isEmpty) return;
    tracks.clear();
    index = -1;
    revision++;
  }

  void append(Track track) {
    if (index + 1 < tracks.length) tracks.removeRange(index + 1, tracks.length);
    tracks.add(track);
    if (tracks.length > PlaybackQueueService.waveHistoryPreviousLimit + 1) {
      tracks.removeAt(0);
    }
    index = tracks.length - 1;
    revision++;
  }

  void moveTo(int target, Track latest) {
    tracks[target] = latest;
    index = target;
    revision++;
  }
}

final class _WaveSelection {
  const _WaveSelection(this.selected, this.candidates, this.repeatGuardMessage,
      this.poolMessage);
  final RecommendationResult selected;
  final List<RecommendationResult> candidates;
  final String? repeatGuardMessage;
  final String? poolMessage;
}

final class _NoWaveSelection implements Exception {
  const _NoWaveSelection(this.message);
  final String message;
}

final class _AutomaticRecovery {
  final Set<Object> attempted = {};
  final Set<Object> failed = {};
  Object? selectedKey;
  int attempts = 0;
  bool pending = false;
}

final class _ObsoleteAutomaticAdvance implements Exception {
  const _ObsoleteAutomaticAdvance();
}

final class _AutomaticCandidateRejected implements Exception {
  const _AutomaticCandidateRejected();
}

final class _AutomaticRecoveryExhausted implements Exception {
  const _AutomaticRecoveryExhausted();
}
