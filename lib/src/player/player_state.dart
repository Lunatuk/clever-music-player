import '../domain/models/track.dart';

enum PlayerPlaybackStatus {
  idle,
  loading,
  playing,
  paused,
  stopped,
  completed,
  error,
}

enum PlayerFailureKind { source, operation }

const Object _unset = Object();

final class PlayerState {
  const PlayerState({
    this.currentTrack,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration,
    this.volume = 1,
    this.status = PlayerPlaybackStatus.idle,
    this.errorMessage,
    this.failureKind,
  });

  const PlayerState.idle()
      : currentTrack = null,
        isPlaying = false,
        position = Duration.zero,
        duration = null,
        volume = 1,
        status = PlayerPlaybackStatus.idle,
        errorMessage = null,
        failureKind = null;

  final Track? currentTrack;

  /// Playback is requested, including buffering/loading. A paused source can
  /// finish loading without automatically starting audio.
  final bool isPlaying;
  final Duration position;
  final Duration? duration;
  final double volume;
  final PlayerPlaybackStatus status;
  final String? errorMessage;
  final PlayerFailureKind? failureKind;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  PlayerState copyWith({
    Object? currentTrack = _unset,
    bool? isPlaying,
    Duration? position,
    Object? duration = _unset,
    double? volume,
    PlayerPlaybackStatus? status,
    Object? errorMessage = _unset,
    Object? failureKind = _unset,
  }) {
    return PlayerState(
      currentTrack: identical(currentTrack, _unset)
          ? this.currentTrack
          : currentTrack as Track?,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration:
          identical(duration, _unset) ? this.duration : duration as Duration?,
      volume: volume ?? this.volume,
      status: status ?? this.status,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      failureKind: identical(failureKind, _unset)
          ? (errorMessage == null ? null : this.failureKind)
          : failureKind as PlayerFailureKind?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlayerState &&
            other.currentTrack == currentTrack &&
            other.isPlaying == isPlaying &&
            other.position == position &&
            other.duration == duration &&
            other.volume == volume &&
            other.status == status &&
            other.errorMessage == errorMessage &&
            other.failureKind == failureKind;
  }

  @override
  int get hashCode {
    return Object.hash(
      currentTrack,
      isPlaying,
      position,
      duration,
      volume,
      status,
      errorMessage,
      failureKind,
    );
  }
}
