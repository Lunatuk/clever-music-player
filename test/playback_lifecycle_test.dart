import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/app/app_dependencies.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/custom_artwork_service.dart';
import 'package:clever_music_player/src/library/directory_picker_service.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:clever_music_player/src/player/transition_player_service.dart';
import 'package:clever_music_player/src/player/windows_playback_cache.dart';
import 'package:clever_music_player/src/queue/playback_queue_service.dart';
import 'package:clever_music_player/src/recommendation/recommendation_service.dart';
import 'package:clever_music_player/src/smtc/smtc_service.dart';
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

  for (final type in [
    PlaybackEventType.started,
    PlaybackEventType.paused,
    PlaybackEventType.completed
  ]) {
    test('player disposal waits for accepted ${type.name} history', () async {
      final gate = f.gate();
      final entered = Completer<void>();
      f.events.beforeRecord = (event) async {
        if (event.type == type) {
          entered.complete();
          await gate.future;
        }
      };
      await f.player.playTrack(f.a);
      if (type == PlaybackEventType.paused) await f.player.pause();
      if (type == PlaybackEventType.completed) {
        f.first.emitState(const AudioEngineState(
            isPlaying: false,
            processingState: AudioEngineProcessingState.completed));
      }
      await entered.future;
      var closed = false;
      final closing = f.player.dispose().then((_) => closed = true);
      await _pump();
      expect(closed, isFalse);
      expect(f.first.disposeCalls, 1);
      gate.complete();
      await closing;
      final events = await f.repositories.playbackEvents.recentEvents();
      expect(events.where((event) => event.type == type), hasLength(1));
      final state = await f.repositories.trackUserState.findByTrackId(f.a.id!);
      expect(state!.playCount, 1);
      if (type == PlaybackEventType.completed) expect(state.completeCount, 1);
    });
  }

  test('volume disposal waits for both keys of an accepted settings save',
      () async {
    final gate = f.gate();
    final entered = Completer<void>();
    f.settings.beforeWrite = (key, value) async {
      if (key == 'player.volume') {
        entered.complete();
        await gate.future;
      }
    };
    final saving = f.player.setVolume(.37);
    await entered.future;
    var closed = false;
    final closing = f.player.dispose().then((_) => closed = true);
    await _pump();
    expect(closed, isFalse);
    gate.complete();
    await Future.wait([saving, closing]);
    expect(await f.repositories.settings.readString('player.volume'), '0.37');
    expect(
        await f.repositories.settings
            .readString('player.previousVolumeBeforeMute'),
        '0.37');
    expect(f.settings.writes,
        ['player.volume', 'player.previousVolumeBeforeMute']);
  });

  test('crossfade settings write finishes before player disposal returns',
      () async {
    final gate = f.gate();
    final entered = Completer<void>();
    f.settings.beforeWrite = (key, _) async {
      if (key == 'player.crossfadeMilliseconds') {
        entered.complete();
        await gate.future;
      }
    };
    final saving = f.player.setCrossfadeDuration(const Duration(seconds: 7));
    await entered.future;
    var closed = false;
    final closing = f.player.dispose().then((_) => closed = true);
    await _pump();
    expect(closed, isFalse);
    gate.complete();
    await Future.wait([saving, closing]);
    expect(
        await f.repositories.settings
            .readString('player.crossfadeMilliseconds'),
        '7000');
  });

  test('settings restore stops issuing reads after shutdown begins', () async {
    final gate = f.gate();
    final entered = Completer<void>();
    f.settings.beforeRead = (_) async {
      entered.complete();
      await gate.future;
    };
    final restoring = f.player.restoreSettings();
    await entered.future;
    final closing = f.player.dispose();
    gate.complete();
    await Future.wait([restoring, closing]);
    expect(f.settings.reads, ['player.previousVolumeBeforeMute']);
    expect(f.first.setVolumeCalls, 0);
    expect(f.second.setVolumeCalls, 0);
  });

  test('queue waits for feedback commit but skips its late refresh', () async {
    await f.queue.playTrackManually(f.a);
    await _pump();
    final reads = f.states.singleReads;
    final gate = f.gate();
    final entered = Completer<void>();
    f.states.beforeToggle = () async {
      entered.complete();
      await gate.future;
    };
    final liking = f.queue.toggleLike(f.a);
    await entered.future;
    var closed = false;
    final closing = f.queue.dispose().then((_) => closed = true);
    await _pump();
    expect(closed, isFalse);
    gate.complete();
    await Future.wait([liking, closing]);
    expect(
        (await f.repositories.trackUserState.findByTrackId(f.a.id!))!
            .isFavorite,
        isTrue);
    expect(f.states.singleReads, reads);
    await f.queue.toggleDislike(f.a);
    expect(f.states.toggles, 1);
  });

  test('queue drains a late feedback read without publishing its state',
      () async {
    final gate = f.gate();
    final entered = Completer<void>();
    f.states.beforeSingleRead = () async {
      entered.complete();
      await gate.future;
    };
    await f.queue.playTrackManually(f.a);
    await entered.future;
    final beforeClose = f.queue.state;
    var closed = false;
    final closing = f.queue.dispose().then((_) => closed = true);
    await _pump();
    expect(closed, isFalse);
    gate.complete();
    await closing;
    expect(f.queue.state, same(beforeClose));
    expect(f.states.singleReads, 1);
  });

  for (final stage in ['tracks', 'states', 'history']) {
    test('closing Wave during $stage stops later reads and playback', () async {
      final gate = f.gate();
      final entered = Completer<void>();
      Future<void> wait() async {
        entered.complete();
        await gate.future;
      }

      switch (stage) {
        case 'tracks':
          f.tracks.beforeList = wait;
        case 'states':
          f.states.beforeBatchRead = wait;
        case 'history':
          f.events.beforeRecent = wait;
      }
      final choosing = f.queue.playSmartNext();
      await entered.future;
      var closed = false;
      final closing = f.queue.dispose().then((_) => closed = true);
      await _pump();
      expect(closed, isFalse);
      gate.complete();
      await Future.wait([choosing, closing]);
      expect(f.first.playCalls, 0);
      expect(f.second.setFilePathCalls, 0);
      expect(f.states.batchReads, stage == 'tracks' ? 0 : 1);
      expect(f.events.recentReads, stage == 'history' ? 1 : 0);
    });
  }

  for (final source in ['library', 'playlist']) {
    test('closing $source selection stops resolving the remaining entries',
        () async {
      final gate = f.gate();
      final entered = Completer<void>();
      f.tracks.beforeFind = () async {
        entered.complete();
        await gate.future;
      };
      final choosing = source == 'library'
          ? f.queue.playLibraryTrack(track: f.a, visibleTracks: f.items)
          : f.queue.playPlaylist(
              playlistId: 1,
              playlistName: 'Test',
              entries: f.entries,
              startTrackId: f.a.id!);
      await entered.future;
      final closing = f.queue.dispose();
      gate.complete();
      await Future.wait([choosing, closing]);
      expect(f.tracks.findCalls, 1);
      expect(f.first.setFilePathCalls, 0);
    });
  }

  test('background next-track planning drains before SQLite closes', () async {
    final gate = f.gate();
    final entered = Completer<void>();
    f.tracks.beforeList = () async {
      entered.complete();
      await gate.future;
    };
    f.queue.enableWave();
    await f.queue.playTrackManually(f.a);
    await entered.future;
    expect(f.first.playCalls, 1,
        reason: 'Planning must not delay foreground playback');
    var closed = false;
    final closing = f.dependencies.dispose().then((_) => closed = true);
    await _pump();
    expect(closed, isFalse);
    expect(f.database.closeCalls, 0);
    gate.complete();
    await closing;
    expect(f.second.setFilePathCalls, 0);
    expect(f.database.closeCalls, 1);
  });

  test('app starts native disposal before waiting for queue and media commands',
      () async {
    final load = Completer<Duration?>();
    final entered = Completer<void>();
    f.first.setFilePathHandler = (_, __) {
      entered.complete();
      return load.future;
    };
    f.first.disposeHandler = () async {
      if (!load.isCompleted) {
        load.completeError(StateError('native load interrupted'));
      }
    };
    final playing = f.queue.playTrackManually(f.a);
    f.media.onDispose = () => playing;
    await entered.future;
    await f.dependencies.dispose().timeout(const Duration(seconds: 2));
    await playing;
    expect(f.first.disposeCalls, 1);
    expect(f.second.disposeCalls, 1);
    expect(f.first.playCalls, 0);
    expect(f.database.closeCalls, 1);
  });

  test('native Play may stay pending after disposal without blocking cleanup',
      () async {
    final play = Completer<void>();
    f.first.playHandler = (_) => play.future;
    await f.player.playTrack(f.a);
    await f.player.dispose().timeout(const Duration(seconds: 2));
    expect(play.isCompleted, isFalse);
    expect(f.first.disposeCalls, 1);
    play.completeError(StateError('late native play failure'));
    await _pump();
    expect(await f.repositories.playbackEvents.recentEvents(), hasLength(1));
  });

  test(
      'one decoder disposal error still closes the other and every public stream',
      () async {
    final primary = StateError('native dispose');
    f.first.disposeError = primary;
    f.expectedCleanupError = primary;
    final stateDone = Completer<void>();
    final transitionDone = Completer<void>();
    final settingsDone = Completer<void>();
    f.player.stateStream.listen((_) {}, onDone: stateDone.complete);
    f.player.automaticTransitionStream
        .listen((_) {}, onDone: transitionDone.complete);
    f.player.crossfadeDurationStream
        .listen((_) {}, onDone: settingsDone.complete);
    final closing = f.player.dispose();
    expect(identical(closing, f.player.dispose()), isTrue);
    await expectLater(closing, throwsA(same(primary)));
    await Future.wait(
        [stateDone.future, transitionDone.future, settingsDone.future]);
    expect(f.first.disposeCalls, 1);
    expect(f.second.disposeCalls, 1);
    await expectLater(f.dependencies.dispose(), throwsA(same(primary)));
    expect(f.database.closeCalls, 1);
  });

  test('pending cache acquisition is drained and its late lease released',
      () async {
    await f.close();
    final cache = _Cache();
    f = await _Fixture.create(cache: cache);
    final playing = f.queue.playTrackManually(f.a);
    await cache.entered.future;
    var closed = false;
    final closing = f.dependencies.dispose().then((_) => closed = true);
    try {
      await _pump();
      expect(closed, isFalse);
      expect(f.first.disposeCalls, 1);
      expect(f.database.closeCalls, 0);
      cache.result.complete(_Cache.entry);
      await Future.wait([playing, closing]);
      expect(cache.released, [_Cache.entry.filePath]);
      expect(f.first.setFilePathCalls, 0);
      expect(f.database.closeCalls, 1);
    } finally {
      if (!cache.result.isCompleted) cache.result.complete(_Cache.entry);
      await closing;
    }
  });

  test('closed player and queue reject new database and audio operations',
      () async {
    await Future.wait([f.queue.dispose(), f.player.dispose()]);
    await Future.wait([
      f.player.playTrack(f.a),
      f.player.prepareNextTrack(f.b),
      f.player.restoreSettings(),
      f.player.setVolume(.4),
      f.player.setCrossfadeDuration(const Duration(seconds: 5)),
      f.queue.toggleLike(f.a),
      f.queue.toggleDislike(f.a),
      f.queue.playTrackManually(f.a),
      f.queue.playSmartNext(),
      f.queue.addToQueue(f.a),
      f.queue.next(),
      f.queue.previous(),
      f.queue.playLibraryTrack(track: f.a, visibleTracks: f.items),
    ]);
    expect(f.settings.reads, isEmpty);
    expect(f.settings.writes, isEmpty);
    expect(f.events.recordCalls, 0);
    expect(f.states.toggles, 0);
    expect(f.tracks.findCalls, 0);
    expect(f.tracks.listCalls, 0);
    expect(f.first.setFilePathCalls, 0);
    expect(f.second.setVolumeCalls, 0);
  });

  test(
      'failed history write during shutdown is diagnosed and cleanup completes',
      () async {
    final gate = f.gate();
    final entered = Completer<void>();
    f.events.beforeRecord = (_) async {
      entered.complete();
      await gate.future;
      throw StateError('PRIVATE history failure');
    };
    await f.player.playTrack(f.a);
    await entered.future;
    final closing = f.player.dispose();
    gate.complete();
    await closing;
    expect(f.diagnostics.events,
        contains(DiagnosticEvent.playbackHistoryWriteFailed));
    expect(await f.repositories.playbackEvents.recentEvents(), isEmpty);
    expect(f.first.disposeCalls, 1);
    expect(f.second.disposeCalls, 1);
  });

  test(
      'failed feedback write during shutdown is diagnosed and cleanup completes',
      () async {
    final gate = f.gate();
    final entered = Completer<void>();
    f.states.beforeToggle = () async {
      entered.complete();
      await gate.future;
      throw StateError('PRIVATE feedback failure');
    };
    final liking = f.queue.toggleLike(f.a);
    await entered.future;
    final closing = f.queue.dispose();
    gate.complete();
    await Future.wait([liking, closing]);
    expect(f.diagnostics.events,
        contains(DiagnosticEvent.trackFeedbackWriteFailed));
    expect(
        (await f.repositories.trackUserState.findByTrackId(f.a.id!))
                ?.isFavorite ??
            false,
        isFalse);
  });

  test(
      'app drains concurrent history feedback and settings before file database closes',
      () async {
    await f.close();
    final directory =
        await Directory.systemTemp.createTemp('cmp-playback-drain-');
    final databaseFile = File('${directory.path}/library.sqlite');
    f = await _Fixture.create(databaseFile: databaseFile);
    final history = f.gate();
    final feedback = f.gate();
    final volume = f.gate();
    final fade = f.gate();
    final historyEntered = Completer<void>();
    final feedbackEntered = Completer<void>();
    final volumeEntered = Completer<void>();
    final fadeEntered = Completer<void>();
    f.events.beforeRecord = (_) async {
      historyEntered.complete();
      await history.future;
    };
    f.states.beforeToggle = () async {
      feedbackEntered.complete();
      await feedback.future;
    };
    f.settings.beforeWrite = (key, _) async {
      if (key == 'player.volume') {
        volumeEntered.complete();
        await volume.future;
      }
      if (key == 'player.crossfadeMilliseconds') {
        fadeEntered.complete();
        await fade.future;
      }
    };
    try {
      await f.queue.playTrackManually(f.a);
      final liking = f.queue.toggleLike(f.a);
      final savingVolume = f.player.setVolume(.42);
      final savingFade =
          f.player.setCrossfadeDuration(const Duration(seconds: 6));
      await Future.wait([
        historyEntered.future,
        feedbackEntered.future,
        volumeEntered.future,
        fadeEntered.future
      ]);
      final closing = f.dependencies.dispose();
      expect(identical(closing, f.dependencies.dispose()), isTrue);
      history.complete();
      feedback.complete();
      fade.complete();
      await Future.wait([liking, savingFade]);
      await _pump();
      expect(f.database.closeCalls, 0,
          reason: 'The volume save is still pending');
      volume.complete();
      await Future.wait([savingVolume, closing]);
      expect(f.database.closeCalls, 1);
      final reopened = AppDatabase(NativeDatabase(databaseFile));
      try {
        final repositories = DriftRepositories(reopened);
        final state = await repositories.trackUserState.findByTrackId(f.a.id!);
        expect(state!.isFavorite, isTrue);
        expect(state.playCount, 1);
        expect(await repositories.settings.readString('player.volume'), '0.42');
        expect(
            await repositories.settings
                .readString('player.previousVolumeBeforeMute'),
            '0.42');
        expect(
            await repositories.settings
                .readString('player.crossfadeMilliseconds'),
            '6000');
        final events = await repositories.playbackEvents.recentEvents();
        expect(events, hasLength(1));
        expect(events.single.type, PlaybackEventType.started);
      } finally {
        await reopened.close();
      }
    } finally {
      await f.close();
      await directory.delete(recursive: true);
    }
  });
}

