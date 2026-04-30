import 'dart:async';

import 'package:flutter/material.dart';

import 'src/app/clever_music_player_app.dart';
import 'src/app/dependency_scope.dart';
import 'src/data/drift/app_database.dart';
import 'src/data/repositories/drift_repositories.dart';
import 'src/library/directory_picker_service.dart';
import 'src/library/library_scanner_service.dart';
import 'src/library/metadata_reader_service.dart';
import 'src/player/just_audio_player_service.dart';
import 'src/recommendation/recommendation_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final database = AppDatabase.open();
  final repositories = DriftRepositories(database);
  final recommendationService = RecommendationService(
    tracks: repositories.tracks,
    trackUserState: repositories.trackUserState,
    playbackEvents: repositories.playbackEvents,
  );
  final libraryScanner = LibraryScannerService(
    libraryRepository: repositories.libraryFolders,
    trackRepository: repositories.tracks,
    metadataReader: const FallbackMetadataReaderService(),
  );
  final playerService = JustAudioPlayerService(
    playbackEvents: repositories.playbackEvents,
    trackUserState: repositories.trackUserState,
  );
  final dependencies = AppDependencies(
    database: database,
    repositories: repositories,
    recommendationService: recommendationService,
    libraryScanner: libraryScanner,
    directoryPicker: const FilePickerDirectoryPickerService(),
    playerService: playerService,
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
