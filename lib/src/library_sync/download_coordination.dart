import '../domain/models/models.dart';

enum DownloadCoordinationOutcome {
  completed,
  requiresDownload,
  cancelled,
  ownershipLost,
  busy,
  failed,
  needsReconciliation,
}

final class DownloadCoordinationResult {
  const DownloadCoordinationResult(
      {required this.outcome,
      required this.job,
      this.imported,
      this.failure,
      this.cleanupFailed = false});
  final DownloadCoordinationOutcome outcome;
  final DownloadJob job;
  final DownloadImportResult? imported;
  final DownloadFailure? failure;
  final bool cleanupFailed;
}