Future<void> _pump() => pumpEventQueue(times: 20);

final class _Fixture {
  _Fixture(this.database, this.repositories, this.items, PlaybackCache? cache) {
    events = _Events(repositories.playbackEvents);
    states = _States(repositories.trackUserState);
    settings = _Settings(repositories.settings);
    tracks = _Tracks(repositories.tracks);
    final deck = JustAudioPlayerService(
        playbackEvents: events,
        diagnostics: diagnostics,
        settings: settings,
        audioEngine: first,
        fileExists: (_) => true,
        isWindows: cache != null,
        playbackCache: cache);
    final standby = JustAudioPlayerService(
        playbackEvents: events,
        diagnostics: diagnostics,
        audioEngine: second,
        fileExists: (_) => true,
        isWindows: false);
    player = TransitionPlayerService(
        first: deck, second: standby, settings: settings);
    final recommendations = RecommendationService(
        tracks: tracks, trackUserState: states, playbackEvents: events);
    queue = PlaybackQueueService(
        playerService: player,
        tracks: tracks,
        trackUserState: states,
        playbackEvents: events,
        recommendationService: recommendations,
        diagnostics: diagnostics,
        randomDouble: () => 0);
    dependencies = AppDependencies(
        database: database,
        repositories: repositories,
        recommendationService: recommendations,
        libraryScanner: LibraryScannerService(
            libraryRepository: repositories.libraryFolders,
            trackRepository: repositories.tracks,
            metadataReader: const FallbackMetadataReaderService()),
        directoryPicker: const _Picker(),
        customArtwork: const FilePickerCustomArtworkService(
            artworkCache: NoopArtworkCacheService()),
        playerService: player,
        playbackQueue: queue,
        smtcService: media);
  }
  final _Database database;
  final DriftRepositories repositories;
  final List<Track> items;
  final first = TestAudioEngine();
  final second = TestAudioEngine();
  final media = _Media();
  final diagnostics = _Diagnostics();
  final _gates = <Completer<void>>[];
  Object? expectedCleanupError;
  late final _Events events;
  late final _States states;
  late final _Settings settings;
  late final _Tracks tracks;
  late final TransitionPlayerService player;
  late final PlaybackQueueService queue;
  late final AppDependencies dependencies;
  Track get a => items[0];
  Track get b => items[1];
  List<PlaylistEntry> get entries => [
        for (var i = 0; i < items.length; i++)
          PlaylistEntry(
              playlistId: 1,
              trackId: items[i].id!,
              position: i,
              addedAt: DateTime(2026),
              track: items[i]),
      ];
  Completer<void> gate() {
    final gate = Completer<void>();
    _gates.add(gate);
    return gate;
  }

