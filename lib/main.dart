import 'package:flutter/material.dart';

import 'src/app/clever_music_player_app.dart';
import 'src/app/dependency_scope.dart';
import 'src/data/drift/app_database.dart';
import 'src/data/repositories/drift_repositories.dart';
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

  runApp(
    AppDependenciesScope(
      dependencies: AppDependencies(
        database: database,
        repositories: repositories,
        recommendationService: recommendationService,
      ),
      child: const CleverMusicPlayerApp(),
    ),
  );
}
