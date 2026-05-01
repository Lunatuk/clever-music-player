import 'wave_mode.dart';

final class TrackUserState {
  const TrackUserState({
    required this.trackId,
    this.isFavorite = false,
    this.isHidden = false,
    this.rating,
    this.playCount = 0,
    this.completeCount = 0,
    this.skipCount = 0,
    this.lastPlayedAt,
    this.lastSkippedAt,
    this.lastCompletedAt,
    this.userScoreBoost = 0,
    this.preferredWaveMode,
    required this.updatedAt,
  });

  final int trackId;
  final bool isFavorite;
  final bool isHidden;
  final int? rating;
  final int playCount;
  final int completeCount;
  final int skipCount;
  final DateTime? lastPlayedAt;
  final DateTime? lastSkippedAt;
  final DateTime? lastCompletedAt;
  final double userScoreBoost;
  final WaveMode? preferredWaveMode;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TrackUserState &&
            other.trackId == trackId &&
            other.isFavorite == isFavorite &&
            other.isHidden == isHidden &&
            other.rating == rating &&
            other.playCount == playCount &&
            other.completeCount == completeCount &&
            other.skipCount == skipCount &&
            other.lastPlayedAt == lastPlayedAt &&
            other.lastSkippedAt == lastSkippedAt &&
            other.lastCompletedAt == lastCompletedAt &&
            other.userScoreBoost == userScoreBoost &&
            other.preferredWaveMode == preferredWaveMode &&
            other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      trackId,
      isFavorite,
      isHidden,
      rating,
      playCount,
      completeCount,
      skipCount,
      lastPlayedAt,
      lastSkippedAt,
      lastCompletedAt,
      userScoreBoost,
      preferredWaveMode,
      updatedAt,
    );
  }
}
