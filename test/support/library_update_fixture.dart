import 'dart:async';

import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/library_sync_repository.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/downloaded_asset_checker.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:clever_music_player/src/library_sync/yandex_audio_selection.dart';
import 'package:clever_music_player/src/library_sync/yandex_connection_controller.dart';
import 'package:clever_music_player/src/library_sync/yandex_credential_store.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_runner.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_client.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_update_controller.dart';

import 'download_fixture.dart';
import 'yandex_connection_fixture.dart';
import 'yandex_fixture.dart';

final class LibraryUpdateFixture {
  LibraryUpdateFixture._(this.f);
  final DownloadFixture f;
  late YandexConnectionController connection;
  late YandexLibraryUpdateController updates;
  late UpdatePlans plans;
  final transport = YandexTestTransport();
  final credentials = MemoryYandexCredentials();
  final probe = UpdateProbe();
  SourceFingerprintProbe Function()? probeFactory;
  final fakeRunner = UpdateRunner();
  final diagnostics = UpdateDiagnostics();
  late YandexDownloadRunService runner;
  DateTime? apiClock;
  List<Object?> tracks = [
    yandexTrack('001'),
    yandexTrack('2'),
    yandexTrack('001')
  ];
  bool supported = true;
  Future<bool> Function(LibraryFolder, LibraryScanControl)? validateDestination;
  static Future<LibraryUpdateFixture> open(
      {bool supported = true, bool connected = true}) async {
    final fixture = LibraryUpdateFixture._(await DownloadFixture.open());
    fixture.f.account = await fixture.f.repositories.remoteLibrary
        .activateAccount(yandexAccount);
    fixture.supported = supported;
    fixture.runner = fixture.fakeRunner;
    fixture.plans = UpdatePlans(fixture.f.repositories.librarySync);
    if (connected) {
      fixture.credentials.value = YandexSavedCredential(
          account: fixture.f.account,
          token: YandexAccessToken('SYNTHETIC_UPDATE_SECRET'));
    }
    fixture.transport.onGet =
        (request, control) async => fixture.reply(request);
    fixture.connection = YandexConnectionController(
        repository: fixture.f.repositories.remoteLibrary,
        sessions: fixture.f.repositories.yandexSessions,
        credentials: fixture.credentials,
        readerFactory: (token) => YandexLibraryClient(
            token: token,
            transport: fixture.transport,
            clock: () => fixture.apiClock ?? fixture.f.now));
    await fixture.connection.initialize();
    if (connected) await fixture.connection.select(yandexLiked, true);
    fixture.updates = fixture.newController();
    return fixture;
  }

  Object? reply(YandexReadRequest request) => switch (request.endpoint) {
        YandexReadEndpoint.account => yandexStatus(),
        YandexReadEndpoint.likedTracks => yandexLikes(tracks: tracks),
        YandexReadEndpoint.playlist =>
          yandexList(tracks: tracks, count: tracks.length),
        YandexReadEndpoint.playlists => [yandexList()],
        YandexReadEndpoint.likedPlaylists => [],
        _ => throw StateError('Use native download server'),
      };
  YandexLibraryUpdateController newController() =>
      YandexLibraryUpdateController(
          connection: connection,
          library: f.repositories.libraryFolders,
          plans: plans,
          settings: f.repositories.settings,
          supported: supported,
          validateDestination: (folder, control) async =>
              await validateDestination?.call(folder, control) ?? true,
          diagnostics: diagnostics,
          clock: f.clock,
          checkerFactory: () => DownloadedAssetChecker(
              repository: f.repositories.downloadedAssets,
              probe: probeFactory?.call() ?? probe,
              clock: f.clock),
          runnerFactory: () => runner);
  Future<void> ready() async {
    await updates.initialize();
    await updates.configure(folderId: f.folderId);
  }

