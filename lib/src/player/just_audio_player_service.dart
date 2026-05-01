import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart' as just_audio;

import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';
import 'player_service.dart';
import 'player_state.dart';

enum AudioEngineProcessingState {
  idle,
  loading,
  buffering,
  ready,
  completed,
}

final class AudioEngineState {
  const AudioEngineState({
    required this.isPlaying,
    required this.processingState,
  });

  final bool isPlaying;
  final AudioEngineProcessingState processingState;
}

abstract interface class LocalAudioEngine {
  Stream<AudioEngineState> get stateStream;

  Stream<Duration> get positionStream;

  Stream<Duration?> get durationStream;

  Future<Duration?> setFilePath(String filePath);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seek(Duration position);

  Future<void> setVolume(double volume);

  Future<void> dispose();
}

final class JustAudioEngine implements LocalAudioEngine {
  JustAudioEngine([just_audio.AudioPlayer? player])
      : _player = player ?? just_audio.AudioPlayer();

  final just_audio.AudioPlayer _player;

  @override
  Stream<AudioEngineState> get stateStream {
    return _player.playerStateStream.map((state) {
      return AudioEngineState(
        isPlaying: state.playing,
        processingState: _mapProcessingState(state.processingState),
      );
    });
  }

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Future<Duration?> setFilePath(String filePath) {
    return _player.setFilePath(filePath);
  }

  @override
  Future<void> play() {
    return _player.play();
  }

  @override
  Future<void> pause() {
    return _player.pause();
  }

  @override
  Future<void> stop() {
    return _player.stop();
  }

  @override
  Future<void> seek(Duration position) {
    return _player.seek(position);
  }

  @override
  Future<void> setVolume(double volume) {
    return _player.setVolume(volume);
  }

  @override
  Future<void> dispose() {
    return _player.dispose();
  }

  static AudioEngineProcessingState _mapProcessingState(
    just_audio.ProcessingState state,
  ) {
    return switch (state) {
      just_audio.ProcessingState.idle => AudioEngineProcessingState.idle,
      just_audio.ProcessingState.loading => AudioEngineProcessingState.loading,
      just_audio.ProcessingState.buffering =>
        AudioEngineProcessingState.buffering,
      just_audio.ProcessingState.ready => AudioEngineProcessingState.ready,
      just_audio.ProcessingState.completed =>
        AudioEngineProcessingState.completed,
    };
  }
}

final class JustAudioPlayerService implements PlayerService {
  JustAudioPlayerService({
    required PlaybackEventRepository playbackEvents,
    required TrackUserStateRepository trackUserState,
    LocalAudioEngine? audioEngine,
    bool Function(String filePath)? fileExists,
  })  : _playbackEvents = playbackEvents,
        _trackUserState = trackUserState,
        _audioEngine = audioEngine ?? JustAudioEngine(),
        _fileExists =
            fileExists ?? ((filePath) => File(filePath).existsSync()) {
    _subscriptions
      ..add(_audioEngine.stateStream.listen(_handleAudioState))
      ..add(_audioEngine.positionStream.listen(_handlePosition))
      ..add(_audioEngine.durationStream.listen(_handleDuration));
  }

  final PlaybackEventRepository _playbackEvents;
  final TrackUserStateRepository _trackUserState;
  final LocalAudioEngine _audioEngine;
  final bool Function(String filePath) _fileExists;
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  PlayerState _state = const PlayerState.idle();
  bool _isDisposed = false;
  bool _didRecordCompletion = false;

  @override
  PlayerState get state => _state;

  @override
  Track? get currentTrack => _state.currentTrack;

  @override
  bool get isPlaying => _state.isPlaying;

  @override
  Duration get position => _state.position;

  @override
  Duration? get duration => _state.duration;

  @override
  double get volume => _state.volume;

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  @override
  Future<void> playTrack(Track track) async {
    if (_isDisposed) {
      return;
    }

    _didRecordCompletion = false;
    _emit(
      _state.copyWith(
        currentTrack: track,
        isPlaying: false,
        position: Duration.zero,
        duration: track.duration,
        status: PlayerPlaybackStatus.loading,
        errorMessage: null,
      ),
    );

    if (!_fileExists(track.filePath)) {
      await _stopAfterFailure(
        'File does not exist: ${track.filePath}',
      );
      return;
    }

    try {
      await _audioEngine.stop();
      final loadedDuration = await _audioEngine.setFilePath(track.filePath);
      _emit(
        _state.copyWith(
          currentTrack: track,
          isPlaying: true,
          position: Duration.zero,
          duration: loadedDuration ?? track.duration,
          status: PlayerPlaybackStatus.playing,
          errorMessage: null,
        ),
      );
      unawaited(_recordPlaybackStarted(track));
      _playInBackground();
    } on Object catch (error) {
      await _stopAfterFailure(
        'Could not play "${track.displayTitle}": ${_describeError(error)}',
      );
    }
  }

