import '../domain/models/models.dart';

const Object _unset = Object();

final class QueueState {
  QueueState({
    this.currentTrack,
    this.currentTrackUserState,
    this.upcomingTrack,
    this.selectedWaveMode = WaveMode.balanced,
    this.lastRecommendationResult,
    Iterable<RecommendationResult> recommendationCandidates = const [],
    this.isWaveEnabled = false,
    this.isChoosingNext = false,
    this.repeatGuardMessage,
    this.lastError,
  }) : recommendationCandidates = List.unmodifiable(recommendationCandidates);

  final Track? currentTrack;
  final TrackUserState? currentTrackUserState;
  final Track? upcomingTrack;
  final WaveMode selectedWaveMode;
  final RecommendationResult? lastRecommendationResult;
  final List<RecommendationResult> recommendationCandidates;
  final bool isWaveEnabled;
  final bool isChoosingNext;
  final String? repeatGuardMessage;
  final String? lastError;

  bool get smartModeEnabled => isWaveEnabled;

  bool get isCurrentTrackLiked {
    final state = currentTrackUserState;
    if (state == null) {
      return false;
    }
    return state.isFavorite && !state.isHidden;
  }

  bool get isCurrentTrackDisliked {
    final state = currentTrackUserState;
    if (state == null) {
      return false;
    }
    return state.isHidden;
  }

  QueueState copyWith({
    Object? currentTrack = _unset,
    Object? currentTrackUserState = _unset,
    Object? upcomingTrack = _unset,
    WaveMode? selectedWaveMode,
    Object? lastRecommendationResult = _unset,
    Iterable<RecommendationResult>? recommendationCandidates,
    bool? isWaveEnabled,
    bool? isChoosingNext,
    Object? repeatGuardMessage = _unset,
    Object? lastError = _unset,
  }) {
    return QueueState(
      currentTrack: identical(currentTrack, _unset)
          ? this.currentTrack
          : currentTrack as Track?,
      currentTrackUserState: identical(currentTrackUserState, _unset)
          ? this.currentTrackUserState
          : currentTrackUserState as TrackUserState?,
      upcomingTrack: identical(upcomingTrack, _unset)
          ? this.upcomingTrack
          : upcomingTrack as Track?,
      selectedWaveMode: selectedWaveMode ?? this.selectedWaveMode,
      lastRecommendationResult: identical(lastRecommendationResult, _unset)
          ? this.lastRecommendationResult
          : lastRecommendationResult as RecommendationResult?,
      recommendationCandidates:
          recommendationCandidates ?? this.recommendationCandidates,
      isWaveEnabled: isWaveEnabled ?? this.isWaveEnabled,
      isChoosingNext: isChoosingNext ?? this.isChoosingNext,
      repeatGuardMessage: identical(repeatGuardMessage, _unset)
          ? this.repeatGuardMessage
          : repeatGuardMessage as String?,
      lastError:
          identical(lastError, _unset) ? this.lastError : lastError as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is QueueState &&
            other.currentTrack == currentTrack &&
            other.currentTrackUserState == currentTrackUserState &&
            other.upcomingTrack == upcomingTrack &&
            other.selectedWaveMode == selectedWaveMode &&
            other.lastRecommendationResult == lastRecommendationResult &&
            _listEquals(
              other.recommendationCandidates,
              recommendationCandidates,
            ) &&
            other.isWaveEnabled == isWaveEnabled &&
            other.isChoosingNext == isChoosingNext &&
            other.repeatGuardMessage == repeatGuardMessage &&
            other.lastError == lastError;
  }

  @override
  int get hashCode {
    return Object.hash(
      currentTrack,
      currentTrackUserState,
      upcomingTrack,
      selectedWaveMode,
      lastRecommendationResult,
      Object.hashAll(recommendationCandidates),
      isWaveEnabled,
      isChoosingNext,
      repeatGuardMessage,
      lastError,
    );
  }
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
