import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:path/path.dart' as p;

import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';
import 'player_service.dart';
import 'player_state.dart';
import 'windows_playback_cache.dart';

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

  Future<Duration?> setFilePath(String filePath, {bool preload = true});

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
  Stream<Object> get errorStream => _player.errorStream;

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  Future<Duration?> setFilePath(String filePath, {bool preload = true}) {
    return _player.setFilePath(filePath, preload: preload);
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

const _defaultWindowsProgressRecoveryInterval = Duration(milliseconds: 250);
const _defaultWindowsSyntheticProgressGrace = Duration(seconds: 2);
const _volumeSettingKey = 'player.volume';
const _previousVolumeBeforeMuteSettingKey = 'player.previousVolumeBeforeMute';
const _defaultVolume = 1.0;
const _volumeStep = 0.05;

final class JustAudioPlayerService implements PlayerService {
  JustAudioPlayerService({
    required PlaybackEventRepository playbackEvents,
    required TrackUserStateRepository trackUserState,
    SettingsRepository? settings,
    LocalAudioEngine? audioEngine,
    bool Function(String filePath)? fileExists,
    bool? isWindows,
    PlaybackCache? playbackCache,
    @visibleForTesting Duration windowsProgressRecoveryInterval =
        _defaultWindowsProgressRecoveryInterval,
    @visibleForTesting Duration windowsSyntheticProgressGrace =
        _defaultWindowsSyntheticProgressGrace,
  })  : assert(windowsProgressRecoveryInterval > Duration.zero),
        assert(windowsSyntheticProgressGrace >= Duration.zero),
        _playbackEvents = playbackEvents,
        _trackUserState = trackUserState,
        _settings = settings,
        _audioEngine = audioEngine ?? JustAudioEngine(),
        _isWindows = isWindows ?? Platform.isWindows,
        _playbackCache = playbackCache ?? WindowsPlaybackCache(),
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

  final PlaybackEventRepository _playbackEvents;
  final TrackUserStateRepository _trackUserState;
  final SettingsRepository? _settings;
  final LocalAudioEngine _audioEngine;
  final bool _isWindows;
  final PlaybackCache _playbackCache;
  final Duration _windowsProgressRecoveryInterval;
  final Duration _windowsSyntheticProgressGrace;
  final bool Function(String filePath) _fileExists;
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  PlayerState _state = const PlayerState.idle();
  bool _isDisposed = false;
  bool _didRecordCompletion = false;
  int _positionEventsSinceLoad = 0;
  int _durationEventsSinceLoad = 0;
  Timer? _positionDiagnosticsTimer;
  Timer? _windowsProgressRecoveryTimer;
  DateTime? _lastWindowsRealProgressAt;
  DateTime? _windowsSyntheticAnchorTime;
  Duration _windowsSyntheticAnchorPosition = Duration.zero;
  Duration? _lastWindowsPolledPosition;
  double _previousVolumeBeforeMute = _defaultVolume;

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

    _resetPlaybackDiagnostics();
    _resetWindowsProgressRecovery();
    _didRecordCompletion = false;
    final normalizedPath = _normalizedAbsolutePath(track.filePath);
    _emit(
      _state.copyWith(
        currentTrack: track,
        isPlaying: false,
        position: Duration.zero,
        duration: _effectiveDuration(null, track),
        status: PlayerPlaybackStatus.loading,
        errorMessage: null,
      ),
    );

    _debugLogPlaybackDiagnostics(
      originalPath: track.filePath,
      normalizedPath: normalizedPath,
      strategy: _initialLoadStrategy(normalizedPath),
    );

    if (!_fileExists(normalizedPath)) {
      await _stopAfterFailure(
        'Файл не найден: ${track.filePath} (путь: $normalizedPath)',
      );
      return;
    }

    try {
      await _audioEngine.stop();
      final loadedAudio = await _loadTrackAudio(track, normalizedPath);
      if (_isDisposed ||
          _state.status == PlayerPlaybackStatus.error ||
          _state.currentTrack != track) {
        return;
      }
      _emit(
        _state.copyWith(
          currentTrack: track,
          isPlaying: true,
          position: Duration.zero,
          duration: _effectiveDuration(loadedAudio.duration, track),
          status: PlayerPlaybackStatus.playing,
          errorMessage: null,
        ),
      );
      _startWindowsProgressRecovery(anchorPosition: Duration.zero);
      _scheduleWindowsPositionDiagnostics(track);
      unawaited(_recordPlaybackStarted(track));
      _playInBackground();
    } on Object catch (error) {
      await _stopAfterFailure(
        'Не удалось воспроизвести "${track.displayTitle}": '
        '${_describeError(error)}',
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
          errorMessage: 'Выберите трек для воспроизведения.',
        ),
      );
      return;
    }

    try {
      if (_state.status == PlayerPlaybackStatus.completed) {
        _didRecordCompletion = false;
        await _audioEngine.seek(Duration.zero);
        _emit(_state.copyWith(position: Duration.zero));
        _resetWindowsProgressRecovery();
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
      _startWindowsProgressRecovery(anchorPosition: _state.position);
      _playInBackground();
    } on Object catch (error) {
      _emitPlaybackError(
          'Воспроизведение не удалось: ${_describeError(error)}');
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
      _resetWindowsProgressRecovery();
      _emit(
        _state.copyWith(
          isPlaying: false,
          status: PlayerPlaybackStatus.paused,
          errorMessage: null,
        ),
      );
      unawaited(_recordEvent(track, PlaybackEventType.paused));
    } on Object catch (error) {
      _emitPlaybackError(
        'Не удалось поставить воспроизведение на паузу: '
        '${_describeError(error)}',
      );
    }
  }

  @override
  Future<void> stop() async {
    if (_state.currentTrack == null && !_state.isPlaying) {
      return;
    }

    try {
      await _audioEngine.stop();
      _resetWindowsProgressRecovery();
      _didRecordCompletion = false;
      _emit(
        PlayerState(
          volume: _state.volume,
          status: PlayerPlaybackStatus.stopped,
        ),
      );
    } on Object catch (error) {
      _emitPlaybackError(
        'Не удалось остановить воспроизведение: ${_describeError(error)}',
      );
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
      _resetWindowsProgressRecovery();
      _emit(
        _state.copyWith(
          position: target,
          errorMessage: null,
        ),
      );
      _startWindowsProgressRecovery(anchorPosition: target);
    } on Object catch (error) {
      _emitPlaybackError(
        'Не удалось перейти к позиции: ${_describeError(error)}',
      );
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    final normalizedVolume = _normalizeVolume(volume);
    try {
      await _audioEngine.setVolume(normalizedVolume);
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
      _emitPlaybackError(
        'Не удалось изменить громкость: ${_describeError(error)}',
      );
    }
  }

  @override
  Future<void> increaseVolume() {
    return setVolume(_state.volume + _volumeStep);
  }

  @override
  Future<void> decreaseVolume() {
    return setVolume(_state.volume - _volumeStep);
  }

  @override
  Future<void> toggleMute() async {
    if (_state.volume > 0) {
      _previousVolumeBeforeMute = _state.volume;
      await _persistPreviousVolumeBeforeMute(_previousVolumeBeforeMute);
      await setVolume(0);
      return;
    }

    await setVolume(_volumeToRestoreAfterMute());
  }

  Future<void> restoreSavedVolume() async {
    final settings = _settings;
    if (settings == null || _isDisposed) {
      return;
    }

    final savedPreviousVolume = _parseVolume(
        await settings.readString(_previousVolumeBeforeMuteSettingKey));
    if (savedPreviousVolume != null && savedPreviousVolume > 0) {
      _previousVolumeBeforeMute = savedPreviousVolume;
    }

    final savedVolume =
        _parseVolume(await settings.readString(_volumeSettingKey));
    if (savedVolume == null) {
      return;
    }

    await setVolume(savedVolume);
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _positionDiagnosticsTimer?.cancel();
    _resetWindowsProgressRecovery();
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

    if (completed) {
      _resetWindowsProgressRecovery();
    } else if (_shouldRunWindowsProgressRecovery) {
      _startWindowsProgressRecovery(anchorPosition: _state.position);
    } else if (status != PlayerPlaybackStatus.playing) {
      _resetWindowsProgressRecovery();
    }

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

    _positionEventsSinceLoad += 1;
    _debugLogPositionEvent(position);
    final previousPosition = _state.position;
    _emit(_state.copyWith(position: position));
    if (_isWindows && position != previousPosition) {
      _recordWindowsRealProgress(position);
    }
  }

  void _handleDuration(Duration? duration) {
    if (_isDisposed) {
      return;
    }

    _durationEventsSinceLoad += 1;
    final effectiveDuration = _effectiveDuration(duration, _state.currentTrack);
    _debugLogDurationEvent(duration, effectiveDuration);
    _emit(_state.copyWith(duration: effectiveDuration));
  }

  void _handleAudioError(Object error) {
    if (_isDisposed || _state.currentTrack == null) {
      return;
    }

    final track = _state.currentTrack!;
    _debugLogAudioError(error);
    unawaited(
      _stopAfterFailure(
        'Не удалось воспроизвести "${track.displayTitle}": '
        '${_describeError(error)}',
      ),
    );
  }

  Future<_LoadedAudio> _loadTrackAudio(
    Track track,
    String normalizedPath,
  ) async {
    if (_shouldPreferWindowsCache(normalizedPath)) {
      return _loadFromWindowsCache(
        track: track,
        normalizedPath: normalizedPath,
        directError: null,
      );
    }

    try {
      final duration = await _audioEngine.setFilePath(
        normalizedPath,
        preload: false,
      );
      return _LoadedAudio(duration: duration);
    } on Object catch (directError) {
      if (!_shouldUseWindowsCacheFallback(
        path: normalizedPath,
        error: directError,
      )) {
        rethrow;
      }

      // TODO: Remove this fallback if the Windows audio backend reliably
      // accepts Unicode local file paths.
      return _loadFromWindowsCache(
        track: track,
        normalizedPath: normalizedPath,
        directError: directError,
      );
    }
  }

  Future<_LoadedAudio> _loadFromWindowsCache({
    required Track track,
    required String normalizedPath,
    required Object? directError,
  }) async {
    try {
      final cached = await _playbackCache.resolve(track, normalizedPath);
      final strategyPrefix = directError == null
          ? 'windows_cache_preferred'
          : 'windows_cache_fallback';
      _debugLogPlaybackDiagnostics(
        originalPath: track.filePath,
        normalizedPath: cached.filePath,
        strategy: cached.reusedExistingFile
            ? '${strategyPrefix}_reused'
            : '${strategyPrefix}_copied',
      );
      final duration = await _audioEngine.setFilePath(
        cached.filePath,
        preload: false,
      );
      return _LoadedAudio(duration: duration);
    } on Object catch (cacheError) {
      final directDetails = directError == null
          ? 'Прямая загрузка пропущена для Windows-пути с не-ASCII символами.'
          : 'Ошибка прямой загрузки: ${_describeError(directError)}.';
      throw PlaybackLoadException(
        'Не удалось загрузить путь Windows с Unicode. '
        '$directDetails '
        'Ошибка кэша: ${_describeError(cacheError)}. '
        'Исходный путь: $normalizedPath',
      );
    }
  }

  void _playInBackground() {
    unawaited(_playAndReportErrors());
  }

  Future<void> _playAndReportErrors() async {
    try {
      await _audioEngine.play();
    } on Object catch (error) {
      _emitPlaybackError(
          'Воспроизведение не удалось: ${_describeError(error)}');
    }
  }

  Future<void> _stopAfterFailure(String message) async {
    try {
      await _audioEngine.stop();
    } on Object {
      // Keep the user-facing error focused on the original playback failure.
    }

    _resetWindowsProgressRecovery();
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
    _resetWindowsProgressRecovery();
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
          errorMessage: 'История воспроизведения не была сохранена: '
              '${_describeError(error)}',
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
      if (kDebugMode) {
        debugPrint('JustAudioPlayerService settings write failed: $error');
      }
    }
  }

  String _normalizedAbsolutePath(String filePath) {
    return p.normalize(File(filePath).absolute.path);
  }

  bool _shouldUseWindowsCacheFallback({
    required String path,
    required Object error,
  }) {
    if (!_isWindows) {
      return false;
    }
    if (_isLikelyUnsupportedFormatError(error)) {
      return false;
    }
    return _isLikelyFilePathError(error) || _containsNonAscii(path);
  }

  bool _shouldPreferWindowsCache(String path) {
    return _isWindows && _containsNonAscii(path);
  }

  String _initialLoadStrategy(String path) {
    return _shouldPreferWindowsCache(path)
        ? 'windows_cache_preferred'
        : 'direct';
  }

  bool _isLikelyUnsupportedFormatError(Object error) {
    final message = _errorText(error).toLowerCase();
    return message.contains('unsupported') ||
        message.contains('format') ||
        message.contains('codec') ||
        message.contains('decode');
  }

  bool _isLikelyFilePathError(Object error) {
    if (error is FileSystemException || error is PathNotFoundException) {
      return true;
    }

    final message = _errorText(error).toLowerCase();
    return message.contains('path') ||
        message.contains('file') ||
        message.contains('not found') ||
        message.contains('cannot find') ||
        message.contains('does not exist') ||
        message.contains('не удается найти') ||
        message.contains('не удаётся найти') ||
        message.contains('указанный путь') ||
        message.contains('путь');
  }

  String _errorText(Object error) {
    if (error is just_audio.PlayerException) {
      return [
        error.code,
        if (error.message != null) error.message!,
      ].join(' ');
    }
    return error.toString();
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

  void _scheduleWindowsPositionDiagnostics(Track track) {
    if (!kDebugMode || !_isWindows) {
      return;
    }

    _positionDiagnosticsTimer?.cancel();
    _positionDiagnosticsTimer = Timer(const Duration(seconds: 3), () {
      if (_isDisposed || _state.currentTrack != track) {
        return;
      }
      debugPrint(
        'JustAudioPlayerService Windows position diagnostics: '
        'positionStreamEvents=$_positionEventsSinceLoad, '
        'durationStreamEvents=$_durationEventsSinceLoad, '
        'position=${_state.position}, duration=${_state.duration}, '
        'status=${_state.status}',
      );
    });
  }

  void _debugLogPositionEvent(Duration position) {
    if (!kDebugMode || !_isWindows || _positionEventsSinceLoad > 3) {
      return;
    }
    debugPrint(
      'JustAudioPlayerService positionStream event '
      '#$_positionEventsSinceLoad: position=$position',
    );
  }

  void _debugLogDurationEvent(
    Duration? backendDuration,
    Duration? effectiveDuration,
  ) {
    if (!kDebugMode || !_isWindows || _durationEventsSinceLoad > 5) {
      return;
    }
    debugPrint(
      'JustAudioPlayerService durationStream event '
      '#$_durationEventsSinceLoad: backend=$backendDuration, '
      'effective=$effectiveDuration',
    );
  }

  void _debugLogAudioError(Object error) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      'JustAudioPlayerService audio error: '
      'isWindows=$_isWindows, error=${_describeError(error)}',
    );
  }

  void _debugLogPlaybackDiagnostics({
    required String originalPath,
    required String normalizedPath,
    required String strategy,
  }) {
    if (!kDebugMode) {
      return;
    }

    final file = File(normalizedPath);
    final exists = file.existsSync();
    Object? length;
    if (exists) {
      try {
        length = file.lengthSync();
      } on Object catch (error) {
        length = 'unavailable ($error)';
      }
    }

    debugPrint(
      'JustAudioPlayerService load diagnostics: '
      'originalPath="$originalPath", '
      'normalizedPath="$normalizedPath", '
      'isWindows=$_isWindows, '
      'exists=$exists, '
      'length=$length, '
      'extension="${p.extension(normalizedPath).toLowerCase()}", '
      'containsNonAscii=${_containsNonAscii(normalizedPath)}, '
      'strategy=$strategy',
    );
  }

  String _describeError(Object error) {
    if (error is just_audio.PlayerException) {
      final message = error.message;
      if (message != null && message.isNotEmpty) {
        return message;
      }
      return 'Ошибка аудиоплеера ${error.code}';
    }
    if (error is PlaybackLoadException || error is PlaybackCacheException) {
      return error.toString();
    }

    return error.toString();
  }
}

final class _LoadedAudio {
  const _LoadedAudio({
    required this.duration,
  });

  final Duration? duration;
}

final class PlaybackLoadException implements Exception {
  const PlaybackLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}
