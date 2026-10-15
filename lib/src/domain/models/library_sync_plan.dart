import 'download_job.dart';
import 'downloaded_asset.dart';
import 'external_track_ref.dart';
import 'remote_library.dart';

enum LibrarySyncAction {
  checkExisting,
  createJob,
  joinJob,
  retryJob,
  repairCompleted,
  needsAction
}

enum LibrarySyncBlocker {
  inactiveAccount,
  disabledDestination,
  missingSnapshot,
  staleSnapshot
}

enum LibrarySyncItemReason { failedJob, cancelledJob, otherSession }

enum LibrarySyncApplyStatus { applied, stale, blocked }

final class LibrarySyncDestination {
  const LibrarySyncDestination(
      {required this.id, required this.path, required this.isEnabled});
  final int id;
  final String path;
  final bool isEnabled;
  @override
  bool operator ==(Object other) =>
      other is LibrarySyncDestination &&
      id == other.id &&
      path == other.path &&
      isEnabled == other.isEnabled;
  @override
  int get hashCode => Object.hash(id, path, isEnabled);
}

/// Null items means the selected collection has never been completely fetched.
final class LibrarySyncCollection {
  LibrarySyncCollection(
      {required this.collection, Iterable<ExternalTrackIdentity>? items})
      : items = items == null
            ? null
            : _bounded(items, LibrarySyncSnapshot.maxEntries) {
    if ((collection.completedAt == null) != (this.items == null) ||
        (this.items != null && this.items!.length != collection.itemCount)) {
      throw ArgumentError('Несогласованный снимок коллекции.');
    }
  }
  final RemoteLibraryCollection collection;
  final List<ExternalTrackIdentity>? items;
  @override
  bool operator ==(Object other) =>
      other is LibrarySyncCollection &&
      collection == other.collection &&
      ((items == null && other.items == null) ||
          (items != null &&
              other.items != null &&
              syncListsEqual(items!, other.items!)));
  @override
  int get hashCode =>
      Object.hash(collection, items == null ? null : Object.hashAll(items!));
}

/// A consistent database input. Assets are database candidates for this exact
/// destination; none is proof that a physical file is still accessible.
final class LibrarySyncSnapshot {
  factory LibrarySyncSnapshot(
      {required RemoteLibraryAccount account,
      required LibrarySyncDestination destination,
      required String quality,
      required Iterable<LibrarySyncCollection> collections,
      required Iterable<DownloadedAsset> assets,
      required Iterable<DownloadJob> jobs,
      DateTime? minimumCompletedAt}) {
    validateAssetQuality(quality);
    if (destination.id <= 0 || destination.path.isEmpty) {
      throw ArgumentError('Требуется назначение.');
    }
    final copiedCollections = _bounded(collections, 256);
    final copiedAssets = _bounded(assets, maxEntries);
    final copiedJobs = _bounded(jobs, maxEntries);
    var occurrences = 0;
    final collectionIds = <int>{};
    for (final source in copiedCollections) {
      if (!source.collection.isSelected ||
          source.collection.account != account.identity ||
          !collectionIds.add(source.collection.id)) {
        throw ArgumentError('Неверный выбор коллекций.');
      }
      occurrences += source.items?.length ?? 0;
      if (occurrences > maxEntries ||
          source.items
                  ?.any((item) => item.provider != account.identity.provider) ==
              true) {
        throw ArgumentError('Некорректный или слишком большой состав.');
      }
    }
    final jobKeys = <DownloadJobKey>{};
    for (final job in copiedJobs) {
      if (job.key.libraryFolderId != destination.id ||
          job.key.identity.provider != account.identity.provider ||
          !jobKeys.add(job.key)) {
        throw ArgumentError('Несогласованные задания назначения.');
      }
    }
    return LibrarySyncSnapshot._(
        account,
        destination,
        quality,
        copiedCollections,
        copiedAssets,
        copiedJobs,
        minimumCompletedAt?.toUtc());
  }
  const LibrarySyncSnapshot._(this.account, this.destination, this.quality,
      this.collections, this.assets, this.jobs, this.minimumCompletedAt);
  static const maxEntries = 100000;
  final RemoteLibraryAccount account;
  final LibrarySyncDestination destination;
  final String quality;
  final List<LibrarySyncCollection> collections;
  final List<DownloadedAsset> assets;
  final List<DownloadJob> jobs;
  final DateTime? minimumCompletedAt;
  @override
  bool operator ==(Object other) =>
      other is LibrarySyncSnapshot &&
      account == other.account &&
      destination == other.destination &&
      quality == other.quality &&
      minimumCompletedAt == other.minimumCompletedAt &&
      syncListsEqual(collections, other.collections) &&
      syncListsEqual(assets, other.assets) &&
      syncListsEqual(jobs, other.jobs);
  @override
  int get hashCode => Object.hash(
      account,
      destination,
      quality,
      minimumCompletedAt,
      Object.hashAll(collections),
      Object.hashAll(assets),
      Object.hashAll(jobs));
}