  Future<DownloadedAsset> asset({String id = '001'}) async {
    final quality = updates.quality.selection.resourceQuality;
    final identity = ExternalTrackIdentity(
        provider: 'yandex_music', externalId: id, variantKey: '009');
    final trackId = await f.repositories.tracks.upsertTrack(Track(
        filePath: '${f.destination.path}/existing-$id.mp3',
        libraryFolderId: f.folderId,
        title: 'PRIVATE_TITLE',
        contentHash: f.proof().contentHash,
        fileSizeBytes: 3,
        addedAt: f.now,
        updatedAt: f.now));
    await f.repositories.externalTracks.linkAll([
      ExternalTrackRef(
          trackId: trackId,
          identity: identity,
          origin: ExternalTrackRefOrigin.providerResponse,
          linkedAt: f.now)
    ]);
    return f.repositories.downloadedAssets.registerVerified(
        DownloadedAssetPublication(
            trackId: trackId,
            identity: identity,
            source: FileAudioSource('${f.destination.path}/existing-$id.mp3'),
            publicationId: 'existing-$id',
            requestedQuality: quality),
        DownloadedAssetVerification(
            actualQuality: quality,
            container: 'mp3',
            codec: 'mp3',
            fileSizeBytes: 3,
            duration: const Duration(seconds: 3),
            contentHash: f.proof().contentHash,
            checkedAt: f.now));
  }

  Future<void> close() async {
    await updates.close();
    await connection.close();
    await f.close();
  }
}

final class UpdateRunner implements YandexDownloadRunService {
  int calls = 0, closes = 0, cancellations = 0;
  bool _busy = false;
  RemoteLibraryAccount? account;
  int? folder, limit;
  YandexAudioSelection? selection;
  Future<YandexDownloadRunResult> Function(
      LibraryScanControl, void Function(YandexDownloadRunProgress)?)? onRun;
  @override
  bool get isBusy => _busy;
  @override
  Future<YandexDownloadRunResult> run(
      {required RemoteLibraryAccount account,
      required int libraryFolderId,
      required YandexAudioSelection selection,
      int maxJobs = 3,
      LibraryScanControl? control,
      void Function(YandexDownloadRunProgress)? onProgress}) async {
    calls++;
    this.account = account;
    folder = libraryFolderId;
    limit = maxJobs;
    this.selection = selection;
    _busy = true;
    try {
      return await onRun?.call(control!, onProgress) ??
          const YandexDownloadRunResult(
              YandexDownloadRunOutcome.completed, 0, 0);
    } finally {
      _busy = false;
    }
  }

  @override
  void cancel() {
    cancellations++;
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

final class UpdateProbe implements SourceFingerprintProbe {
  int calls = 0, closes = 0;
  SourceFingerprintResult result = SourceFingerprintResult.fingerprinted(
      3, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  Future<void> Function(LibraryScanControl)? onProbe;
  @override
  Future<SourceFingerprintResult> fingerprint(AudioSourceReference source,
      {required int expectedSize, required LibraryScanControl control}) async {
    calls++;
    await onProbe?.call(control);
    return result;
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

final class UpdatePlans implements LibrarySyncRepository {
  UpdatePlans(this.inner);
  final LibrarySyncRepository inner;
  int captures = 0, applies = 0;
  LibrarySyncPlan? lastPlan;
  bool stale = false;
  Future<void> Function()? onApply;
  @override
  Future<LibrarySyncSnapshot?> capture(RemoteLibraryAccount account,
      {required int libraryFolderId,
      required String quality,
      DateTime? minimumCompletedAt}) {
    captures++;
    return inner.capture(account,
        libraryFolderId: libraryFolderId,
        quality: quality,
        minimumCompletedAt: minimumCompletedAt);
  }

  @override
  Future<LibrarySyncApplyResult> apply(LibrarySyncPlan plan,
      {required DateTime now}) async {
    applies++;
    lastPlan = plan;
    await onApply?.call();
    return stale
        ? LibrarySyncApplyResult(status: LibrarySyncApplyStatus.stale)
        : inner.apply(plan, now: now);
  }
}

final class UpdateDiagnostics implements DiagnosticsService {
  final entries =
      <({DiagnosticEvent event, Map<DiagnosticField, Object?> fields})>[];
  @override
  void record(DiagnosticEvent event,
      {Map<DiagnosticField, Object?> fields = const {}, Object? error}) {
    entries.add((event: event, fields: Map.of(fields)));
  }

  @override
  Future<void> flush() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unused diagnostic IO');
}
