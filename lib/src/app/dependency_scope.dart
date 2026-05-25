import 'package:flutter/widgets.dart';

import '../data/drift/app_database.dart';
import '../domain/repositories/repositories.dart';
import '../library/custom_artwork_service.dart';
import '../library/directory_picker_service.dart';
import '../library/library_scanner_service.dart';
import '../player/player_service.dart';
import '../queue/playback_queue_service.dart';
import '../recommendation/recommendation_service.dart';
import '../system_media/system_media_controls_service.dart';

final class AppDependencies {
  const AppDependencies({
    required this.database,
    required this.repositories,
    required this.recommendationService,
    required this.libraryScanner,
    required this.directoryPicker,
    required this.customArtwork,
    required this.playerService,
    required this.playbackQueue,
    required this.systemMediaControlsService,
  });

  final AppDatabase database;
  final AppRepositories repositories;
  final RecommendationService recommendationService;
  final LibraryScannerService libraryScanner;
  final DirectoryPickerService directoryPicker;
  final CustomArtworkService customArtwork;
  final PlayerService playerService;
  final PlaybackQueueService playbackQueue;
  final SystemMediaControlsService systemMediaControlsService;

  Future<void> dispose() async {
    await systemMediaControlsService.dispose();
    await playbackQueue.dispose();
    await playerService.dispose();
    await database.close();
  }
}

final class AppDependenciesScope extends InheritedWidget {
  const AppDependenciesScope({
    required this.dependencies,
    required super.child,
    super.key,
  });

  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppDependenciesScope>();
    assert(scope != null, 'AppDependenciesScope was not found in the tree.');
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(AppDependenciesScope oldWidget) {
    return dependencies != oldWidget.dependencies;
  }
}