  static Future<_Fixture> create(
      {PlaybackCache? cache, File? databaseFile}) async {
    final database = _Database(databaseFile);
    final repositories = DriftRepositories(database);
    final tracks = <Track>[];
    for (var i = 0; i < 3; i++) {
      final id = await repositories.tracks.upsertTrack(Track(
          filePath: '${Directory.systemTemp.path}/cmp-треки/$i.mp3',
          title: 'Track $i',
          duration: const Duration(minutes: 3),
          addedAt: DateTime(2026),
          updatedAt: DateTime(2026)));
      tracks.add((await repositories.tracks.findById(id))!);
    }
    return _Fixture(database, repositories, tracks, cache);
  }

  Future<void> close() async {
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
    try {
      await dependencies.dispose();
    } catch (error) {
      if (!identical(error, expectedCleanupError)) rethrow;
    }
  }
}

final class _Database extends AppDatabase {
  _Database([File? file])
      : super(file == null ? NativeDatabase.memory() : NativeDatabase(file));
  int closeCalls = 0;
  @override
  Future<void> close() {
    closeCalls++;
    return super.close();
  }
}

final class _Events implements PlaybackEventRepository {
  _Events(this.inner);
  final PlaybackEventRepository inner;
  Future<void> Function(PlaybackEvent)? beforeRecord;
  Future<void> Function()? beforeRecent;
  int recordCalls = 0;
  int recentReads = 0;
  @override
  Future<int> recordEvent(PlaybackEvent event) async {
    recordCalls++;
    await beforeRecord?.call(event);
    return inner.recordEvent(event);
  }