  @override
  Future<void> play() async {
    final track = _state.currentTrack;
    if (track == null) {
      _emit(
        _state.copyWith(
          status: PlayerPlaybackStatus.error,
          errorMessage: 'Select a track to play.',
        ),
      );
      return;
    }

    try {
      if (_state.status == PlayerPlaybackStatus.completed) {
        _didRecordCompletion = false;
        await _audioEngine.seek(Duration.zero);
        _emit(_state.copyWith(position: Duration.zero));
        unawaited(_recordPlaybackStarted(track));
      } else if (_state.status == PlayerPlaybackStatus.paused) {
        unawaited(_recordEvent(track, PlaybackEventType.resumed));
      }

      _emit(
        _state.copyWith(
          isPlaying: true,
          status: PlayerPlaybackStatus.playing,
          errorMessage: null,
        ),
      );
      _playInBackground();
    } on Object catch (error) {
      _emitPlaybackError('Playback failed: ${_describeError(error)}');
    }
  }

  @override
  Future<void> pause() async {
    final track = _state.currentTrack;
    if (track == null || !_state.isPlaying) {
      return;
    }

    try {
      await _audioEngine.pause();
      _emit(
        _state.copyWith(
          isPlaying: false,
          status: PlayerPlaybackStatus.paused,
          errorMessage: null,
        ),
      );
      unawaited(_recordEvent(track, PlaybackEventType.paused));
    } on Object catch (error) {
      _emitPlaybackError('Could not pause playback: ${_describeError(error)}');
    }
  }

