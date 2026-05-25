import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'src/app/clever_music_player_app.dart';
import 'src/app/dependency_scope.dart';
import 'src/data/drift/app_database.dart';
import 'src/data/repositories/drift_repositories.dart';
import 'src/library/artwork_cache_service.dart';
import 'src/library/custom_artwork_service.dart';
import 'src/library/directory_picker_service.dart';
import 'src/library/library_scanner_service.dart';
import 'src/library/metadata_reader_service.dart';
import 'src/player/just_audio_player_service.dart';
import 'src/queue/playback_queue_service.dart';
import 'src/recommendation/recommendation_service.dart';
import 'src/smtc/smtc_service.dart';
import 'src/smtc/smtc_windows_plugin_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = AppDatabase.open();
  final repositories = DriftRepositories(database);
  final recommendationService = RecommendationService(
    tracks: repositories.tracks,
    trackUserState: repositories.trackUserState,
    playbackEvents: repositories.playbackEvents,
  );
  final artworkCache = AppSupportArtworkCacheService();
  final libraryScanner = LibraryScannerService(
    libraryRepository: repositories.libraryFolders,
    trackRepository: repositories.tracks,
    metadataReader: const AudioMetadataReaderService(),
    artworkCache: artworkCache,
  );
  final playerService = JustAudioPlayerService(
    playbackEvents: repositories.playbackEvents,
    trackUserState: repositories.trackUserState,
    settings: repositories.settings,
  );
  await playerService.restoreSavedVolume();
  final playbackQueue = PlaybackQueueService(
    playerService: playerService,
    tracks: repositories.tracks,
    trackUserState: repositories.trackUserState,
    playbackEvents: repositories.playbackEvents,
    recommendationService: recommendationService,
  );
  final smtcService = Platform.isWindows
      ? WindowsSmtcService(
          playerService: playerService,
          onNext: playbackQueue.next,
          onPrevious: playbackQueue.previous,
          client: SmtcWindowsPluginClient(),
        )
      : const NoopSmtcService();
  await smtcService.initialize();
  final dependencies = AppDependencies(
    database: database,
    repositories: repositories,
    recommendationService: recommendationService,
    libraryScanner: libraryScanner,
    directoryPicker: const FilePickerDirectoryPickerService(),
    customArtwork: FilePickerCustomArtworkService(
      artworkCache: artworkCache,
    ),
    playerService: playerService,
    playbackQueue: playbackQueue,
    smtcService: smtcService,
  );

  runApp(
    _DependencyRoot(
      dependencies: dependencies,
      child: const CleverMusicPlayerApp(),
    ),
  );
}

final class _DependencyRoot extends StatefulWidget {
  const _DependencyRoot({
    required this.dependencies,
    required this.child,
  });

  final AppDependencies dependencies;
  final Widget child;

  @override
  State<_DependencyRoot> createState() => _DependencyRootState();
}

final class _DependencyRootState extends State<_DependencyRoot> {
  @override
  void dispose() {
    unawaited(widget.dependencies.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDependenciesScope(
      dependencies: widget.dependencies,
      child: widget.child,
    );
  }
}
