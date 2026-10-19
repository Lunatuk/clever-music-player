import 'dart:async';

import 'package:clever_music_player/src/android/android_media_controls.dart';

import 'package:clever_music_player/src/app/app_bootstrap.dart';
import 'package:clever_music_player/src/app/default_platform_adapters.dart';
import 'package:clever_music_player/src/app/resource_cleanup.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/custom_artwork_service.dart';
import 'package:clever_music_player/src/library/directory_picker_service.dart';
import 'package:clever_music_player/src/library/library_controller.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/downloaded_asset_checker.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:clever_music_player/src/player/player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/player/transition_player_service.dart';
import 'package:clever_music_player/src/queue/playback_queue_service.dart';
import 'package:clever_music_player/src/smtc/smtc_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_audio_engine.dart';
import 'support/asset_check_fixture.dart';

void main() {
  late _Adapters adapters;
  late _Diagnostics diagnostics;
  setUp(() {
    adapters = _Adapters();
    diagnostics = _Diagnostics();
  });
  tearDown(() async {
    if (adapters.player.disposeCalls == 0) await adapters.player.dispose();
    if (adapters.database.closeCalls == 0) await adapters.database.close();
  });

  test('bootstrap publishes one shared player and queue after initialization',
      () async {
    final dependencies = await bootstrapApplication(
        adapters: adapters, diagnostics: diagnostics);
    expect(adapters.order, [
      'library',
      'database',
      'player',
      'playerInitialize',
      'media',
      'mediaInitialize'
    ]);
    expect(identical(adapters.mediaPlayer, dependencies.playerService), isTrue);
    expect(identical(adapters.mediaQueue, dependencies.playbackQueue), isTrue);
    expect(identical(dependencies.playerService, adapters.player), isTrue);
    final first = dependencies.dispose();
    final second = dependencies.dispose();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    expect(adapters.media.disposeCalls, 1);
    expect(adapters.player.disposeCalls, 1);
    expect(adapters.database.closeCalls, 1);
    expect(diagnostics.flushCalls, 1);
    expect(await dependencies.libraryController.addFolder(),
        LibraryOperationOutcome.closed);
  });

  test('startup rollback interrupts a media command before draining its queue',
      () async {
    final load = Completer<void>();
    final entered = Completer<void>();
    Future<void>? playing;
    adapters.player.playAction = () {
      entered.complete();
      return load.future;
    };
    adapters.player.onDispose = () {
      if (!load.isCompleted) load.complete();
    };
    adapters.beforeMediaInitialize = (queue) async {
      playing = queue.playTrackManually(Track(
          filePath: 'test.mp3',
          addedAt: DateTime(2026),
          updatedAt: DateTime(2026)));
      await entered.future;
      throw adapters.startupError;
    };
    try {
      await expectLater(
          bootstrapApplication(adapters: adapters, diagnostics: diagnostics)
              .timeout(const Duration(seconds: 2)),
          throwsA(same(adapters.startupError)));
      await playing;
      expect(adapters.player.disposeCalls, 1);
      expect(adapters.database.closeCalls, 1);
    } finally {
      if (!load.isCompleted) load.complete();
    }
  });

  test('asset verification is lazy and shutdown never creates a worker',
      () async {
    var created = 0;
    adapters.probeFactory = () {
      created++;
      return _AssetProbe();
    };
    final dependencies = await bootstrapApplication(adapters: adapters);
    expect(created, 0);
    await dependencies.dispose();
    expect(created, 0);
    expect(() => dependencies.assetChecker, throwsStateError);
    expect(() => dependencies.yandexUpdate, throwsStateError);
    expect(() => dependencies.yandexConnection, throwsStateError);
  });

  test(
      'update owner is shared and local initialization drains before SQLite closes',
      () async {
    final dependencies = await bootstrapApplication(adapters: adapters);
    final updates = dependencies.yandexUpdate;
    expect(identical(updates, dependencies.yandexUpdate), isTrue);
    expect(
        identical(updates.connection, dependencies.yandexConnection), isTrue);
    final initializing = updates.initialize();
    await dependencies.dispose();
    await initializing;
    expect(updates.isBusy, isFalse);
    expect(adapters.database.closeCalls, 1);
    expect(() => dependencies.yandexUpdate, throwsStateError);
  });

  test('shutdown drains cancelled asset read before closing SQLite', () async {
    final probe = _AssetProbe();
    adapters.probeFactory = () => probe;
    final dependencies = await bootstrapApplication(adapters: adapters);
    final asset = await registerTestAsset(DriftRepositories(adapters.database));
    final checker = dependencies.assetChecker;
    expect(identical(checker, dependencies.assetChecker), isTrue);
    final reading = checker.check(asset);
    final closing = dependencies.dispose();
    expect(probe.control!.isCancellationRequested, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(adapters.database.closeCalls, 0);
    expect(
        await adapters.database.customSelect('SELECT 1').get(), hasLength(1));
    probe.gate.complete(SourceFingerprintResult.fingerprinted(3, abcHash));
    expect(await reading, AssetCheckOutcome.cancelled);
    await closing;
    expect(probe.closed, isTrue);
    expect(adapters.database.closeCalls, 1);
  });

  test('asset worker cleanup failure still closes SQLite and reports resource',
      () async {
    final probe = _AssetProbe()..failClose = true;
    adapters.probeFactory = () => probe;
    final dependencies = await bootstrapApplication(
        adapters: adapters, diagnostics: diagnostics);
    dependencies.assetChecker;
    await expectLater(dependencies.dispose(), throwsStateError);
    expect(adapters.database.closeCalls, 1);
    expect(diagnostics.failedStages, [AppResource.assetVerification.index + 1]);
  });

  for (final stage in [
    'library',
    'database',
    'player',
    'playerInitialize',
    'media',
    'mediaInitialize'
  ]) {
    test('startup failure at $stage releases already owned resources',
        () async {
      adapters.failAt = stage;
      await expectLater(
          bootstrapApplication(adapters: adapters, diagnostics: diagnostics),
          throwsA(same(adapters.startupError)));
      expect(adapters.database.closeCalls,
          ['library', 'database'].contains(stage) ? 0 : 1);
      expect(adapters.player.disposeCalls,
          ['library', 'database', 'player'].contains(stage) ? 0 : 1);
      expect(adapters.media.disposeCalls, stage == 'mediaInitialize' ? 1 : 0);
    });
  }

  test('migration/open failure rolls back the returned lazy database',
      () async {
    await adapters.database.close();
    adapters.database = _Database(broken: true);
    await expectLater(
        bootstrapApplication(adapters: adapters), throwsA(anything));
    expect(adapters.database.closeCalls, 1);
    expect(adapters.player.disposeCalls, 0);
  });

  test('rollback cleanup failures preserve the original startup error',
      () async {
    adapters.failAt = 'mediaInitialize';
    adapters.media.disposeError = StateError('PRIVATE media cleanup');
    adapters.player.disposeError = StateError('PRIVATE player cleanup');
    await expectLater(
        bootstrapApplication(adapters: adapters, diagnostics: diagnostics),
        throwsA(same(adapters.startupError)));
    expect(adapters.database.closeCalls, 1);
    expect(diagnostics.failedStages,
        [AppResource.mediaControls.index + 1, AppResource.player.index + 1]);
  });

  test('shutdown attempts every resource despite media and player failures',
      () async {
    final dependencies = await bootstrapApplication(
        adapters: adapters, diagnostics: diagnostics);
    final primary = adapters.media.disposeError = StateError('PRIVATE cleanup');
    adapters.player.disposeError = StateError('later failure');
    final closing = dependencies.dispose();
    await expectLater(closing, throwsA(same(primary)));
    await expectLater(dependencies.dispose(), throwsA(same(primary)));
    expect(adapters.media.disposeCalls, 1);
    expect(adapters.player.disposeCalls, 1);
    expect(adapters.database.closeCalls, 1);
    expect(diagnostics.flushCalls, 1);
    expect(await dependencies.libraryController.addFolder(),
        LibraryOperationOutcome.closed);
    await expectLater(
        adapters.database.customSelect('SELECT 1').get(), throwsA(anything));
  });

  test('concurrent shutdown callers both await native media disposal',
      () async {
    final dependencies = await bootstrapApplication(
        adapters: adapters, diagnostics: diagnostics);
    final gate = adapters.media.disposeGate = Completer<void>();
    var finished = false;
    final first = dependencies.dispose();
    final second = dependencies.dispose().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(adapters.database.closeCalls, 0);
    gate.complete();
    await Future.wait([first, second]);
    expect(finished, isTrue);
    expect(adapters.database.closeCalls, 1);
  });

  test('diagnostic errors cannot prevent cleanup of later resources', () async {
    diagnostics.throwOnRecord = true;
    var lastClosed = false;
    final primary = StateError('first error');
    final failure = await closeAppResources([
      AppCleanupAction(AppResource.player, () => Future.error(primary)),
      AppCleanupAction(AppResource.database, () async {
        lastClosed = true;
      }),
    ], diagnostics);
    expect(failure!.error, same(primary));
    expect(lastClosed, isTrue);
  });

  test(
      'desktop player factory releases the first deck if second creation fails',
      () async {
    final engine = TestAudioEngine();
    var calls = 0;
    final platform = DefaultAppPlatformAdapters(
        platform: AppHostPlatform.windows,
        audioEngineFactory: () {
          if (++calls == 2) throw adapters.startupError;
          return engine;
        });
    await expectLater(
        platform.createPlayer(
            DriftRepositories(adapters.database), diagnostics),
        throwsA(same(adapters.startupError)));
    expect(engine.disposeCalls, 1);
  });

  test(
      'default player runtime restores settings for one logical two-deck player',
      () async {
    final engines = <TestAudioEngine>[];
    final platform = DefaultAppPlatformAdapters(
        platform: AppHostPlatform.other,
        audioEngineFactory: () {
          final engine = TestAudioEngine();
          engines.add(engine);
          return engine;
        });
    final runtime = await platform.createPlayer(
        DriftRepositories(adapters.database), diagnostics);
    try {
      await runtime.initialize();
      expect(runtime.player, isA<TransitionPlayerService>());
      expect(engines, hasLength(2));
      expect(runtime.player.volume, 1);
    } finally {
      await runtime.player.dispose();
    }
    expect(engines.every((engine) => engine.disposeCalls == 1), isTrue);
  });

  test('platform selection constructs only the corresponding media adapter',
      () async {
    final dependencies = await bootstrapApplication(adapters: adapters);
    try {
      expect(
          DefaultAppPlatformAdapters(platform: AppHostPlatform.windows)
              .createMediaControls(
                  adapters.player, dependencies.playbackQueue, diagnostics),
          isA<WindowsSmtcService>());
      expect(
          DefaultAppPlatformAdapters(platform: AppHostPlatform.macos)
              .createMediaControls(
                  adapters.player, dependencies.playbackQueue, diagnostics),
          isA<MacosNowPlayingService>());
      expect(
          DefaultAppPlatformAdapters(platform: AppHostPlatform.android)
              .createMediaControls(
                  adapters.player, dependencies.playbackQueue, diagnostics),
          isA<AndroidMediaControlsService>());
    } finally {
      await dependencies.dispose();
    }
  });
}

final class _Adapters implements AppPlatformAdapters {
  _Database database = _Database();
  final player = _Player();
  final media = _Media();
  final order = <String>[];
  final startupError = StateError('PRIVATE startup error');
  String? failAt;
  Future<void> Function(PlaybackQueueService)? beforeMediaInitialize;
  PlayerService? mediaPlayer;
  PlaybackQueueService? mediaQueue;
  SourceFingerprintProbe Function()? probeFactory;
  void step(String stage) {
    order.add(stage);
    if (failAt == stage) throw startupError;
  }

  @override
  LocalLibraryAdapters createLocalLibrary() {
    step('library');
    return LocalLibraryAdapters(
        metadataReader: const FallbackMetadataReaderService(),
        artworkCache: const NoopArtworkCacheService(),
        directoryPicker: const _Picker(),
        customArtwork: const FilePickerCustomArtworkService(
            artworkCache: NoopArtworkCacheService()),
        sourceFingerprintProbeFactory: probeFactory);
  }

  @override
  Future<AppDatabase> openDatabase(DiagnosticsService diagnostics) async {
    step('database');
    return database;
  }

  @override
  Future<AppPlayerRuntime> createPlayer(
      AppRepositories repositories, DiagnosticsService diagnostics) async {
    step('player');
    return AppPlayerRuntime(
        player: player,
        initialize: () async {
          step('playerInitialize');
        });
  }

  @override
  SmtcService createMediaControls(PlayerService player,
      PlaybackQueueService queue, DiagnosticsService diagnostics) {
    step('media');
    mediaPlayer = player;
    mediaQueue = queue;
    media.initializeAction = () async {
      step('mediaInitialize');
      await beforeMediaInitialize?.call(queue);
    };
    return media;
  }
}

final class _AssetProbe implements SourceFingerprintProbe {
  final gate = Completer<SourceFingerprintResult>();
  LibraryScanControl? control;
  bool closed = false;
  bool failClose = false;
  @override
  Future<SourceFingerprintResult> fingerprint(AudioSourceReference source,
      {required int expectedSize, required LibraryScanControl control}) {
    this.control = control;
    return gate.future;
  }

  @override
  Future<void> close() async {
    closed = true;
    if (failClose) throw StateError('worker cleanup failed');
  }
}

class _Database extends AppDatabase {
  _Database({bool broken = false})
      : super(NativeDatabase.memory(
            setup:
                broken ? (db) => db.execute('PRAGMA user_version=8;') : null));
  int closeCalls = 0;
  @override
  Future<void> close() {
    closeCalls++;
    return super.close();
  }
}

final class _Player implements PlayerService {
  final controller = StreamController<PlayerState>.broadcast();
  int disposeCalls = 0;
  Object? disposeError;
  Future<void> Function()? playAction;
  void Function()? onDispose;
  @override
  PlayerState get state => const PlayerState.idle();
  @override
  Track? get currentTrack => null;
  @override
  Stream<PlayerState> get stateStream => controller.stream;
  @override
  Future<void> playTrack(Track track) =>
      playAction?.call() ?? Future.error(StateError('Unexpected play'));
  @override
  Future<void> dispose() async {
    disposeCalls++;
    onDispose?.call();
    await controller.close();
    if (disposeError != null) throw disposeError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected player call');
}

final class _Media implements SmtcService {
  FutureOr<void> Function()? initializeAction;
  Completer<void>? disposeGate;
  Object? disposeError;
  int disposeCalls = 0;
  @override
  Future<void> initialize() async {
    await initializeAction?.call();
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await disposeGate?.future;
    if (disposeError != null) throw disposeError!;
  }
}

final class _Picker implements DirectoryPickerService {
  const _Picker();
  @override
  Future<String?> pickMusicFolder() async => null;
}

final class _Diagnostics implements DiagnosticsService {
  final failedStages = <Object?>[];
  int flushCalls = 0;
  bool throwOnRecord = false;
  @override
  void record(DiagnosticEvent event,
      {Map<DiagnosticField, Object?> fields = const {}, Object? error}) {
    if (throwOnRecord) throw StateError('diagnostic failed');
    if (event == DiagnosticEvent.appCleanupFailed) {
      failedStages.add(fields[DiagnosticField.cleanupStage]);
    }
  }

  @override
  Future<void> flush() async {
    flushCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected diagnostic call');
}
