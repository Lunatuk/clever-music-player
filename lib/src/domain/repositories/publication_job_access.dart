import '../models/download_job.dart';

/// Minimal lease access used by platform publishers. A coordinator may
/// serialize these short fences with its own heartbeat on the same attempt.
abstract interface class PublicationJobAccess {
  Future<List<DownloadAttempt>> listAttempts(int jobId, {int limit = 50});
  Future<T?> withOwnedDestination<T extends Object>(DownloadJob expected,
      {required DateTime Function() clock,
      // Persisted file path or SAF tree URI, without path normalization.
      required Future<T> Function(String destinationPath) action});
}
