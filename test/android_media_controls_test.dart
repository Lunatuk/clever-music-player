import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:clever_music_player/src/android/android_audio_session.dart';
import 'package:clever_music_player/src/android/android_folder_bookmarks.dart';
import 'package:clever_music_player/src/android/android_media_controls.dart';
import 'package:clever_music_player/src/android/android_preview_app.dart';
import 'package:clever_music_player/src/app/app_dependencies.dart';
import 'package:clever_music_player/src/app/default_platform_adapters.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/player/transition_player_service.dart';
import 'package:clever_music_player/src/queue/playback_queue_service.dart';
import 'package:clever_music_player/src/recommendation/recommendation_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_audio_engine.dart';
import 'support/test_audio_folders.dart';

void main() {
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() => f.close());

  testWidgets('Android root keeps music playing across background and return',
      (tester) async {
    final dependencies = f.previewDependencies();
    final bookmarks = AndroidFolderBookmarks(settings: TestFolderSettings());
    await tester.runAsync(bookmarks.initialize);
    await tester.runAsync(() => f.player.playTrack(f.tracks.first));
    await tester.pumpWidget(
        AndroidPreviewApp(dependencies: dependencies, bookmarks: bookmarks));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(f.player.isPlaying, isTrue);
    expect(f.first.pauseCalls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(f.player.currentTrack, f.tracks.first);
    expect(f.first.playCalls, 1);
    // Start async SQLite/stream cleanup outside the widget test's fake clock.
    await tester.runAsync(dependencies.dispose);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  test('UI and notification share metadata, playback and seek', () async {
    await f.player.playTrack(f.tracks.first);
    await flush();
    final item = f.handler.mediaItem.value!;
    expect(item.id, 'track:${f.tracks.first.id}');
    expect(item.title, 'Track 0');
    expect(item.artist, 'Artist');
    expect(item.artUri, Uri.file(r'C:\covers\test.webp'));
    expect(item.duration, const Duration(seconds: 60));
    expect(f.handler.playbackState.value.playing, isTrue);
    expect(f.handler.playbackState.value.controls, [
      MediaControl.skipToPrevious,
      MediaControl.pause,
      MediaControl.skipToNext,
      MediaControl.stop
    ]);
    await f.handler.pause();
    await flush();
    expect(f.player.isPlaying, isFalse);
    expect(f.handler.playbackState.value.processingState,
        AudioProcessingState.ready);
    await f.handler.click();
    await flush();
    expect(f.player.isPlaying, isTrue);
    await f.handler.seek(const Duration(seconds: 12));
    expect(f.player.position, const Duration(seconds: 12));
    expect(f.handler.playbackState.value.updatePosition,
        const Duration(seconds: 12));
  });

  test('same track ID publishes updated title and duration', () async {
    await f.player.playTrack(f.tracks.first);
    await flush();
    final seen = <MediaItem?>[];
    final subscription = f.handler.mediaItem.listen(seen.add);
    await f.player.playTrack(f.tracks.first.copyWith(title: 'New title'));
    await flush();
    expect(f.handler.mediaItem.value!.title, 'New title');
    f.first.emitDuration(const Duration(seconds: 90));
    await flush();
    expect(f.handler.mediaItem.value!.duration, const Duration(seconds: 90));
    expect(seen.any((item) => item?.title == 'New title'), isTrue);
    await subscription.cancel();
  });

  test('unsaved content URI is hashed in the media ID', () async {
    final track = Track.fromSource(
        source: f.tracks.first.source,
        title: 'Unsaved',
        addedAt: DateTime(2026),
        updatedAt: DateTime(2026));
    await f.player.playTrack(track);
    await flush();
    expect(f.handler.mediaItem.value!.id,
        matches(RegExp(r'^track:[0-9a-f]{64}$')));
    expect(f.handler.mediaItem.value!.id, isNot(contains('content://')));
  });

  test('loading keeps the play request visible while source opens', () async {
    final gate = Completer<Duration?>();
    f.first.setSourceHandler = (_, __) => gate.future;
    final play = f.player.playTrack(f.tracks.first);
    await flush();
    expect(f.handler.playbackState.value.processingState,
        AudioProcessingState.loading);
    expect(f.handler.playbackState.value.playing, isTrue);
    gate.complete(const Duration(seconds: 60));
    await play;
  });

  test('ordinary position ticks do not flood native state; seek does publish',
      () async {
    await f.player.playTrack(f.tracks.first);
    await flush();
    final seen = <PlaybackState>[];
    final subscription = f.handler.playbackState.listen(seen.add);
    await flush();
    final baseline = seen.length;
    for (var i = 1; i <= 5; i++) {
      f.now = f.now.add(const Duration(milliseconds: 100));
      f.first.emitPosition(Duration(milliseconds: i * 100));
      await flush();
    }
    expect(seen.length, baseline);
    await f.handler.seek(const Duration(seconds: 20));
    expect(f.handler.playbackState.value.updatePosition,
        const Duration(seconds: 20));
    expect(seen.length, greaterThan(baseline));
    await subscription.cancel();
  });

  test('system Back/Next replay five Wave visits and preserve queue priority',
      () async {
    await f.queue
        .playLibraryTrack(track: f.tracks.last, visibleTracks: f.tracks);
    final visits = [f.player.currentTrack!.id];
    for (var i = 0; i < 5; i++) {
      await f.handler.skipToNext();
      visits.add(f.player.currentTrack!.id);
    }
    for (var i = 4; i >= 0; i--) {
      await f.handler.skipToPrevious();
      expect(f.player.currentTrack!.id, visits[i]);
    }
    await f.handler.skipToNext();
    expect(f.player.currentTrack!.id, visits[1]);
    await f.queue.addToQueue(f.tracks[3]);
    await f.handler.skipToNext();
    expect(f.player.currentTrack!.id, f.tracks[3].id);
    expect(f.queue.state.manualQueue, isEmpty);
  });

  test('natural transition does not publish idle or terminal completion',
      () async {
    await f.player.setCrossfadeDuration(Duration.zero);
    await f.queue
        .playLibraryTrack(track: f.tracks.first, visibleTracks: f.tracks);
    await until(() => f.second.sources.isNotEmpty);
    final seen = <PlaybackState>[];
    final subscription = f.handler.playbackState.listen(seen.add);
    await flush();
    f.first.emitState(const AudioEngineState(
        isPlaying: false,
        processingState: AudioEngineProcessingState.completed));
    await until(() =>
        f.player.currentTrack?.id == f.tracks[1].id && f.player.isPlaying);
    await flush();
    expect(seen, isNotEmpty);
    expect(seen.every((state) => state.playing), isTrue,
        reason:
            seen.map((s) => '${s.processingState}:${s.playing}').join(', '));
    expect(
        seen.any((state) =>
            state.processingState == AudioProcessingState.idle ||
            state.processingState == AudioProcessingState.completed),
        isFalse);
    expect(f.handler.mediaItem.value!.id, 'track:${f.tracks[1].id}');
    await subscription.cancel();
  });

  test('automatic source recovery keeps the service active until a valid track',
      () async {
    await f.player.setCrossfadeDuration(Duration.zero);
    f.first.setSourceHandler = f.second.setSourceHandler = (source, _) {
      if (source == f.tracks[1].source) throw StateError('unreadable document');
      return const Duration(seconds: 60);
    };
    await f.queue
        .playLibraryTrack(track: f.tracks.first, visibleTracks: f.tracks);
    await flush();
    final seen = <PlaybackState>[];
    final subscription = f.handler.playbackState.listen(seen.add);
    await flush();
    f.first.emitState(const AudioEngineState(
        isPlaying: false,
        processingState: AudioEngineProcessingState.completed));
    await until(() =>
        f.player.currentTrack?.id == f.tracks[2].id && f.player.isPlaying);
    await flush();
    expect(seen.every((state) => state.playing), isTrue,
        reason:
            seen.map((s) => '${s.processingState}:${s.playing}').join(', '));
    expect(
        seen.any((state) =>
            state.processingState == AudioProcessingState.idle ||
            state.processingState == AudioProcessingState.error),
        isFalse);
    await subscription.cancel();
  });

  test('exhausted automatic recovery eventually releases playing state',
      () async {
    await f.player.setCrossfadeDuration(Duration.zero);
    f.second.setSourceHandler = (_, __) => throw StateError('unreadable');
    await f.queue
        .playLibraryTrack(track: f.tracks.first, visibleTracks: f.tracks);
    f.first.setSourceHandler = (_, __) => throw StateError('unreadable');
    f.first.emitState(const AudioEngineState(
        isPlaying: false,
        processingState: AudioEngineProcessingState.completed));
    await until(() =>
        !f.queue.isRecoveringAutomatically &&
        !f.queue.state.isChoosingNext &&
        f.handler.playbackState.value.processingState ==
            AudioProcessingState.error);
    expect(f.handler.playbackState.value.playing, isFalse);
  });

  test('completion without a queue is terminal and releases playing state',
      () async {
    await f.player.playTrack(f.tracks.first);
    f.first.emitState(const AudioEngineState(
        isPlaying: false,
        processingState: AudioEngineProcessingState.completed));
    await until(() =>
        f.handler.playbackState.value.processingState ==
        AudioProcessingState.completed);
    expect(f.handler.playbackState.value.playing, isFalse);
  });

  test('terminal source error publishes fixed text without private source',
      () async {
    await f.player.playTrack(f.tracks.first);
    f.first.emitError(StateError('content://private-provider/secret'));
    await until(() =>
        f.handler.playbackState.value.processingState ==
        AudioProcessingState.error);
    expect(
        f.handler.playbackState.value.errorMessage, isNot(contains('secret')));
    expect(f.handler.playbackState.value.errorCode, 1);
    expect(f.handler.playbackState.value.playing, isFalse);
  });

  for (final noisy in [false, true]) {
    test(
        '${noisy ? 'headphone removal' : 'audio interruption'} pauses both fade decks',
        () async {
      await f.player.setVolume(.6);
      await f.player.playTrack(f.tracks.first);
      await f.player.prepareNextTrack(f.tracks[1]);
      f.first.emitPosition(const Duration(seconds: 57));
      await flush();
      await f.player.playAutomatically(f.tracks[1]);
      await until(() => f.first.playing && f.second.playing);
      expect(f.first.playing && f.second.playing, isTrue);
      (noisy ? f.session.noisy : f.session.interrupted).add(null);
      await until(() => !f.first.playing && !f.second.playing);
      expect(f.player.isPlaying, isFalse);
      expect(f.player.volume, .6);
      expect(f.player.crossfadeDuration, const Duration(seconds: 3));
      await flush();
      expect(f.player.isPlaying, isFalse);
      await f.handler.play();
      expect(f.player.isPlaying, isTrue);
    });
  }

  test('Stop waits for native stop before releasing focus and publishing idle',
      () async {
    await f.player.playTrack(f.tracks.first);
    final gate = Completer<void>();
    final entered = Completer<void>();
    f.first.stopHandler = (_) {
      entered.complete();
      return gate.future;
    };
    final stopping = f.handler.stop();
    await entered.future;
    await flush();
    expect(f.session.deactivations, 0);
    expect(f.handler.playbackState.value.processingState,
        isNot(AudioProcessingState.idle));
    gate.complete();
    await stopping;
    expect(f.session.deactivations, 1);
    expect(f.handler.playbackState.value.processingState,
        AudioProcessingState.idle);
    expect(f.player.isPlaying, isFalse);
    f.first.stopHandler = null;
    await f.player.playTrack(f.tracks[1]);
    expect(f.player.isPlaying, isTrue);
  });

  test('removing task keeps playing; paused task stops and releases focus',
      () async {
    await f.player.playTrack(f.tracks.first);
    await f.handler.onTaskRemoved();
    expect(f.player.isPlaying, isTrue);
    expect(f.session.deactivations, 0);
    await f.handler.pause();
    await f.handler.onTaskRemoved();
    expect(f.player.state.status, PlayerPlaybackStatus.stopped);
    expect(f.session.deactivations, 1);
  });

  test('initialization and disposal are idempotent and do not own decoders',
      () async {
    await f.service.initialize();
    await f.service.initialize();
    expect(f.session.configurations, 1);
    expect(f.registrations, 1);
    final closing = f.service.dispose();
    expect(identical(closing, f.service.dispose()), isTrue);
    await closing;
    expect(f.first.disposeCalls + f.second.disposeCalls, 0);
    final calls = f.first.playCalls + f.second.playCalls;
    await f.handler.play();
    expect(f.first.playCalls + f.second.playCalls, calls);
    f.session.noisy.add(null);
    await flush();
  });

  test('disposal drains accepted media commands before closing subjects',
      () async {
    await f.player.playTrack(f.tracks.first);
    final gate = Completer<void>();
    f.first.seekHandler = (_) => gate.future;
    final seeking = f.handler.seek(const Duration(seconds: 10));
    var closed = false;
    final closing = f.service.dispose().then((_) => closed = true);
    await flush();
    expect(closed, isFalse);
    gate.complete();
    await seeking;
    await closing;
    expect(f.handler.playbackState.isClosed, isTrue);
  });

  test(
      'late registration during close cannot start publishing or accept commands',
      () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    final service = AndroidMediaControlsService(
        player: f.player,
        queue: f.queue,
        diagnostics: const NoopDiagnosticsService(),
        session: _Session(),
        nativeErrors: const Stream.empty(),
        register: (_) {
          entered.complete();
          return gate.future;
        });
    final initializing = service.initialize();
    await entered.future;
    var closed = false;
    final closing = service.dispose().then((_) => closed = true);
    await flush();
    expect(closed, isFalse);
    await service.handler.play();
    expect(f.player.isPlaying, isFalse);
    gate.complete();
    await initializing;
    await closing;
    expect(service.handler.playbackState.isClosed, isTrue);
  });

  test('startup failure still allows full cleanup', () async {
    final session = _Session()
      ..configurationError = StateError('configure failed');
    final service = AndroidMediaControlsService(
        player: f.player,
        queue: f.queue,
        diagnostics: const NoopDiagnosticsService(),
        session: session,
        nativeErrors: const Stream.empty(),
        register: (_) async => fail('must not register'));
    await expectLater(service.initialize(), throwsStateError);
    await service.dispose();
    expect(session.deactivations, 1);
    expect(service.handler.playbackState.isClosed, isTrue);
    await session.close();
  });
}

Future<void> flush() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 250 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue,
      reason: 'Expected media/player state did not arrive');
}

