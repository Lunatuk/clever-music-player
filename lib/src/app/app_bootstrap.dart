import '../data/drift/app_database.dart';
import '../data/repositories/drift_repositories.dart';
import '../diagnostics/diagnostics_service.dart';
import '../domain/repositories/repositories.dart';
import '../library/artwork_cache_service.dart';
import '../library/custom_artwork_service.dart';
import '../library/directory_picker_service.dart';
import '../library/library_controller.dart';
import '../library/library_management_service.dart';
import '../library/library_scanner_service.dart';
import '../library/metadata_reader_service.dart';
import '../player/player_service.dart';
import '../queue/playback_queue_service.dart';
import '../recommendation/recommendation_service.dart';
import '../smtc/smtc_service.dart';
import 'app_dependencies.dart';
import 'resource_cleanup.dart';

final class LocalLibraryAdapters {
  const LocalLibraryAdapters(
      {required this.metadataReader,
      required this.artworkCache,
      required this.directoryPicker,
      required this.customArtwork});
  final MetadataReaderService metadataReader;
  final ArtworkCacheService artworkCache;
  final DirectoryPickerService directoryPicker;
  final CustomArtworkService customArtwork;
}

final class AppPlayerRuntime {
  const AppPlayerRuntime({required this.player, required this.initialize});
  final PlayerService player;
  final Future<void> Function() initialize;
}

/// Native construction lives behind this boundary. UI, queue and system media
/// controls receive the same logical player/queue, including its two decoders.
abstract interface class AppPlatformAdapters {
  Future<AppDatabase> openDatabase(DiagnosticsService diagnostics);
  LocalLibraryAdapters createLocalLibrary();
  Future<AppPlayerRuntime> createPlayer(
      AppRepositories repositories, DiagnosticsService diagnostics);
  SmtcService createMediaControls(PlayerService player,
      PlaybackQueueService queue, DiagnosticsService diagnostics);
}

Future<AppDependencies> bootstrapApplication(
    {required AppPlatformAdapters adapters,
    DiagnosticsService diagnostics = const NoopDiagnosticsService()}) async {
  final owned = <AppCleanupAction>[];
  try {
    final local = adapters.createLocalLibrary();
    final database = await adapters.openDatabase(diagnostics);
    owned.add(AppCleanupAction(AppResource.database, database.close));
    // Force lazy open/migration while rollback still owns the connection.
    await database.customSelect('SELECT 1').get();
    final repositories = DriftRepositories(database);
    final recommendations = RecommendationService(
        tracks: repositories.tracks,
        trackUserState: repositories.trackUserState,
        playbackEvents: repositories.playbackEvents);
    final scanner = LibraryScannerService(
        libraryRepository: repositories.libraryFolders,
        trackRepository: repositories.tracks,
        metadataReader: local.metadataReader,
        artworkCache: local.artworkCache,
        diagnostics: diagnostics);
    final runtime = await adapters.createPlayer(repositories, diagnostics);
    owned.add(AppCleanupAction(AppResource.player, runtime.player.dispose));
    await runtime.initialize();
    final queue = PlaybackQueueService(
        playerService: runtime.player,
        tracks: repositories.tracks,
        trackUserState: repositories.trackUserState,
        playbackEvents: repositories.playbackEvents,
        recommendationService: recommendations,
        diagnostics: diagnostics);
    owned.add(AppCleanupAction(AppResource.queue, queue.dispose));
    final library = LibraryController(
        directoryPicker: local.directoryPicker,
        scanFolder: scanner.scanFolder,
        controlledScanFolder: scanner.scanFolder,
        management: LibraryManagementService(
            libraryRepository: repositories.libraryFolders,
            scanFolder: scanner.scanFolder,
            controlledScanFolder: scanner.scanFolder),
        diagnostics: diagnostics);
    owned.add(AppCleanupAction(AppResource.library, library.close));
    final media =
        adapters.createMediaControls(runtime.player, queue, diagnostics);
    owned.add(AppCleanupAction(AppResource.mediaControls, media.dispose));
    await media.initialize();
    return AppDependencies(
        database: database,
        repositories: repositories,
        recommendationService: recommendations,
        libraryScanner: scanner,
        directoryPicker: local.directoryPicker,
        customArtwork: local.customArtwork,
        playerService: runtime.player,
        playbackQueue: queue,
        smtcService: media,
        libraryController: library,
        diagnostics: diagnostics);
  } on Object catch (error, stack) {
    // Native disposal can release a command started by media initialization.
    // Start service shutdown together, but keep SQLite open until all settle.
    final closing = <AppCleanupAction>[];
    for (final action in owned.reversed) {
      if (action.resource == AppResource.database) {
        closing.add(action);
        continue;
      }
      final operation = Future<void>.sync(action.close);
      operation.ignore();
      closing.add(AppCleanupAction(action.resource, () => operation));
    }
    await closeAppResources(closing, diagnostics);
    // Cleanup failures are reported separately; keep the original startup cause.
    Error.throwWithStackTrace(error, stack);
  }
}
