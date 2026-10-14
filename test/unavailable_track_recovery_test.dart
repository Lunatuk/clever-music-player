import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/player/player_service.dart';
import 'package:clever_music_player/src/player/transition_player_service.dart';
import 'package:clever_music_player/src/queue/playback_queue_service.dart';
import 'package:clever_music_player/src/queue/queue_state.dart';
import 'package:clever_music_player/src/recommendation/recommendation_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/test_audio_engine.dart';

void main() {
  late _Fixture f;
  setUp(() async {
    f = await _Fixture.create();
  });
  tearDown(() async {
    await f.dispose();
  });

  test('automatic transition bypasses a file deleted since the scan', () async {
    await f.library();
    f.missing.add(f.b.filePath);
    f.complete();
    await until(() => f.player.currentTrack == f.c && f.player.isPlaying);
    expect(f.queue.state.playbackContext.currentIndex, 2);
    expect(await f.starts(f.b), 0);
    expect(await f.starts(f.c), 1);
  });

  test('automatic transition bypasses a decoder load failure', () async {
    await f.library();
    f.broken.add(f.b.filePath);
    f.complete();
    await until(() => f.player.currentTrack == f.c && f.player.isPlaying);
    expect(await f.starts(f.b), 0);
    expect(await f.starts(f.c), 1);
  });

  test(
      'explicit selection reports unavailable file and does not choose another',
      () async {
    f.missing.add(f.b.filePath);
    await f.queue.playLibraryTrack(track: f.b, visibleTracks: f.tracks);
    await flush();
    expect(f.player.currentTrack, f.b);
    expect(f.player.state.status, PlayerPlaybackStatus.error);
    expect(f.queue.state.lastError, isNotNull);
    expect(f.engine.playCalls, 0);
  });

  test('all unavailable tracks terminate recovery without looping repeat-one',
      () async {
    await f.library();
    f.queue.setRepeatMode(PlaybackRepeatMode.track);
    f.missing.addAll(f.tracks.map((track) => track.filePath));
    f.complete();
    await until(
        () => f.queue.state.lastError != null && !f.queue.state.isChoosingNext);
    await flush();
    expect(f.player.isPlaying, isFalse);
    expect(f.engine.setFilePathCalls, lessThanOrEqualTo(4));
    expect(f.queue.state.lastError, contains('доступ'));
  });

  test('repeat-playlist cannot cycle endlessly through failed sources',
      () async {
    await f.library();
    f.queue.setRepeatMode(PlaybackRepeatMode.playlist);
    f.missing.addAll(f.tracks.map((track) => track.filePath));
    f.complete();
    await until(() => f.queue.state.lastError?.contains('ограничен') == true);
    final calls = f.engine.setFilePathCalls;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(f.engine.setFilePathCalls, calls);
    expect(f.queue.state.isChoosingNext, isFalse);
    expect(await f.starts(f.b), 0);
  });

  test('late decoder error after automatic start advances once', () async {
    await f.library();
    f.complete();
    await until(() => f.player.currentTrack == f.b && f.player.isPlaying);
    f.engine.emitError(StateError('late decode error'));
    await until(() => f.player.currentTrack == f.c && f.player.isPlaying);
    expect(await f.starts(f.c), 1);
    expect(f.queue.state.playbackContext.currentIndex, 2);
  });

  test('operation failure does not masquerade as an unavailable source',
      () async {
    await f.library();
    f.complete();
    await until(() => f.player.currentTrack == f.b && f.player.isPlaying);
    f.engine.seekHandler = (_) async {
      throw StateError('seek failed');
    };
    await f.player.seek(const Duration(seconds: 20));
    await flush();
    expect(f.player.currentTrack, f.b);
    expect(f.player.state.failureKind, PlayerFailureKind.operation);
    expect(await f.starts(f.c), 0);
  });

  test('manual source error never starts automatic recovery', () async {
    await f.library();
    f.engine.emitError(StateError('manual source failed'));
    await flush();
    expect(f.player.currentTrack, f.a);
    expect(f.player.state.failureKind, PlayerFailureKind.source);
    expect(await f.starts(f.b), 0);
  });

  test('manual library selection wins over recovery waiting for a decoder',
      () async {
    await f.library();
    final load = Completer<Duration?>();
    f.engine.setFilePathHandler = (path, _) =>
        path == f.b.filePath ? load.future : const Duration(seconds: 60);
    f.complete();
    await until(() => f.engine.setFilePathCalls == 2);
    final manual =
        f.queue.playLibraryTrack(track: f.a, visibleTracks: f.tracks);
    load.completeError(const FormatException('obsolete failure'));
    await manual;
    await flush();
    expect(f.player.currentTrack, f.a);
    expect(f.player.isPlaying, isTrue);
    expect(await f.starts(f.c), 0);
  });

  test('dual-deck playback recovers when the preloaded candidate was broken',
      () async {
    final g = await _Fixture.create(dual: true);
    addTearDown(g.dispose);
    g.broken.add(g.b.filePath);
    await g.library();
    await until(() => g.second.setFilePathCalls == 1);
    g.complete();
    await until(() => g.player.currentTrack == g.c && g.player.isPlaying);
    expect(await g.starts(g.b), 0);
    expect(await g.starts(g.c), 1);
  });

  test(
      'incoming source failure during crossfade cancels its tail and recovers once',
      () async {
    final g = await _Fixture.create(dual: true);
    addTearDown(g.dispose);
    await g.library();
    await until(() => g.second.setFilePathCalls == 1);
    g.engine.emitPosition(const Duration(seconds: 57));
    await until(() => g.player.currentTrack == g.b && g.second.playing);
    g.second.emitError(StateError('incoming decoder failed'));
    await until(() => g.player.currentTrack == g.c && g.player.isPlaying);
    expect(await g.starts(g.c), 1);
    expect(
        [g.engine, g.second].where((engine) => engine.playing), hasLength(1));
  });

  test(
      'duplicate failed manual queue items do not prevent reaching the next source',
      () async {
    await f.queue.playTrackManually(f.a);
    await f.queue.addToQueue(f.b);
    await f.queue.addToQueue(f.b);
    await f.queue.addToQueue(f.c);
    f.missing.add(f.b.filePath);
    f.complete();
    await until(() => f.player.currentTrack == f.c && f.player.isPlaying);
    expect(await f.starts(f.b), 0);
    expect(await f.starts(f.c), 1);
    expect(f.queue.state.manualQueue, isEmpty);
  });

  test('Wave stops with an explanation when all sources are unavailable',
      () async {
    await f.queue.playSmartNext();
    f.missing.addAll(f.tracks.map((track) => track.filePath));
    f.complete();
    await until(() => f.queue.state.lastError?.contains('доступный') == true);
    expect(f.player.isPlaying, isFalse);
    expect(f.queue.state.isChoosingNext, isFalse);
    expect(f.engine.playCalls, 1);
  });

  test(
      'record removed from the database is bypassed without loading its snapshot',
      () async {
    await f.library();
    await f.repositories.tracks.deleteTrack(f.b.id!);
    f.complete();
    await until(() => f.player.currentTrack == f.c && f.player.isPlaying);
    expect(f.engine.setFilePaths, isNot(contains(f.b.filePath)));
  });

  for (final command in ['pause', 'stop', 'dispose']) {
    test('$command cancels recovery while an automatic load is pending',
        () async {
      await f.library();
      final load = Completer<Duration?>();
      f.engine.setFilePathHandler = (path, _) =>
          path == f.b.filePath ? load.future : const Duration(seconds: 60);
      f.complete();
      await until(() => f.engine.setFilePathCalls == 2);
      if (command == 'pause') await f.player.pause();
      Future<void>? stopping;
      if (command == 'stop') stopping = f.player.stop();
      Future<void>? closing;
      if (command == 'dispose') closing = f.queue.dispose();
      await flush();
      load.completeError(const FormatException('cancelled source failed'));
      await stopping;
      await closing;
      await flush();
      expect(await f.starts(f.c), 0);
      if (command != 'dispose') expect(f.queue.state.isChoosingNext, isFalse);
      if (command == 'dispose') {
        expect(await f.queue.stateStream.isEmpty, isTrue);
      }
    });
  }
}

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 10));
Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 100; i++) {
    if (predicate()) {
      await flush();
      return;
    }
    await flush();
  }
  fail('Timed out waiting for source recovery');
}

