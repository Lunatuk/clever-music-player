import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/player/transition_player_service.dart';
import 'package:clever_music_player/src/player/windows_playback_cache.dart';
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

  test(
      'preparation opens the decoder silently without changing current/history',
      () async {
    await f.player.playTrack(f.a);
    await f.player.prepareNextTrack(f.b);
    await flush();
    expect(f.player.currentTrack, f.a);
    expect(f.second.setFilePathPreloads, [true]);
    expect(f.second.playCalls, 0);
    expect(f.second.setVolumes.last, 0);
    expect(await f.starts(f.b), 0);
    expect(await f.starts(f.a), 1);
  });

  test(
      'prepared track starts with no new load; disabled crossfade still preloads',
      () async {
    await f.player.setCrossfadeDuration(Duration.zero);
    await f.player.playTrack(f.a);
    await f.player.prepareNextTrack(f.b);
    final loads = f.second.setFilePathCalls;
    await f.player.playAutomatically(f.b);
    await flush();
    expect(f.second.setFilePathCalls, loads);
    expect(f.second.playCalls, 1);
    expect(f.first.playing, isFalse);
    expect(f.second.setVolumes.last, 1);
    expect(f.player.currentTrack, f.b);
    expect(await f.starts(f.b), 1);
  });

  test('natural playlist transition consumes prepared decoder exactly once',
      () async {
    await f.player.setCrossfadeDuration(Duration.zero);
    await f.library();
    await until(() => f.second.setFilePathCalls == 1);
    f.first.emitState(const AudioEngineState(
        isPlaying: true,
        processingState: AudioEngineProcessingState.completed));
    await until(() => f.player.currentTrack == f.b && f.second.playCalls == 1);
    await flush();
    expect(f.second.setFilePathCalls, 1);
    expect(f.queue.state.playbackContext.currentIndex, 1);
    expect(await f.starts(f.b), 1);
    expect(await f.completions(f.a), 1);
  });

  test(
      'crossfade overlaps decks, uses complementary gains and keeps one current track',
      () async {
    await f.startFade();
    expect(f.first.playing, isTrue);
    expect(f.second.playing, isTrue);
    expect(f.player.currentTrack, f.b);
    f.clock.advance(const Duration(seconds: 1));
    await tick();
    expect(f.first.setVolumes.last, closeTo(2 / 3, .001));
    expect(f.second.setVolumes.last, closeTo(1 / 3, .001));
    expect(
        f.first.setVolumes.last + f.second.setVolumes.last, closeTo(1, .001));
    expect(await f.starts(f.b), 1);
    f.clock.advance(const Duration(seconds: 2));
    await tick();
    await until(() => !f.first.playing);
    expect(f.second.setVolumes.last, 1);
    expect(await f.completions(f.a), 1);
    expect(f.player.currentTrack, f.b);
  });

  test('pause freezes both decks and fade; resume continues it', () async {
    await f.startFade();
    f.clock.advance(const Duration(seconds: 1));
    await tick();
    await f.player.pause();
    await flush();
    expect(f.first.playing, isFalse);
    expect(f.second.playing, isFalse);
    final volume = f.second.setVolumes.last;
    f.clock.advance(const Duration(seconds: 10));
    await tick();
    expect(f.second.setVolumes.last, volume);
    expect(f.player.state.status, PlayerPlaybackStatus.paused);
    await f.player.play();
    await flush();
    expect(f.first.playing, isTrue);
    expect(f.second.playing, isTrue);
    f.clock.advance(const Duration(seconds: 1));
    await tick();
    expect(f.second.setVolumes.last, closeTo(2 / 3, .001));
    expect(await f.starts(f.b), 1);
  });

  test('mute and volume affect both fade outputs without changing the gains',
      () async {
    await f.startFade();
    f.clock.advance(const Duration(seconds: 1));
    await tick();
    await f.player.setVolume(.6);
    expect(f.first.setVolumes.last, closeTo(.4, .001));
    expect(f.second.setVolumes.last, closeTo(.2, .001));
    expect(f.player.volume, .6);
    await f.player.toggleMute();
    expect(f.first.setVolumes.last, 0);
    expect(f.second.setVolumes.last, 0);
    await f.player.toggleMute();
    expect(f.player.volume, .6);
    expect(
        f.first.setVolumes.last + f.second.setVolumes.last, closeTo(.6, .001));
  });

  test('seek cancels outgoing audio and never fabricates its completion',
      () async {
    await f.startFade();
    await f.player.seek(const Duration(seconds: 25));
    await flush();
    expect(f.first.playing, isFalse);
    expect(f.second.seekPositions.last, const Duration(seconds: 25));
    expect(f.second.setVolumes.last, 1);
    expect(await f.completions(f.a), 0);
    f.clock.advance(const Duration(seconds: 10));
    await tick();
    expect(f.player.currentTrack, f.b);
  });

  test('manual next uses prepared decoder without starting an overlap',
      () async {
    await f.library();
    await until(() => f.second.setFilePathCalls == 1);
    f.first.emitPosition(const Duration(seconds: 20));
    await f.queue.next();
    await flush();
    expect(f.player.currentTrack, f.b);
    expect(f.first.playing, isFalse);
    expect(f.second.setFilePathCalls, 1);
    expect(f.second.setVolumes.last, 1);
    expect(await f.completions(f.a), 0);
  });

  test(
      'manual selection during a fade stops the old tail and cancels its timer',
      () async {
    await f.startFade();
    await f.player.playTrack(f.c);
    await flush();
    f.clock.advance(const Duration(seconds: 8));
    await tick();
    expect(f.player.currentTrack, f.c);
    expect(f.first.playing, isFalse);
    expect(f.second.setVolumes.last, 1);
    expect(await f.completions(f.a), 0);
  });

  test('pause immediately after selecting a track cancels pending autoplay',
      () async {
    final load = Completer<Duration?>();
    f.first.setFilePathHandler = (_, __) => load.future;
    final playing = f.player.playTrack(f.a);
    await f.player.pause();
    load.complete(const Duration(seconds: 60));
    await playing;
    await flush();
    expect(f.first.playCalls, 0);
    expect(f.player.state.status, PlayerPlaybackStatus.paused);
  });

  test('background load error leaves current audio and state intact', () async {
    await f.player.playTrack(f.a);
    f.second.setFilePathError = StateError('broken file');
    await f.player.prepareNextTrack(f.b);
    await flush();
    expect(f.first.playing, isTrue);
    expect(f.player.currentTrack, f.a);
    expect(f.player.state.hasError, isFalse);
    expect(await f.starts(f.b), 0);
  });

  test(
      'pause while prepared promotion is awaiting volume confirmation stays paused',
      () async {
    await f.player.playTrack(f.a);
    await f.player.prepareNextTrack(f.b);
    final volume = Completer<void>();
    f.second.volumeHandler = (_) => volume.future;
    final promotion = f.player.playAutomatically(f.b);
    await f.player.pause();
    volume.complete();
    await promotion;
    await flush();
    expect(f.player.currentTrack, f.b);
    expect(f.player.state.status, PlayerPlaybackStatus.paused);
    expect(f.second.playing, isFalse);
  });

  test('dispose during preparation cancels both decks and late preparation',
      () async {
    final load = Completer<Duration?>();
    f.second.setFilePathHandler = (_, __) => load.future;
    final preparation = f.player.prepareNextTrack(f.b);
    await flush();
    final closing = f.player.dispose();
    load.complete(const Duration(seconds: 60));
    await preparation;
    await closing;
    expect(f.first.disposeCalls, 1);
    expect(f.second.disposeCalls, 1);
    expect(f.second.playCalls, 0);
    expect(await f.starts(f.b), 0);
  });

  test(
      'failed fade gain command stops affected output without an uncaught error',
      () async {
    await f.startFade();
    f.second.volumeHandler = (_) async {
      throw StateError('volume failed');
    };
    f.clock.advance(const Duration(seconds: 1));
    await tick();
    await flush();
    expect(f.player.state.hasError, isTrue);
    expect(f.first.playing, isFalse);
    expect(f.second.playing, isFalse);
  });

  test('slow preparation cannot block a different manual selection', () async {
    await f.player.playTrack(f.a);
    final load = Completer<Duration?>();
    f.second.setFilePathHandler = (_, __) => load.future;
    final preparation = f.player.prepareNextTrack(f.b);
    await flush();
    await f.player.playTrack(f.c).timeout(const Duration(seconds: 1));
    expect(f.player.currentTrack, f.c);
    load.complete(const Duration(seconds: 60));
    await preparation;
    await flush();
    expect(f.second.playCalls, 0);
    expect(await f.starts(f.b), 0);
  });

  test('changing queue invalidates prepared item before automatic transition',
      () async {
    await f.library();
    await until(() => f.second.setFilePathCalls == 1);
    await f.queue.addToQueue(f.c);
    await until(() => f.second.setFilePathCalls == 2);
    f.first.emitPosition(const Duration(seconds: 57));
    await until(() => f.player.currentTrack == f.c);
    expect(f.queue.state.activeSource, PlaybackSource.manualQueue);
    expect(await f.starts(f.b), 0);
    expect(await f.starts(f.c), 1);
  });

  test('repeat-one prepares same track as a separate listening session',
      () async {
    await f.library();
    f.queue.setRepeatMode(PlaybackRepeatMode.track);
    await until(() =>
        f.second.setFilePaths.isNotEmpty &&
        f.second.setFilePaths.last.endsWith('a.mp3'));
    f.first.emitPosition(const Duration(seconds: 57));
    await until(() => f.second.playCalls == 1);
    expect(f.player.currentTrack, f.a);
    expect(f.queue.state.playbackContext.currentIndex, 0);
    expect(await f.starts(f.a), 2);
  });

  test('shuffle preparation does not consume or redraw the selected item',
      () async {
    await f.playlist();
    f.queue.setPlaylistShuffleEnabled(true);
    await until(() => f.second.setFilePathCalls >= 1);
    await flush();
    final path = f.second.setFilePaths.last;
    f.first.emitPosition(const Duration(seconds: 57));
    await until(() => f.second.playCalls == 1);
    expect(f.player.currentTrack!.filePath, path);
    expect(f.queue.state.isPlaylistShuffleEnabled, isTrue);
  });

  test('Wave preselects next candidate and promotes that same candidate',
      () async {
    await f.queue.playSmartNext();
    await until(() => f.second.setFilePathCalls == 1);
    final prepared = f.second.setFilePaths.single;
    f.first.emitPosition(const Duration(seconds: 57));
    await until(() => f.second.playCalls == 1);
    expect(f.player.currentTrack!.filePath, prepared);
    expect(
        f.queue.state.lastRecommendationResult!.track, f.player.currentTrack);
  });

  test(
      'native completion of outgoing during fade is recorded once and cannot advance queue',
      () async {
    await f.startFade();
    f.first.emitState(const AudioEngineState(
        isPlaying: true,
        processingState: AudioEngineProcessingState.completed));
    await flush();
    await flush();
    expect(f.player.currentTrack, f.b);
    expect(await f.completions(f.a), 1);
    expect(await f.starts(f.b), 1);
  });

  test('stop cancels fade, prepared successor and both audio outputs',
      () async {
    await f.startFade();
    await f.player.prepareNextTrack(f.c);
    await f.player.stop();
    f.clock.advance(const Duration(seconds: 10));
    await tick();
    expect(f.player.currentTrack, isNull);
    expect(f.first.playing, isFalse);
    expect(f.second.playing, isFalse);
    expect(await f.starts(f.c), 0);
  });

  test('unknown native duration never starts a fade from metadata alone',
      () async {
    await f.player.playTrack(f.a);
    await f.player.prepareNextTrack(f.b);
    f.first.loadedDuration = null;
    final requests = <Track>[];
    final sub = f.player.automaticTransitionStream.listen(requests.add);
    addTearDown(sub.cancel);
    f.first.emitPosition(const Duration(seconds: 59));
    await flush();
    expect(requests, isEmpty);
  });

  test('crossfade setting persists and clamps excessive durations', () async {
    await f.player.setCrossfadeDuration(const Duration(seconds: 7));
    expect(
        await f.repositories.settings
            .readString('player.crossfadeMilliseconds'),
        '7000');
    await f.player.restoreSettings();
    expect(f.player.crossfadeDuration, const Duration(seconds: 7));
    await f.player.setCrossfadeDuration(const Duration(seconds: 99));
    expect(f.player.crossfadeDuration, const Duration(seconds: 10));
  });

  test(
      'removing queued item replaces its prepared decoder with the context successor',
      () async {
    await f.library();
    await f.queue.addToQueue(f.c);
    await until(() =>
        f.second.setFilePaths.isNotEmpty &&
        f.second.setFilePaths.last == f.c.filePath);
    f.queue.clearQueue();
    await until(() => f.second.setFilePaths.last == f.b.filePath);
    f.first.emitPosition(const Duration(seconds: 57));
    await until(() => f.player.currentTrack == f.b);
    expect(await f.starts(f.c), 0);
  });

  test('disliking the prepared Wave candidate selects a new candidate',
      () async {
    await f.queue.playSmartNext();
    await until(() => f.second.setFilePathCalls == 1);
    final prepared = f.tracks
        .singleWhere((track) => track.filePath == f.second.setFilePaths.single);
    await f.queue.toggleDislike(prepared);
    await until(() => f.second.setFilePathCalls >= 2);
    final replacement = f.second.setFilePaths.last;
    expect(replacement, isNot(prepared.filePath));
    f.first.emitPosition(const Duration(seconds: 57));
    await until(() => f.player.currentTrack!.filePath == replacement);
    expect(await f.starts(prepared), 0);
  });

  test(
      'shuffle lookahead does not start another cycle after repeat is disabled',
      () async {
    await f.playlist();
    f.queue.setPlaylistShuffleEnabled(true);
    await f.queue.next();
    await f.queue.next();
    f.queue.setRepeatMode(PlaybackRepeatMode.playlist);
    await flush();
    await flush();
    f.queue.setRepeatMode(PlaybackRepeatMode.none);
    await flush();
    await flush();
    // At the end of the exhausted shuffle bag the established behaviour is Wave.
    await f.queue.next();
    expect(f.queue.state.activeSource, PlaybackSource.wave);
    expect(f.queue.state.isPlaylistShuffleEnabled, isFalse);
  });

  test(
      'outgoing source failure ends the fade without skipping the healthy incoming track',
      () async {
    await f.startFade();
    f.first.emitError(StateError('outgoing decoder failed'));
    await flush();
    expect(f.player.currentTrack, f.b);
    expect(f.player.isPlaying, isTrue);
    expect(f.first.playing, isFalse);
    expect(f.second.setVolumes.last, 1);
    expect(await f.completions(f.a), 0);
  });

  for (final action in ['stop', 'dispose', 'load failure', 'cancelled load']) {
    test('cache decoder lease is released after $action', () async {
      final cache = _LeasedCache();
      final engine = TestAudioEngine();
      final deck = JustAudioPlayerService(
          playbackEvents: f.repositories.playbackEvents,
          audioEngine: engine,
          playbackCache: cache,
          isWindows: true,
          fileExists: (_) => true);
      addTearDown(deck.dispose);
      final track = f.a.copyWith(filePath: r'C:\Музыка\a.mp3');
      if (action == 'cancelled load') {
        cache.pending = Completer<PlaybackCacheEntry>();
        final loading = deck.prepareTrack(track);
        await flush();
        final stopping = deck.stop();
        cache.pending!.complete(_LeasedCache.entry);
        await Future.wait([loading, stopping]);
        expect(engine.setFilePathCalls, 0);
      } else {
        if (action == 'load failure') {
          engine.setFilePathError = StateError('broken decoder');
        }
        await deck.prepareTrack(track);
        if (action == 'stop') await deck.stop();
        if (action == 'dispose') await deck.dispose();
      }
      expect(cache.releases, [_LeasedCache.entry.filePath]);
      expect(engine.playCalls, 0);
    });
  }
}

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 5));
Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 65));
Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 200; i++) {
    if (predicate()) {
      await flush();
      return;
    }
    await flush();
  }
  fail('Timed out waiting for the transition');
}

