import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:path/path.dart' as p;

import '../diagnostics/diagnostics_service.dart';
import '../core/async_lifecycle.dart';
import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';
import 'player_service.dart';
import 'player_state.dart';
import 'windows_playback_cache.dart';
import 'windows_playback_snapshot.dart';

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

  Stream<Object> get errorStream;

  Duration get position;

  Duration? get duration;

  Future<Duration?> setSource(AudioSourceReference source,
      {bool preload = true});

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seek(Duration position);

  Future<void> setVolume(double volume);

  Future<void> dispose();
}

final class JustAudioEngine implements LocalAudioEngine {
  JustAudioEngine(
      {just_audio.AudioPlayer? player,
      bool? isAndroid,
      bool? isWindows,
      Duration windowsLoadTimeout = const Duration(seconds: 20),
      bool handleInterruptions = true})
      : assert(windowsLoadTimeout > Duration.zero),
        _player = player ??
            just_audio.AudioPlayer(handleInterruptions: handleInterruptions),
        _isAndroid = isAndroid ?? Platform.isAndroid,
        _isWindows = (isWindows ?? Platform.isWindows) &&
            !(isAndroid ?? Platform.isAndroid),
        _windowsLoadTimeout = windowsLoadTimeout;

  final just_audio.AudioPlayer _player;
  final bool _isAndroid;
  final bool _isWindows;
  final Duration _windowsLoadTimeout;
  int _loadRevision = 0;

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
  Stream<Object> get errorStream => _player.errorStream;

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  Future<Duration?> setSource(AudioSourceReference source,
      {bool preload = true}) {
    switch (source) {
      case FileAudioSource(:final path):
        return _isWindows
            ? _loadWindows(() => _player.setFilePath(path, preload: preload))
            : _player.setFilePath(path, preload: preload);
      case ContentUriAudioSource(:final uri):
        if (!_isAndroid) {
          return Future.error(UnsupportedError('Content URI требует Android.'));
        }
        return _player.setAudioSource(just_audio.ProgressiveAudioSource(uri),
            preload: preload);
    }
  }

