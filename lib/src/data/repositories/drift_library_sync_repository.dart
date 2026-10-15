import '../../domain/models/models.dart';
import '../../domain/repositories/library_sync_repository.dart';
import '../../domain/services/library_sync_planner.dart';
import '../drift/app_database.dart';
import 'drift_download_job_repository.dart';
import 'drift_downloaded_asset_repository.dart';
import 'drift_remote_library_repository.dart';

final class DriftLibrarySyncRepository implements LibrarySyncRepository {
  const DriftLibrarySyncRepository(this.database);
  final AppDatabase database;

  @override
  Future<LibrarySyncSnapshot?> capture(RemoteLibraryAccount account,
      {required int libraryFolderId,
      required String quality,
      DateTime? minimumCompletedAt}) {
    if (libraryFolderId <= 0) throw ArgumentError('Требуется назначение.');
    validateAssetQuality(quality);
    return database.transaction(
        () => _capture(account, libraryFolderId, quality, minimumCompletedAt));
  }

  Future<LibrarySyncSnapshot?> _capture(RemoteLibraryAccount account,
      int folderId, String quality, DateTime? minimumCompletedAt) async {
    final remote = DriftRemoteLibraryRepository(database);
    if (!account.isActive ||
        await remote.findAccount(account.identity) != account) {
      return null;
    }
    final folder = await (database.select(database.libraryFolders)
          ..where((t) => t.id.equals(folderId)))
        .getSingleOrNull();
    if (folder == null) return null;
    final selected =
        await remote.listCollections(account.identity, selectedOnly: true);
    if (selected.length > 256 ||
        selected.fold(0, (sum, source) => sum + source.itemCount) >
            LibrarySyncSnapshot.maxEntries) {
      throw StateError('Выбор слишком велик для одного снимка.');
    }
    final collections = <LibrarySyncCollection>[];
    final identities = <ExternalTrackIdentity>{};
    for (final source in selected) {
      final content = source.completedAt == null
          ? null
          : await remote.readContent(account.identity, source.key);
      if (source.completedAt != null &&
          (content == null || content.collection != source)) {
        throw StateError('Несогласованный состав коллекции.');
      }
      final items = content?.items;
      if (items != null) identities.addAll(items);
      collections.add(LibrarySyncCollection(collection: source, items: items));
    }
    final assets = await DriftDownloadedAssetRepository(database)
        .findCandidatesForFolder(quality: quality, libraryFolderId: folderId);
    final jobs = await DriftDownloadJobRepository(database)
        .listForDestination(folderId, provider: account.identity.provider);
    return LibrarySyncSnapshot(
        account: account,
        destination: LibrarySyncDestination(
            id: folder.id, path: folder.path, isEnabled: folder.isEnabled),
        quality: quality,
        collections: collections,
        assets: assets
            .where((asset) => identities.contains(asset.publication.identity)),
        jobs: jobs.where((job) =>
            (job.key.quality == quality &&
                identities.contains(job.key.identity)) ||
            (!job.isTerminal &&
                job.accountId == account.id &&
                job.accountRevision == account.revision)),
        minimumCompletedAt: minimumCompletedAt);
  }

  @override
  Future<LibrarySyncApplyResult> apply(LibrarySyncPlan plan,
      {required DateTime now}) async {
    if (!plan.isReady) {
      return LibrarySyncApplyResult(status: LibrarySyncApplyStatus.blocked);
    }
    try {
      return await database.transaction(() async {
        final input = plan.snapshot;
        final fresh = await _capture(input.account, input.destination.id,
            input.quality, input.minimumCompletedAt);
        if (fresh == null ||
            fresh != input ||
            const LibrarySyncPlanner()
                    .build(fresh, retryTerminalJobs: plan.retryTerminalJobs) !=
                plan) {
          throw const _StalePlan();
        }
        final jobs = DriftDownloadJobRepository(database);
        final scheduled = <DownloadJob>[];
        final cancelled = <DownloadJob>[];
        for (final obsolete in plan.obsoleteJobs) {
          final changed = await jobs.cancel(obsolete, now: now);
          if (changed == null) throw const _StalePlan();
          cancelled.add(changed);
        }
        final newKeys = plan.items
            .where((item) => item.action == LibrarySyncAction.createJob)
            .map((item) => item.key)
            .toList();
        for (var start = 0; start < newKeys.length; start += 64) {
          scheduled.addAll(await jobs.enqueue(input.account,
              newKeys.sublist(start, (start + 64).clamp(0, newKeys.length)),
              now: now));
        }
        for (final item in plan.items) {
          if (item.action == LibrarySyncAction.retryJob ||
              item.action == LibrarySyncAction.repairCompleted) {
            final changed = await jobs.retry(item.job!, input.account,
                now: now,
                repairCompleted:
                    item.action == LibrarySyncAction.repairCompleted);
            if (changed == null) throw const _StalePlan();
            scheduled.add(changed);
          }
        }
        return LibrarySyncApplyResult(
            status: LibrarySyncApplyStatus.applied,
            scheduledJobs: scheduled,
            cancelledJobs: cancelled);
      });
    } on _StalePlan {
      return LibrarySyncApplyResult(status: LibrarySyncApplyStatus.stale);
    }
  }
}

final class _StalePlan {
  const _StalePlan();
}
