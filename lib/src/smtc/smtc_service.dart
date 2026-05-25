import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/models/track.dart';
import '../player/player_service.dart';
import '../player/player_state.dart';
import 'smtc_platform_client.dart';

abstract interface class SmtcService {
  Future<void> initialize();

  Future<void> dispose();
}

final class NoopSmtcService implements SmtcService {
  const NoopSmtcService();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}

final class WindowsSmtcService implements SmtcService {
  WindowsSmtcService({
    required PlayerService playerService,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
    required SmtcPlatformClient client,
    bool Function(String path)? fileExists,
  })  : _playerService = playerService,
        _onNext = onNext,
        _onPrevious = onPrevious,
        _client = client,
        _fileExists = fileExists ?? ((path) => File(path).existsSync());

  static const _buttonConfig = SmtcButtonConfig(
    playEnabled: true,
    pauseEnabled: true,
    stopEnabled: false,
    nextEnabled: true,
    previousEnabled: true,
    fastForwardEnabled: false,
    rewindEnabled: false,
  );

  final PlayerService _playerService;
  final Future<void> Function() _onNext;
  final Future<void> Function() _onPrevious;
  final SmtcPlatformClient _client;
  final bool Function(String path) _fileExists;

  StreamSubscription<PlayerState>? _playerSubscription;
  StreamSubscription<SmtcButton>? _buttonSubscription;
  Future<void> _commandQueue = Future<void>.value();
  Future<void> _stateQueue = Future<void>.value();
  SmtcMetadata? _lastMetadata;
  SmtcMetadata? _lastRejectedArtworkMetadata;
  SmtcTimeline? _lastTimeline;
  String? _lastTimelineTrackKey;
  SmtcPlaybackStatus? _lastStatus;
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isEnabled = true;

  @override
  Future<void> initialize() async {
    if (_isDisposed || _isInitialized) {
      return;
    }

    try {
      await _client.initialize(_buttonConfig);
      _isInitialized = true;
      _debugLog('initialized');
      _buttonSubscription = _client.buttonPressStream.listen(
        _handleButtonPress,
        onError: _logError,
      );
      _playerSubscription = _playerService.stateStream.listen(
        _enqueuePlayerStateSync,
        onError: _logError,
      );
      final initialState = _playerService.state;
      if (_shouldClearMetadata(initialState)) {
        await _setPlaybackStatus(smtcStatusForPlayerState(initialState));
      } else {
        await _syncPlayerState(initialState);
      }
    } on Object catch (error) {
      _logError(error);
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    await _playerSubscription?.cancel();
    await _buttonSubscription?.cancel();
    await _client.dispose();
  }

  void _enqueuePlayerStateSync(PlayerState state) {
    _stateQueue = _stateQueue.catchError(_logError).then((_) async {
      await _syncPlayerState(state);
    });
  }

  Future<void> _syncPlayerState(PlayerState state) async {
    if (_isDisposed || !_isInitialized) {
      return;
    }

    final status = smtcStatusForPlayerState(state);
    if (_shouldClearMetadata(state)) {
      _debugLog('sync terminal state: status=$status');
      await _setPlaybackStatus(status);
      await _clearAndDisable();
      return;
    }

    final track = state.currentTrack;
    if (track == null) {
      await _setPlaybackStatus(SmtcPlaybackStatus.stopped);
      await _clearAndDisable();
      return;
    }

    await _enable();
    final metadata = smtcMetadataForTrack(track, fileExists: _fileExists);
    await _updateMetadata(metadata);
    await _updateTimeline(
      smtcTimelineForPlayerState(state),
      trackKey: _timelineTrackKey(track),
    );
    await _setPlaybackStatus(status);
  }

  void _handleButtonPress(SmtcButton button) {
    _debugLog('button pressed: $button');
    final command = switch (button) {
      SmtcButton.play => _playerService.play,
      SmtcButton.pause => _playerService.pause,
      SmtcButton.next => _onNext,
      SmtcButton.previous => _onPrevious,
      _ => null,
    };

    if (command == null) {
      return;
    }

    _commandQueue = _commandQueue.catchError(_logError).then((_) async {
      if (_isDisposed) {
        return;
      }

      try {
        await command();
        _debugLog('button handled: $button');
      } on Object catch (error) {
        _logError(error);
      }
    });
  }

  Future<void> _enable() async {
    if (_isEnabled) {
      return;
    }

    try {
      await _client.enable();
      _isEnabled = true;
    } on Object catch (error) {
      _logError(error);
    }
  }

  Future<void> _clearAndDisable() async {
    if (_lastMetadata != null) {
      try {
        await _client.clearMetadata();
        _lastMetadata = null;
        _lastRejectedArtworkMetadata = null;
      } on Object catch (error) {
        _logError(error);
      }
    }

    _lastTimeline = null;
    _lastTimelineTrackKey = null;

    if (!_isEnabled) {
      return;
    }

    try {
      await _client.disable();
      _isEnabled = false;
    } on Object catch (error) {
      _logError(error);
    }
  }

  Future<void> _updateMetadata(SmtcMetadata metadata) async {
    var nextMetadata = metadata;
    if (metadata.thumbnail != null &&
        metadata == _lastRejectedArtworkMetadata) {
      nextMetadata = metadata.withoutThumbnail();
    }

    if (nextMetadata == _lastMetadata) {
      return;
    }

    try {
      await _client.updateMetadata(nextMetadata);
      _lastMetadata = nextMetadata;
      _debugLog(
        'metadata updated: title="${nextMetadata.title}", '
        'hasArtwork=${nextMetadata.thumbnail != null}',
      );
      return;
    } on Object catch (error) {
      _logError(error);
    }

    if (nextMetadata.thumbnail == null) {
      return;
    }

    _lastRejectedArtworkMetadata = nextMetadata;
    final fallbackMetadata = nextMetadata.withoutThumbnail();
    if (fallbackMetadata == _lastMetadata) {
      return;
    }

    try {
      await _client.updateMetadata(fallbackMetadata);
      _lastMetadata = fallbackMetadata;
      _debugLog(
        'metadata updated without artwork: '
        'title="${fallbackMetadata.title}"',
      );
    } on Object catch (error) {
      _logError(error);
    }
  }

  Future<void> _updateTimeline(
    SmtcTimeline timeline, {
    required String trackKey,
  }) async {
    if (_lastTimelineTrackKey == trackKey &&
        _sameTimelineBounds(timeline, _lastTimeline)) {
      return;
    }

    try {
      await _client.updateTimeline(timeline);
      _lastTimeline = timeline;
      _lastTimelineTrackKey = trackKey;
      _debugLog(
          'timeline updated: position=${timeline.position}, end=${timeline.end}');
    } on Object catch (error) {
      _logError(error);
    }
  }

  Future<void> _setPlaybackStatus(SmtcPlaybackStatus status) async {
    if (status == _lastStatus) {
      return;
    }

    try {
      await _client.setPlaybackStatus(status);
      _lastStatus = status;
      _debugLog('status updated: $status');
    } on Object catch (error) {
      _logError(error);
    }
  }

  bool _shouldClearMetadata(PlayerState state) {
    return state.currentTrack == null ||
        switch (state.status) {
          PlayerPlaybackStatus.idle ||
          PlayerPlaybackStatus.stopped ||
          PlayerPlaybackStatus.completed ||
          PlayerPlaybackStatus.error =>
            true,
          PlayerPlaybackStatus.loading ||
          PlayerPlaybackStatus.playing ||
          PlayerPlaybackStatus.paused =>
            false,
        };
  }

  void _logError(Object error) {
    if (kDebugMode) {
      debugPrint('WindowsSmtcService ignored error: $error');
    }
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('WindowsSmtcService $message');
    }
  }
}