final class _Session implements AndroidAudioSession {
  final interrupted = StreamController<void>.broadcast();
  final noisy = StreamController<void>.broadcast();
  int configurations = 0, deactivations = 0;
  Object? configurationError;
  @override
  Future<void> configure() async {
    configurations++;
    if (configurationError != null) throw configurationError!;
  }

  @override
  Stream<void> get interruptions => interrupted.stream;
  @override
  Stream<void> get becomingNoisy => noisy.stream;
  @override
  Future<void> deactivate() async {
    deactivations++;
  }

  Future<void> close() async {
    await interrupted.close();
    await noisy.close();
  }
}

final class _Fixture {
  _Fixture(this.database, this.repositories, this.tracks) {
    player = TransitionPlayerService(
        first: JustAudioPlayerService(
            audioEngine: first,
            isWindows: false,
            playbackEvents: repositories.playbackEvents),
        second: JustAudioPlayerService(
            audioEngine: second,
            isWindows: false,
            playbackEvents: repositories.playbackEvents));
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
    service = AndroidMediaControlsService(
        player: player,
        queue: queue,
        diagnostics: const NoopDiagnosticsService(),
        session: session,
        nativeErrors: const Stream.empty(),
        clock: () => now,
        register: (_) async {
          registrations++;
        });
    handler = service.handler;
  }
  final AppDatabase database;
  final DriftRepositories repositories;
  final List<Track> tracks;
  final first = TestAudioEngine()..loadedDuration = const Duration(seconds: 60);
  final second = TestAudioEngine()
    ..loadedDuration = const Duration(seconds: 60);
  final session = _Session();
  late final TransitionPlayerService player;
  late final PlaybackQueueService queue;
  late final AndroidMediaControlsService service;
  late final AppAudioHandler handler;
  int registrations = 0;
  DateTime now = DateTime(2026);
  AppDependencies? _dependencies;
  AppDependencies previewDependencies() {
    final local = DefaultAppPlatformAdapters(platform: AppHostPlatform.android)
        .createLocalLibrary();
    return _dependencies = AppDependencies(
        database: database,
        repositories: repositories,
        recommendationService: RecommendationService(
            tracks: repositories.tracks,
            trackUserState: repositories.trackUserState,
            playbackEvents: repositories.playbackEvents),
        libraryScanner: LibraryScannerService(
            libraryRepository: repositories.libraryFolders,
            trackRepository: repositories.tracks,
            metadataReader: local.metadataReader),
        directoryPicker: local.directoryPicker,
        customArtwork: local.customArtwork,
        playerService: player,
        playbackQueue: queue,
        smtcService: service);
  }

  static Future<_Fixture> create() async {
    final db = AppDatabase(NativeDatabase.memory());
    final repos = DriftRepositories(db);
    final tracks = <Track>[];
    for (var i = 0; i < 7; i++) {
      final id = await repos.tracks.upsertTrack(Track.fromSource(
          source: ContentUriAudioSource('content://test.documents/music/$i'),
          title: 'Track $i',
          artist: 'Artist',
          artworkPath: r'C:\covers\test.webp',
          duration: const Duration(seconds: 60),
          addedAt: DateTime(2026),
          updatedAt: DateTime(2026)));
      tracks.add((await repos.tracks.findById(id))!);
    }
    final fixture = _Fixture(db, repos, tracks);
    await fixture.service.initialize();
    return fixture;
  }

  Future<void> close() async {
    if (_dependencies != null) {
      await _dependencies!.dispose();
      await session.close();
      return;
    }
    await Future.wait([service.dispose(), queue.dispose(), player.dispose()]);
    await session.close();
    await database.close();
  }
}
