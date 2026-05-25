import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/models/track.dart';
import '../player/player_service.dart';
import '../player/player_state.dart';
import 'macos_now_playing_client.dart';
import 'system_media_controls_service.dart';

final class MacosNowPlayingService implements SystemMediaControlsService {
  MacosNowPlayingService({
    required PlayerService playerService,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
    required MacosNowPlayingClient client,
    bool Function(String path)? fileExists,
    bool? isMacOS,
  }) : _playerService = playerService,
       _onNext = onNext,
       _onPrevious = onPrevious,
       _client = client,
       _fileExists = fileExists ?? ((path) => File(path).existsSync()),
       _isMacOS = isMacOS ?? Platform.isMacOS;

  final PlayerService _playerService;
  final Future<void> Function() _onNext;
  final Future<void> Function() _onPrevious;
  final MacosNowPlayingClient _client;
  final bool Function(String path) _fileExists;
  final bool _isMacOS;

  StreamSubscription<PlayerState>? _playerSubscription;
  StreamSubscription<MacosNowPlayingCommand>? _commandSubscription;
  Future<void> _commandQueue = Future<void>.value();
  Future<void> _stateQueue = Future<void>.value();
  MacosNowPlayingMetadata? _lastMetadata;
  MacosNowPlayingMetadata? _lastRejectedArtworkMetadata;
  MacosNowPlayingPlaybackStatus? _lastStatus;
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isNativeMetadataCleared = false;

  @override
  Future<void> initialize() async {
    if (!_isMacOS || _isDisposed || _isInitialized) {
      return;
    }

    try {
      await _client.initialize();
      _isInitialized = true;
      _debugLog('initialized');
      _commandSubscription = _client.commandStream.listen(
        _handleCommand,
        onError: _logError,
      );
      _playerSubscription = _playerService.stateStream.listen(
        _enqueuePlayerStateSync,
        onError: _logError,
      );
      await _syncPlayerState(_playerService.state);
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
    await _commandSubscription?.cancel();
    if (_isInitialized) {
      await _client.dispose();
    }
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

    final status = macosPlaybackStatusForPlayerState(state);
    if (_shouldClearMetadata(state)) {
      _debugLog('sync terminal state: status=$status');
      await _setPlaybackStatus(status);
      await _clearMetadata();
      return;
    }

    final track = state.currentTrack;
    if (track == null) {
      await _setPlaybackStatus(MacosNowPlayingPlaybackStatus.stopped);
      await _clearMetadata();
      return;
    }

    final metadata = macosNowPlayingMetadataForTrack(
      track,
      fileExists: _fileExists,
    );
    await _updateMetadata(metadata);
    await _setPlaybackStatus(status);
  }

  void _handleCommand(MacosNowPlayingCommand command) {
    _debugLog('command received: $command');
    final action = switch (command) {
      MacosNowPlayingCommand.play => _playerService.play,
      MacosNowPlayingCommand.pause => _playerService.pause,
      MacosNowPlayingCommand.next => _onNext,
      MacosNowPlayingCommand.previous => _onPrevious,
    };

    _commandQueue = _commandQueue.catchError(_logError).then((_) async {
      if (_isDisposed) {
        return;
      }

      try {
        await action();
        _debugLog('command handled: $command');
      } on Object catch (error) {
        _logError(error);
      }
    });
  }

  Future<void> _updateMetadata(MacosNowPlayingMetadata metadata) async {
    var nextMetadata = metadata;
    if (metadata.artworkPath != null &&
        metadata == _lastRejectedArtworkMetadata) {
      nextMetadata = metadata.withoutArtwork();
    }

    if (nextMetadata == _lastMetadata) {
      return;
    }

    try {
      await _client.updateMetadata(nextMetadata);
      _lastMetadata = nextMetadata;
      _isNativeMetadataCleared = false;
      _debugLog(
        'metadata updated: title="${nextMetadata.title}", '
        'hasArtwork=${nextMetadata.artworkPath != null}',
      );
      return;
    } on Object catch (error) {
      _logError(error);
    }

    if (nextMetadata.artworkPath == null) {
      return;
    }

    _lastRejectedArtworkMetadata = nextMetadata;
    final fallbackMetadata = nextMetadata.withoutArtwork();
    if (fallbackMetadata == _lastMetadata) {
      return;
    }

    try {
      await _client.updateMetadata(fallbackMetadata);
      _lastMetadata = fallbackMetadata;
      _isNativeMetadataCleared = false;
      _debugLog(
        'metadata updated without artwork: '
        'title="${fallbackMetadata.title}"',
      );
    } on Object catch (error) {
      _logError(error);
    }
  }

  Future<void> _setPlaybackStatus(MacosNowPlayingPlaybackStatus status) async {
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

  Future<void> _clearMetadata() async {
    if (_isNativeMetadataCleared && _lastMetadata == null) {
      return;
    }

    try {
      await _client.clearMetadata();
      _lastMetadata = null;
      _lastRejectedArtworkMetadata = null;
      _isNativeMetadataCleared = true;
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
          PlayerPlaybackStatus.error => true,
          PlayerPlaybackStatus.loading ||
          PlayerPlaybackStatus.playing ||
          PlayerPlaybackStatus.paused => false,
        };
  }

  void _logError(Object error) {
    if (kDebugMode) {
      debugPrint('MacosNowPlayingService ignored error: $error');
    }
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('MacosNowPlayingService $message');
    }
  }
}

MacosNowPlayingMetadata macosNowPlayingMetadataForTrack(
  Track track, {
  required bool Function(String path) fileExists,
}) {
  return MacosNowPlayingMetadata(
    title: track.displayTitle,
    artist: _firstNonEmpty([track.artist, track.albumArtist]) ?? '',
    album: _trimmedOrNull(track.album),
    albumArtist: _trimmedOrNull(track.albumArtist),
    artworkPath: _artworkPathForTrack(track, fileExists: fileExists),
  );
}

MacosNowPlayingPlaybackStatus macosPlaybackStatusForPlayerState(
  PlayerState state,
) {
  if (state.currentTrack == null) {
    return MacosNowPlayingPlaybackStatus.stopped;
  }

  return switch (state.status) {
    PlayerPlaybackStatus.loading => MacosNowPlayingPlaybackStatus.unknown,
    PlayerPlaybackStatus.playing => MacosNowPlayingPlaybackStatus.playing,
    PlayerPlaybackStatus.paused => MacosNowPlayingPlaybackStatus.paused,
    PlayerPlaybackStatus.idle ||
    PlayerPlaybackStatus.stopped ||
    PlayerPlaybackStatus.completed ||
    PlayerPlaybackStatus.error => MacosNowPlayingPlaybackStatus.stopped,
  };
}

String? _artworkPathForTrack(
  Track track, {
  required bool Function(String path) fileExists,
}) {
  for (final path in [track.customArtworkPath, track.artworkPath]) {
    final trimmedPath = _trimmedOrNull(path);
    if (trimmedPath == null || !fileExists(trimmedPath)) {
      continue;
    }
    return trimmedPath;
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
