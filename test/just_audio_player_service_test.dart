import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/player/windows_playback_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('playTrack reports missing files without loading audio', () async {
    final engine = _FakeAudioEngine();
    final service = _service(
      audioEngine: engine,
      fileExists: (_) => false,
    );

    await service.playTrack(_track());

    expect(service.state.status, PlayerPlaybackStatus.error);
    expect(service.state.currentTrack, isNull);
    expect(service.state.errorMessage, contains('File not found'));
    expect(engine.setFilePathCalls, 0);
    expect(engine.playCalls, 0);

    await service.dispose();
  });

  test('playTrack reports audio load failures without starting playback',
      () async {
    final engine = _FakeAudioEngine()
      ..setFilePathError = UnsupportedError('unsupported format');
    final service = _service(audioEngine: engine);

    await service.playTrack(_track());

    expect(service.state.status, PlayerPlaybackStatus.error);
    expect(service.state.currentTrack, isNull);
    expect(service.state.errorMessage, contains('Could not play'));
    expect(engine.setFilePathCalls, 1);
    expect(engine.playCalls, 0);

    await service.dispose();
  });

  test('playTrack starts playback and records local listening state', () async {
    final engine = _FakeAudioEngine()
      ..loadedDuration = const Duration(minutes: 4);
    final playbackEvents = _FakePlaybackEventRepository();
    final userState = _FakeTrackUserStateRepository();
    final service = _service(
      audioEngine: engine,
      playbackEvents: playbackEvents,
      trackUserState: userState,
    );

    await service.playTrack(_track());
    await Future<void>.delayed(Duration.zero);

    expect(service.state.status, PlayerPlaybackStatus.playing);
    expect(service.state.duration, const Duration(minutes: 4));
    expect(engine.playCalls, 1);
    expect(playbackEvents.events.single.type, PlaybackEventType.started);
    expect(userState.states[1]!.playCount, 1);
    expect(userState.states[1]!.lastPlayedAt, isNotNull);

    await service.dispose();
  });

  test('direct Windows playback uses the normalized source path', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_direct_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final file = File(p.join(tempDirectory.path, 'song.mp3'));
    await file.writeAsBytes([1, 2, 3, 4]);
    final engine = _FakeAudioEngine();
    final service = _service(
      audioEngine: engine,
      isWindows: true,
      fileExists: (path) => File(path).existsSync(),
    );

    final track = _track(filePath: file.path);
    await service.playTrack(track);

    expect(engine.setFilePaths, [p.normalize(file.absolute.path)]);
    expect(service.state.currentTrack?.filePath, file.path);
    expect(service.state.status, PlayerPlaybackStatus.playing);

    await service.dispose();
  });

  test('non-ASCII Windows path falls back to cached ASCII path', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_unicode_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final appSupportDirectory =
        Directory(p.join(tempDirectory.path, 'support'));
    final source = File(p.join(tempDirectory.path, 'МУЗЫКА', 'трек.mp3'));
    await source.parent.create(recursive: true);
    await source.writeAsBytes([1, 2, 3, 4]);
    final normalizedSourcePath = p.normalize(source.absolute.path);
    final engine = _FakeAudioEngine();
    final service = _service(
      audioEngine: engine,
      isWindows: true,
      fileExists: (path) => File(path).existsSync(),
      playbackCache: WindowsPlaybackCache(
        appSupportDirectoryProvider: () async => appSupportDirectory,
      ),
    );

    final track = _track(filePath: source.path, stableId: 'stable-track');
    await service.playTrack(track);

    expect(engine.setFilePaths, hasLength(1));
    final cachedPath = engine.setFilePaths.single;
    expect(cachedPath, isNot(normalizedSourcePath));
    expect(p.basename(cachedPath), matches(RegExp(r'^[A-Za-z0-9_.-]+$')));
    expect(p.extension(cachedPath), '.mp3');
    expect(File(cachedPath).readAsBytesSync(), [1, 2, 3, 4]);
    expect(service.state.currentTrack?.filePath, source.path);
    expect(service.state.status, PlayerPlaybackStatus.playing);

    await service.dispose();
  });

  test('Windows playback cache reuses a valid cached file', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_cache_reuse_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final appSupportDirectory =
        Directory(p.join(tempDirectory.path, 'support'));
    final source = File(p.join(tempDirectory.path, 'МУЗЫКА', 'трек.mp3'));
    await source.parent.create(recursive: true);
    await source.writeAsBytes([1, 2, 3, 4]);
    final engine = _FakeAudioEngine();
    final service = _service(
      audioEngine: engine,
      isWindows: true,
      fileExists: (path) => File(path).existsSync(),
      playbackCache: WindowsPlaybackCache(
        appSupportDirectoryProvider: () async => appSupportDirectory,
      ),
    );

    final track = _track(filePath: source.path, stableId: 'stable-track');
    await service.playTrack(track);
    final cachedPath = engine.setFilePaths.last;
    await File(cachedPath).writeAsBytes([9, 9, 9, 9]);

    await service.playTrack(track);

    expect(engine.setFilePaths, hasLength(2));
    expect(engine.setFilePaths.last, cachedPath);
    expect(File(cachedPath).readAsBytesSync(), [9, 9, 9, 9]);

    await service.dispose();
  });

  test('missing source file fails without loading or caching audio', () async {
    final engine = _FakeAudioEngine();
    final cache = _ThrowingPlaybackCache('cache should not be used');
    final service = _service(
      audioEngine: engine,
      isWindows: true,
      fileExists: (_) => false,
      playbackCache: cache,
    );

    await service.playTrack(_track(filePath: r'D:\МУЗЫКА\missing.mp3'));

    expect(service.state.status, PlayerPlaybackStatus.error);
    expect(service.state.errorMessage, contains('File not found'));
    expect(engine.setFilePathCalls, 0);
    expect(cache.calls, 0);

    await service.dispose();
  });

  test('failed direct load and failed cache fallback report useful error',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_cache_failure_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final source = File(p.join(tempDirectory.path, 'МУЗЫКА', 'трек.mp3'));
    await source.parent.create(recursive: true);
    await source.writeAsBytes([1, 2, 3, 4]);
    final engine = _FakeAudioEngine()
      ..setFilePathHandler = (filePath, _) {
        throw FileSystemException('Cannot find path', filePath);
      };
    final cache = _ThrowingPlaybackCache('cache copy failed');
    final service = _service(
      audioEngine: engine,
      isWindows: true,
      fileExists: (path) => File(path).existsSync(),
      playbackCache: cache,
    );

    await service.playTrack(_track(filePath: source.path));

    expect(service.state.status, PlayerPlaybackStatus.error);
    expect(
      service.state.errorMessage,
      allOf(
        contains('Windows Unicode path fallback failed'),
        contains('cache copy failed'),
      ),
    );
    expect(engine.playCalls, 0);
    expect(cache.calls, 1);

    await service.dispose();
  });

  test('duration stream null preserves track duration fallback', () async {
    final engine = _FakeAudioEngine()..loadedDuration = null;
    final service = _service(audioEngine: engine);

    await service.playTrack(_track());
    engine.emitDuration(null);
    await Future<void>.delayed(Duration.zero);

    expect(service.state.duration, const Duration(minutes: 3));

    await service.dispose();
  });

  test('duration stream uses backend duration when available', () async {
    final engine = _FakeAudioEngine()..loadedDuration = null;
    final service = _service(audioEngine: engine);

    await service.playTrack(_track());
    engine.emitDuration(const Duration(minutes: 4));
    await Future<void>.delayed(Duration.zero);

    expect(service.state.duration, const Duration(minutes: 4));

    await service.dispose();
  });

  test('audio error stream stops loading and reports failure', () async {
    final engine = _FakeAudioEngine()..loadedDuration = Duration.zero;
    final service = _service(audioEngine: engine);

    await service.playTrack(_track());
    engine.emitState(
      const AudioEngineState(
        isPlaying: false,
        processingState: AudioEngineProcessingState.loading,
      ),
    );
    engine.emitError(FileSystemException('Cannot find path', r'D:\song.mp3'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(service.state.status, PlayerPlaybackStatus.error);
    expect(service.state.currentTrack, isNull);
    expect(service.state.errorMessage, contains('Cannot find path'));

    await service.dispose();
  });

  test('pause and play record paused and resumed events', () async {
    final engine = _FakeAudioEngine();
    final playbackEvents = _FakePlaybackEventRepository();
    final service = _service(
      audioEngine: engine,
      playbackEvents: playbackEvents,
    );

    await service.playTrack(_track());
    await Future<void>.delayed(Duration.zero);
    await service.pause();
    await Future<void>.delayed(Duration.zero);
    await service.play();
    await Future<void>.delayed(Duration.zero);

    expect(
      playbackEvents.events.map((event) => event.type),
      [
        PlaybackEventType.started,
        PlaybackEventType.paused,
        PlaybackEventType.resumed,
      ],
    );

    await service.dispose();
  });

  test('completed audio records completion once', () async {
    final engine = _FakeAudioEngine()
      ..loadedDuration = const Duration(minutes: 2);
    final playbackEvents = _FakePlaybackEventRepository();
    final userState = _FakeTrackUserStateRepository();
    final service = _service(
      audioEngine: engine,
      playbackEvents: playbackEvents,
      trackUserState: userState,
    );

    await service.playTrack(_track());
    await Future<void>.delayed(Duration.zero);
    engine.emitState(
      const AudioEngineState(
        isPlaying: false,
        processingState: AudioEngineProcessingState.completed,
      ),
    );
    engine.emitState(
      const AudioEngineState(
        isPlaying: false,
        processingState: AudioEngineProcessingState.completed,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.state.status, PlayerPlaybackStatus.completed);
    expect(service.state.position, const Duration(minutes: 2));
    expect(
      playbackEvents.events.map((event) => event.type),
      [PlaybackEventType.started, PlaybackEventType.completed],
    );
    expect(userState.states[1]!.completeCount, 1);
    expect(userState.states[1]!.lastCompletedAt, isNotNull);

    await service.dispose();
  });
}

JustAudioPlayerService _service({
  required _FakeAudioEngine audioEngine,
  bool Function(String filePath)? fileExists,
  bool? isWindows,
  PlaybackCache? playbackCache,
  _FakePlaybackEventRepository? playbackEvents,
  _FakeTrackUserStateRepository? trackUserState,
}) {
  return JustAudioPlayerService(
    playbackEvents: playbackEvents ?? _FakePlaybackEventRepository(),
    trackUserState: trackUserState ?? _FakeTrackUserStateRepository(),
    audioEngine: audioEngine,
    isWindows: isWindows ?? false,
    playbackCache: playbackCache,
    fileExists: fileExists ?? (_) => true,
  );
}

Track _track({
  String filePath = '/music/song.flac',
  String? stableId,
}) {
  final now = DateTime(2026);
  return Track(
    id: 1,
    stableId: stableId,
    filePath: filePath,
    title: 'Song',
    artist: 'Artist',
    duration: const Duration(minutes: 3),
    addedAt: now,
    updatedAt: now,
  );
}

final class _FakeAudioEngine implements LocalAudioEngine {
  final StreamController<AudioEngineState> _stateController =
      StreamController<AudioEngineState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();

  Duration? loadedDuration = const Duration(minutes: 3);
  Object? setFilePathError;
  Duration? Function(String filePath, int call)? setFilePathHandler;
  int setFilePathCalls = 0;
  final List<String> setFilePaths = [];
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int seekCalls = 0;
  int setVolumeCalls = 0;

  @override
  Stream<AudioEngineState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<Object> get errorStream => _errorController.stream;

  @override
  Future<Duration?> setFilePath(String filePath) async {
    setFilePathCalls += 1;
    setFilePaths.add(filePath);
    final handler = setFilePathHandler;
    if (handler != null) {
      return handler(filePath, setFilePathCalls);
    }
    final error = setFilePathError;
    if (error != null) {
      throw error;
    }
    return loadedDuration;
  }

  @override
  Future<void> play() async {
    playCalls += 1;
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls += 1;
  }

  @override
  Future<void> setVolume(double volume) async {
    setVolumeCalls += 1;
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _errorController.close();
  }

  void emitState(AudioEngineState state) {
    _stateController.add(state);
  }

  void emitDuration(Duration? duration) {
    _durationController.add(duration);
  }

  void emitError(Object error) {
    _errorController.add(error);
  }
}

final class _ThrowingPlaybackCache implements PlaybackCache {
  _ThrowingPlaybackCache(this.message);

  final String message;
  int calls = 0;

  @override
  Future<PlaybackCacheEntry> resolve(Track track, String sourcePath) async {
    calls += 1;
    throw PlaybackCacheException(message);
  }
}

final class _FakePlaybackEventRepository implements PlaybackEventRepository {
  final List<PlaybackEvent> events = [];

  @override
  Future<int> addEvent(PlaybackEvent event) async {
    events.add(event);
    return events.length;
  }

  @override
  Future<List<PlaybackEvent>> recentEvents({int limit = 100}) async {
    return events.reversed.take(limit).toList(growable: false);
  }

  @override
  Future<List<PlaybackEvent>> recentForTrack(int trackId, {int limit = 50}) {
    return Future.value(
      events.where((event) => event.trackId == trackId).toList(growable: false),
    );
  }
}

final class _FakeTrackUserStateRepository implements TrackUserStateRepository {
  final Map<int, TrackUserState> states = {};

  @override
  Future<void> upsertState(TrackUserState state) async {
    states[state.trackId] = state;
  }

  @override
  Future<TrackUserState?> findByTrackId(int trackId) async {
    return states[trackId];
  }

  @override
  Future<Map<int, TrackUserState>> findByTrackIds(
    Iterable<int> trackIds,
  ) async {
    return {
      for (final trackId in trackIds)
        if (states[trackId] != null) trackId: states[trackId]!,
    };
  }

  @override
  Stream<TrackUserState?> watchTrackState(int trackId) {
    return Stream.value(states[trackId]);
  }

  @override
  Stream<Map<int, TrackUserState>> watchTrackStatesByTrackIds(
    Iterable<int> trackIds,
  ) {
    return Stream.value({
      for (final trackId in trackIds)
        if (states[trackId] != null) trackId: states[trackId]!,
    });
  }

  @override
  Future<void> deleteState(int trackId) async {
    states.remove(trackId);
  }
}