class _Fixture {
  _Fixture(this.database, this.repositories, this.tracks, {bool dual = false}) {
    engine.setFilePathHandler = (path, _) {
      if (broken.contains(path)) throw const FormatException('invalid audio');
      return const Duration(seconds: 60);
    };
    second.setFilePathHandler = engine.setFilePathHandler;
    final firstDeck = JustAudioPlayerService(
        playbackEvents: repositories.playbackEvents,
        audioEngine: engine,
        isWindows: false,
        fileExists: (path) => !missing.contains(path));
    player = dual
        ? TransitionPlayerService(
            first: firstDeck,
            second: JustAudioPlayerService(
                playbackEvents: repositories.playbackEvents,
                audioEngine: second,
                isWindows: false,
                fileExists: (path) => !missing.contains(path)))
        : firstDeck;
    queue = PlaybackQueueService(
        playerService: player,
        tracks: repositories.tracks,
        trackUserState: repositories.trackUserState,
        playbackEvents: repositories.playbackEvents,
        recommendationService: RecommendationService(
            tracks: repositories.tracks,
            trackUserState: repositories.trackUserState,
            playbackEvents: repositories.playbackEvents),
        randomDouble: () => 0);
  }
  final AppDatabase database;
  final DriftRepositories repositories;
  final List<Track> tracks;
  final missing = <String>{};
  final broken = <String>{};
  final engine = TestAudioEngine()
    ..loadedDuration = const Duration(seconds: 60);
  final second = TestAudioEngine()
    ..loadedDuration = const Duration(seconds: 60);
  late final PlayerService player;
  late final PlaybackQueueService queue;
  Track get a => tracks[0];
  Track get b => tracks[1];
  Track get c => tracks[2];
  static Future<_Fixture> create({bool dual = false}) async {
    final db = AppDatabase(NativeDatabase.memory());
    final repositories = DriftRepositories(db);
    final tracks = <Track>[];
    for (final name in ['a', 'b', 'c']) {
      final id = await repositories.tracks.upsertTrack(Track(
          filePath: p.join(Directory.systemTemp.path, 'cmp-music', '$name.mp3'),
          title: name,
          artist: 'artist $name',
          duration: const Duration(seconds: 60),
          addedAt: DateTime(2026),
          updatedAt: DateTime(2026)));
      tracks.add((await repositories.tracks.findById(id))!);
    }
    return _Fixture(db, repositories, tracks, dual: dual);
  }

  Future<void> library() =>
      queue.playLibraryTrack(track: a, visibleTracks: tracks);
  void complete() => engine.emitState(const AudioEngineState(
      isPlaying: true, processingState: AudioEngineProcessingState.completed));
  Future<int> starts(Track track) async => (await repositories.playbackEvents
          .recentEvents(limit: 100))
      .where((event) =>
          event.trackId == track.id && event.type == PlaybackEventType.started)
      .length;
  Future<void> dispose() async {
    await Future.wait([queue.dispose(), player.dispose()]);
    await database.close();
  }
}
