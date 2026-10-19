import '../diagnostics/diagnostics_service.dart';

enum AppResource {
  mediaControls,
  queue,
  player,
  library,
  database,
  diagnostics,
  audioDeck,
  assetVerification,
  remoteLibrary,
  libraryUpdate
}

final class AppCleanupAction {
  const AppCleanupAction(this.resource, this.close);
  final AppResource resource;
  final Future<void> Function() close;
}

final class AppCleanupFailure {
  const AppCleanupFailure(this.error, this.stack);
  final Object error;
  final StackTrace stack;
  Never rethrowError() => Error.throwWithStackTrace(error, stack);
}

/// Attempts every action. Preserves the first failure and reports fixed numeric
/// resource codes only; a diagnostics failure cannot interrupt other cleanup.
Future<AppCleanupFailure?> closeAppResources(
    Iterable<AppCleanupAction> actions, DiagnosticsService diagnostics) async {
  AppCleanupFailure? first;
  for (final action in actions) {
    try {
      await Future<void>.sync(action.close);
    } on Object catch (error, stack) {
      first ??= AppCleanupFailure(error, stack);
      try {
        diagnostics.record(DiagnosticEvent.appCleanupFailed,
            error: error,
            fields: {DiagnosticField.cleanupStage: action.resource.index + 1});
      } on Object {/* Reporting must not prevent resource cleanup. */}
    }
  }
  return first;
}
