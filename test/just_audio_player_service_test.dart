import 'dart:async';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(service.state.errorMessage, contains('File does not exist'));
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
  _FakePlaybackEventRepository? playbackEvents,
  _FakeTrackUserStateRepository? trackUserState,
}) {
  return JustAudioPlayerService(
    playbackEvents: playbackEvents ?? _FakePlaybackEventRepository(),
    trackUserState: trackUserState ?? _FakeTrackUserStateRepository(),
    audioEngine: audioEngine,
    fileExists: fileExists ?? (_) => true,
  );
}

Track _track() {
  final now = DateTime(2026);
  return Track(
    id: 1,
    filePath: '/music/song.flac',
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

  Duration? loadedDuration = const Duration(minutes: 3);
  Object? setFilePathError;
  int setFilePathCalls = 0;
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
  Future<Duration?> setFilePath(String filePath) async {
    setFilePathCalls += 1;
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
  }

  void emitState(AudioEngineState state) {
    _stateController.add(state);
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
