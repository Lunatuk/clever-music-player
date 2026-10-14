import 'dart:async';
import 'package:clever_music_player/src/domain/models/audio_source_reference.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';

final class TestAudioEngine implements LocalAudioEngine {
  final StreamController<AudioEngineState> _stateController =
      StreamController<AudioEngineState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();

  Duration? loadedDuration = const Duration(minutes: 3);
  Duration polledPosition = Duration.zero;
  Duration? polledDuration;
  Object? setFilePathError;
  FutureOr<Duration?> Function(AudioSourceReference source, int call)?
      setSourceHandler;
  final sources = <AudioSourceReference>[];
  final sourcePreloads = <bool>[];
  FutureOr<Duration?> Function(String filePath, int call)? setFilePathHandler;
  Future<void> Function()? pauseHandler;
  Future<void> Function(int call)? stopHandler;
  Future<void> Function(int call)? playHandler;
  Future<void> Function(Duration position)? seekHandler;
  Future<void> Function()? disposeHandler;
  Object? disposeError;
  int concurrentLoads = 0;
  int maxConcurrentLoads = 0;
  int setFilePathCalls = 0;
  final List<String> setFilePaths = [];
  final List<bool> setFilePathPreloads = [];
  bool playing = false;
  int disposeCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int seekCalls = 0;
  int positionPolls = 0;
  int durationPolls = 0;
  Future<void> Function(double volume)? volumeHandler;
  int setVolumeCalls = 0;
  final List<Duration> seekPositions = [];
  final List<double> setVolumes = [];

  @override
  Stream<AudioEngineState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<Object> get errorStream => _errorController.stream;

  @override
  Duration get position {
    positionPolls += 1;
    return polledPosition;
  }

  @override
  Duration? get duration {
    durationPolls += 1;
    return polledDuration ?? loadedDuration;
  }

  @override
  Future<Duration?> setSource(AudioSourceReference source,
      {bool preload = true}) async {
    sources.add(source);
    sourcePreloads.add(preload);
    final handler = setSourceHandler;
    if (handler != null) return handler(source, sources.length);
    return switch (source) {
      FileAudioSource(:final path) => setFilePath(path, preload: preload),
      ContentUriAudioSource() => preload ? loadedDuration : null,
    };
  }

  Future<Duration?> setFilePath(
    String filePath, {
    bool preload = true,
  }) async {
    polledPosition = Duration.zero;
    setFilePathCalls += 1;
    setFilePaths.add(filePath);
    setFilePathPreloads.add(preload);
    final handler = setFilePathHandler;
    if (handler != null) {
      concurrentLoads++;
      if (concurrentLoads > maxConcurrentLoads) {
        maxConcurrentLoads = concurrentLoads;
      }
      try {
        return await handler(filePath, setFilePathCalls);
      } finally {
        concurrentLoads--;
      }
    }
    final error = setFilePathError;
    if (error != null) {
      throw error;
    }
    if (!preload) {
      return null;
    }
    return loadedDuration;
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    await playHandler?.call(playCalls);
    playing = true;
    emitState(const AudioEngineState(
        isPlaying: true, processingState: AudioEngineProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    await pauseHandler?.call();
    playing = false;
    emitState(const AudioEngineState(
        isPlaying: false, processingState: AudioEngineProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    await stopHandler?.call(stopCalls);
    playing = false;
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls += 1;
    seekPositions.add(position);
    await seekHandler?.call(position);
    polledPosition = position;
  }

  @override
  Future<void> setVolume(double volume) async {
    setVolumeCalls += 1;
    setVolumes.add(volume);
    await volumeHandler?.call(volume);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await disposeHandler?.call();
    playing = false;
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _errorController.close();
    if (disposeError != null) throw disposeError!;
  }

  void emitState(AudioEngineState state) {
    _stateController.add(state);
  }

  void emitDuration(Duration? duration) {
    _durationController.add(duration);
  }

  void emitPosition(Duration position) {
    polledPosition = position;
    _positionController.add(position);
  }

  void emitError(Object error) {
    _errorController.add(error);
  }
}
