import '../data/drift/app_database.dart';
import '../diagnostics/diagnostics_service.dart';
import '../domain/repositories/repositories.dart';
import '../library/custom_artwork_service.dart';
import '../library/directory_picker_service.dart';
import '../library/library_scanner_service.dart';
import '../library/library_controller.dart';
import '../library/library_management_service.dart';
import '../library_sync/downloaded_asset_checker.dart';
import '../library_sync/source_fingerprint_probe.dart';
import '../player/player_service.dart';
import '../queue/playback_queue_service.dart';
import '../recommendation/recommendation_service.dart';
import '../smtc/smtc_service.dart';

import 'resource_cleanup.dart';

final class AppDependencies {
  AppDependencies({
    required this.database,
    required this.repositories,
    required this.recommendationService,
    required this.libraryScanner,
    required this.directoryPicker,
    required this.customArtwork,
    required this.playerService,
    required this.playbackQueue,
    required this.smtcService,
    this.diagnostics = const NoopDiagnosticsService(),
    LibraryController? libraryController,
    SourceFingerprintProbe Function()? sourceFingerprintProbeFactory,
  })  : _sourceFingerprintProbeFactory =
            sourceFingerprintProbeFactory ?? FileSourceFingerprintProbe.new,
        libraryController = libraryController ??
            LibraryController(
              directoryPicker: directoryPicker,
              scanFolder: libraryScanner.scanFolder,
              controlledScanFolder: libraryScanner.scanFolder,
              management: LibraryManagementService(
                libraryRepository: repositories.libraryFolders,
                scanFolder: libraryScanner.scanFolder,
                controlledScanFolder: libraryScanner.scanFolder,
              ),
              diagnostics: diagnostics,
            );

  final LibraryController libraryController;
  final DiagnosticsService diagnostics;
  final AppDatabase database;
  final AppRepositories repositories;
  final RecommendationService recommendationService;
  final LibraryScannerService libraryScanner;
  final DirectoryPickerService directoryPicker;
  final CustomArtworkService customArtwork;
  final PlayerService playerService;
  final PlaybackQueueService playbackQueue;
  final SmtcService smtcService;
  final SourceFingerprintProbe Function() _sourceFingerprintProbeFactory;
  DownloadedAssetChecker? _assetChecker;

  /// Lazy: ordinary playback does not open a hashing worker or read files.
  DownloadedAssetChecker get assetChecker {
    if (_closing != null) throw StateError('Приложение закрывается.');
    return _assetChecker ??= DownloadedAssetChecker(
        repository: repositories.downloadedAssets,
        probe: _sourceFingerprintProbeFactory());
  }

  Future<void>? _closing;

  Future<void> dispose() => _closing ??= _dispose();

  Future<void> _dispose() async {
    final assetClosing = _assetChecker?.close();
    assetClosing?.ignore();
    // Admission closes synchronously before the first native cleanup await.
    final libraryClosing = Future<void>.sync(libraryController.close);
    libraryClosing.ignore();
    // Queue/media commands can await native loads. Begin every shutdown before
    // waiting, so player disposal can interrupt those loads without a cycle.
    final mediaClosing = Future<void>.sync(smtcService.dispose);
    mediaClosing.ignore();
    final queueClosing = Future<void>.sync(playbackQueue.dispose);
    queueClosing.ignore();
    final playerClosing = Future<void>.sync(playerService.dispose);
    playerClosing.ignore();
    final failure = await closeAppResources([
      AppCleanupAction(AppResource.mediaControls, () => mediaClosing),
      AppCleanupAction(AppResource.queue, () => queueClosing),
      AppCleanupAction(AppResource.player, () => playerClosing),
      AppCleanupAction(AppResource.library, () => libraryClosing),
      if (assetClosing != null)
        AppCleanupAction(AppResource.assetVerification, () => assetClosing),
      AppCleanupAction(AppResource.database, database.close),
      AppCleanupAction(AppResource.diagnostics, diagnostics.flush),
    ], diagnostics);
    failure?.rethrowError();
  }
}
