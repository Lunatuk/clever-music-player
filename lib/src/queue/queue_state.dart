import '../domain/models/models.dart';

const Object _unset = Object();

enum PlaybackSource {
  none,
  singleTrack,
  wave,
  manualQueue,
  playlist,
  library,
}

enum PlaybackRepeatMode {
  none,
  playlist,
  track,
}

final class PlaybackContext {
  PlaybackContext({
    this.source = PlaybackSource.none,
    this.playlistId,
    this.playlistName,
    Iterable<Track> tracks = const [],
    this.currentIndex = -1,
  }) : tracks = List.unmodifiable(tracks);

  final PlaybackSource source;
  final int? playlistId;
  final String? playlistName;
  final List<Track> tracks;
  final int currentIndex;

  bool get isPlaylist =>
      source == PlaybackSource.playlist &&
      playlistId != null &&
      tracks.isNotEmpty &&
      currentIndex >= 0 &&
      currentIndex < tracks.length;

  bool get isLibrary =>
      source == PlaybackSource.library &&
      tracks.isNotEmpty &&
      currentIndex >= 0 &&
      currentIndex < tracks.length;

  bool get isTrackList => isPlaylist || isLibrary;

  Track? get currentTrack => isTrackList ? tracks[currentIndex] : null;

  PlaybackContext copyWith({
    PlaybackSource? source,
    Object? playlistId = _unset,
    Object? playlistName = _unset,
    Iterable<Track>? tracks,
    int? currentIndex,
  }) {
    return PlaybackContext(
      source: source ?? this.source,
      playlistId:
          identical(playlistId, _unset) ? this.playlistId : playlistId as int?,
      playlistName: identical(playlistName, _unset)
          ? this.playlistName
          : playlistName as String?,
      tracks: tracks ?? this.tracks,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }

  static PlaybackContext none() => PlaybackContext();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlaybackContext &&
            other.source == source &&
            other.playlistId == playlistId &&
            other.playlistName == playlistName &&
            _listEquals(other.tracks, tracks) &&
            other.currentIndex == currentIndex;
  }

  @override
  int get hashCode {
    return Object.hash(
      source,
      playlistId,
      playlistName,
      Object.hashAll(tracks),
      currentIndex,
    );
  }
}

final class QueueState {
  QueueState({
    this.currentTrack,
    this.currentTrackUserState,
    Iterable<Track> manualQueue = const [],
    PlaybackContext? playbackContext,
    this.activeSource = PlaybackSource.none,
    this.repeatMode = PlaybackRepeatMode.none,
    this.isPlaylistShuffleEnabled = false,
    this.selectedWaveMode = WaveMode.balanced,
    this.lastRecommendationResult,
    Iterable<RecommendationResult> recommendationCandidates = const [],
    this.isWaveEnabled = false,
    this.isChoosingNext = false,
    this.repeatGuardMessage,
    this.selectionPoolMessage,
    this.lastError,
  })  : manualQueue = List.unmodifiable(manualQueue),
        playbackContext = playbackContext ?? PlaybackContext.none(),
        recommendationCandidates = List.unmodifiable(recommendationCandidates);

  final Track? currentTrack;
  final TrackUserState? currentTrackUserState;
  final List<Track> manualQueue;
  final PlaybackContext playbackContext;
  final PlaybackSource activeSource;
  final PlaybackRepeatMode repeatMode;
  final bool isPlaylistShuffleEnabled;
  final WaveMode selectedWaveMode;
  final RecommendationResult? lastRecommendationResult;
  final List<RecommendationResult> recommendationCandidates;
  final bool isWaveEnabled;
  final bool isChoosingNext;
  final String? repeatGuardMessage;
  final String? selectionPoolMessage;
  final String? lastError;

  bool get smartModeEnabled => isWaveEnabled;

  bool get isWaveCurrentSource => activeSource == PlaybackSource.wave;

  bool get hasPlaylistContext => playbackContext.isPlaylist;

  bool get hasLibraryContext => playbackContext.isLibrary;

  bool get hasTrackListContext => playbackContext.isTrackList;

  bool get canAdvance =>
      manualQueue.isNotEmpty || hasTrackListContext || isWaveEnabled;

  bool get canUseRepeat =>
      (activeSource == PlaybackSource.playlist && hasPlaylistContext) ||
      (activeSource == PlaybackSource.library && hasLibraryContext);

  bool get canUseShuffle =>
      activeSource == PlaybackSource.playlist && hasPlaylistContext;

  bool get canGoToPreviousPlaylistTrack {
    if (!hasPlaylistContext) {
      return false;
    }
    return playbackContext.currentIndex > 0 ||
        repeatMode == PlaybackRepeatMode.playlist;
  }

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
    Iterable<Track>? manualQueue,
    Object? playbackContext = _unset,
    PlaybackSource? activeSource,
    PlaybackRepeatMode? repeatMode,
    bool? isPlaylistShuffleEnabled,
    WaveMode? selectedWaveMode,
    Object? lastRecommendationResult = _unset,
    Iterable<RecommendationResult>? recommendationCandidates,
    bool? isWaveEnabled,
    bool? isChoosingNext,
    Object? repeatGuardMessage = _unset,
    Object? selectionPoolMessage = _unset,
    Object? lastError = _unset,
  }) {
    return QueueState(
      currentTrack: identical(currentTrack, _unset)
          ? this.currentTrack
          : currentTrack as Track?,
      currentTrackUserState: identical(currentTrackUserState, _unset)
          ? this.currentTrackUserState
          : currentTrackUserState as TrackUserState?,
      manualQueue: manualQueue ?? this.manualQueue,
      playbackContext: identical(playbackContext, _unset)
          ? this.playbackContext
          : playbackContext as PlaybackContext,
      activeSource: activeSource ?? this.activeSource,
      repeatMode: repeatMode ?? this.repeatMode,
      isPlaylistShuffleEnabled:
          isPlaylistShuffleEnabled ?? this.isPlaylistShuffleEnabled,
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
      selectionPoolMessage: identical(selectionPoolMessage, _unset)
          ? this.selectionPoolMessage
          : selectionPoolMessage as String?,
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
            _listEquals(other.manualQueue, manualQueue) &&
            other.playbackContext == playbackContext &&
            other.activeSource == activeSource &&
            other.repeatMode == repeatMode &&
            other.isPlaylistShuffleEnabled == isPlaylistShuffleEnabled &&
            other.selectedWaveMode == selectedWaveMode &&
            other.lastRecommendationResult == lastRecommendationResult &&
            _listEquals(
              other.recommendationCandidates,
              recommendationCandidates,
            ) &&
            other.isWaveEnabled == isWaveEnabled &&
            other.isChoosingNext == isChoosingNext &&
            other.repeatGuardMessage == repeatGuardMessage &&
            other.selectionPoolMessage == selectionPoolMessage &&
            other.lastError == lastError;
  }

  @override
  int get hashCode {
    return Object.hash(
      currentTrack,
      currentTrackUserState,
      Object.hashAll(manualQueue),
      playbackContext,
      activeSource,
      repeatMode,
      isPlaylistShuffleEnabled,
      selectedWaveMode,
      lastRecommendationResult,
      Object.hashAll(recommendationCandidates),
      isWaveEnabled,
      isChoosingNext,
      repeatGuardMessage,
      selectionPoolMessage,
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
