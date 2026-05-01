final class PlayerProgress {
  const PlayerProgress({
    required this.position,
    required this.duration,
    this.dragPosition,
  });

  final Duration position;
  final Duration? duration;
  final Duration? dragPosition;

  bool get canSeek => duration != null && duration! > Duration.zero;

  Duration get displayPosition {
    if (!canSeek) {
      return Duration.zero;
    }

    return clampPosition(dragPosition ?? position, duration);
  }

  Duration get displayDuration {
    return canSeek ? duration! : Duration.zero;
  }

  double get maxMilliseconds {
    return canSeek ? duration!.inMilliseconds.toDouble() : 1;
  }

  double get valueMilliseconds {
    if (!canSeek) {
      return 0;
    }

    return displayPosition.inMilliseconds
        .clamp(0, duration!.inMilliseconds)
        .toDouble();
  }

  static Duration fromSliderValue(double value, Duration duration) {
    return clampPosition(
      Duration(milliseconds: value.round()),
      duration,
    );
  }

  static Duration clampPosition(Duration position, Duration? duration) {
    if (position < Duration.zero) {
      return Duration.zero;
    }

    if (duration != null && position > duration) {
      return duration;
    }

    return position;
  }

  static String formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