SmtcMetadata smtcMetadataForTrack(
  Track track, {
  required bool Function(String path) fileExists,
}) {
  return SmtcMetadata(
    title: track.displayTitle,
    artist: _firstNonEmpty([track.artist, track.albumArtist]) ?? '',
    album: _trimmedOrNull(track.album),
    albumArtist: _trimmedOrNull(track.albumArtist),
    thumbnail: _artworkUriForTrack(track, fileExists: fileExists),
  );
}

SmtcPlaybackStatus smtcStatusForPlayerState(PlayerState state) {
  if (state.currentTrack == null) {
    return SmtcPlaybackStatus.stopped;
  }

  return switch (state.status) {
    PlayerPlaybackStatus.loading => SmtcPlaybackStatus.changing,
    PlayerPlaybackStatus.playing => SmtcPlaybackStatus.playing,
    PlayerPlaybackStatus.paused => SmtcPlaybackStatus.paused,
    PlayerPlaybackStatus.idle ||
    PlayerPlaybackStatus.stopped ||
    PlayerPlaybackStatus.completed ||
    PlayerPlaybackStatus.error =>
      SmtcPlaybackStatus.stopped,
  };
}

SmtcTimeline smtcTimelineForPlayerState(PlayerState state) {
  final duration = state.duration;
  final end =
      duration == null || duration < Duration.zero ? Duration.zero : duration;
  final position = _clampDuration(state.position, max: end);
  return SmtcTimeline(
    start: Duration.zero,
    end: end,
    position: position,
    minSeekTime: Duration.zero,
    maxSeekTime: end,
  );
}

String? _artworkUriForTrack(
  Track track, {
  required bool Function(String path) fileExists,
}) {
  for (final path in [track.customArtworkPath, track.artworkPath]) {
    final trimmedPath = _trimmedOrNull(path);
    if (trimmedPath == null || !fileExists(trimmedPath)) {
      continue;
    }
    return Uri.file(trimmedPath).toString();
  }
  return null;
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = _trimmedOrNull(value);
    if (trimmed != null) {
      return trimmed;
    }
  }
  return null;
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

Duration _clampDuration(Duration value, {required Duration max}) {
  if (value < Duration.zero) {
    return Duration.zero;
  }
  if (max > Duration.zero && value > max) {
    return max;
  }
  return value;
}

String _timelineTrackKey(Track track) {
  final id = track.id;
  if (id != null) {
    return 'id:$id';
  }
  return 'path:${track.filePath}';
}

bool _sameTimelineBounds(SmtcTimeline next, SmtcTimeline? previous) {
  return previous != null &&
      next.start == previous.start &&
      next.end == previous.end &&
      next.minSeekTime == previous.minSeekTime &&
      next.maxSeekTime == previous.maxSeekTime;
}