  @override
  Future<List<PlaybackEvent>> recentEvents({int limit = 100}) async {
    recentReads++;
    await beforeRecent?.call();
    return inner.recentEvents(limit: limit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected events call');
}

final class _States implements TrackUserStateRepository {
  _States(this.inner);
  final TrackUserStateRepository inner;
  Future<void> Function()? beforeToggle;
  Future<void> Function()? beforeSingleRead;
  Future<void> Function()? beforeBatchRead;
  int toggles = 0;
  int singleReads = 0;
  int batchReads = 0;
  @override
  Future<TrackUserState> toggleFeedback(int trackId, TrackFeedback feedback,
      {required DateTime updatedAt}) async {
    toggles++;
    await beforeToggle?.call();
    return inner.toggleFeedback(trackId, feedback, updatedAt: updatedAt);
  }

  @override
  Future<TrackUserState?> findByTrackId(int trackId) async {
    singleReads++;
    await beforeSingleRead?.call();
    return inner.findByTrackId(trackId);
  }

  @override
  Future<Map<int, TrackUserState>> findByTrackIds(
      Iterable<int> trackIds) async {
    batchReads++;
    await beforeBatchRead?.call();
    return inner.findByTrackIds(trackIds);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected states call');
}

final class _Settings implements SettingsRepository {
  _Settings(this.inner);
  final SettingsRepository inner;
  Future<void> Function(String, String)? beforeWrite;
  Future<void> Function(String)? beforeRead;
  final writes = <String>[];
  final reads = <String>[];
  @override
  Future<void> writeString(String key, String value) async {
    writes.add(key);
    await beforeWrite?.call(key, value);
    return inner.writeString(key, value);
  }

  @override
  Future<String?> readString(String key) async {
    reads.add(key);
    await beforeRead?.call(key);
    return inner.readString(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected settings call');
}

final class _Tracks implements TrackRepository {
  _Tracks(this.inner);
  final TrackRepository inner;
  Future<void> Function()? beforeList;
  Future<void> Function()? beforeFind;
  int listCalls = 0;
  int findCalls = 0;
  @override
  Future<Track?> findById(int id) async {
    findCalls++;
    await beforeFind?.call();
    return inner.findById(id);
  }

  @override
  Future<List<Track>> listTracks(
      {int limit = 100,
      int offset = 0,
      bool includeDisabledFolders = false}) async {
    listCalls++;
    await beforeList?.call();
    return inner.listTracks(
        limit: limit,
        offset: offset,
        includeDisabledFolders: includeDisabledFolders);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected tracks call');
}

final class _Media implements SmtcService {
  Future<void> Function()? onDispose;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {
    await onDispose?.call();
  }
}

final class _Diagnostics implements DiagnosticsService {
  final events = <DiagnosticEvent>[];
  @override
  void record(DiagnosticEvent event,
      {Map<DiagnosticField, Object?> fields = const {}, Object? error}) {
    events.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected diagnostics call');
}

final class _Picker implements DirectoryPickerService {
  const _Picker();
  @override
  Future<String?> pickMusicFolder() async => null;
}

final class _Cache implements ProtectedPlaybackCache {
  static const entry = PlaybackCacheEntry(
      filePath: r'C:\cache\audio.mp3',
      reusedExistingFile: true,
      cacheSizeBeforeCleanupBytes: 1,
      cacheSizeAfterCleanupBytes: 1,
      cleanupDeletedFileCount: 0,
      cleanupDeletedPaths: [],
      sourceSizeBytes: 1);
  final entered = Completer<void>();
  final result = Completer<PlaybackCacheEntry>();
  final released = <String>[];
  @override
  Future<PlaybackCacheEntry> acquire(Track track, String sourcePath) {
    entered.complete();
    return result.future;
  }

  @override
  Future<PlaybackCacheEntry> resolve(Track track, String sourcePath) =>
      acquire(track, sourcePath);
  @override
  void release(String cachedPath) {
    released.add(cachedPath);
  }
}
