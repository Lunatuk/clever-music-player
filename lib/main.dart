import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'src/app/clever_music_player_app.dart';
import 'src/app/dependency_scope.dart';
import 'src/diagnostics/diagnostics_service.dart';
import 'src/app/app_bootstrap.dart';
import 'src/app/default_platform_adapters.dart';
import 'src/android/android_preview_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final diagnostics = LocalDiagnosticsService();
  final startupTimer = Stopwatch()..start();
  diagnostics.record(DiagnosticEvent.appStarted);
  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    diagnostics.record(DiagnosticEvent.frameworkFailure,
        error: details.exception);
    previousFlutterHandler?.call(details);
  };
  final previousPlatformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    diagnostics.record(DiagnosticEvent.asyncFailure, error: error);
    return previousPlatformHandler?.call(error, stack) ?? false;
  };
  try {
    await _startApplication(diagnostics, startupTimer);
  } on Object catch (error) {
    diagnostics.record(DiagnosticEvent.appFailure, error: error);
    await diagnostics.flush();
    rethrow;
  }
}

Future<void> _startApplication(
    DiagnosticsService diagnostics, Stopwatch startupTimer) async {
  final dependencies = await bootstrapApplication(
      adapters: DefaultAppPlatformAdapters(), diagnostics: diagnostics);

  WidgetsBinding.instance.addPostFrameCallback((_) {
    diagnostics.record(DiagnosticEvent.appReady,
        fields: {DiagnosticField.elapsedMs: startupTimer.elapsedMilliseconds});
  });
  runApp(
    Platform.isAndroid
        ? AndroidPreviewApp(dependencies: dependencies)
        : _DependencyRoot(
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
    unawaited(widget.dependencies
        .dispose()
        .catchError((Object error, StackTrace stack) {
      // The owner already reported each cleanup failure. Widget disposal cannot
      // await shutdown; hosts that need a drain must await AppDependencies.dispose.
    }));
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
