import '../models/library_sync_plan.dart';
import '../models/remote_library.dart';

abstract interface class LibrarySyncRepository {
  /// One database snapshot; null if the account or destination no longer exists
  /// or the account session has changed. No IO verification is performed here.
  Future<LibrarySyncSnapshot?> capture(RemoteLibraryAccount account,
      {required int libraryFolderId,
      required String quality,
      DateTime? minimumCompletedAt});

  /// Atomic job changes, not a completed network sync. Rechecks the full input
  /// and canonical plan; stale/blocked plans never partially change the queue.
  Future<LibrarySyncApplyResult> apply(LibrarySyncPlan plan,
      {required DateTime now});
}
