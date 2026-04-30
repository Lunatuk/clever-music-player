import 'wave_mode.dart';

enum PlaybackEventType {
  started,
  paused,
  resumed,
  skipped,
  completed,
  stopped,
  seeked;

  String get storageKey => name;

  static PlaybackEventType fromStorageKey(String value) {
    return PlaybackEventType.values.firstWhere(
      (type) => type.storageKey == value,
      orElse: () => PlaybackEventType.started,
    );
  }
}

final class PlaybackEvent {
  const PlaybackEvent({
    this.id,
    required this.trackId,
    required this.type,
    required this.occurredAt,
    this.position,
    this.trackDuration,
    this.waveMode,
    this.metadataJson,
  });

  final int? id;
  final int trackId;
  final PlaybackEventType type;
  final DateTime occurredAt;
  final Duration? position;
  final Duration? trackDuration;
  final WaveMode? waveMode;
  final String? metadataJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlaybackEvent &&
            other.id == id &&
            other.trackId == trackId &&
            other.type == type &&
            other.occurredAt == occurredAt &&
            other.position == position &&
            other.trackDuration == trackDuration &&
            other.waveMode == waveMode &&
            other.metadataJson == metadataJson;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      trackId,
      type,
      occurredAt,
      position,
      trackDuration,
      waveMode,
      metadataJson,
    );
  }
}
