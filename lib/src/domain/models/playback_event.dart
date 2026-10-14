import 'dart:math';

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
    this.operationId,
    required this.trackId,
    required this.type,
    required this.occurredAt,
    this.position,
    this.trackDuration,
    this.waveMode,
    this.metadataJson,
  });

  /// Create once, then reuse this event (including its ID) for retries.
  factory PlaybackEvent.recording({
    required int trackId,
    required PlaybackEventType type,
    required DateTime occurredAt,
    Duration? position,
    Duration? trackDuration,
    WaveMode? waveMode,
    String? metadataJson,
  }) {
    return PlaybackEvent(
      operationId: List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      trackId: trackId,
      type: type,
      occurredAt: occurredAt,
      position: position,
      trackDuration: trackDuration,
      waveMode: waveMode,
      metadataJson: metadataJson,
    );
  }

  static final Random _random = Random.secure();

  final int? id;
  final String? operationId;
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
            other.operationId == operationId &&
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
      operationId,
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
