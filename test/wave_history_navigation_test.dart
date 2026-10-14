import 'dart:async';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/track_repository.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:clever_music_player/src/player/player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/player/transition_player_service.dart';
import 'package:clever_music_player/src/queue/playback_queue_service.dart';
import 'package:clever_music_player/src/queue/queue_state.dart';
import 'package:clever_music_player/src/recommendation/recommendation_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_audio_engine.dart';

void main() {
  for (final uri in [false, true]) {
    group(uri ? 'content URI history' : 'file history', () {
      late _Fixture f;
      setUp(() async => f = await _Fixture.create(uri: uri));
      tearDown(() => f.close());

      test('end of library still enters Wave; Back returns its last track',
          () async {
        await f.libraryLast();
        final last = f.player.currentTrack!;
        expect(f.queue.state.isWaveEnabled, isFalse);
        await f.queue.next();
        final firstWave = f.player.currentTrack!;
        expect(firstWave.id, isNot(last.id));
        expect(f.queue.state.activeSource, PlaybackSource.wave);
        expect(f.queue.state.hasTrackListContext, isFalse);
        expect(f.queue.state.isWaveEnabled, isTrue);
        await f.queue.previous();
        expect(f.player.currentTrack!.id, last.id);
        await f.queue.next();
        expect(f.player.currentTrack!.id, firstWave.id);
      });

      test(
          'five backward steps and forward replay share the same bounded timeline',
          () async {
        await f.libraryLast();
        final visits = <int>[f.player.currentTrack!.id!];
        for (var i = 0; i < 9; i++) {
          await f.queue.next();
          visits.add(f.player.currentTrack!.id!);
        }
        final retained = visits.sublist(visits.length - 6);
        for (var i = 4; i >= 0; i--) {
          await f.queue.previous();
          expect(f.player.currentTrack!.id, retained[i]);
        }
        final loads = f.playCalls;
        await f.queue.previous();
        expect(f.playCalls, loads);
        expect(f.player.currentTrack!.id, retained.first);
        expect(f.first.seekPositions.last, Duration.zero);
        for (final id in retained.skip(1)) {
          await f.queue.next();
          expect(f.player.currentTrack!.id, id);
          expect(f.queue.state.lastRecommendationResult, isNull);
        }
        await f.queue.next();
        expect(f.queue.state.lastRecommendationResult, isNotNull);
      });

      test('Back after five seconds restarts then a second press goes backward',
          () async {
        await f.libraryLast();
        final previous = f.player.currentTrack!;
        await f.queue.next();
        final current = f.player.currentTrack!;
        f.first.emitPosition(const Duration(seconds: 6));
        await _flush();
        await f.queue.previous();
        expect(f.player.currentTrack!.id, current.id);
        expect(f.player.position, Duration.zero);
        await f.queue.previous();
        expect(f.player.currentTrack!.id, previous.id);
      });

      test('fresh library/playlist selections leave Wave history behind',
          () async {
        await f.libraryLast();
        await f.queue.next();
        await f.queue.next();
        await f.queue
            .playLibraryTrack(track: f.tracks[1], visibleTracks: f.tracks);
        await f.queue.previous();
        expect(f.player.currentTrack!.id, f.tracks.first.id);
        expect(f.queue.state.activeSource, PlaybackSource.library);
        await f.playlistLast();
        await f.queue.next();
        await f.queue.previous();
        expect(f.player.currentTrack!.id, f.tracks.last.id);
        final plays = f.playCalls;
        await f.queue.previous();
        expect(f.playCalls, plays);
      });

      test('manual queued item keeps priority over forward history', () async {
        await f.libraryLast();
        await f.queue.next();
        await f.queue.previous();
        final queued = f.tracks[4];
        await f.queue.addToQueue(queued);
        await f.queue.next();
        expect(f.player.currentTrack!.id, queued.id);
        expect(f.queue.state.activeSource, PlaybackSource.manualQueue);
        expect(f.queue.state.manualQueue, isEmpty);
        await f.queue.next();
        await f.queue.previous();
        expect(f.player.currentTrack!.id, queued.id);
      });

      test(
          'removed and missing history entries are skipped without changing IDs',
          () async {
        await f.libraryLast();
        final a = f.player.currentTrack!;
        await f.queue.next();
        final b = f.player.currentTrack!;
        await f.queue.next();
        final c = f.player.currentTrack!;
        await f.queue.next();
        final d = f.player.currentTrack!;
        await f.repositories.tracks.deleteTrack(c.id!);
        await f.repositories.tracks.upsertTrack(b.copyWith(isMissing: true));
        await f.queue.previous();
        expect(f.player.currentTrack!.id, a.id);
        await f.queue.next();
        expect(f.player.currentTrack!.id, d.id);
      });

      test('history reads fresh metadata and feedback; replay starts once',
          () async {
        await f.libraryLast();
        final original = f.player.currentTrack!;
        await f.queue.next();
        await f.repositories.tracks
            .upsertTrack(original.copyWith(title: 'Changed title'));
        await f.queue.toggleLike(original);
        final startsBefore = await f.starts(original);
        await f.queue.previous();
        await _until(
            () => f.queue.state.currentTrackUserState?.isFavorite == true);
        expect(f.player.currentTrack!.title, 'Changed title');
        expect(f.player.currentTrack!.id, original.id);
        expect(await f.starts(original), startsBefore + 1);
      });

      test('failed fresh recommendation is not a played history visit',
          () async {
        await f.libraryLast();
        final last = f.player.currentTrack!;
        f.failAllLoads = true;
        await f.queue.next();
        expect(f.player.state.status, PlayerPlaybackStatus.error);
        f.failAllLoads = false;
        await f.queue.previous();
        expect(f.player.currentTrack!.id, last.id);
        expect(f.player.isPlaying, isTrue);
      });

      test('disabling Wave still stops automatic continuation after Back',
          () async {
        await f.libraryLast();
        await f.queue.next();
        await f.queue.previous();
        f.queue.disableWave();
        final calls = f.playCalls;
        f.complete();
        await _flush();
        expect(f.playCalls, calls);
        expect(f.queue.state.isWaveEnabled, isFalse);
      });

      test('single-track manual selection resets the former Wave session',
          () async {
        await f.libraryLast();
        await f.queue.next();
        final manual = f.tracks[3];
        await f.queue.playTrackManually(manual);
        final calls = f.playCalls;
        await f.queue.previous();
        expect(f.playCalls, calls);
        await f.queue.playSmartNext();
        await f.queue.previous();
        expect(f.player.currentTrack!.id, manual.id);
        final atSeed = f.playCalls;
        await f.queue.previous();
        expect(f.playCalls, atSeed);
      });

      test('manual selection supersedes a blocked history lookup', () async {
        await f.libraryLast();
        final seed = f.player.currentTrack!;
        await f.queue.next();
        final entered = Completer<void>();
        final lookup = Completer<Track?>();
        f.lookup.onFind = (id) {
          if (id != seed.id) return f.repositories.tracks.findById(id);
          entered.complete();
          return lookup.future;
        };
        final back = f.queue.previous();
        await entered.future;
        await f.queue.playTrackManually(f.tracks[3]);
        lookup.complete(seed);
        await back;
        expect(f.player.currentTrack!.id, f.tracks[3].id);
        expect(f.queue.state.activeSource, PlaybackSource.singleTrack);
      });

      test('shutdown drains a history lookup without starting another decoder',
          () async {
        await f.libraryLast();
        final seed = f.player.currentTrack!;
        await f.queue.next();
        final entered = Completer<void>();
        final lookup = Completer<Track?>();
        f.lookup.onFind = (id) {
          entered.complete();
          return lookup.future;
        };
        final back = f.queue.previous();
        await entered.future;
        final calls = f.playCalls;
        var closed = false;
        final closing = f.queue.dispose().then((_) => closed = true);
        await _flush();
        expect(closed, isFalse);
        lookup.complete(seed);
        await back;
        await closing;
        expect(f.playCalls, calls);
      });
    });
  }

  group('prepared Wave history', () {
    late _Fixture f;
    setUp(() async => f = await _Fixture.create(uri: true, dual: true));
    tearDown(() => f.close());

    test(
        'Back replaces prepared recommendation with the historical forward visit',
        () async {
      await f.libraryLast();
      await _flush();
      await f.queue.next();
      final firstWave = f.player.currentTrack!;
      await _flush();
      await f.queue.next();
      final secondWave = f.player.currentTrack!;
      await _flush();
      await f.queue.previous();
      expect(f.player.currentTrack!.id, firstWave.id);
      await _until(() =>
          f.standby.sources.isNotEmpty &&
          f.standby.sources.last == secondWave.source);
      final loads = f.loads;
      final startsBefore = await f.starts(secondWave);
      f.active.emitPosition(const Duration(seconds: 57));
      await _until(() =>
          f.player.currentTrack!.id == secondWave.id &&
          !f.queue.state.isChoosingNext);
      expect(await f.starts(secondWave), startsBefore + 1);
      expect(f.loads,
          lessThanOrEqualTo(loads + 1)); // next recommendation may preload
      expect(f.queue.state.lastRecommendationResult, isNull);
    });

    test('deletion after preloading a forward visit never resurrects its row',
        () async {
      await f.libraryLast();
      await f.queue.next();
      final firstWave = f.player.currentTrack!;
      await f.queue.next();
      final secondWave = f.player.currentTrack!;
      await f.queue.previous();
      await _until(() =>
          f.standby.sources.isNotEmpty &&
          f.standby.sources.last == secondWave.source);
      await f.repositories.tracks.deleteTrack(secondWave.id!);
      await f.queue.next();
      expect(f.player.currentTrack!.id, isNot(secondWave.id));
      expect(await f.repositories.tracks.findById(secondWave.id!), isNull);
      expect(f.player.currentTrack!.id, isNot(firstWave.id));
    });
  });

  test(
      'repeated visits to one track still invalidate preparation by history position',
      () async {
    final f = await _Fixture.create(uri: true, dual: true, count: 1);
    addTearDown(f.close);
    await f.libraryLast();
    for (var i = 0; i < 7; i++) {
      await f.queue.next();
      await _flush();
    }
    for (var i = 0; i < 5; i++) {
      await f.queue.previous();
      await _flush();
    }
    final calls = f.playCalls;
    await f.queue.previous();
    expect(f.playCalls, calls);
    for (var i = 0; i < 5; i++) {
      await f.queue.next();
      await _flush();
      expect(f.queue.state.lastRecommendationResult, isNull);
    }
    await f.queue.next();
    expect(f.queue.state.lastRecommendationResult, isNotNull);
  });
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 20));
Future<void> _until(bool Function() predicate) async {
  final timer = Stopwatch()..start();
  while (!predicate()) {
    if (timer.elapsed > const Duration(seconds: 3)) {
      fail('Timed out waiting for history playback');
    }
    await _flush();
  }
}

