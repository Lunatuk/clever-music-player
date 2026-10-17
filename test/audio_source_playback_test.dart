import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/player/transition_player_service.dart';
import 'package:clever_music_player/src/player/windows_playback_cache.dart';
import 'package:clever_music_player/src/queue/playback_queue_service.dart';
import 'package:clever_music_player/src/recommendation/recommendation_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_audio_engine.dart';

void main() {
  late _Fixture f;
  setUp(() async {
    f = await _Fixture.create();
  });
  tearDown(() async {
    await f.close();
  });

  test('content URI plays without filesystem probes or Windows cache',
      () async {
    await f.player.playTrack(f.a);
    expect(f.player.isPlaying, isTrue);
    expect(f.first.sources.single, f.a.source);
    expect(f.first.sourcePreloads, [true]);
    expect(f.first.setFilePathCalls, 0);
    expect(f.probes, isEmpty);
    expect(f.cache.calls, 0);
    await f.player.dispose();
    expect(await f.starts(f.a), 1);
  });

  test('URI preload is silent and promotion records only the audible session',
      () async {
    await f.player.playTrack(f.a);
    await f.player.prepareNextTrack(f.b);
    expect(f.second.sources.single, f.b.source);
    expect(f.second.playCalls, 0);
    expect(await f.starts(f.b), 0);
    await f.player.playAutomatically(f.b);
    expect(f.player.currentTrack, f.b);
    expect(f.second.playCalls, 1);
    await f.player.dispose();
    expect(await f.starts(f.a), 1);
    expect(await f.starts(f.b), 1);
    expect(f.probes, isEmpty);
    expect(f.cache.calls, 0);
  });

  test('URI crossfade finishes the outgoing session exactly once', () async {
    await f.player.playTrack(f.a);
    await f.player.prepareNextTrack(f.b);
    final requested = f.player.automaticTransitionStream.first;
    f.first.emitPosition(const Duration(seconds: 57));
    expect(await requested.timeout(const Duration(seconds: 2)), f.b);
    await f.player.playAutomatically(f.b);
    // Play completes at the transport boundary; native playback acknowledges
    // asynchronously after the output settings have been confirmed.
    await _until(() => f.first.playing && f.second.playing);
    expect(f.first.playing, isTrue);
    expect(f.second.playing, isTrue);
    f.clock.advance(const Duration(seconds: 4));
    await _until(() => !f.first.playing);
    await f.player.dispose();
    final events = await f.repositories.playbackEvents.recentEvents();
    expect(
        events.where((event) =>
            event.trackId == f.a.id &&
            event.type == PlaybackEventType.completed),
        hasLength(1));
    expect(await f.starts(f.a), 1);
    expect(await f.starts(f.b), 1);
    expect(f.cache.calls, 0);
  });

  test('late URI load failure cannot replace a newer selected track', () async {
    final firstLoad = Completer<Duration?>();
    final entered = Completer<void>();
    f.first.setSourceHandler = (_, call) {
      if (call == 1) {
        entered.complete();
        return firstLoad.future;
      }
      return const Duration(seconds: 60);
    };
    final old = f.player.playTrack(f.a);
    await entered.future;
    final latest = f.player.playTrack(f.c);
    try {
      firstLoad.completeError(StateError('late provider failure'));
      await Future.wait([old, latest]);
      expect(f.player.currentTrack, f.c);
      expect(f.player.isPlaying, isTrue);
      await f.player.dispose();
      expect(await f.starts(f.a), 0);
      expect(await f.starts(f.c), 1);
      expect(f.cache.calls, 0);
    } finally {
      if (!firstLoad.isCompleted) firstLoad.completeError(StateError('cancel'));
    }
  });

  test('manual URI selection does not wait for a cancelled standby load',
      () async {
    await f.player.playTrack(f.a);
    final standbyLoad = Completer<Duration?>();
    final entered = Completer<void>();
    f.second.setSourceHandler = (_, __) {
      entered.complete();
      return standbyLoad.future;
    };
    final preparing = f.player.prepareNextTrack(f.b);
    await entered.future;
    try {
      await f.player.playTrack(f.c).timeout(const Duration(seconds: 2));
      expect(f.player.currentTrack, f.c);
      expect(f.player.isPlaying, isTrue);
      standbyLoad.complete(const Duration(seconds: 60));
      await preparing;
      await f.player.dispose();
      expect(await f.starts(f.b), 0);
      expect(await f.starts(f.c), 1);
    } finally {
      if (!standbyLoad.isCompleted) standbyLoad.complete(null);
    }
  });

  test(
      'revoked provider access reports a source failure without a file fallback',
      () async {
    f.first.setSourceHandler =
        (_, __) => throw StateError('PRIVATE provider denied');
    await f.player.playTrack(f.a);
    expect(f.player.state.failureKind, PlayerFailureKind.source);
    expect(f.player.state.status, PlayerPlaybackStatus.error);
    expect(f.player.state.errorMessage, isNot(contains('PRIVATE')));
    expect(f.probes, isEmpty);
    expect(f.cache.calls, 0);
    expect(await f.starts(f.a), 0);
  });

  test(
      'invalid persisted source reports a controlled error before any source IO',
      () async {
    for (final value in [
      'content:///PRIVATE',
      'content://PRIVATE',
      'content://provider/PRIVATE%zz',
      'https://PRIVATE/song.mp3',
      '',
      'PRIVATE\u0000'
    ]) {
      await f.player.playTrack(f.a.copyWith(filePath: value));
      expect(f.player.state.failureKind, PlayerFailureKind.source);
      expect(f.player.state.status, PlayerPlaybackStatus.error);
      expect(f.player.state.errorMessage, isNot(contains('PRIVATE')));
    }
    expect(f.probes, isEmpty);
    expect(f.cache.calls, 0);
    expect(f.first.sources, isEmpty);
    expect(await f.starts(f.a), 0);
  });

  test('URI load is drained during disposal without late play or history',
      () async {
    final load = Completer<Duration?>();
    final entered = Completer<void>();
    f.second.setSourceHandler = (_, __) {
      entered.complete();
      return load.future;
    };
    final preparing = f.player.prepareNextTrack(f.b);
    await entered.future;
    final closing = f.player.dispose();
    expect(identical(closing, f.player.dispose()), isTrue);
    try {
      load.completeError(StateError('cancelled native content load'));
      await Future.wait([preparing, closing]);
      expect(f.second.playCalls, 0);
      expect(await f.starts(f.b), 0);
      expect(f.probes, isEmpty);
    } finally {
      if (!load.isCompleted) load.complete(null);
    }
  });

  test('automatic queue recovery bypasses an inaccessible content URI',
      () async {
    FutureOr<Duration?> load(AudioSourceReference source, int _) {
      if (source == f.b.source) throw StateError('provider access lost');
      return const Duration(seconds: 60);
    }

    f.first.setSourceHandler = load;
    f.second.setSourceHandler = load;
    await f.queue.playLibraryTrack(track: f.a, visibleTracks: f.tracks);
    await _until(() => f.second.sources.isNotEmpty);
    f.first.emitState(const AudioEngineState(
        isPlaying: false,
        processingState: AudioEngineProcessingState.completed));
    await _until(() => f.player.currentTrack == f.c && f.player.isPlaying);
    await Future.wait([f.queue.dispose(), f.player.dispose()]);
    expect(await f.starts(f.b), 0);
    expect(await f.starts(f.c), 1);
    expect(f.probes, isEmpty);
    expect(f.cache.calls, 0);
  });

  test('Windows cache rejects URI input before creating its directory',
      () async {
    var directoryRequested = false;
    final cache = WindowsPlaybackCache(appSupportDirectoryProvider: () async {
      directoryRequested = true;
      throw StateError('Must not create a filesystem cache for a provider URI');
    });
    await expectLater(cache.resolve(f.a, f.a.filePath), throwsFormatException);
    await expectLater(cache.acquire(f.a, f.a.filePath), throwsFormatException);
    expect(directoryRequested, isFalse);
  });

  test('content URI and provider error text stay out of a release report',
      () async {
    await f.close();
    final directory =
        await Directory.systemTemp.createTemp('cmp-content-diagnostics-');
    final diagnostics =
        LocalDiagnosticsService(directoryProvider: () async => directory);
    f = await _Fixture.create(diagnostics: diagnostics);
    try {
      f.first.setSourceHandler =
          (source, _) => throw StateError('PRIVATE ${source.storageValue}');
      await f.player.playTrack(f.a);
      final report = await diagnostics.exportReport();
      final text = await report.readAsString();
      expect(text, contains('audioLoadFailed'));
      expect(text, isNot(contains('PRIVATE')));
      expect(text, isNot(contains('content://')));
      expect(text, isNot(contains('provider')));
    } finally {
      await f.close();
      await diagnostics.flush();
      await directory.delete(recursive: true);
    }
  });
}

