import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';

import '../core/async_lifecycle.dart';
import '../diagnostics/diagnostics_service.dart';
import '../domain/models/track.dart';
import '../player/player_service.dart';
import '../player/player_state.dart';
import '../queue/playback_queue_service.dart';
import '../smtc/smtc_service.dart';
import 'android_audio_session.dart';

typedef RegisterAndroidMediaHandler = Future<void> Function(AppAudioHandler);

const androidAudioServiceConfig = AudioServiceConfig(
  androidNotificationChannelId:
      'dev.lunatuk.clever_music_player.preview.playback',
  androidNotificationChannelName: 'Воспроизведение музыки',
  androidNotificationIcon: 'drawable/music_notification',
  androidNotificationOngoing: true,
  // Release the wake lock while paused. Notification actions resume playback.
  androidStopForegroundOnPause: true,
  artDownscaleWidth: 384,
  artDownscaleHeight: 384,
  preloadArtwork: false,
);

final class AndroidMediaControlsService implements SmtcService {
  AndroidMediaControlsService(
      {required PlayerService player,
      required PlaybackQueueService queue,
      required this.diagnostics,
      AndroidAudioSession? session,
      RegisterAndroidMediaHandler? register,
      Stream<Object>? nativeErrors,
      DateTime Function()? clock})
      : _session = session ?? PluginAndroidAudioSession(),
        _register = register ?? _registerPlugin,
        _nativeErrors = nativeErrors ?? AudioService.asyncError {
    handler = AppAudioHandler(
        player: player,
        playbackQueue: queue,
        diagnostics: diagnostics,
        deactivate: _session.deactivate,
        clock: clock);
  }
  final DiagnosticsService diagnostics;
  final AndroidAudioSession _session;
  final RegisterAndroidMediaHandler _register;
  final Stream<Object> _nativeErrors;
  late final AppAudioHandler handler;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Future<void>? _initializing, _closing;
  bool _disposed = false;

  static Future<void> _registerPlugin(AppAudioHandler handler) async {
    await AudioService.init(
        builder: () => handler, config: androidAudioServiceConfig);
  }

  @override
  Future<void> initialize() {
    if (_disposed) return Future.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    _subscriptions.add(_nativeErrors.listen((error) {
      diagnostics.record(DiagnosticEvent.systemMediaFailed, error: error);
    }));
    await _session.configure();
    if (_disposed) return;
    _subscriptions
        .add(_session.interruptions.listen((_) => _pauseForInterruption()));
    _subscriptions
        .add(_session.becomingNoisy.listen((_) => _pauseForInterruption()));
    await _register(handler);
    if (_disposed) return;
    handler.start();
    diagnostics.record(DiagnosticEvent.systemMediaReady);
  }

  void _pauseForInterruption() {
    if (_disposed) return;
    unawaited(handler.pause().catchError((Object error, StackTrace stack) {
      diagnostics.record(DiagnosticEvent.audioOperationFailed, error: error);
    }));
  }

  Future<void> stop() => handler.stop();

  @override
  Future<void> dispose() {
    _disposed = true;
    handler.closeAdmission();
    return _closing ??= finishCleanup([
      () async {
        try {
          await _initializing;
        } on Object {/* startup rollback */}
      },
      () => finishCleanup(_subscriptions.map((s) => s.cancel)),
      handler.close,
      _session.deactivate,
    ]);
  }
}

/// A projection/command adapter over the application's existing player/queue.
/// No decoder, playback queue or database connection is created here.
final class AppAudioHandler extends BaseAudioHandler {
  AppAudioHandler(
      {required PlayerService player,
      required PlaybackQueueService playbackQueue,
      required this.diagnostics,
      Future<void> Function()? deactivate,
      DateTime Function()? clock})
      : _player = player,
        _playbackQueue = playbackQueue,
        _deactivate = deactivate ?? _noop,
        _clock = clock ?? DateTime.now;
  final PlayerService _player;
  final PlaybackQueueService _playbackQueue;
  final DiagnosticsService diagnostics;
  final Future<void> Function() _deactivate;
  final DateTime Function() _clock;
  final _operations = AsyncOperationTracker();
  StreamSubscription<PlayerState>? _playerSubscription;
  StreamSubscription<Object?>? _queueSubscription;
  PlayerState? _publishedState;
  bool? _publishedContinuing;
  DateTime? _publishedAt;
  Track? _publishedMediaTrack;
  Duration? _publishedMediaDuration;
  bool _closed = false, _started = false, _stopping = false;
  Future<void>? _closing;
  static Future<void> _noop() async {}

  void start() {
    if (_closed || _started) return;
    _started = true;
    _playerSubscription = _player.stateStream.listen((state) {
      // Give the existing automatic recovery coordinator its first microtask.
      if (state.status == PlayerPlaybackStatus.error) {
        scheduleMicrotask(() => _publish());
      } else {
        _publish();
      }
    });
    _queueSubscription = _playbackQueue.stateStream.listen((_) => _publish());
    _publish(force: true);
  }