final class _Fixture {
  _Fixture(this.database, this.repositories, this.tracks,
      {required bool dual}) {
    JustAudioPlayerService deck(TestAudioEngine engine) =>
        JustAudioPlayerService(
            playbackEvents: repositories.playbackEvents,
            audioEngine: engine,
            isWindows: false,
            fileExists: (_) => true);
    player = dual
        ? TransitionPlayerService(first: deck(first), second: deck(second))
        : deck(first);
    first.setSourceHandler = second.setSourceHandler = (source, call) {
      if (failAllLoads) throw StateError('Broken source');
      return const Duration(seconds: 60);
    };
    first.setFilePathHandler = second.setFilePathHandler = (path, call) {
      if (failAllLoads) throw StateError('Broken source');
      return const Duration(seconds: 60);
    };
    lookup = _ControllableTracks(repositories.tracks);
    queue = PlaybackQueueService(
        playerService: player,
        tracks: lookup,
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
  final first = TestAudioEngine()..loadedDuration = const Duration(seconds: 60);
  final second = TestAudioEngine()
    ..loadedDuration = const Duration(seconds: 60);
  late final PlayerService player;
  late final PlaybackQueueService queue;
  late final _ControllableTracks lookup;
  bool failAllLoads = false;
  int get playCalls => first.playCalls + second.playCalls;
  int get loads => first.sources.length + second.sources.length;
  TestAudioEngine get active => first.playing ? first : second;
  TestAudioEngine get standby => first.playing ? second : first;
  static Future<_Fixture> create(
      {bool uri = false, bool dual = false, int count = 9}) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repositories = DriftRepositories(database);
    final tracks = <Track>[];
    for (var i = 0; i < count; i++) {
      final id = await repositories.tracks.upsertTrack(Track.fromSource(
          source: uri
              ? ContentUriAudioSource('content://music.documents/song$i')
              : FileAudioSource('C:\\cmp-test\\song$i.mp3'),
          title: 'Track $i',
          artist: 'Artist $i',
          album: 'Album $i',
          duration: const Duration(seconds: 60),
          addedAt: DateTime(2026),
          updatedAt: DateTime(2026)));
      tracks.add((await repositories.tracks.findById(id))!);
    }
    return _Fixture(database, repositories, tracks, dual: dual);
  }

  Future<void> libraryLast() =>
      queue.playLibraryTrack(track: tracks.last, visibleTracks: tracks);
  Future<void> playlistLast() => queue.playPlaylist(
          playlistId: 1,
          playlistName: 'Test',
          startTrackId: tracks.last.id!,
          entries: [
            for (var i = 0; i < tracks.length; i++)
              PlaylistEntry(
                  playlistId: 1,
                  trackId: tracks[i].id!,
                  position: i,
                  addedAt: DateTime(2026),
                  track: tracks[i])
          ]);
  void complete() => active.emitState(const AudioEngineState(
      isPlaying: false, processingState: AudioEngineProcessingState.completed));
  Future<int> starts(Track track) async =>
      (await repositories.playbackEvents.recentForTrack(track.id!))
          .where((event) => event.type == PlaybackEventType.started)
          .length;
  Future<void> close() async {
    await Future.wait([queue.dispose(), player.dispose()]);
    await database.close();
  }
}

final class _ControllableTracks implements TrackRepository {
  _ControllableTracks(this.delegate);
  final TrackRepository delegate;
  Future<Track?> Function(int)? onFind;
  @override
  Future<Track?> findById(int id) => onFind?.call(id) ?? delegate.findById(id);
  @override
  Future<List<Track>> listTracks(
          {int limit = 100,
          int offset = 0,
          bool includeDisabledFolders = false}) =>
      delegate.listTracks(
          limit: limit,
          offset: offset,
          includeDisabledFolders: includeDisabledFolders);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