  @override
  Future<void> stop() async {
    if (_state.currentTrack == null && !_state.isPlaying) {
      return;
    }

    try {
      await _audioEngine.stop();
      _didRecordCompletion = false;
      _emit(
        PlayerState(
          volume: _state.volume,
          status: PlayerPlaybackStatus.stopped,
        ),
      );
    } on Object catch (error) {
      _emitPlaybackError('Could not stop playback: ${_describeError(error)}');
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final track = _state.currentTrack;
    if (track == null) {
      return;
    }

    final target = _clampPosition(position, _state.duration);
    try {
      await _audioEngine.seek(target);
      _emit(
        _state.copyWith(
          position: target,
          errorMessage: null,
        ),
      );
    } on Object catch (error) {
      _emitPlaybackError('Could not seek: ${_describeError(error)}');
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    final normalizedVolume = volume.clamp(0.0, 1.0).toDouble();
    try {
      await _audioEngine.setVolume(normalizedVolume);
      _emit(
        _state.copyWith(
          volume: normalizedVolume,
          errorMessage: null,
        ),
      );
    } on Object catch (error) {
      _emitPlaybackError('Could not set volume: ${_describeError(error)}');
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _audioEngine.dispose();
    await _stateController.close();
  }

  void _handleAudioState(AudioEngineState audioState) {
    if (_isDisposed) {
      return;
    }

    final status = switch (audioState.processingState) {
      AudioEngineProcessingState.idle =>
        _state.currentTrack == null ? PlayerPlaybackStatus.idle : _state.status,
      AudioEngineProcessingState.loading ||
      AudioEngineProcessingState.buffering =>
        PlayerPlaybackStatus.loading,
      AudioEngineProcessingState.ready => audioState.isPlaying
          ? PlayerPlaybackStatus.playing
          : _state.currentTrack == null
              ? PlayerPlaybackStatus.idle
              : PlayerPlaybackStatus.paused,
      AudioEngineProcessingState.completed => PlayerPlaybackStatus.completed,
    };

    final completed =
        audioState.processingState == AudioEngineProcessingState.completed;
    final nextPosition = completed && _state.duration != null
        ? _state.duration!
        : _state.position;

    _emit(
      _state.copyWith(
        isPlaying: completed ? false : audioState.isPlaying,
        position: nextPosition,
        status: status,
      ),
    );

    final track = _state.currentTrack;
    if (completed && track != null && !_didRecordCompletion) {
      _didRecordCompletion = true;
      unawaited(_recordPlaybackCompleted(track));
    }
  }

  void _handlePosition(Duration position) {
    if (_isDisposed || _state.status == PlayerPlaybackStatus.completed) {
      return;
    }

    _emit(_state.copyWith(position: position));
  }

  void _handleDuration(Duration? duration) {
    if (_isDisposed) {
      return;
    }

    _emit(_state.copyWith(duration: duration));
  }

  void _playInBackground() {
    unawaited(_playAndReportErrors());
  }

  Future<void> _playAndReportErrors() async {
    try {
      await _audioEngine.play();
    } on Object catch (error) {
      _emitPlaybackError('Playback failed: ${_describeError(error)}');
    }
  }

  Future<void> _stopAfterFailure(String message) async {
    try {
      await _audioEngine.stop();
    } on Object {
      // Keep the user-facing error focused on the original playback failure.
    }

    _didRecordCompletion = false;
    _emit(
      PlayerState(
        volume: _state.volume,
        status: PlayerPlaybackStatus.error,
        errorMessage: message,
      ),
    );
  }

  void _emitPlaybackError(String message) {
    _emit(
      _state.copyWith(
        isPlaying: false,
        status: PlayerPlaybackStatus.error,
        errorMessage: message,
      ),
    );
  }

  void _emit(PlayerState state) {
    if (_isDisposed) {
      return;
    }

    _state = state;
    _stateController.add(state);
  }

  Future<void> _recordPlaybackStarted(Track track) async {
    final trackId = track.id;
    if (trackId == null) {
      return;
    }

    final now = DateTime.now();
    await _recordSafely(() async {
      await _playbackEvents.addEvent(
        PlaybackEvent(
          trackId: trackId,
          type: PlaybackEventType.started,
          occurredAt: now,
          position: Duration.zero,
          trackDuration: _state.duration ?? track.duration,
        ),
      );

      final existing = await _trackUserState.findByTrackId(trackId);
      await _trackUserState.upsertState(
        _copyUserState(
          existing,
          trackId: trackId,
          playCount: (existing?.playCount ?? 0) + 1,
          lastPlayedAt: now,
          updatedAt: now,
        ),
      );
    });
  }

  Future<void> _recordPlaybackCompleted(Track track) async {
    final trackId = track.id;
    if (trackId == null) {
      return;
    }

    final now = DateTime.now();
    await _recordSafely(() async {
      await _playbackEvents.addEvent(
        PlaybackEvent(
          trackId: trackId,
          type: PlaybackEventType.completed,
          occurredAt: now,
          position: _state.position,
          trackDuration: _state.duration ?? track.duration,
        ),
      );

      final existing = await _trackUserState.findByTrackId(trackId);
      await _trackUserState.upsertState(
        _copyUserState(
          existing,
          trackId: trackId,
          completeCount: (existing?.completeCount ?? 0) + 1,
          lastCompletedAt: now,
          updatedAt: now,
        ),
      );
    });
  }

  Future<void> _recordEvent(
    Track track,
    PlaybackEventType type,
  ) async {
    final trackId = track.id;
    if (trackId == null) {
      return;
    }

    await _recordSafely(() async {
      await _playbackEvents.addEvent(
        PlaybackEvent(
          trackId: trackId,
          type: type,
          occurredAt: DateTime.now(),
          position: _state.position,
          trackDuration: _state.duration ?? track.duration,
        ),
      );
    });
  }

  Future<void> _recordSafely(Future<void> Function() write) async {
    try {
      await write();
    } on Object catch (error) {
      _emit(
        _state.copyWith(
          errorMessage:
              'Playback history was not saved: ${_describeError(error)}',
        ),
      );
    }
  }

  TrackUserState _copyUserState(
    TrackUserState? existing, {
    required int trackId,
    int? playCount,
    int? completeCount,
    DateTime? lastPlayedAt,
    DateTime? lastCompletedAt,
    required DateTime updatedAt,
  }) {
    return TrackUserState(
      trackId: trackId,
      isFavorite: existing?.isFavorite ?? false,
      isHidden: existing?.isHidden ?? false,
      rating: existing?.rating,
      playCount: playCount ?? existing?.playCount ?? 0,
      completeCount: completeCount ?? existing?.completeCount ?? 0,
      skipCount: existing?.skipCount ?? 0,
      lastPlayedAt: lastPlayedAt ?? existing?.lastPlayedAt,
      lastSkippedAt: existing?.lastSkippedAt,
      lastCompletedAt: lastCompletedAt ?? existing?.lastCompletedAt,
      userScoreBoost: existing?.userScoreBoost ?? 0,
      preferredWaveMode: existing?.preferredWaveMode,
      updatedAt: updatedAt,
    );
  }

  Duration _clampPosition(Duration position, Duration? duration) {
    if (position < Duration.zero) {
      return Duration.zero;
    }
    if (duration != null && position > duration) {
      return duration;
    }
    return position;
  }

  String _describeError(Object error) {
    if (error is just_audio.PlayerException) {
      final message = error.message;
      if (message != null && message.isNotEmpty) {
        return message;
      }
      return 'Audio player error ${error.code}';
    }

    return error.toString();
  }
}