class _Clock extends Stopwatch {
  Duration _elapsed = Duration.zero;
  bool _running = false;
  @override
  bool get isRunning => _running;
  @override
  int get elapsedMicroseconds => _elapsed.inMicroseconds;
  @override
  void start() {
    _running = true;
  }

  @override
  void stop() {
    _running = false;
  }

  @override
  void reset() {
    _elapsed = Duration.zero;
  }

  void advance(Duration duration) {
    if (_running) _elapsed += duration;
  }
}

class _Fixture {
  _Fixture(this.database, this.repositories, this.tracks) {
    player = TransitionPlayerService(
        first: JustAudioPlayerService(
            playbackEvents: repositories.playbackEvents,
            settings: repositories.settings,
            audioEngine: first,
            fileExists: (_) => true,
            isWindows: false),
        second: JustAudioPlayerService(
            playbackEvents: repositories.playbackEvents,
            audioEngine: second,
            fileExists: (_) => true,
            isWindows: false),
        settings: repositories.settings,
        fadeClock: clock);
  }
  final AppDatabase database;
  final DriftRepositories repositories;
  final List<Track> tracks;
  final first = TestAudioEngine()..loadedDuration = const Duration(seconds: 60);
  final second = TestAudioEngine()
    ..loadedDuration = const Duration(seconds: 60);
  final clock = _Clock();
  late final TransitionPlayerService player;
  PlaybackQueueService? _queue;
  PlaybackQueueService get queue => _queue ??= PlaybackQueueService(
      playerService: player,
      tracks: repositories.tracks,
      trackUserState: repositories.trackUserState,
      playbackEvents: repositories.playbackEvents,
      recommendationService: RecommendationService(
          tracks: repositories.tracks,
          trackUserState: repositories.trackUserState,
          playbackEvents: repositories.playbackEvents),
      randomDouble: () => 0);
  Track get a => tracks[0];
  Track get b => tracks[1];
  Track get c => tracks[2];

