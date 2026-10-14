import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/player/windows_playback_cache.dart';
import 'package:clever_music_player/src/queue/playback_queue_service.dart';
import 'package:clever_music_player/src/recommendation/recommendation_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/learning_repository_helpers.dart';

void main() {
  group('playback session ordering', () {
    late _FakeAudioEngine engine;
    late _FakePlaybackEventRepository events;
    late JustAudioPlayerService service;

    setUp(() {
      engine = _FakeAudioEngine();
      events = _FakePlaybackEventRepository();
      service = _service(audioEngine: engine, playbackEvents: events);
      addTearDown(() => service.dispose());
    });

    Future<void> flush() => Future<void>.delayed(Duration.zero);

    for (final fail in [false, true]) {
      test('superseded load cannot publish ${fail ? 'failure' : 'success'}',
          () async {
        final firstLoad = Completer<Duration?>();
        engine.setFilePathHandler = (_, call) =>
            call == 1 ? firstLoad.future : const Duration(minutes: 2);
        final states = <PlayerState>[];
        final subscription = service.stateStream.listen(states.add);
        addTearDown(subscription.cancel);
        final first = service.playTrack(_track(filePath: '/music/first.mp3'));
        await flush();
        final secondTrack = _track(filePath: '/music/second.mp3');
        final second = service.playTrack(secondTrack);
        await flush();
        states.clear();
        if (fail) {
          firstLoad.completeError(StateError('late failure'));
        } else {
          firstLoad.complete(const Duration(seconds: 30));
        }
        await Future.wait([first, second]);
        await flush();

        expect(service.currentTrack, secondTrack);
        expect(service.state.status, PlayerPlaybackStatus.playing);
        expect(states.where((state) => state.hasError), isEmpty);
        expect(engine.playCalls, 1);
        expect(engine.maxConcurrentLoads, 1);
        expect(events.events.where((e) => e.type == PlaybackEventType.started),
            hasLength(1));
      });
    }

    test('restarting the same Track creates a distinct session', () async {
      final firstLoad = Completer<Duration?>();
      engine.setFilePathHandler = (_, call) =>
          call == 1 ? firstLoad.future : const Duration(minutes: 2);
      final track = _track(duration: null);
      final first = service.playTrack(track);
      await flush();
      final second = service.playTrack(track);
      await flush();
      firstLoad.complete(const Duration(seconds: 30));
      await Future.wait([first, second]);
      await flush();
      expect(service.duration, const Duration(minutes: 2));
      expect(engine.playCalls, 1);
      expect(events.events, hasLength(1));
    });

    for (final fail in [false, true]) {
      test('stop cancels pending load ${fail ? 'failure' : 'success'}',
          () async {
        final load = Completer<Duration?>();
        engine.setFilePathHandler = (_, __) => load.future;
        final playing = service.playTrack(_track());
        await flush();
        final stopping = service.stop();
        await flush();
        final stateWhileWaiting = service.state;
        if (fail) {
          load.completeError(StateError('late failure'));
        } else {
          load.complete(const Duration(minutes: 3));
        }
        await Future.wait([playing, stopping]);
        expect(stateWhileWaiting.status, PlayerPlaybackStatus.stopped);
        expect(stateWhileWaiting.currentTrack, isNull);
        expect(service.state.status, PlayerPlaybackStatus.stopped);
        expect(service.currentTrack, isNull);
        expect(engine.playCalls, 0);
        expect(events.events, isEmpty);
      });
    }

    test('pause during load prevents autoplay and play starts it once',
        () async {
      final load = Completer<Duration?>();
      engine.setFilePathHandler = (_, __) => load.future;
      final playing = service.playTrack(_track());
      await flush();
      await service.pause();
      load.complete(const Duration(minutes: 3));
      await playing;
      await flush();
      expect(service.state.status, PlayerPlaybackStatus.paused);
      expect(engine.playCalls, 0);
      expect(events.events, isEmpty);
      await service.play();
      await flush();
      expect(engine.playCalls, 1);
      expect(events.events.map((event) => event.type),
          [PlaybackEventType.started]);
    });

    test('play while loading does not start the engine prematurely', () async {
      final load = Completer<Duration?>();
      engine.setFilePathHandler = (_, __) => load.future;
      final playing = service.playTrack(_track());
      await flush();
      await service.pause();
      await service.play();
      final callsBeforeLoad = engine.playCalls;
      load.complete(const Duration(minutes: 3));
      await playing;
      await flush();
      expect(callsBeforeLoad, 0);
      expect(engine.playCalls, 1);
      expect(events.events, hasLength(1));
    });

    test(
        'seek during load is applied after loading and only the last seek wins',
        () async {
      final load = Completer<Duration?>();
      engine.setFilePathHandler = (_, __) => load.future;
      final playing = service.playTrack(_track());
      await flush();
      await service.seek(const Duration(seconds: 10));
      await service.seek(const Duration(seconds: 25));
      final earlySeeks = [...engine.seekPositions];
      load.complete(const Duration(minutes: 3));
      await playing;
      expect(earlySeeks, isEmpty);
      expect(engine.seekPositions, [const Duration(seconds: 25)]);
      expect(service.position, const Duration(seconds: 25));
      await flush();
      expect(events.events.single.position, const Duration(seconds: 25));
    });

    for (final fail in [false, true]) {
      test('late pause cannot pause or rename the next track (failure=$fail)',
          () async {
        await service.playTrack(_track());
        final pause = Completer<void>();
        engine.pauseHandler = () => pause.future;
        final pausing = service.pause();
        await flush();
        final nextTrack = _track(filePath: '/music/next.mp3');
        final next = service.playTrack(nextTrack);
        await flush();
        if (fail) {
          pause.completeError(StateError('late command failure'));
        } else {
          pause.complete();
        }
        await Future.wait([pausing, next]);
        expect(service.currentTrack, nextTrack);
        expect(service.state.status, PlayerPlaybackStatus.playing);
      });
    }

    for (final fail in [false, true]) {
      test('late seek cannot replace the next track position (failure=$fail)',
          () async {
        await service.playTrack(_track());
        final seek = Completer<void>();
        engine.seekHandler = (_) => seek.future;
        final seeking = service.seek(const Duration(seconds: 45));
        await flush();
        final next = service.playTrack(_track(filePath: '/music/next.mp3'));
        await flush();
        if (fail) {
          seek.completeError(StateError('late command failure'));
        } else {
          seek.complete();
        }
        await Future.wait([seeking, next]);
        expect(service.position, Duration.zero);
        expect(service.state.status, PlayerPlaybackStatus.playing);
      });
    }

    for (final fail in [false, true]) {
      test('late stop cannot clear the next track (failure=$fail)', () async {
        await service.playTrack(_track());
        final stop = Completer<void>();
        engine.stopHandler = (call) => call == 2 ? stop.future : Future.value();
        final stopping = service.stop();
        await flush();
        final nextTrack = _track(filePath: '/music/next.mp3');
        final next = service.playTrack(nextTrack);
        await flush();
        if (fail) {
          stop.completeError(StateError('late command failure'));
        } else {
          stop.complete();
        }
        await Future.wait([stopping, next]);
        expect(service.currentTrack, nextTrack);
        expect(service.state.status, PlayerPlaybackStatus.playing);
      });
    }

    test('late play error from old session cannot fail the next track',
        () async {
      final play = Completer<void>();
      engine.playHandler = (call) => call == 1 ? play.future : Future.value();
      await service.playTrack(_track());
      final nextTrack = _track(filePath: '/music/next.mp3');
      await service.playTrack(nextTrack);
      play.completeError(StateError('old play failed'));
      await flush();
      expect(service.currentTrack, nextTrack);
      expect(service.state.status, PlayerPlaybackStatus.playing);
      expect(service.state.hasError, isFalse);
    });

    test('late play error after pause does not undo pause', () async {
      final play = Completer<void>();
      engine.playHandler = (_) => play.future;
      await service.playTrack(_track());
      await service.pause();
      play.completeError(StateError('interrupted play'));
      await flush();
      expect(service.state.status, PlayerPlaybackStatus.paused);
      expect(service.state.hasError, isFalse);
    });

    test('late play error after completion cannot replace completed state',
        () async {
      final play = Completer<void>();
      engine.playHandler = (_) => play.future;
      await service.playTrack(_track());
      engine.emitState(const AudioEngineState(
        isPlaying: false,
        processingState: AudioEngineProcessingState.completed,
      ));
      await flush();
      play.completeError(StateError('late terminal error'));
      engine.emitError(StateError('late terminal stream error'));
      await flush();
      expect(service.state.status, PlayerPlaybackStatus.completed);
      expect(service.state.hasError, isFalse);
    });

    test('native pause is reflected after the engine confirms playback',
        () async {
      await service.playTrack(_track());
      engine.emitState(const AudioEngineState(
        isPlaying: true,
        processingState: AudioEngineProcessingState.ready,
      ));
      await flush();
      engine.emitState(const AudioEngineState(
        isPlaying: false,
        processingState: AudioEngineProcessingState.ready,
      ));
      await flush();
      expect(service.isPlaying, isFalse);
      expect(service.state.status, PlayerPlaybackStatus.paused);
      await service.play();
      expect(service.isPlaying, isTrue);
      expect(engine.playCalls, 2);
    });

    test('queued ready state cannot undo a requested pause', () async {
      await service.playTrack(_track());
      await service.pause();
      engine.emitState(const AudioEngineState(
        isPlaying: true,
        processingState: AudioEngineProcessingState.ready,
      ));
      await flush();
      expect(service.state.status, PlayerPlaybackStatus.paused);
      expect(service.isPlaying, isFalse);
    });

    test('burst of track requests loads only the first and last source',
        () async {
      final firstLoad = Completer<Duration?>();
      engine.setFilePathHandler = (_, call) =>
          call == 1 ? firstLoad.future : const Duration(minutes: 3);
      final requests = [service.playTrack(_track(filePath: '/music/0.mp3'))];
      await flush();
      for (var i = 1; i <= 10; i++) {
        requests.add(service.playTrack(_track(filePath: '/music/$i.mp3')));
      }
      firstLoad.complete(const Duration(minutes: 3));
      await Future.wait(requests);
      await flush();
      expect(engine.setFilePathCalls, 2);
      expect(engine.maxConcurrentLoads, 1);
      expect(service.currentTrack?.filePath, '/music/10.mp3');
      expect(engine.playCalls, 1);
      expect(events.events, hasLength(1));
    });

    test('seek while loading clamps to the newly discovered duration',
        () async {
      final load = Completer<Duration?>();
      engine.setFilePathHandler = (_, __) => load.future;
      final playing = service.playTrack(_track(duration: null));
      await flush();
      await service.seek(const Duration(minutes: 5));
      load.complete(const Duration(minutes: 2));
      await playing;
      expect(engine.seekPositions, [const Duration(minutes: 2)]);
      expect(service.position, const Duration(minutes: 2));
    });

    test('failure cleanup cannot stop the replacement source', () async {
      await service.playTrack(_track());
      final cleanupStop = Completer<void>();
      engine.stopHandler =
          (call) => call == 2 ? cleanupStop.future : Future.value();
      engine.emitError(StateError('current playback failed'));
      await flush();
      expect(service.state.status, PlayerPlaybackStatus.error);
      final nextTrack = _track(filePath: '/music/replacement.mp3');
      final next = service.playTrack(nextTrack);
      await flush();
      cleanupStop.complete();
      await next;
      expect(service.currentTrack, nextTrack);
      expect(service.state.status, PlayerPlaybackStatus.playing);
    });

    test('a failed current command does not block later playback', () async {
      await service.playTrack(_track());
      engine.pauseHandler = () => Future.error(StateError('pause failed'));
      await service.pause();
      expect(service.state.status, PlayerPlaybackStatus.error);
      engine.pauseHandler = null;
      await service.playTrack(_track(filePath: '/music/recovery.mp3'));
      expect(service.state.status, PlayerPlaybackStatus.playing);
      expect(service.currentTrack?.filePath, '/music/recovery.mp3');
    });

    test('replay after completion starts a new listening session', () async {
      await service.playTrack(_track());
      engine.emitState(const AudioEngineState(
        isPlaying: false,
        processingState: AudioEngineProcessingState.completed,
      ));
      await flush();
      await service.play();
      await flush();
      expect(service.position, Duration.zero);
      expect(service.state.status, PlayerPlaybackStatus.playing);
      expect(events.events.where((e) => e.type == PlaybackEventType.started),
          hasLength(2));
      expect(events.events.where((e) => e.type == PlaybackEventType.completed),
          hasLength(1));
    });

    test('obsolete direct failure does not try cache or poison later loads',
        () async {
      await service.dispose();
      final cache = _ThrowingPlaybackCache('cache must not be used');
      engine = _FakeAudioEngine();
      service = _service(
          audioEngine: engine,
          isWindows: true,
          playbackEvents: events,
          playbackCache: cache);
      final firstLoad = Completer<Duration?>();
      engine.setFilePathHandler = (_, call) =>
          call == 1 ? firstLoad.future : const Duration(minutes: 3);
      final firstTrack = _track(filePath: r'C:\music\first.mp3');
      final first = service.playTrack(firstTrack);
      await flush();
      final next = service.playTrack(_track(filePath: r'C:\music\next.mp3'));
      firstLoad.completeError(StateError('obsolete direct failure'));
      await Future.wait([first, next]);
      await service.playTrack(firstTrack);
      expect(cache.calls, 0);
      expect(service.state.status, PlayerPlaybackStatus.playing);
      expect(engine.setFilePathCalls, 3);
    });

    test('obsolete cached source is never submitted to the engine', () async {
      await service.dispose();
      engine = _FakeAudioEngine();
      final cache = _ControlledPlaybackCache();
      service = _service(
          audioEngine: engine,
          isWindows: true,
          playbackEvents: events,
          playbackCache: cache);
      final first = service.playTrack(_track(filePath: r'C:\music\первый.mp3'));
      await flush();
      expect(cache.calls, 1);
      final nextTrack = _track(filePath: r'C:\music\next.mp3');
      final next = service.playTrack(nextTrack);
      cache.result.complete(const PlaybackCacheEntry(
        filePath: '/cache/obsolete.mp3',
        reusedExistingFile: false,
        cacheSizeBeforeCleanupBytes: 0,
        cacheSizeAfterCleanupBytes: 100,
        cleanupDeletedFileCount: 0,
        cleanupDeletedPaths: [],
        sourceSizeBytes: 100,
      ));
      await Future.wait([first, next]);
      expect(engine.setFilePathCalls, 1);
      expect(engine.setFilePaths.single, isNot(contains('obsolete')));
      expect(service.currentTrack, nextTrack);
      expect(service.state.status, PlayerPlaybackStatus.playing);
    });

    test('old engine events during next load do not complete the next track',
        () async {
      await service.playTrack(_track());
      final load = Completer<Duration?>();
      engine.setFilePathHandler = (_, __) => load.future;
      final next = service.playTrack(_track(filePath: '/music/next.mp3'));
      await flush();
      engine.emitState(const AudioEngineState(
        isPlaying: false,
        processingState: AudioEngineProcessingState.completed,
      ));
      engine.emitPosition(const Duration(seconds: 170));
      engine.emitDuration(const Duration(seconds: 170));
      engine.emitError(StateError('old engine error'));
      await flush();
      load.complete(const Duration(minutes: 3));
      await next;
      await flush();
      expect(service.state.status, PlayerPlaybackStatus.playing);
      expect(service.position, Duration.zero);
      expect(events.events.where((e) => e.type == PlaybackEventType.completed),
          isEmpty);
    });

    test('dispose cancels load and later commands do not touch the engine',
        () async {
      final load = Completer<Duration?>();
      engine.setFilePathHandler = (_, __) => load.future;
      final playing = service.playTrack(_track());
      await flush();
      final closing = service.dispose();
      load.completeError(StateError('disposed load'));
      await playing;
      await closing;
      final calls = [
        engine.playCalls,
        engine.stopCalls,
        engine.seekCalls,
        engine.setVolumeCalls
      ];
      await service.play();
      await service.pause();
      await service.seek(const Duration(seconds: 1));
      await service.stop();
      await service.setVolume(0.3);
      await service.toggleMute();
      expect([
        engine.playCalls,
        engine.stopCalls,
        engine.seekCalls,
        engine.setVolumeCalls
      ], calls);
      expect(events.events, isEmpty);
    });
  });

  test('concurrent feedback toggles do not collapse into one toggle', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final id = await repositories.tracks.upsertTrack(_track());
    final track = (await repositories.tracks.findById(id))!;
    final service = JustAudioPlayerService(
      playbackEvents: repositories.playbackEvents,
      audioEngine: _FakeAudioEngine(),
      fileExists: (_) => true,
      isWindows: false,
    );
    addTearDown(service.dispose);
    final queue = PlaybackQueueService(
      playerService: service,
      tracks: repositories.tracks,
      trackUserState: repositories.trackUserState,
      playbackEvents: repositories.playbackEvents,
      recommendationService: RecommendationService(
        tracks: repositories.tracks,
        trackUserState: repositories.trackUserState,
        playbackEvents: repositories.playbackEvents,
      ),
    );
    addTearDown(queue.dispose);

    await service.playTrack(track);
    await Future.wait([queue.toggleLike(track), queue.toggleLike(track)]);
    expect((await repositories.trackUserState.findByTrackId(id))?.isFavorite,
        isFalse);
    expect(queue.state.isCurrentTrackLiked, isFalse);
    await Future.wait([queue.toggleDislike(track), queue.toggleDislike(track)]);
    expect((await repositories.trackUserState.findByTrackId(id))?.isHidden,
        isFalse);
    expect(queue.state.isCurrentTrackDisliked, isFalse);
  });

  test('feedback during playback start preserves both like and play count',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final id = await repositories.tracks.upsertTrack(_track());
    final track = (await repositories.tracks.findById(id))!;
    final service = JustAudioPlayerService(
      playbackEvents: repositories.playbackEvents,
      audioEngine: _FakeAudioEngine(),
      fileExists: (_) => true,
      isWindows: false,
    );
    addTearDown(service.dispose);
    final queue = PlaybackQueueService(
      playerService: service,
      tracks: repositories.tracks,
      trackUserState: repositories.trackUserState,
      playbackEvents: repositories.playbackEvents,
      recommendationService: RecommendationService(
        tracks: repositories.tracks,
        trackUserState: repositories.trackUserState,
        playbackEvents: repositories.playbackEvents,
      ),
    );
    addTearDown(queue.dispose);

    await Future.wait([service.playTrack(track), queue.toggleLike(track)]);
    // Wait for the unawaited history write to finish on the database executor.
    for (var i = 0; i < 100; i++) {
      final state = await repositories.trackUserState.findByTrackId(id);
      if ((state?.playCount ?? 0) > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final state = await repositories.trackUserState.findByTrackId(id);
    expect(state?.playCount, 1);
    expect(state?.isFavorite, isTrue);
  });

  test('playTrack reports missing files without loading audio', () async {
    final engine = _FakeAudioEngine();
    final service = _service(
      audioEngine: engine,
      fileExists: (_) => false,
    );

    await service.playTrack(_track());

    expect(service.state.status, PlayerPlaybackStatus.error);
    expect(service.state.currentTrack?.filePath, _track().filePath);
    expect(service.state.errorMessage, _controlledPlaybackError);
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
    expect(service.state.currentTrack?.filePath, _track().filePath);
    expect(service.state.errorMessage, _controlledPlaybackError);
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

  test('playTrack validates the decoder before starting playback', () async {
    final engine = _FakeAudioEngine();
    final service = _service(audioEngine: engine);

    await service.playTrack(_track());

    expect(engine.setFilePathPreloads, [true]);
    expect(engine.playCalls, 1);
    expect(service.state.status, PlayerPlaybackStatus.playing);

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

  test('path length above 180 uses Windows playback cache', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_long_path_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final appSupportDirectory =
        Directory(p.join(tempDirectory.path, 'support'));
    var sourceDirectory = tempDirectory.path;
    while (p
            .normalize(File(p.join(sourceDirectory, 'song.mp3')).absolute.path)
            .length <=
        180) {
      sourceDirectory = p.join(sourceDirectory, 'very_long_directory_name');
    }
    final source = File(p.join(sourceDirectory, 'song.mp3'));
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

    await service.playTrack(_track(filePath: source.path));

    expect(normalizedSourcePath.length, greaterThan(180));
    expect(engine.setFilePaths.single, isNot(normalizedSourcePath));
    expect(p.basename(engine.setFilePaths.single), matches(_asciiFileName));
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

  test('short ASCII Windows path uses direct playback', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_short_ascii_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final source = File(p.join(tempDirectory.path, 'song.mp3'));
    await source.writeAsBytes([1, 2, 3, 4]);
    final normalizedSourcePath = p.normalize(source.absolute.path);
    final engine = _FakeAudioEngine();
    final cache = _ThrowingPlaybackCache('cache should not be used');
    final service = _service(
      audioEngine: engine,
      isWindows: true,
      fileExists: (path) => File(path).existsSync(),
      playbackCache: cache,
    );

    await service.playTrack(_track(filePath: source.path));

    expect(engine.setFilePaths, [normalizedSourcePath]);
    expect(cache.calls, 0);
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

  test('direct Windows load failure retries through playback cache', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_direct_retry_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final appSupportDirectory =
        Directory(p.join(tempDirectory.path, 'support'));
    final source = File(p.join(tempDirectory.path, 'song.mp3'));
    await source.writeAsBytes([1, 2, 3, 4]);
    final normalizedSourcePath = p.normalize(source.absolute.path);
    final engine = _FakeAudioEngine()
      ..setFilePathHandler = (filePath, call) {
        if (filePath == normalizedSourcePath) {
          throw FileSystemException('Cannot find path', filePath);
        }
        return const Duration(minutes: 3);
      };
    final service = _service(
      audioEngine: engine,
      isWindows: true,
      fileExists: (path) => File(path).existsSync(),
      playbackCache: WindowsPlaybackCache(
        appSupportDirectoryProvider: () async => appSupportDirectory,
      ),
    );

    await service.playTrack(_track(filePath: source.path));

    expect(engine.setFilePaths, hasLength(2));
    expect(engine.setFilePaths.first, normalizedSourcePath);
    expect(engine.setFilePaths.last, isNot(normalizedSourcePath));
    expect(service.state.status, PlayerPlaybackStatus.playing);

    await service.dispose();
  });

  test('source path with previous direct failure uses cache next time',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_previous_failure_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final appSupportDirectory =
        Directory(p.join(tempDirectory.path, 'support'));
    final source = File(p.join(tempDirectory.path, 'song.mp3'));
    await source.writeAsBytes([1, 2, 3, 4]);
    final normalizedSourcePath = p.normalize(source.absolute.path);
    var failDirect = true;
    final engine = _FakeAudioEngine()
      ..setFilePathHandler = (filePath, call) {
        if (filePath == normalizedSourcePath && failDirect) {
          failDirect = false;
          throw FileSystemException('Cannot find path', filePath);
        }
        return const Duration(minutes: 3);
      };
    final service = _service(
      audioEngine: engine,
      isWindows: true,
      fileExists: (path) => File(path).existsSync(),
      playbackCache: WindowsPlaybackCache(
        appSupportDirectoryProvider: () async => appSupportDirectory,
      ),
    );
    final track = _track(filePath: source.path);

    await service.playTrack(track);
    final cachedPath = engine.setFilePaths.last;
    await service.playTrack(track);

    expect(engine.setFilePaths, [
      normalizedSourcePath,
      cachedPath,
      cachedPath,
    ]);
    expect(service.state.status, PlayerPlaybackStatus.playing);

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
    expect(service.state.errorMessage, _controlledPlaybackError);
    expect(engine.setFilePathCalls, 0);
    expect(cache.calls, 0);

    await service.dispose();
  });

  test('failed direct load and failed cache fallback report controlled error',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_cache_failure_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final source = File(p.join(tempDirectory.path, 'song.mp3'));
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
    expect(service.state.errorMessage, _controlledPlaybackError);
    expect(engine.setFilePathCalls, 1);
    expect(engine.playCalls, 0);
    expect(cache.calls, 1);

    await service.dispose();
  });

  test(
      'failed cache load does not stay loading or expose MissingPluginException',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_player_missing_plugin_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final appSupportDirectory =
        Directory(p.join(tempDirectory.path, 'support'));
    final source = File(p.join(tempDirectory.path, 'song.mp3'));
    await source.writeAsBytes([1, 2, 3, 4]);
    final engine = _FakeAudioEngine()
      ..setFilePathHandler = (_, __) {
        throw MissingPluginException('No implementation found for setFilePath');
      };
    final service = _service(
      audioEngine: engine,
      isWindows: true,
      fileExists: (path) => File(path).existsSync(),
      playbackCache: WindowsPlaybackCache(
        appSupportDirectoryProvider: () async => appSupportDirectory,
      ),
    );

    await service.playTrack(_track(filePath: source.path));
    engine.emitState(
      const AudioEngineState(
        isPlaying: true,
        processingState: AudioEngineProcessingState.loading,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.state.status, PlayerPlaybackStatus.error);
    expect(service.state.isPlaying, isFalse);
    expect(service.state.errorMessage, _controlledPlaybackError);
    expect(
        service.state.errorMessage, isNot(contains('MissingPluginException')));
    expect(service.state.errorMessage, isNot(contains('No implementation')));
    expect(engine.setFilePaths, hasLength(2));
    expect(engine.playCalls, 0);

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

  test('Windows recovery uses polled position before synthetic progress',
      () async {
    final engine = _FakeAudioEngine();
    final service = _service(
      audioEngine: engine,
      isWindows: true,
      windowsProgressRecoveryInterval: const Duration(milliseconds: 5),
      windowsSyntheticProgressGrace: const Duration(seconds: 1),
    );

    await service.playTrack(_track(filePath: r'C:\music\song.flac'));
    engine.polledPosition = const Duration(seconds: 20);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(engine.positionPolls, greaterThan(0));
    expect(service.state.position, const Duration(seconds: 20));

    await service.dispose();
  });

  test('Windows synthetic progress starts only after polling stalls', () async {
    final engine = _FakeAudioEngine();
    final service = _service(
      audioEngine: engine,
      isWindows: true,
      windowsProgressRecoveryInterval: const Duration(milliseconds: 5),
      windowsSyntheticProgressGrace: const Duration(milliseconds: 20),
    );

    await service.playTrack(_track(filePath: r'C:\music\song.flac'));
    await Future<void>.delayed(const Duration(milliseconds: 12));
    expect(service.state.position, Duration.zero);

    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(service.state.position, greaterThan(Duration.zero));
    expect(service.state.position, lessThan(const Duration(minutes: 3)));

    await service.dispose();
  });

  test('non-Windows playback does not use progress recovery polling', () async {
    final engine = _FakeAudioEngine()
      ..polledPosition = const Duration(seconds: 20);
    final service = _service(
      audioEngine: engine,
      isWindows: false,
      windowsProgressRecoveryInterval: const Duration(milliseconds: 5),
      windowsSyntheticProgressGrace: const Duration(milliseconds: 10),
    );

    await service.playTrack(_track());
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(engine.positionPolls, 0);
    expect(engine.durationPolls, 0);
    expect(service.state.position, Duration.zero);

    await service.dispose();
  });

  test('Windows recovery uses polled duration when load and stream omit it',
      () async {
    final engine = _FakeAudioEngine()
      ..loadedDuration = null
      ..polledDuration = const Duration(minutes: 5);
    final service = _service(
      audioEngine: engine,
      isWindows: true,
      windowsProgressRecoveryInterval: const Duration(milliseconds: 5),
      windowsSyntheticProgressGrace: const Duration(seconds: 1),
    );

    await service.playTrack(
      _track(filePath: r'C:\music\song.flac', duration: null),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(engine.durationPolls, greaterThan(0));
    expect(service.state.duration, const Duration(minutes: 5));

    await service.dispose();
  });

  test('seek clamps to Windows recovered duration', () async {
    final engine = _FakeAudioEngine()
      ..loadedDuration = null
      ..polledDuration = const Duration(minutes: 2);
    final service = _service(
      audioEngine: engine,
      isWindows: true,
      windowsProgressRecoveryInterval: const Duration(milliseconds: 5),
      windowsSyntheticProgressGrace: const Duration(seconds: 1),
    );

    await service.playTrack(
      _track(filePath: r'C:\music\song.flac', duration: null),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await service.seek(const Duration(minutes: 3));

    expect(engine.seekPositions, [const Duration(minutes: 2)]);
    expect(service.state.position, const Duration(minutes: 2));

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
    expect(service.state.currentTrack?.filePath, _track().filePath);
    expect(service.state.errorMessage, _controlledPlaybackError);

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
    engine.emitDuration(const Duration(minutes: 2));
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

  test('setVolume clamps below zero and calls audio engine', () async {
    final engine = _FakeAudioEngine();
    final service = _service(audioEngine: engine);

    await service.setVolume(-0.5);

    expect(service.state.volume, 0);
    expect(engine.setVolumes, [0]);

    await service.dispose();
  });

  test('setVolume clamps above one and calls audio engine', () async {
    final engine = _FakeAudioEngine();
    final service = _service(audioEngine: engine);

    await service.setVolume(1.5);

    expect(service.state.volume, 1);
    expect(engine.setVolumes, [1]);

    await service.dispose();
  });

  test('toggleMute sets volume to zero without pausing playback', () async {
    final engine = _FakeAudioEngine();
    final service = _service(audioEngine: engine);
    await service.playTrack(_track());
    await Future<void>.delayed(Duration.zero);

    await service.setVolume(0.7);
    await service.toggleMute();

    expect(service.state.volume, 0);
    expect(service.state.isPlaying, isTrue);
    expect(engine.pauseCalls, 0);
    expect(engine.setVolumes.sublist(engine.setVolumes.length - 2), [0.7, 0]);

    await service.dispose();
  });

  test('toggleMute restores previous non-zero volume', () async {
    final engine = _FakeAudioEngine();
    final service = _service(audioEngine: engine);

    await service.setVolume(0.35);
    await service.toggleMute();
    await service.toggleMute();

    expect(service.state.volume, 0.35);
    expect(engine.setVolumes, [0.35, 0, 0.35]);

    await service.dispose();
  });

  test('volume persists to settings', () async {
    final engine = _FakeAudioEngine();
    final settings = _FakeSettingsRepository();
    final service = _service(
      audioEngine: engine,
      settings: settings,
    );

    await service.setVolume(0.4);

    expect(await settings.readString('player.volume'), '0.4');
    expect(await settings.readString('player.previousVolumeBeforeMute'), '0.4');

    await service.dispose();
  });

  test('startup restores saved volume', () async {
    final engine = _FakeAudioEngine();
    final settings = _FakeSettingsRepository();
    await settings.writeString('player.volume', '0.25');
    final service = _service(
      audioEngine: engine,
      settings: settings,
    );

    await service.restoreSavedVolume();

    expect(service.state.volume, 0.25);
    expect(engine.setVolumes, [0.25]);

    await service.dispose();
  });
}

const _controlledPlaybackError =
    'Не удалось воспроизвести трек. Возможно, файл недоступен, повреждён или '
    'имеет неподдерживаемый формат.';
final _asciiFileName = RegExp(r'^[A-Za-z0-9_.-]+$');

JustAudioPlayerService _service({
  required _FakeAudioEngine audioEngine,
  bool Function(String filePath)? fileExists,
  bool? isWindows,
  PlaybackCache? playbackCache,
  Duration windowsProgressRecoveryInterval = const Duration(milliseconds: 250),
  Duration windowsSyntheticProgressGrace = const Duration(seconds: 2),
  _FakePlaybackEventRepository? playbackEvents,
  _FakeTrackUserStateRepository? trackUserState,
  SettingsRepository? settings,
}) {
  final stateRepository = trackUserState ?? _FakeTrackUserStateRepository();
  final eventRepository = playbackEvents ?? _FakePlaybackEventRepository();
  eventRepository.userState = stateRepository;
  return JustAudioPlayerService(
    playbackEvents: eventRepository,
    settings: settings,
    audioEngine: audioEngine,
    isWindows: isWindows ?? false,
    playbackCache: playbackCache,
    fileExists: fileExists ?? (_) => true,
    windowsProgressRecoveryInterval: windowsProgressRecoveryInterval,
    windowsSyntheticProgressGrace: windowsSyntheticProgressGrace,
  );
}

Track _track({
  String filePath = '/music/song.flac',
  String? stableId,
  Duration? duration = const Duration(minutes: 3),
}) {
  final now = DateTime(2026);
  return Track(
    id: 1,
    stableId: stableId,
    filePath: filePath,
    title: 'Song',
    artist: 'Artist',
    duration: duration,
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
  Duration polledPosition = Duration.zero;
  Duration? polledDuration;
  Object? setFilePathError;
  FutureOr<Duration?> Function(String filePath, int call)? setFilePathHandler;
  Future<void> Function()? pauseHandler;
  Future<void> Function(int call)? stopHandler;
  Future<void> Function(int call)? playHandler;
  Future<void> Function(Duration position)? seekHandler;
  int concurrentLoads = 0;
  int maxConcurrentLoads = 0;
  int setFilePathCalls = 0;
  final List<String> setFilePaths = [];
  final List<bool> setFilePathPreloads = [];
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int seekCalls = 0;
  int positionPolls = 0;
  int durationPolls = 0;
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
          {bool preload = true}) =>
      switch (source) {
        FileAudioSource(:final path) => setFilePath(path, preload: preload),
        ContentUriAudioSource() =>
          Future.error(UnsupportedError('Unsupported fake source')),
      };

  Future<Duration?> setFilePath(
    String filePath, {
    bool preload = true,
  }) async {
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
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    await pauseHandler?.call();
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    await stopHandler?.call(stopCalls);
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

  void emitPosition(Duration position) {
    _positionController.add(position);
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

final class _ControlledPlaybackCache implements PlaybackCache {
  final result = Completer<PlaybackCacheEntry>();
  int calls = 0;

  @override
  Future<PlaybackCacheEntry> resolve(Track track, String sourcePath) {
    calls++;
    return result.future;
  }
}

final class _FakePlaybackEventRepository implements PlaybackEventRepository {
  final List<PlaybackEvent> events = [];

  TrackUserStateRepository? userState;

  @override
  Future<int> recordEvent(PlaybackEvent event) =>
      recordTestEvent(this, userState, event);

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

final class _FakeSettingsRepository implements SettingsRepository {
  final Map<String, AppSetting> _settings = {};

  @override
  Future<AppSetting?> read(String key) async => _settings[key];

  @override
  Future<String?> readString(String key) async => _settings[key]?.value;

  @override
  Future<void> writeString(String key, String value) async {
    _settings[key] = AppSetting(
      key: key,
      value: value,
      updatedAt: DateTime(2026),
    );
  }

  @override
  Future<void> delete(String key) async {
    _settings.remove(key);
  }
}

final class _FakeTrackUserStateRepository implements TrackUserStateRepository {
  final Map<int, TrackUserState> states = {};

  @override
  Future<TrackUserState> toggleFeedback(int trackId, TrackFeedback feedback,
          {required DateTime updatedAt}) =>
      toggleTestFeedback(this, trackId, feedback, updatedAt);

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
