import '../models/download_job.dart';

/// Minimal lease access used by the filesystem publisher. A coordinator may
/// serialize these short fences with its own heartbeat on the same attempt.
abstract interface class PublicationJobAccess {
  Future<List<DownloadAttempt>> listAttempts(int jobId, {int limit = 50});
  Future<T?> withOwnedDestination<T extends Object>(DownloadJob expected,
      {required DateTime Function() clock,
      required Future<T> Function(String destinationPath) action});
}