  bool _continues(PlayerState state) =>
      (state.status == PlayerPlaybackStatus.completed &&
          _playbackQueue.state.canAdvance) ||
      (state.status == PlayerPlaybackStatus.error &&
          (_playbackQueue.state.isChoosingNext ||
              _playbackQueue.isRecoveringAutomatically));

  void _publish({bool force = false}) {
    if (_closed) return;
    final state = _player.state;
    final continuing = _continues(state);
    final now = _clock();
    if (force ||
        state.currentTrack != _publishedMediaTrack ||
        state.duration != _publishedMediaDuration) {
      _publishedMediaTrack = state.currentTrack;
      _publishedMediaDuration = state.duration;
      mediaItem.add(state.currentTrack == null
          ? null
          : _mediaItem(state.currentTrack!, state.duration));
    }
    final previous = _publishedState;
    final estimated = previous == null
        ? Duration.zero
        : previous.position +
            (previous.isPlaying &&
                    previous.status == PlayerPlaybackStatus.playing
                ? now.difference(_publishedAt!)
                : Duration.zero);
    final positionChanged =
        (state.position - estimated).abs() >= const Duration(milliseconds: 750);
    if (!force &&
        previous != null &&
        previous.currentTrack == state.currentTrack &&
        previous.status == state.status &&
        previous.isPlaying == state.isPlaying &&
        previous.duration == state.duration &&
        continuing == _publishedContinuing &&
        !positionChanged) {
      return;
    }
    _publishedState = state;
    _publishedAt = now;
    _publishedContinuing = continuing;
    final processing = continuing
        ? AudioProcessingState.buffering
        : switch (state.status) {
            PlayerPlaybackStatus.idle ||
            PlayerPlaybackStatus.stopped =>
              _stopping
                  ? AudioProcessingState.ready
                  : AudioProcessingState.idle,
            PlayerPlaybackStatus.loading => AudioProcessingState.loading,
            PlayerPlaybackStatus.playing ||
            PlayerPlaybackStatus.paused =>
              AudioProcessingState.ready,
            PlayerPlaybackStatus.completed => AudioProcessingState.completed,
            PlayerPlaybackStatus.error => AudioProcessingState.error,
          };
    final playing = state.isPlaying || continuing;
    playbackState.add(PlaybackState(
      controls: state.currentTrack == null
          ? const []
          : [
              MediaControl.skipToPrevious,
              playing ? MediaControl.pause : MediaControl.play,
              MediaControl.skipToNext,
              MediaControl.stop,
            ],
      androidCompactActionIndices:
          state.currentTrack == null ? const [] : const [0, 1, 2],
      systemActions: const {MediaAction.seek, MediaAction.playPause},
      processingState: processing,
      playing: playing,
      updatePosition: state.position,
      updateTime: now,
      errorCode: processing == AudioProcessingState.error ? 1 : null,
      errorMessage: processing == AudioProcessingState.error
          ? 'Не удалось воспроизвести трек. Выберите другой файл.'
          : null,
    ));
  }

  static MediaItem _mediaItem(Track track, Duration? duration) {
    final artwork = track.customArtworkPath ?? track.artworkPath;
    return MediaItem(
        id: track.id == null
            ? 'track:${sha256.convert(utf8.encode(track.filePath))}'
            : 'track:${track.id}',
        title: track.displayTitle,
        artist: track.artist,
        album: track.album,
        duration: duration ?? track.duration,
        artUri: artwork == null ? null : Uri.file(artwork));
  }

  Future<void> _command(Future<void> Function() action) =>
      _operations.run(() async {
        if (_closed) return;
        try {
          await action();
        } on Object catch (error) {
          diagnostics.record(DiagnosticEvent.systemMediaFailed, error: error);
          rethrow;
        }
      });
  @override
  Future<void> play() => _command(_player.play);
  @override
  Future<void> pause() => _command(_player.pause);
  @override
  Future<void> seek(Duration position) => _command(() async {
        await _player.seek(position);
        _publish(force: true);
      });
  @override
  Future<void> skipToNext() => _command(_playbackQueue.next);
  @override
  Future<void> skipToPrevious() => _command(_playbackQueue.previous);
  @override
  Future<void> stop() => _command(() async {
        _stopping = true;
        try {
          await _player.stop();
          if (_player.state.status == PlayerPlaybackStatus.stopped) {
            await _deactivate();
          }
        } finally {
          _stopping = false;
          _publish(force: true);
        }
      });
  @override
  Future<void> onTaskRemoved() async {
    if (!_player.isPlaying) await stop();
  }

  void closeAdmission() {
    _closed = true;
    _operations.closeAdmission();
  }

  Future<void> close() {
    closeAdmission();
    return _closing ??= finishCleanup([
      () async {
        await _playerSubscription?.cancel();
      },
      () async {
        await _queueSubscription?.cancel();
      },
      _operations.drain,
      () async {
        playbackState
            .add(PlaybackState(processingState: AudioProcessingState.idle));
        await playbackState.close();
      },
      mediaItem.close,
      queue.close,
      queueTitle.close,
      androidPlaybackInfo.close,
      ratingStyle.close,
      customEvent.close,
      customState.close,
    ]);
  }
}
