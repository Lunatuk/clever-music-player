import '../models/download_job.dart';
import '../models/downloaded_asset.dart';
import '../models/external_track_ref.dart';
import '../models/library_sync_plan.dart';

/// Pure planning: no network, file reads, mutations or recommendation logic.
final class LibrarySyncPlanner {
  const LibrarySyncPlanner();
  LibrarySyncPlan build(LibrarySyncSnapshot snapshot,
      {bool retryTerminalJobs = false}) {
    final blockers = <LibrarySyncBlocker>{};
    final blockedCollections = <int>[];
    if (!snapshot.account.isActive) {
      blockers.add(LibrarySyncBlocker.inactiveAccount);
    }
    if (!snapshot.destination.isEnabled) {
      blockers.add(LibrarySyncBlocker.disabledDestination);
    }
    for (final source in snapshot.collections) {
      if (source.items == null) {
        blockers.add(LibrarySyncBlocker.missingSnapshot);
        blockedCollections.add(source.collection.id);
      } else if (snapshot.minimumCompletedAt != null &&
          source.collection.completedAt!
              .isBefore(snapshot.minimumCompletedAt!)) {
        blockers.add(LibrarySyncBlocker.staleSnapshot);
        blockedCollections.add(source.collection.id);
      }
    }
    if (blockers.isNotEmpty) {
      return LibrarySyncPlan(
          snapshot: snapshot,
          retryTerminalJobs: retryTerminalJobs,
          blockers: blockers,
          blockedCollectionIds: blockedCollections,
          items: const [],
          obsoleteJobs: const []);
    }

    final memberships = <ExternalTrackIdentity, Map<int, int>>{};
    for (final source in snapshot.collections) {
      for (final identity in source.items!) {
        final counts = memberships.putIfAbsent(identity, () => {});
        counts.update(source.collection.id, (count) => count + 1,
            ifAbsent: () => 1);
      }
    }
    final assets = <ExternalTrackIdentity, List<DownloadedAsset>>{};
    for (final asset in snapshot.assets) {
      if (asset.state == DownloadedAssetState.verified &&
          asset.verification.actualQuality == snapshot.quality &&
          asset.publication.identity.provider ==
              snapshot.account.identity.provider) {
        assets.putIfAbsent(asset.publication.identity, () => []).add(asset);
      }
    }
    final jobs = {for (final job in snapshot.jobs) job.key: job};
    final items = <LibrarySyncPlanItem>[];
    for (final entry in memberships.entries) {
      final key = DownloadJobKey(
          libraryFolderId: snapshot.destination.id,
          identity: entry.key,
          quality: snapshot.quality);
      final job = jobs[key];
      final candidates = assets[entry.key] ?? const <DownloadedAsset>[];
      LibrarySyncAction action;
      LibrarySyncItemReason? reason;
      if (job != null && !job.isTerminal) {
        final currentSession = job.accountId == snapshot.account.id &&
            job.accountRevision == snapshot.account.revision;
        action = currentSession
            ? LibrarySyncAction.joinJob
            : LibrarySyncAction.needsAction;
        if (!currentSession) reason = LibrarySyncItemReason.otherSession;
      } else if (candidates.isNotEmpty) {
        action = LibrarySyncAction.checkExisting;
      } else if (job == null) {
        action = LibrarySyncAction.createJob;
      } else if (job.state == DownloadJobState.completed) {
        action = LibrarySyncAction.repairCompleted;
      } else {
        action = retryTerminalJobs
            ? LibrarySyncAction.retryJob
            : LibrarySyncAction.needsAction;
        reason = job.state == DownloadJobState.failed
            ? LibrarySyncItemReason.failedJob
            : LibrarySyncItemReason.cancelledJob;
      }
      items.add(LibrarySyncPlanItem(
          key: key,
          action: action,
          memberships: entry.value.entries
              .map((source) => LibrarySyncMembership(source.key, source.value)),
          candidates: candidates,
          job: job,
          reason: reason));
    }
    final desired = items.map((item) => item.key).toSet();
    final obsolete = snapshot.jobs.where((job) =>
        !job.isTerminal &&
        job.accountId == snapshot.account.id &&
        job.accountRevision == snapshot.account.revision &&
        !desired.contains(job.key));
    return LibrarySyncPlan(
        snapshot: snapshot,
        retryTerminalJobs: retryTerminalJobs,
        blockers: const [],
        blockedCollectionIds: const [],
        items: items,
        obsoleteJobs: obsolete);
  }
}