  static Future<_Fixture> create() async {
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
    return _Fixture(db, repositories, tracks);
  }

  Future<void> library() =>
      queue.playLibraryTrack(track: a, visibleTracks: tracks);
  Future<void> playlist() => queue.playPlaylist(
          playlistId: 1,
          playlistName: 'Test',
          startTrackId: a.id!,
          entries: [
            for (var i = 0; i < tracks.length; i++)
              PlaylistEntry(
                  playlistId: 1,
                  trackId: tracks[i].id!,
                  position: i,
                  addedAt: DateTime(2026),
                  track: tracks[i]),
          ]);
  Future<void> startFade() async {
    await player.playTrack(a);
    await player.prepareNextTrack(b);
    first.emitPosition(const Duration(seconds: 57));
    await flush();
    await player.playAutomatically(b);
    await flush();
  }

  Future<int> starts(Track track) => count(track, PlaybackEventType.started);
  Future<int> completions(Track track) =>
      count(track, PlaybackEventType.completed);
  Future<int> count(Track track, PlaybackEventType type) async =>
      (await repositories.playbackEvents.recentEvents(limit: 100))
          .where((event) => event.trackId == track.id && event.type == type)
          .length;
  Future<void> dispose() async {
    await _queue?.dispose();
    await player.dispose();
    await database.close();
  }
}

class _LeasedCache implements ProtectedPlaybackCache {
  static const entry = PlaybackCacheEntry(
      filePath: r'C:\cache\audio.mp3',
      reusedExistingFile: true,
      cacheSizeBeforeCleanupBytes: 1,
      cacheSizeAfterCleanupBytes: 1,
      cleanupDeletedFileCount: 0,
      cleanupDeletedPaths: [],
      sourceSizeBytes: 1);
  Completer<PlaybackCacheEntry>? pending;
  final releases = <String>[];
  @override
  Future<PlaybackCacheEntry> acquire(Track track, String sourcePath) async =>
      pending == null ? entry : await pending!.future;
  @override
  void release(String cachedPath) {
    releases.add(cachedPath);
  }

  @override
  Future<PlaybackCacheEntry> resolve(Track track, String sourcePath) =>
      acquire(track, sourcePath);
}
