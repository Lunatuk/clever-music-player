import '../models/library_sync_plan.dart';
import '../models/download_job.dart';
import '../models/external_track_ref.dart';
import '../models/remote_library.dart';
import '../models/track.dart';

typedef LocalDownloadCandidate = ({
  Track track,
  ExternalTrackIdentity identity
});

abstract interface class LocalDownloadCandidateRepository {
  /// A bounded batch of indexed, enabled files with embedded Yandex links.
  Future<List<LocalDownloadCandidate>> findLocalCandidates(
      Set<String> trackIds);
}

bool canUseLocalDownload(LibrarySyncPlanItem item) => switch (item.action) {
      LibrarySyncAction.createJob ||
      LibrarySyncAction.retryJob ||
      LibrarySyncAction.repairCompleted =>
        true,
      LibrarySyncAction.joinJob => item.job?.state == DownloadJobState.queued &&
          item.job?.stage == DownloadJobStage.download &&
          item.job?.attemptCount == 0,
      _ => false,
    };

Iterable<LocalDownloadCandidate> matchingLocalCandidates(
    ExternalTrackIdentity requested, List<LocalDownloadCandidate> candidates) {
  if (requested.provider != 'yandex_music') return const [];
  final matches = candidates.where((candidate) =>
      candidate.identity.provider == requested.provider &&
      candidate.identity.externalId == requested.externalId);
  if (requested.variantKey.isNotEmpty) {
    return matches.where((candidate) => candidate.identity == requested);
  }
  // A track-only request can use one unambiguous catalogue release.
  final releases = matches
      .map((candidate) => candidate.identity.variantKey)
      .where((id) => id.isNotEmpty)
      .toSet();
  return releases.length > 1 ? const [] : matches;
}

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
      {required DateTime now,
      Map<DownloadJobKey, LocalDownloadCandidate> localCopies = const {}});
}