Future<void> _until(bool Function() predicate) async {
  final timer = Stopwatch()..start();
  while (!predicate()) {
    if (timer.elapsed > const Duration(seconds: 2)) {
      fail('Timed out waiting for URI playback');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

final class _Fixture {
  _Fixture(this.database, this.repositories, this.tracks, this.diagnostics) {
    JustAudioPlayerService deck(TestAudioEngine engine) =>
        JustAudioPlayerService(
            playbackEvents: repositories.playbackEvents,
            audioEngine: engine,
            diagnostics: diagnostics,
            isWindows: true,
            playbackCache: cache,
            fileExists: (path) {
              probes.add(path);
              throw StateError('URI converted to File');
            });
    player = TransitionPlayerService(
        first: deck(first), second: deck(second), fadeClock: clock);
  }
  final AppDatabase database;
  final DriftRepositories repositories;
  final List<Track> tracks;
  final DiagnosticsService diagnostics;
  final first = TestAudioEngine()..loadedDuration = const Duration(seconds: 60);
  final second = TestAudioEngine()
    ..loadedDuration = const Duration(seconds: 60);
  final cache = _NoFileCache();
  final probes = <String>[];
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
      diagnostics: diagnostics,
      randomDouble: () => 0);
  Future<void>? _closing;
  Track get a => tracks[0];
  Track get b => tracks[1];
  Track get c => tracks[2];
  static Future<_Fixture> create(
      {DiagnosticsService diagnostics = const NoopDiagnosticsService()}) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repositories = DriftRepositories(database);
    final tracks = <Track>[];
    for (var i = 0; i < 3; i++) {
      final id = await repositories.tracks.upsertTrack(Track.fromSource(
          source: ContentUriAudioSource(
              'content://provider/document/PRIVATE%2FSong$i.mp3'),
          title: 'Track $i',
          duration: const Duration(seconds: 60),
          addedAt: DateTime(2026),
          updatedAt: DateTime(2026)));
      tracks.add((await repositories.tracks.findById(id))!);
    }
    return _Fixture(database, repositories, tracks, diagnostics);
  }

  Future<int> starts(Track track) async =>
      (await repositories.playbackEvents.recentForTrack(track.id!))
          .where((event) => event.type == PlaybackEventType.started)
          .length;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    await Future.wait(
        [if (_queue != null) _queue!.dispose(), player.dispose()]);
    await database.close();
  }
}

final class _NoFileCache implements PlaybackCache {
  int calls = 0;
  @override
  Future<PlaybackCacheEntry> resolve(Track track, String sourcePath) async {
    calls++;
    throw StateError('Provider URI entered the file cache');
  }
}

final class _Clock extends Stopwatch {
  Duration elapsedValue = Duration.zero;
  bool running = false;
  @override
  bool get isRunning => running;
  @override
  int get elapsedMicroseconds => elapsedValue.inMicroseconds;
  @override
  void start() {
    running = true;
  }

  @override
  void stop() {
    running = false;
  }

  @override
  void reset() {
    elapsedValue = Duration.zero;
  }

  void advance(Duration duration) {
    if (running) elapsedValue += duration;
  }
}
