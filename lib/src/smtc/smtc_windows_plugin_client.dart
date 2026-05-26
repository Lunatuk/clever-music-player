import 'dart:async';

import 'package:smtc_windows/smtc_windows.dart' as smtc;

import 'smtc_platform_client.dart';

final class SmtcWindowsPluginClient implements SmtcPlatformClient {
  smtc.SMTCWindows? _smtc;

  @override
  Stream<SmtcButton> get buttonPressStream {
    final instance = _smtc;
    if (instance == null) {
      return const Stream.empty();
    }

    return instance.buttonPressStream.map(_mapButton);
  }

  @override
  Future<void> initialize(SmtcButtonConfig config) async {
    await smtc.SMTCWindows.initialize();
    _smtc = smtc.SMTCWindows(
      config: _mapConfig(config),
      status: smtc.PlaybackStatus.stopped,
      enabled: true,
    );
  }

  @override
  Future<void> enable() {
    return _requireSmtc().enableSmtc();
  }

  @override
  Future<void> disable() {
    return _requireSmtc().disableSmtc();
  }

  @override
  Future<void> updateMetadata(SmtcMetadata metadata) {
    return _requireSmtc().updateMetadata(
      smtc.MusicMetadata(
        title: metadata.title,
        artist: metadata.artist,
        album: metadata.album,
        albumArtist: metadata.albumArtist,
        thumbnail: metadata.thumbnail,
      ),
    );
  }

  @override
  Future<void> updateTimeline(SmtcTimeline timeline) {
    return _requireSmtc().updateTimeline(
      smtc.PlaybackTimeline(
        startTimeMs: timeline.start.inMilliseconds,
        endTimeMs: timeline.end.inMilliseconds,
        positionMs: timeline.position.inMilliseconds,
        minSeekTimeMs: timeline.minSeekTime.inMilliseconds,
        maxSeekTimeMs: timeline.maxSeekTime.inMilliseconds,
      ),
    );
  }

  @override
  Future<void> clearMetadata() {
    return _requireSmtc().clearMetadata();
  }

  @override
  Future<void> setPlaybackStatus(SmtcPlaybackStatus status) {
    return _requireSmtc().setPlaybackStatus(_mapStatus(status));
  }

  @override
  Future<void> dispose() async {
    final instance = _smtc;
    _smtc = null;
    if (instance != null) {
      await instance.dispose();
    }
  }

  smtc.SMTCWindows _requireSmtc() {
    final instance = _smtc;
    if (instance == null) {
      throw StateError('SMTCWindows has not been initialized.');
    }
    return instance;
  }

  smtc.SMTCConfig _mapConfig(SmtcButtonConfig config) {
    return smtc.SMTCConfig(
      playEnabled: config.playEnabled,
      pauseEnabled: config.pauseEnabled,
      stopEnabled: config.stopEnabled,
      nextEnabled: config.nextEnabled,
      prevEnabled: config.previousEnabled,
      fastForwardEnabled: config.fastForwardEnabled,
      rewindEnabled: config.rewindEnabled,
    );
  }

  smtc.PlaybackStatus _mapStatus(SmtcPlaybackStatus status) {
    return switch (status) {
      SmtcPlaybackStatus.closed => smtc.PlaybackStatus.closed,
      SmtcPlaybackStatus.changing => smtc.PlaybackStatus.changing,
      SmtcPlaybackStatus.stopped => smtc.PlaybackStatus.stopped,
      SmtcPlaybackStatus.playing => smtc.PlaybackStatus.playing,
      SmtcPlaybackStatus.paused => smtc.PlaybackStatus.paused,
    };
  }

  SmtcButton _mapButton(smtc.PressedButton button) {
    return switch (button) {
      smtc.PressedButton.play => SmtcButton.play,
      smtc.PressedButton.pause => SmtcButton.pause,
      smtc.PressedButton.next => SmtcButton.next,
      smtc.PressedButton.previous => SmtcButton.previous,
      smtc.PressedButton.fastForward => SmtcButton.fastForward,
      smtc.PressedButton.rewind => SmtcButton.rewind,
      smtc.PressedButton.stop => SmtcButton.stop,
      smtc.PressedButton.record => SmtcButton.record,
      smtc.PressedButton.channelUp => SmtcButton.channelUp,
      smtc.PressedButton.channelDown => SmtcButton.channelDown,
    };
  }
}
