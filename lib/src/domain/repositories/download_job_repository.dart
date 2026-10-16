import '../models/download_job.dart';
import '../models/downloaded_asset.dart';
import '../models/remote_library.dart';
import 'publication_job_access.dart';

abstract interface class DownloadJobRepository implements PublicationJobAccess {
  /// At most 64 keys, atomic; repeats attach to existing work without resetting
  /// attempts, session binding, terminal state or a completed resource.
  Future<List<DownloadJob>> enqueue(
      RemoteLibraryAccount account, Iterable<DownloadJobKey> keys,
      {required DateTime now, int maxAttempts = 3});
  Future<DownloadJob?> findByKey(DownloadJobKey key);

  /// Complete destination/provider set (all qualities/sessions), bounded at
  /// 100 000 rows. Exceeding the bound fails explicitly instead of truncating.
  Future<List<DownloadJob>> listForDestination(int libraryFolderId,
      {required String provider});
  Future<List<DownloadJob>> listJobs(
      {DownloadJobState? state, int limit = 100});
  @override
  Future<List<DownloadAttempt>> listAttempts(int jobId, {int limit = 50});
  Future<DownloadJob?> claimNext(RemoteLibraryAccount account,
      {required DateTime now, Duration leaseFor = const Duration(seconds: 30)});
  Future<DownloadJob?> renewLease(DownloadJob expected,
      {required DateTime now, Duration leaseFor = const Duration(seconds: 30)});
  Future<DownloadJob?> advance(DownloadJob expected, DownloadJobStage next,
      {required DateTime now});

  /// Reconciliation may rewind, never skip ahead of the persisted checkpoint.
  Future<DownloadJob?> resolveReconciliation(
      DownloadJob expected, DownloadJobStage resumeAt,
      {required DateTime now});
  Future<DownloadJob?> complete(DownloadJob expected, DownloadedAsset asset,
      {required DateTime now});
  Future<DownloadJob?> fail(DownloadJob expected, DownloadFailure reason,
      {required DateTime now, DateTime? retryAt});
  Future<DownloadJob?> cancel(DownloadJob expected, {required DateTime now});

  /// Release a current attempt whose physical result needs inspection. Does
  /// not reset its budget or delete files; exhausted work requires manual retry.
  Future<DownloadJob?> interrupt(DownloadJob expected,
      {required DateTime now,
      DownloadFailure reason = DownloadFailure.interrupted});

  /// Explicit manual retry resets the finite budget; completed work requires
  /// explicit repair intent and still goes through physical reconciliation.
  Future<DownloadJob?> retry(DownloadJob expected, RemoteLibraryAccount account,
      {required DateTime now, bool repairCompleted = false});

  /// Only expired leases: startup never steals work from another live runner.
  Future<int> recoverExpired({required DateTime now});

  /// Holds SQLite's writer reservation while a SHORT physical effect is accepted.
  /// Rechecks the full lease/session/folder after obtaining the reservation.
  /// Never hash, download, decode or call another connection inside [action].
  /// The filesystem effect cannot be rolled back with SQLite: journal first.
  @override
  Future<T?> withOwnedDestination<T extends Object>(DownloadJob expected,
      {required DateTime Function() clock,
      required Future<T> Function(String destinationPath) action});
}