final class LibrarySyncMembership {
  const LibrarySyncMembership(this.collectionId, this.occurrences);
  final int collectionId, occurrences;
  @override
  bool operator ==(Object other) =>
      other is LibrarySyncMembership &&
      collectionId == other.collectionId &&
      occurrences == other.occurrences;
  @override
  int get hashCode => Object.hash(collectionId, occurrences);
}

final class LibrarySyncPlanItem {
  LibrarySyncPlanItem(
      {required this.key,
      required this.action,
      required Iterable<LibrarySyncMembership> memberships,
      required Iterable<DownloadedAsset> candidates,
      this.job,
      this.reason})
      : memberships = List.unmodifiable(memberships),
        candidates = List.unmodifiable(candidates);
  final DownloadJobKey key;
  final LibrarySyncAction action;
  final List<LibrarySyncMembership> memberships;
  final List<DownloadedAsset> candidates;
  final DownloadJob? job;
  final LibrarySyncItemReason? reason;
  @override
  bool operator ==(Object other) =>
      other is LibrarySyncPlanItem &&
      key == other.key &&
      action == other.action &&
      job == other.job &&
      reason == other.reason &&
      syncListsEqual(memberships, other.memberships) &&
      syncListsEqual(candidates, other.candidates);
  @override
  int get hashCode => Object.hash(key, action, job, reason,
      Object.hashAll(memberships), Object.hashAll(candidates));
}

/// Immutable and reviewable; application re-derives the canonical plan before
/// writing, so manually constructed or outdated commands cannot change jobs.
final class LibrarySyncPlan {
  LibrarySyncPlan(
      {required this.snapshot,
      required this.retryTerminalJobs,
      required Iterable<LibrarySyncBlocker> blockers,
      required Iterable<int> blockedCollectionIds,
      required Iterable<LibrarySyncPlanItem> items,
      required Iterable<DownloadJob> obsoleteJobs})
      : blockers = List.unmodifiable(blockers),
        blockedCollectionIds = List.unmodifiable(blockedCollectionIds),
        items = List.unmodifiable(items),
        obsoleteJobs = List.unmodifiable(obsoleteJobs);
  final LibrarySyncSnapshot snapshot;
  final bool retryTerminalJobs;
  final List<LibrarySyncBlocker> blockers;
  final List<int> blockedCollectionIds;
  final List<LibrarySyncPlanItem> items;
  final List<DownloadJob> obsoleteJobs;
  bool get isReady => blockers.isEmpty;
  int get sourceOccurrences => items.fold(
      0,
      (sum, item) =>
          sum +
          item.memberships.fold(0, (sum, source) => sum + source.occurrences));
  @override
  bool operator ==(Object other) =>
      other is LibrarySyncPlan &&
      snapshot == other.snapshot &&
      retryTerminalJobs == other.retryTerminalJobs &&
      syncListsEqual(blockers, other.blockers) &&
      syncListsEqual(blockedCollectionIds, other.blockedCollectionIds) &&
      syncListsEqual(items, other.items) &&
      syncListsEqual(obsoleteJobs, other.obsoleteJobs);
  @override
  int get hashCode => Object.hash(
      snapshot,
      retryTerminalJobs,
      Object.hashAll(blockers),
      Object.hashAll(blockedCollectionIds),
      Object.hashAll(items),
      Object.hashAll(obsoleteJobs));
}

final class LibrarySyncApplyResult {
  LibrarySyncApplyResult(
      {required this.status,
      Iterable<DownloadJob> scheduledJobs = const [],
      Iterable<DownloadJob> cancelledJobs = const []})
      : scheduledJobs = List.unmodifiable(scheduledJobs),
        cancelledJobs = List.unmodifiable(cancelledJobs);
  final LibrarySyncApplyStatus status;
  final List<DownloadJob> scheduledJobs, cancelledJobs;
}

bool syncListsEqual<T>(List<T> first, List<T> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

List<T> _bounded<T>(Iterable<T> values, int limit) {
  final copy = <T>[];
  for (final value in values) {
    if (copy.length == limit) {
      throw ArgumentError('Превышен предел снимка синхронизации.');
    }
    copy.add(value);
  }
  return List.unmodifiable(copy);
}