  Future<Duration?> _loadWindows(Future<Duration?> Function() load) async {
    final revision = ++_loadRevision;
    final result = Completer<Duration?>();
    just_audio.PlayerException? nativeFailure;
    // Install before load: an error can precede the first Opening event.
    final subscription = _player.errorStream.listen((error) {
      if (revision != _loadRevision) return;
      nativeFailure ??= error;
      if (!result.isCompleted) result.completeError(error);
    });
    final loading = Future<Duration?>.sync(load);
    unawaited(loading.then<void>((duration) {
      if (!result.isCompleted) result.complete(duration);
    }, onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    }));
    try {
      return await result.future.timeout(_windowsLoadTimeout);
    } on Object catch (error, stack) {
      // stop() interrupts just_audio's pending load and releases its platform.
      // Drain it before allowing the service's next command/cache attempt.
      if (revision == _loadRevision) await _player.stop();
      try {
        await loading.timeout(const Duration(seconds: 1));
      } on Object {
        // The platform is disposed. A lost old method response must not block
        // a new decoder; the handlers above still consume any late result.
      }
      Error.throwWithStackTrace(nativeFailure ?? error, stack);
    } finally {
      await subscription.cancel();
    }
  }

  /// Convenience for the existing native protocol tests and path callers.
  Future<Duration?> setFilePath(String filePath, {bool preload = true}) {
    return setSource(FileAudioSource(filePath), preload: preload);
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
    _loadRevision++;
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
    _loadRevision++;
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

const _defaultWindowsProgressRecoveryInterval = Duration(milliseconds: 250);
const _defaultWindowsSyntheticProgressGrace = Duration(seconds: 2);
const _volumeSettingKey = 'player.volume';
const _previousVolumeBeforeMuteSettingKey = 'player.previousVolumeBeforeMute';
const _defaultVolume = 1.0;
const _volumeStep = 0.05;
const _windowsPlaybackCachePathLengthThreshold = 180;
const _playbackLoadFailureMessage =
    'Не удалось воспроизвести трек. Возможно, файл недоступен, повреждён или '
    'имеет неподдерживаемый формат.';

final class JustAudioPlayerService implements PlayerService {
  JustAudioPlayerService({
    required PlaybackEventRepository playbackEvents,
    SettingsRepository? settings,
    this.diagnostics = const NoopDiagnosticsService(),
    LocalAudioEngine? audioEngine,
    bool Function(String filePath)? fileExists,
    bool? isWindows,
    PlaybackCache? playbackCache,
    WindowsPlaybackProbe? windowsPlaybackProbe,
    @visibleForTesting
    Duration windowsDiagnosticsDelay = const Duration(seconds: 3),
    @visibleForTesting Duration windowsProgressRecoveryInterval =
        _defaultWindowsProgressRecoveryInterval,
    @visibleForTesting Duration windowsSyntheticProgressGrace =
        _defaultWindowsSyntheticProgressGrace,
  })  : assert(windowsProgressRecoveryInterval > Duration.zero),
        assert(windowsDiagnosticsDelay > Duration.zero),
        assert(windowsSyntheticProgressGrace >= Duration.zero),
        _playbackEvents = playbackEvents,
        _settings = settings,
        _audioEngine = audioEngine ?? JustAudioEngine(),
        _isWindows = isWindows ?? Platform.isWindows,
        _playbackCache = playbackCache ?? WindowsPlaybackCache(),
        _windowsPlaybackProbe = windowsPlaybackProbe ??
            ((audioEngine == null || audioEngine is JustAudioEngine)
                ? readWindowsPlaybackSnapshots
                : null),
        _windowsDiagnosticsDelay = windowsDiagnosticsDelay,
        _windowsProgressRecoveryInterval = windowsProgressRecoveryInterval,
        _windowsSyntheticProgressGrace = windowsSyntheticProgressGrace,
        _fileExists =
            fileExists ?? ((filePath) => File(filePath).existsSync()) {
    _subscriptions
      ..add(_audioEngine.stateStream.listen(_handleAudioState))
      ..add(_audioEngine.positionStream.listen(_handlePosition))
      ..add(_audioEngine.durationStream.listen(_handleDuration))
      ..add(_audioEngine.errorStream.listen(_handleAudioError));
  }

  final DiagnosticsService diagnostics;
  final PlaybackEventRepository _playbackEvents;
  final SettingsRepository? _settings;
  final LocalAudioEngine _audioEngine;
  final bool _isWindows;
  final PlaybackCache _playbackCache;
  final WindowsPlaybackProbe? _windowsPlaybackProbe;
  final Duration _windowsDiagnosticsDelay;
  final Duration _windowsProgressRecoveryInterval;
  final Duration _windowsSyntheticProgressGrace;
  final bool Function(String filePath) _fileExists;
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  PlayerState _state = const PlayerState.idle();
  bool _isDisposed = false;
  final _operations = AsyncOperationTracker();
  final Set<Completer<void>> _playWaiters = {};
  Future<void>? _closing;
  bool _didRecordCompletion = false;
  int _sessionGeneration = 0;
  int _transportRevision = 0;
  int? _pendingTransportRevision;
  int _seekRevision = 0;
  int? _loadingGeneration;
  int? _engineGeneration;
  bool _wantsToPlay = false;
  bool _hasStartedSession = false;
  Duration? _pendingSeek;
  Future<void> _engineCommands = Future<void>.value();
  Future<void> _outputCommands = Future<void>.value();
  double _requestedVolume = _defaultVolume;
  int _volumeRevision = 0;
  int _positionEventsSinceLoad = 0;
  int _durationEventsSinceLoad = 0;
  Timer? _positionDiagnosticsTimer;
  Timer? _windowsProgressRecoveryTimer;
  DateTime? _lastWindowsRealProgressAt;
  DateTime? _windowsSyntheticAnchorTime;
  Duration _windowsSyntheticAnchorPosition = Duration.zero;
  Duration? _lastWindowsPolledPosition;
  String? _leasedCachePath;
  double _outputGain = 1;
  double _previousVolumeBeforeMute = _defaultVolume;
  final Set<String> _windowsDirectLoadFailures = <String>{};

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
  Future<void> playTrack(Track track) => _loadTrack(track, startPlaying: true);

  /// Load and open the decoder without playing or recording a listening event.
  Future<void> prepareTrack(Track track) =>
      _loadTrack(track, startPlaying: false);

  /// Only the audio engine's timeline is used to trigger early transitions.
  /// Metadata duration and the Windows UI clock can be approximate.
  Duration? get transitionRemaining {
    if (_state.status != PlayerPlaybackStatus.playing) return null;
    final duration = _audioEngine.duration;
    final position = _audioEngine.position;
    if (duration == null ||
        duration <= Duration.zero ||
        position <= Duration.zero) {
      return null;
    }
    return duration - position;
  }

  Future<void> setOutputGain(double gain) => _operations.run(() async {
        if (_isDisposed) return;
        _outputGain = gain.clamp(0.0, 1.0);
        final generation = _sessionGeneration;
        try {
          await _applyOutputVolume();
        } on Object catch (error) {
          if (_isCurrentSession(generation)) {
            await _stopAfterFailure(generation,
                'Не удалось изменить громкость перехода: ${_describeError(error)}');
          }
        }
      });

  /// Output commands have their own queue: a slow cache/source load must not
  /// block volume controls, but an old fade must never finish after a newer
  /// foreground gain and leave that decoder silent. Read the latest intent
  /// when the command reaches the engine, including a concurrent mute/volume.
  Future<double> _applyOutputVolume() {
    final result = _outputCommands.then((_) async {
      final output = _requestedVolume * _outputGain;
      if (!_isDisposed) {
        await _audioEngine.setVolume(output);
      }
      return output;
    });
    _outputCommands =
        result.then((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// A full automatic fade finishes the outgoing listening session once.
  /// Interrupted fades (seek, manual selection, stop) use stop() instead.
  Future<void> finishCrossfade() => _operations.run(() async {
        final track = currentTrack;
        final generation = _sessionGeneration;
        if (!_isDisposed &&
            track != null &&
            _hasStartedSession &&
            !_didRecordCompletion) {
          _didRecordCompletion = true;
          await _recordPlaybackCompleted(track);
        }
        if (_isCurrentSession(generation)) await stop();
      });

  Future<void> _loadTrack(Track track, {required bool startPlaying}) =>
      _operations.run(() async {
        if (_isDisposed) return;
        final timer = Stopwatch()..start();
        diagnostics.record(DiagnosticEvent.audioLoadStarted, fields: {
          DiagnosticField.trackId: track.id,
          DiagnosticField.preparing: !startPlaying,
        });
        final generation = ++_sessionGeneration;
        _transportRevision++;
        _pendingTransportRevision = null;
        _seekRevision++;
        _loadingGeneration = generation;
        _engineGeneration = null;
        _wantsToPlay = startPlaying;
        _hasStartedSession = false;
        _pendingSeek = null;
        _resetPlaybackDiagnostics();
        _resetWindowsProgressRecovery();
        _didRecordCompletion = false;
        String? normalizedPath;
        _emit(_state.copyWith(
          currentTrack: track,
          isPlaying: startPlaying,
          position: Duration.zero,
          duration: _effectiveDuration(null, track),
          status: PlayerPlaybackStatus.loading,
          errorMessage: null,
        ));

        _scheduleWindowsPositionDiagnostics(track, opening: true);

        try {
          final source = track.source;
          final AudioSourceReference resolved;
          if (source is FileAudioSource) {
            normalizedPath = _normalizedAbsolutePath(source.path);
            resolved = FileAudioSource(normalizedPath);
            _debugLogPlaybackDiagnostics(
              originalPath: source.path,
              sourcePath: normalizedPath,
              strategy: _initialLoadStrategy(normalizedPath),
              targetPath: _shouldUseWindowsPlaybackCache(normalizedPath)
                  ? null
                  : normalizedPath,
            );
            if (!_fileExists(normalizedPath)) {
              diagnostics.record(DiagnosticEvent.sourceMissing,
                  fields: {DiagnosticField.trackId: track.id});
              throw FileSystemException('File not found', normalizedPath);
            }
          } else {
            resolved = source;
          }
          await _runEngineCommand(generation, () async {
            await _stopEngine();
            _checkSession(generation);
            final loaded = await _loadTrackAudio(track, resolved, generation,
                preload: true);
            _checkSession(generation);
            final duration = _effectiveDuration(loaded.duration, track);
            // A seek can arrive while loading or while an earlier seek is pending.
            // Apply the latest target before enabling playback of this source.
            while (_pendingSeek != null) {
              final revision = _seekRevision;
              final target = _clampPosition(_pendingSeek!, duration);
              await _audioEngine.seek(target);
              _checkSession(generation);
              if (revision == _seekRevision) {
                _pendingSeek = null;
                _emit(_state.copyWith(position: target));
              }
            }
            _loadingGeneration = null;
            _engineGeneration = generation;
            if (!_wantsToPlay) _pendingTransportRevision = null;
            _emit(_state.copyWith(
              duration: duration,
              isPlaying: _wantsToPlay,
              status: _wantsToPlay
                  ? PlayerPlaybackStatus.playing
                  : PlayerPlaybackStatus.paused,
              errorMessage: null,
            ));
            diagnostics.record(DiagnosticEvent.audioLoadCompleted, fields: {
              DiagnosticField.trackId: track.id,
              DiagnosticField.elapsedMs: timer.elapsedMilliseconds,
              DiagnosticField.durationMs: duration?.inMilliseconds,
              DiagnosticField.preparing: !startPlaying,
              DiagnosticField.cached: _leasedCachePath != null,
            });
            if (_wantsToPlay) await _startPlayback(generation, track);
          });
        } on Object catch (error) {
          if (!_isCurrentSession(generation)) return;
          diagnostics.record(DiagnosticEvent.audioLoadFailed,
              error: _playbackLoadCause(error),
              fields: {
                DiagnosticField.trackId: track.id,
                DiagnosticField.elapsedMs: timer.elapsedMilliseconds,
                if (_playbackLoadCause(error) case just_audio.PlayerException e)
                  DiagnosticField.nativeCode: e.code,
              });
          if (normalizedPath != null) {
            _debugLogPlaybackDiagnostics(
              originalPath: track.filePath,
              sourcePath: normalizedPath,
              strategy: _initialLoadStrategy(normalizedPath),
              error: error,
            );
          }
          await _stopAfterFailure(generation, _playbackLoadFailureMessage,
              failureKind: PlayerFailureKind.source);
        }
      });

  @override
  Future<void> play() => _operations.run(() async {
        if (_isDisposed) return;
        final track = _state.currentTrack;
        if (track == null) {
          _emit(_state.copyWith(
            status: PlayerPlaybackStatus.error,
            errorMessage: 'Выберите трек для воспроизведения.',
          ));
          return;
        }
        if (_state.status == PlayerPlaybackStatus.error ||
            _state.status == PlayerPlaybackStatus.completed) {
          await playTrack(track);
          return;
        }
        if (_wantsToPlay) return;
        final generation = _sessionGeneration;
        final revision = ++_transportRevision;
        _pendingTransportRevision = revision;
        _wantsToPlay = true;
        _emit(_state.copyWith(
          isPlaying: true,
          status: _loadingGeneration == generation
              ? PlayerPlaybackStatus.loading
              : PlayerPlaybackStatus.playing,
          errorMessage: null,
        ));
        if (_loadingGeneration == generation) return;
        try {
          await _runEngineCommand(generation, () async {
            if (revision != _transportRevision) return;
            await _startPlayback(generation, track);
          });
        } on Object {
          if (_isCurrentSession(generation) && revision == _transportRevision) {
            await _stopAfterFailure(
                generation, 'Не удалось настроить громкость воспроизведения.');
          }
        }
      });

  @override
  Future<void> pause() => _operations.run(() async {
        if (_isDisposed || _state.currentTrack == null || !_wantsToPlay) return;
        diagnostics.record(DiagnosticEvent.audioPauseRequested,
            fields: {DiagnosticField.trackId: currentTrack?.id});
        final track = _state.currentTrack!;
        final generation = _sessionGeneration;
        final revision = ++_transportRevision;
        _pendingTransportRevision = revision;
        _wantsToPlay = false;
        _resetWindowsProgressRecovery();
        _emit(_state.copyWith(
          isPlaying: false,
          status: PlayerPlaybackStatus.paused,
          errorMessage: null,
        ));
        if (_loadingGeneration == generation) return;
        try {
          await _runEngineCommand(generation, () async {
            if (revision != _transportRevision) return;
            await _audioEngine.pause();
            if (!_isCurrentSession(generation) ||
                revision != _transportRevision) {
              return;
            }
            if (_hasStartedSession) {
              unawaited(_recordEvent(track, PlaybackEventType.paused));
            }
          });
        } on Object catch (error) {
          if (!_isCurrentSession(generation) ||
              revision != _transportRevision) {
            return;
          }
          await _stopAfterFailure(generation,
              'Не удалось поставить воспроизведение на паузу: ${_describeError(error)}');
        }
      });

  @override
  Future<void> stop() => _operations.run(() async {
        if (_isDisposed) return;
        final generation = ++_sessionGeneration;
        _transportRevision++;
        _pendingTransportRevision = null;
        _seekRevision++;
        _loadingGeneration = null;
        _engineGeneration = null;
        _wantsToPlay = false;
        _hasStartedSession = false;
        _pendingSeek = null;
        _resetPlaybackDiagnostics();
        _resetWindowsProgressRecovery();
        _didRecordCompletion = false;
        _emit(PlayerState(
            volume: _state.volume, status: PlayerPlaybackStatus.stopped));
        try {
          await _runEngineCommand(generation, _stopEngine);
        } on Object catch (error) {
          if (!_isCurrentSession(generation)) return;
          await _stopAfterFailure(generation,
              'Не удалось остановить воспроизведение: ${_describeError(error)}');
        }
      });

  @override
  Future<void> seek(Duration position) => _operations.run(() async {
        if (_isDisposed || _state.currentTrack == null) return;
        final generation = _sessionGeneration;
        final revision = ++_seekRevision;
        final target = _clampPosition(position, _state.duration);
        _pendingSeek = target;
        _resetWindowsProgressRecovery();
        _emit(_state.copyWith(position: target, errorMessage: null));
        if (_loadingGeneration == generation) return;
        try {
          await _runEngineCommand(generation, () async {
            if (revision != _seekRevision) return;
            await _audioEngine.seek(target);
            if (!_isCurrentSession(generation) || revision != _seekRevision) {
              return;
            }
            _pendingSeek = null;
            _emit(_state.copyWith(position: target, errorMessage: null));
            _startWindowsProgressRecovery(anchorPosition: target);
          });
        } on Object catch (error) {
          if (!_isCurrentSession(generation) || revision != _seekRevision) {
            return;
          }
          await _stopAfterFailure(generation,
              'Не удалось перейти к позиции: ${_describeError(error)}');
        }
      });

  bool _isCurrentSession(int generation) =>
      !_isDisposed && generation == _sessionGeneration;

  void _checkSession(int generation) {
    if (!_isCurrentSession(generation)) throw const _ObsoletePlayback();
  }

  Future<void> _runEngineCommand(
    int generation,
    Future<void> Function() command,
  ) {
    final result = _engineCommands.then((_) async {
      if (_isCurrentSession(generation)) await command();
    });
    // A failed command must not prevent later commands from being processed.
    _engineCommands =
        result.then((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _startPlayback(int generation, Track track) async {
    if (!_isCurrentSession(generation) || !_wantsToPlay) return;
    final revision = _transportRevision;
    // stop/load can replace the native decoder. Confirm the latest output on
    // that decoder before Play, including prepared-deck promotion/resume.
    // The caller handles errors after leaving the transport queue: stopping
    // through that same queue here would wait on this command itself.
    final outputVolume = await _applyOutputVolume();
    if (!_isCurrentSession(generation) ||
        revision != _transportRevision ||
        !_wantsToPlay) {
      return;
    }
    diagnostics.record(DiagnosticEvent.audioPlayRequested, fields: {
      DiagnosticField.trackId: track.id,
      DiagnosticField.outputVolume: outputVolume,
      DiagnosticField.outputGain: _outputGain,
    });
    if (_hasStartedSession) {
      unawaited(_recordEvent(track, PlaybackEventType.resumed));
    } else {
      _hasStartedSession = true;
      unawaited(_recordPlaybackStarted(track));
    }
    _startWindowsProgressRecovery(anchorPosition: _state.position);
    _scheduleWindowsPositionDiagnostics(track);
    _pendingTransportRevision = revision;
    unawaited(_playAndReportErrors(generation, revision));
  }

  @override
  Future<void> setVolume(double volume) => _operations.run(() async {
        if (_isDisposed) return;
        final normalizedVolume = _normalizeVolume(volume);
        _requestedVolume = normalizedVolume;
        final revision = ++_volumeRevision;
        try {
          await _applyOutputVolume();
          if (_isDisposed || revision != _volumeRevision) return;
          if (normalizedVolume > 0) {
            _previousVolumeBeforeMute = normalizedVolume;
          }
          _emit(
            _state.copyWith(
              volume: normalizedVolume,
              errorMessage: null,
            ),
          );
          await _persistVolume(normalizedVolume);
        } on Object catch (error) {
          if (_isDisposed || revision != _volumeRevision) return;
          _emitPlaybackError(
            'Не удалось изменить громкость: ${_describeError(error)}',
          );
        }
      });

  @override
  Future<void> increaseVolume() {
    return setVolume(_state.volume + _volumeStep);
  }

  @override
  Future<void> decreaseVolume() {
    return setVolume(_state.volume - _volumeStep);
  }

  @override
  Future<void> toggleMute() => _operations.run(() async {
        if (_isDisposed) return;
        if (_state.volume > 0) {
          _previousVolumeBeforeMute = _state.volume;
          await _persistPreviousVolumeBeforeMute(_previousVolumeBeforeMute);
          await setVolume(0);
          return;
        }

        await setVolume(_volumeToRestoreAfterMute());
      });

  Future<void> restoreSavedVolume() => _operations.run(() async {
        final settings = _settings;
        if (settings == null || _isDisposed) {
          return;
        }

        final savedPreviousVolume = _parseVolume(
            await settings.readString(_previousVolumeBeforeMuteSettingKey));
        if (_isDisposed) return;
        if (savedPreviousVolume != null && savedPreviousVolume > 0) {
          _previousVolumeBeforeMute = savedPreviousVolume;
        }

        final savedVolume =
            _parseVolume(await settings.readString(_volumeSettingKey));
        if (_isDisposed) return;
        if (savedVolume == null) {
          return;
        }

        await setVolume(savedVolume);
      });

  @override
  Future<void> dispose() {
    if (_closing != null) return _closing!;
    _isDisposed = true;
    _operations.closeAdmission();
    _positionDiagnosticsTimer?.cancel();
    _resetWindowsProgressRecovery();
    _sessionGeneration++;
    _engineGeneration = null;
    _loadingGeneration = null;
    _wantsToPlay = false;
    _pendingTransportRevision = null;
    for (final waiter in _playWaiters.toList(growable: false)) {
      if (!waiter.isCompleted) waiter.complete();
    }
    return _closing = finishCleanup([
      for (final subscription in _subscriptions) subscription.cancel,
      // Dispose interrupts native play/load futures. Waiting for those first
      // would deadlock on engines whose play completes only at track end.
      _audioEngine.dispose,
      _operations.drain,
      () async {
        _releaseCacheLease();
      },
      _stateController.close,
    ]);
  }

  bool get _canHandleEngineEvents =>
      !_isDisposed &&
      _engineGeneration == _sessionGeneration &&
      _loadingGeneration == null &&
      _state.currentTrack != null &&
      _state.status != PlayerPlaybackStatus.error;

  void _handleAudioState(AudioEngineState audioState) {
    if (!_canHandleEngineEvents ||
        _state.status == PlayerPlaybackStatus.completed) {
      return;
    }
    final completed =
        audioState.processingState == AudioEngineProcessingState.completed;
    var transportAcknowledged = false;
    if (audioState.processingState == AudioEngineProcessingState.idle ||
        (completed && (!_wantsToPlay || !_hasStartedSession))) {
      return;
    }
    if (completed) {
      _wantsToPlay = false;
      _pendingTransportRevision = null;
      _transportRevision++;
    } else if (_pendingTransportRevision != null) {
      // Ignore a queued notification of the previous transport intent. Once
      // the engine confirms this command, native interruptions can pause it.
      if (audioState.isPlaying != _wantsToPlay) return;
      _pendingTransportRevision = null;
      transportAcknowledged = true;
    } else if (audioState.isPlaying != _wantsToPlay) {
      _wantsToPlay = audioState.isPlaying;
      _transportRevision++;
    }
    final buffering =
        audioState.processingState == AudioEngineProcessingState.loading ||
            audioState.processingState == AudioEngineProcessingState.buffering;
    final status = completed
        ? PlayerPlaybackStatus.completed
        : !_wantsToPlay
            ? PlayerPlaybackStatus.paused
            : buffering
                ? PlayerPlaybackStatus.loading
                : PlayerPlaybackStatus.playing;
    if (transportAcknowledged ||
        status != _state.status ||
        _wantsToPlay != _state.isPlaying) {
      diagnostics.record(DiagnosticEvent.audioStateChanged, fields: {
        DiagnosticField.trackId: currentTrack?.id,
        DiagnosticField.playing: _wantsToPlay,
      });
    }
    _emit(_state.copyWith(
      isPlaying: _wantsToPlay,
      position: completed && _state.duration != null
          ? _state.duration!
          : _state.position,
      status: status,
    ));
    if (completed || status != PlayerPlaybackStatus.playing) {
      _resetWindowsProgressRecovery();
    } else {
      _startWindowsProgressRecovery(anchorPosition: _state.position);
    }
    final track = _state.currentTrack;
    if (completed && track != null && !_didRecordCompletion) {
      _didRecordCompletion = true;
      unawaited(_recordPlaybackCompleted(track));
    }
  }

  void _handlePosition(Duration position) {
    if (!_canHandleEngineEvents ||
        _pendingSeek != null ||
        _state.status == PlayerPlaybackStatus.completed) {
      return;
    }
    _positionEventsSinceLoad++;
    final previousPosition = _state.position;
    _emit(_state.copyWith(position: position));
    if (_isWindows && position != previousPosition) {
      _recordWindowsRealProgress(position);
    }
  }

  void _handleDuration(Duration? duration) {
    if (!_canHandleEngineEvents) return;
    _durationEventsSinceLoad++;
    _emit(_state.copyWith(
        duration: _effectiveDuration(duration, _state.currentTrack)));
  }

  void _handleAudioError(Object error) {
    if (!_canHandleEngineEvents ||
        _state.status == PlayerPlaybackStatus.completed) {
      return;
    }
    _debugLogAudioError(error);
    unawaited(_stopAfterFailure(_sessionGeneration, _playbackLoadFailureMessage,
        failureKind: PlayerFailureKind.source));
  }

  Future<_LoadedAudio> _loadTrackAudio(
    Track track,
    AudioSourceReference source,
    int generation, {
    required bool preload,
  }) async {
    if (source is ContentUriAudioSource) {
      final duration = await _audioEngine.setSource(source, preload: preload);
      _checkSession(generation);
      return _LoadedAudio(duration: duration);
    }
    final normalizedPath = (source as FileAudioSource).path;
    if (_shouldUseWindowsPlaybackCache(normalizedPath)) {
      return _loadFromWindowsCache(
        track: track,
        normalizedPath: normalizedPath,
        directError: null,
        generation: generation,
        preload: preload,
      );
    }

    try {
      final duration = await _audioEngine.setSource(
        source,
        preload: preload,
      );
      _checkSession(generation);
      return _LoadedAudio(duration: duration);
    } on Object catch (directError) {
      _checkSession(generation);
      _recordLoadAttemptFailure(track, directError, cached: false);
      _debugLogPlaybackDiagnostics(
        originalPath: track.filePath,
        sourcePath: normalizedPath,
        strategy: 'direct',
        targetPath: normalizedPath,
        error: directError,
      );
      if (!_isWindows) {
        rethrow;
      }

      _windowsDirectLoadFailures.add(normalizedPath);
      return _loadFromWindowsCache(
        track: track,
        normalizedPath: normalizedPath,
        directError: directError,
        generation: generation,
        preload: preload,
      );
    }
  }

  Future<_LoadedAudio> _loadFromWindowsCache({
    required Track track,
    required String normalizedPath,
    required Object? directError,
    required int generation,
    required bool preload,
  }) async {
    PlaybackCacheEntry? cached;
    final strategy =
        directError == null ? 'cache' : 'cache_after_direct_failure';
    try {
      final cache = _playbackCache;
      cached = cache is ProtectedPlaybackCache
          ? await cache.acquire(track, normalizedPath)
          : await cache.resolve(track, normalizedPath);
      if (!_isCurrentSession(generation)) {
        if (cache is ProtectedPlaybackCache) cache.release(cached.filePath);
        _checkSession(generation);
      }
      if (cache is ProtectedPlaybackCache) _leasedCachePath = cached.filePath;
      _debugLogPlaybackDiagnostics(
        originalPath: track.filePath,
        sourcePath: normalizedPath,
        strategy: strategy,
        targetPath: cached.filePath,
        cacheEntry: cached,
      );
      final duration = await _audioEngine.setSource(
        FileAudioSource(cached.filePath),
        preload: preload,
      );
      _checkSession(generation);
      return _LoadedAudio(duration: duration);
    } on Object catch (cacheError) {
      _checkSession(generation);
      _recordLoadAttemptFailure(track, cacheError, cached: true);
      _debugLogPlaybackDiagnostics(
        originalPath: track.filePath,
        sourcePath: normalizedPath,
        strategy: strategy,
        targetPath: cached?.filePath,
        cacheEntry: cached,
        error: cacheError,
      );
      throw PlaybackLoadException(_playbackLoadFailureMessage,
          cause: cacheError);
    }
  }

  void _recordLoadAttemptFailure(Track track, Object error,
      {required bool cached}) {
    diagnostics.record(DiagnosticEvent.audioLoadAttemptFailed,
        error: _playbackLoadCause(error),
        fields: {
          DiagnosticField.trackId: track.id,
          DiagnosticField.cached: cached,
          if (_playbackLoadCause(error) case just_audio.PlayerException e)
            DiagnosticField.nativeCode: e.code,
        });
  }

  Future<void> _stopEngine() async {
    await _audioEngine.stop();
    _releaseCacheLease();
  }

  void _releaseCacheLease() {
    final path = _leasedCachePath;
    _leasedCachePath = null;
    final cache = _playbackCache;
    if (path != null && cache is ProtectedPlaybackCache) cache.release(path);
  }

  Future<void> _playAndReportErrors(int generation, int revision) =>
      _operations.run(() async {
        try {
          // just_audio's Play may wait until playback ends (or remain pending
          // after audio-session activation fails). Native disposal owns stopping
          // sound; this signal ends only our wait and handles any late error.
          await _waitForNativePlay();
        } on Object catch (error) {
          if (!_isCurrentSession(generation) ||
              revision != _transportRevision) {
            return;
          }
          _debugLogAudioError(error);
          await _stopAfterFailure(generation, _playbackLoadFailureMessage,
              failureKind: PlayerFailureKind.source);
        }
      });

  Future<void> _waitForNativePlay() {
    final waiter = Completer<void>();
    _playWaiters.add(waiter);
    unawaited(Future<void>.sync(_audioEngine.play).then((_) {
      if (!waiter.isCompleted) waiter.complete();
    }, onError: (Object error, StackTrace stack) {
      if (!waiter.isCompleted) waiter.completeError(error, stack);
    }));
    return waiter.future.whenComplete(() => _playWaiters.remove(waiter));
  }

  Future<void> _stopAfterFailure(
    int generation,
    String message, {
    PlayerFailureKind failureKind = PlayerFailureKind.operation,
  }) =>
      _operations.run(() async {
        if (!_isCurrentSession(generation)) return;
        if (failureKind == PlayerFailureKind.operation) {
          diagnostics.record(DiagnosticEvent.audioOperationFailed,
              fields: {DiagnosticField.trackId: currentTrack?.id});
        }
        _transportRevision++;
        _pendingTransportRevision = null;
        _loadingGeneration = null;
        _engineGeneration = null;
        _wantsToPlay = false;
        _pendingSeek = null;
        _resetWindowsProgressRecovery();
        _didRecordCompletion = false;
        _emit(PlayerState(
          currentTrack: _state.currentTrack,
          duration: _state.duration,
          volume: _state.volume,
          status: PlayerPlaybackStatus.error,
          errorMessage: message,
          failureKind: failureKind,
        ));
        try {
          await _runEngineCommand(generation, _stopEngine);
        } on Object {
          // Keep the user-facing error focused on the original playback failure.
        }
      });

  void _emitPlaybackError(String message) {
    if (_isDisposed) return;
    _resetWindowsProgressRecovery();
    _wantsToPlay = false;
    _emit(_state.copyWith(
      isPlaying: false,
      status: PlayerPlaybackStatus.error,
      errorMessage: message,
    ));
  }

  void _emit(PlayerState state) {
    if (_isDisposed) {
      return;
    }

    _state = state;
    _stateController.add(state);
  }

  bool get _shouldRunWindowsProgressRecovery {
    return _isWindows &&
        !_isDisposed &&
        _state.currentTrack != null &&
        _state.isPlaying &&
        _state.status == PlayerPlaybackStatus.playing;
  }

  void _startWindowsProgressRecovery({Duration? anchorPosition}) {
    if (!_shouldRunWindowsProgressRecovery) {
      return;
    }
    if (_windowsProgressRecoveryTimer != null) {
      return;
    }

    _recordWindowsRealProgress(anchorPosition ?? _state.position);
    _windowsProgressRecoveryTimer = Timer.periodic(
      _windowsProgressRecoveryInterval,
      (_) => _recoverWindowsProgress(),
    );
  }

  void _recoverWindowsProgress() {
    if (!_shouldRunWindowsProgressRecovery) {
      _resetWindowsProgressRecovery();
      return;
    }

    _recoverWindowsDuration();
    final polledPosition = _clampPosition(
      _audioEngine.position,
      _state.duration,
    );
    final lastPolledPosition = _lastWindowsPolledPosition;
    _lastWindowsPolledPosition = polledPosition;

    if (polledPosition > Duration.zero &&
        (lastPolledPosition == null || polledPosition > lastPolledPosition)) {
      _recordWindowsRealProgress(polledPosition);
      if (polledPosition != _state.position) {
        _emit(_state.copyWith(position: polledPosition));
      }
      return;
    }

    _emitSyntheticWindowsProgressIfNeeded();
  }

  void _recoverWindowsDuration() {
    final polledDuration = _audioEngine.duration;
    if (polledDuration == null || polledDuration <= Duration.zero) {
      return;
    }
    if (polledDuration == _state.duration) {
      return;
    }

    _emit(_state.copyWith(duration: polledDuration));
  }

  void _emitSyntheticWindowsProgressIfNeeded() {
    final duration = _state.duration;
    if (duration == null || duration <= Duration.zero) {
      return;
    }

    final now = DateTime.now();
    final lastRealProgressAt = _lastWindowsRealProgressAt;
    final anchorTime = _windowsSyntheticAnchorTime;
    if (lastRealProgressAt == null || anchorTime == null) {
      _recordWindowsRealProgress(_state.position);
      return;
    }
    if (now.difference(lastRealProgressAt) < _windowsSyntheticProgressGrace) {
      return;
    }

    final syntheticPosition = _clampPosition(
      _windowsSyntheticAnchorPosition + now.difference(anchorTime),
      duration,
    );
    if (syntheticPosition > _state.position) {
      _emit(_state.copyWith(position: syntheticPosition));
    }
  }

  void _recordWindowsRealProgress(Duration position) {
    if (!_isWindows) {
      return;
    }

    final now = DateTime.now();
    final anchorPosition = _clampPosition(position, _state.duration);
    _lastWindowsRealProgressAt = now;
    _windowsSyntheticAnchorTime = now;
    _windowsSyntheticAnchorPosition = anchorPosition;
    _lastWindowsPolledPosition = anchorPosition;
  }

  void _resetWindowsProgressRecovery() {
    _windowsProgressRecoveryTimer?.cancel();
    _windowsProgressRecoveryTimer = null;
    _lastWindowsRealProgressAt = null;
    _windowsSyntheticAnchorTime = null;
    _windowsSyntheticAnchorPosition = Duration.zero;
    _lastWindowsPolledPosition = null;
  }

  Future<void> _recordPlaybackStarted(Track track) async {
    final trackId = track.id;
    if (trackId == null) {
      return;
    }

    final now = DateTime.now();
    await _recordSafely(() async {
      await _playbackEvents.recordEvent(
        PlaybackEvent.recording(
          trackId: trackId,
          type: PlaybackEventType.started,
          occurredAt: now,
          position: _state.position,
          trackDuration: _state.duration ?? track.duration,
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
      await _playbackEvents.recordEvent(
        PlaybackEvent.recording(
          trackId: trackId,
          type: PlaybackEventType.completed,
          occurredAt: now,
          position: _state.position,
          trackDuration: _state.duration ?? track.duration,
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
      await _playbackEvents.recordEvent(
        PlaybackEvent.recording(
          trackId: trackId,
          type: type,
          occurredAt: DateTime.now(),
          position: _state.position,
          trackDuration: _state.duration ?? track.duration,
        ),
      );
    });
  }

  Future<void> _recordSafely(Future<void> Function() write) =>
      _operations.run(() async {
        try {
          await write();
        } on Object catch (error) {
          diagnostics.record(DiagnosticEvent.playbackHistoryWriteFailed,
              error: error);
          _emit(
            _state.copyWith(
              errorMessage: 'История воспроизведения не была сохранена: '
                  '${_describeError(error)}',
            ),
          );
        }
      });

  Duration _clampPosition(Duration position, Duration? duration) {
    if (position < Duration.zero) {
      return Duration.zero;
    }
    if (duration != null && position > duration) {
      return duration;
    }
    return position;
  }

  Duration? _effectiveDuration(Duration? backendDuration, Track? track) {
    if (backendDuration != null && backendDuration > Duration.zero) {
      return backendDuration;
    }
    return track?.duration ?? backendDuration;
  }

  double _volumeToRestoreAfterMute() {
    final previousVolume = _previousVolumeBeforeMute;
    if (previousVolume > 0) {
      return previousVolume;
    }
    return _defaultVolume;
  }

  double _normalizeVolume(double volume) {
    if (volume.isNaN) {
      return _defaultVolume;
    }
    if (volume == double.infinity) {
      return 1;
    }
    if (volume == double.negativeInfinity) {
      return 0;
    }
    return volume.clamp(0.0, 1.0).toDouble();
  }

  double? _parseVolume(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null ? null : _normalizeVolume(parsed);
  }

  Future<void> _persistVolume(double volume) async {
    await _writeSettingSafely(_volumeSettingKey, volume.toString());
    if (volume > 0) {
      await _persistPreviousVolumeBeforeMute(volume);
    }
  }

  Future<void> _persistPreviousVolumeBeforeMute(double volume) {
    return _writeSettingSafely(
      _previousVolumeBeforeMuteSettingKey,
      _normalizeVolume(volume).toString(),
    );
  }

  Future<void> _writeSettingSafely(String key, String value) async {
    final settings = _settings;
    if (settings == null) {
      return;
    }

    try {
      await settings.writeString(key, value);
    } on Object catch (error) {
      diagnostics.record(DiagnosticEvent.settingsWriteFailed, error: error);
      if (kDebugMode) {
        debugPrint('JustAudioPlayerService settings write failed: $error');
      }
    }
  }

  String _normalizedAbsolutePath(String filePath) {
    return p.normalize(File(filePath).absolute.path);
  }

  bool _shouldUseWindowsPlaybackCache(String path) {
    if (!_isWindows) {
      return false;
    }
    return path.length > _windowsPlaybackCachePathLengthThreshold ||
        _containsNonAscii(path) ||
        _windowsDirectLoadFailures.contains(path);
  }

  String _initialLoadStrategy(String path) {
    return _shouldUseWindowsPlaybackCache(path) ? 'cache' : 'direct';
  }

  bool _containsNonAscii(String value) {
    return value.runes.any((rune) => rune > 0x7f);
  }

  void _resetPlaybackDiagnostics() {
    _positionEventsSinceLoad = 0;
    _durationEventsSinceLoad = 0;
    _positionDiagnosticsTimer?.cancel();
    _positionDiagnosticsTimer = null;
  }

  void _scheduleWindowsPositionDiagnostics(Track track,
      {bool opening = false}) {
    if (!_isWindows) {
      return;
    }

    final generation = _sessionGeneration;
    _positionDiagnosticsTimer?.cancel();
    _positionDiagnosticsTimer = Timer(_windowsDiagnosticsDelay, () {
      if (!_isCurrentSession(generation) || _state.currentTrack != track) {
        return;
      }
      if (kDebugMode) {
        debugPrint(
          'JustAudioPlayerService Windows position diagnostics: '
          'positionStreamEvents=$_positionEventsSinceLoad, '
          'durationStreamEvents=$_durationEventsSinceLoad, '
          'position=${_state.position}, duration=${_state.duration}, '
          'status=${_state.status}',
        );
      }
      final probe = _windowsPlaybackProbe;
      if (probe == null) return;
      unawaited(_operations.run(() async {
        try {
          final snapshots = await probe().timeout(const Duration(seconds: 2));
          if (!_isCurrentSession(generation)) return;
          if (snapshots.isEmpty) {
            diagnostics
                .record(DiagnosticEvent.windowsPlaybackObserved, fields: {
              DiagnosticField.trackId: track.id,
              DiagnosticField.opening: opening,
              DiagnosticField.playerPositionMs: _state.position.inMilliseconds,
              DiagnosticField.nativePlayerCount: 0,
            });
          }
          for (var i = 0; i < snapshots.length; i++) {
            final snapshot = snapshots[i];
            diagnostics
                .record(DiagnosticEvent.windowsPlaybackObserved, fields: {
              DiagnosticField.trackId: track.id,
              DiagnosticField.opening: opening,
              DiagnosticField.playerPositionMs: _state.position.inMilliseconds,
              DiagnosticField.nativePlayerSlot: i,
              DiagnosticField.nativePlayerCount: snapshots.length,
              DiagnosticField.nativePlaybackState: snapshot.state,
              DiagnosticField.nativePositionMs: snapshot.positionMs,
              DiagnosticField.nativeDurationMs: snapshot.durationMs,
              DiagnosticField.nativeSourcePresent: snapshot.sourcePresent,
            });
          }
        } on Object catch (error) {
          if (!_isCurrentSession(generation)) return;
          diagnostics.record(DiagnosticEvent.windowsPlaybackObservationFailed,
              error: error,
              fields: {
                DiagnosticField.trackId: track.id,
                DiagnosticField.opening: opening,
                if (error is PlatformException &&
                    int.tryParse(error.code) != null)
                  DiagnosticField.nativeCode: int.parse(error.code),
              });
        }
      }));
    });
  }

  void _debugLogAudioError(Object error) {
    diagnostics
        .record(DiagnosticEvent.audioEngineFailed, error: error, fields: {
      DiagnosticField.trackId: currentTrack?.id,
      if (error is just_audio.PlayerException)
        DiagnosticField.nativeCode: error.code,
    });
    if (!kDebugMode || !_isWindows) {
      return;
    }
    debugPrint(
      'JustAudioPlayerService audio error: '
      'isWindows=$_isWindows, error=${_diagnosticErrorText(error)}',
    );
  }

  void _debugLogPlaybackDiagnostics({
    required String originalPath,
    required String sourcePath,
    required String strategy,
    String? targetPath,
    PlaybackCacheEntry? cacheEntry,
    Object? error,
  }) {
    if (!kDebugMode || !_isWindows) {
      return;
    }

    final file = File(sourcePath);
    final exists = file.existsSync();
    Object? length;
    if (exists) {
      try {
        length = file.lengthSync();
      } on Object catch (error) {
        length = 'unavailable ($error)';
      }
    }
    final cachePath = cacheEntry?.filePath;
    final cacheFile = cachePath == null ? null : File(cachePath);
    final cacheExists = cacheFile?.existsSync();
    Object? cacheSize;
    if (cacheFile != null && cacheExists == true) {
      try {
        cacheSize = cacheFile.lengthSync();
      } on Object catch (cacheLengthError) {
        cacheSize = 'unavailable ($cacheLengthError)';
      }
    }

    debugPrint(
      'JustAudioPlayerService load diagnostics: '
      'originalPath="$originalPath", '
      'fullOriginalPath="$sourcePath", '
      'originalPathLength=${sourcePath.length}, '
      'isWindows=$_isWindows, '
      'containsNonAscii=${_containsNonAscii(sourcePath)}, '
      'fileExists=$exists, '
      'fileSize=$length, '
      'extension="${p.extension(sourcePath).toLowerCase()}", '
      'chosenStrategy=$strategy, '
      'cachePath="${cachePath ?? ''}", '
      'cachePathLength=${cachePath?.length ?? 0}, '
      'cacheExists=${cacheExists ?? false}, '
      'cacheSize=$cacheSize, '
      'cacheAction=${cacheEntry == null ? '' : cacheEntry.reusedExistingFile ? 'reused' : 'copied'}, '
      'cacheCleanupBefore=${cacheEntry?.cacheSizeBeforeCleanupBytes}, '
      'cacheCleanupAfter=${cacheEntry?.cacheSizeAfterCleanupBytes}, '
      'cacheCleanupDeleted=${cacheEntry?.cleanupDeletedFileCount}, '
      'targetPath="${targetPath ?? ''}", '
      'targetPathLength=${targetPath?.length ?? 0}, '
      'exception="${error == null ? '' : _diagnosticErrorText(error)}"',
    );
  }

  String _diagnosticErrorText(Object error) {
    if (error is just_audio.PlayerException) {
      return 'PlayerException(code=${error.code}, message=${error.message})';
    }
    return error.toString();
  }

  String _describeError(Object error) {
    if (error is just_audio.PlayerException) {
      final message = error.message;
      if (message != null && message.isNotEmpty) {
        return message;
      }
      return 'Ошибка аудиоплеера ${error.code}';
    }
    if (error is MissingPluginException) {
      return 'Аудиомодуль Windows недоступен.';
    }
    if (error is PlaybackLoadException || error is PlaybackCacheException) {
      return error.toString();
    }

    return error.toString();
  }
}

final class _ObsoletePlayback implements Exception {
  const _ObsoletePlayback();
}

final class _LoadedAudio {
  const _LoadedAudio({
    required this.duration,
  });

  final Duration? duration;
}

final class PlaybackLoadException implements Exception {
  const PlaybackLoadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

Object _playbackLoadCause(Object error) =>
    error is PlaybackLoadException ? error.cause ?? error : error;
