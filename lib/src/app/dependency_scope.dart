import 'package:flutter/widgets.dart';

import '../data/drift/app_database.dart';
import '../domain/repositories/repositories.dart';
import '../recommendation/recommendation_service.dart';

final class AppDependencies {
  const AppDependencies({
    required this.database,
    required this.repositories,
    required this.recommendationService,
  });

  final AppDatabase database;
  final AppRepositories repositories;
  final RecommendationService recommendationService;
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
