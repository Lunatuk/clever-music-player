import 'track.dart';
import 'wave_mode.dart';

final class RecommendationScoreReason {
  const RecommendationScoreReason({
    required this.code,
    required this.message,
    required this.weight,
  });

  final String code;
  final String message;
  final double weight;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RecommendationScoreReason &&
            other.code == code &&
            other.message == message &&
            other.weight == weight;
  }

  @override
  int get hashCode => Object.hash(code, message, weight);
}

final class RecommendationResult {
  RecommendationResult({
    required this.track,
    required this.score,
    required this.waveMode,
    required Iterable<RecommendationScoreReason> reasons,
    required this.generatedAt,
    this.candidatesConsidered = 1,
  }) : reasons = List.unmodifiable(reasons);

  final Track track;
  final double score;
  final WaveMode waveMode;
  final List<RecommendationScoreReason> reasons;
  final DateTime generatedAt;
  final int candidatesConsidered;

  Track get selectedTrack => track;

  double get finalScore => score;

  RecommendationResult copyWith({
    Track? track,
    double? score,
    WaveMode? waveMode,
    Iterable<RecommendationScoreReason>? reasons,
    DateTime? generatedAt,
    int? candidatesConsidered,
  }) {
    return RecommendationResult(
      track: track ?? this.track,
      score: score ?? this.score,
      waveMode: waveMode ?? this.waveMode,
      reasons: reasons ?? this.reasons,
      generatedAt: generatedAt ?? this.generatedAt,
      candidatesConsidered: candidatesConsidered ?? this.candidatesConsidered,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RecommendationResult &&
            other.track == track &&
            other.score == score &&
            other.waveMode == waveMode &&
            _listEquals(other.reasons, reasons) &&
            other.generatedAt == generatedAt &&
            other.candidatesConsidered == candidatesConsidered;
  }

  @override
  int get hashCode {
    return Object.hash(
      track,
      score,
      waveMode,
      Object.hashAll(reasons),
      generatedAt,
      candidatesConsidered,
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
