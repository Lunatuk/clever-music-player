import 'dart:async';

import 'package:flutter/services.dart';

import 'smtc_platform_client.dart';

final class MacosNowPlayingClient implements SmtcPlatformClient {
  static const _methodChannel =
      MethodChannel('clever_music_player/macos_now_playing');
  static const _eventChannel =
      EventChannel('clever_music_player/macos_now_playing/events');

  @override
  Stream<SmtcButton> get buttonPressStream {
    return _eventChannel
        .receiveBroadcastStream()
        .map(_mapButton)
        .where((button) => button != null)
        .cast<SmtcButton>();
  }

  @override
  Future<void> initialize(SmtcButtonConfig config) {
    return _methodChannel.invokeMethod<void>('initialize', {
      'playEnabled': config.playEnabled,
      'pauseEnabled': config.pauseEnabled,
      'stopEnabled': config.stopEnabled,
      'nextEnabled': config.nextEnabled,
      'previousEnabled': config.previousEnabled,
      'fastForwardEnabled': config.fastForwardEnabled,
      'rewindEnabled': config.rewindEnabled,
    });
  }

  @override
  Future<void> enable() {
    return _methodChannel.invokeMethod<void>('enable');
  }

  @override
  Future<void> disable() {
    return _methodChannel.invokeMethod<void>('disable');
  }

  @override
  Future<void> updateMetadata(SmtcMetadata metadata) {
    return _methodChannel.invokeMethod<void>('updateMetadata', {
      'title': metadata.title,
      'artist': metadata.artist,
      'album': metadata.album,
      'albumArtist': metadata.albumArtist,
      'thumbnail': metadata.thumbnail,
    });
  }

  @override
  Future<void> updateTimeline(SmtcTimeline timeline) {
    return _methodChannel.invokeMethod<void>('updateTimeline', {
      'startMs': timeline.start.inMilliseconds,
      'endMs': timeline.end.inMilliseconds,
      'positionMs': timeline.position.inMilliseconds,
      'minSeekTimeMs': timeline.minSeekTime.inMilliseconds,
      'maxSeekTimeMs': timeline.maxSeekTime.inMilliseconds,
    });
  }

  @override
  Future<void> clearMetadata() {
    return _methodChannel.invokeMethod<void>('clearMetadata');
  }

  @override
  Future<void> setPlaybackStatus(SmtcPlaybackStatus status) {
    return _methodChannel.invokeMethod<void>(
      'setPlaybackStatus',
      _statusName(status),
    );
  }

  @override
  Future<void> dispose() {
    return _methodChannel.invokeMethod<void>('dispose');
  }

  SmtcButton? _mapButton(Object? event) {
    return switch (event) {
      'play' => SmtcButton.play,
      'pause' => SmtcButton.pause,
      'next' => SmtcButton.next,
      'previous' => SmtcButton.previous,
      _ => null,
    };
  }

  String _statusName(SmtcPlaybackStatus status) {
    return switch (status) {
      SmtcPlaybackStatus.closed => 'closed',
      SmtcPlaybackStatus.changing => 'changing',
      SmtcPlaybackStatus.stopped => 'stopped',
      SmtcPlaybackStatus.playing => 'playing',
      SmtcPlaybackStatus.paused => 'paused',
    };
  }
}
