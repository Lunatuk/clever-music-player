import 'package:drift/drift.dart';

import '../../domain/models/download_job.dart';
import '../../domain/models/download_publication.dart';
import '../../domain/models/downloaded_asset.dart';
import '../../domain/models/document_publication_location.dart';
import '../../domain/models/external_track_ref.dart';
import '../../domain/repositories/download_import_repository.dart';
import '../drift/app_database.dart';
import 'drift_download_job_repository.dart';
import 'drift_downloaded_asset_repository.dart';
import 'drift_external_track_repository.dart';
import 'drift_repositories.dart';

final class DriftDownloadImportRepository implements DownloadImportRepository {
  const DriftDownloadImportRepository(this.database);
  final AppDatabase database;

  @override
  Future<DownloadImportResult?> commit(
      DownloadJob expected, DownloadedTrackImport publication,
      {required DateTime Function() clock}) async {
    if (publication.jobId != expected.id ||
        publication.key != expected.key ||
        expected.stage != DownloadJobStage.importing) {
      throw ArgumentError('Другой контекст импорта.');
    }
    final jobs = DriftDownloadJobRepository(database);
    final tracks = DriftTrackRepository(database);
    final assets = DriftDownloadedAssetRepository(database);
    if (expected.state != DownloadJobState.running &&
        expected.state != DownloadJobState.completed) {
      return null;
    }
    try {
      return await database.transaction(() async {
        // Reserve the writer before any reads, including acknowledgement replay.
        await database.customUpdate(
            'UPDATE download_jobs SET revision = revision WHERE id = ?',
            variables: [Variable.withInt(expected.id)],
            updates: {});
        final current = await jobs.findByKey(expected.key);
        if (current == null || current.id != expected.id) return null;
        if (current.state == DownloadJobState.completed) {
          return _replay(expected, current, publication, clock());
        }
        return jobs.withOwnedDestination(expected, clock: clock,
            action: (path) async {
          if (!_destinationMatches(publication, path)) {
            throw StateError(
                'Источник не соответствует назначению публикации.');
          }
          final existing = await tracks.findByPath(publication.track.filePath);
          if (existing != null &&
              existing.libraryFolderId != expected.key.libraryFolderId) {
            throw StateError('Источник уже принадлежит другой библиотеке.');
          }
          if (existing != null) {
            final asset = await assets.findForTrack(existing.id!);
            if (asset != null &&
                (asset.publication.publicationId != publication.publicationId ||
                    asset.publication.identity != expected.key.identity ||
                    !asset.verification
                        .describesSameBytes(publication.verification))) {
              throw StateError(
                  'В назначении зарегистрирована другая публикация.');
            }
          }
          final id =
              (await tracks.upsertScannedTracks([publication.track])).single;
          await DriftExternalTrackRepository(database).linkAll([
            ExternalTrackRef(
                trackId: id,
                identity: expected.key.identity,
                origin: ExternalTrackRefOrigin.providerResponse,
                linkedAt: publication.verification.checkedAt),
          ]);
          var asset = await assets.registerVerified(
              DownloadedAssetPublication(
                  trackId: id,
                  identity: expected.key.identity,
                  source: publication.track.source,
                  publicationId: publication.publicationId,
                  requestedQuality: expected.key.quality),
              publication.verification);
          if (asset.state != DownloadedAssetState.verified ||
              asset.verification != publication.verification) {
            if (!await assets.confirm(asset, publication.verification)) {
              throw const _ImportOwnershipLost();
            }
            asset = (await assets.findForTrack(id))!;
          }
          final completed = await jobs.complete(expected, asset, now: clock());
          // Throw through every savepoint: returning null here would commit Track.
          if (completed == null) throw const _ImportOwnershipLost();
          return DownloadImportResult(
              job: completed,
              track: (await tracks.findById(id))!,
              asset: asset,
              replayed: false);
        });
      });
    } on _ImportOwnershipLost {
      return null;
    }
  }

  Future<DownloadImportResult?> _replay(
      DownloadJob expected,
      DownloadJob current,
      DownloadedTrackImport publication,
      DateTime now) async {
    if (current.accountId != expected.accountId ||
        current.accountRevision != expected.accountRevision ||
        current.attemptCount != expected.attemptCount ||
        now.isBefore(current.updatedAt) ||
        publication.verification.checkedAt.isAfter(now) ||
        (expected.state == DownloadJobState.completed
            ? current != expected
            : current.revision != expected.revision + 1)) {
      return null;
    }
    final account = await (database.select(database.remoteAccounts)
          ..where((t) => t.id.equals(current.accountId)))
        .getSingleOrNull();
    final folder = await (database.select(database.libraryFolders)
          ..where((t) => t.id.equals(current.key.libraryFolderId)))
        .getSingleOrNull();
    final attempts = await DriftDownloadJobRepository(database)
        .listAttempts(current.id, limit: 1);
    if (account == null ||
        !account.isActive ||
        account.revision != current.accountRevision ||
        account.provider != current.key.identity.provider ||
        folder == null ||
        !folder.isEnabled ||
        !_destinationMatches(publication, folder.path) ||
        attempts.isEmpty ||
        attempts.single.outcome != DownloadAttemptOutcome.completed ||
        (expected.attemptToken != null &&
            attempts.single.token != expected.attemptToken)) {
      return null;
    }
    final tracks = DriftTrackRepository(database);
    final track = await tracks.findById(current.completedTrackId!);
    final asset = await DriftDownloadedAssetRepository(database)
        .findForTrack(current.completedTrackId!);
    if (track == null ||
        track.isMissing ||
        track.libraryFolderId != current.key.libraryFolderId ||
        track.filePath != publication.track.filePath ||
        track.contentHash != publication.verification.contentHash ||
        track.fileSizeBytes != publication.verification.fileSizeBytes ||
        asset == null ||
        asset.state != DownloadedAssetState.verified ||
        asset.publication.publicationId != publication.publicationId ||
        asset.publication.identity != current.key.identity ||
        asset.publication.requestedQuality != current.key.quality ||
        asset.publication.source != track.source ||
        !asset.verification.describesSameBytes(publication.verification)) {
      return null;
    }
    if (!(await DriftExternalTrackRepository(database).listForTrack(track.id!))
        .any((ref) => ref.identity == current.key.identity)) {
      return null;
    }
    return DownloadImportResult(
        job: current, track: track, asset: asset, replayed: true);
  }
}

bool _destinationMatches(DownloadedTrackImport publication, String path) =>
    publicationSourceMatchesDestination(
        source: publication.track.source,
        destination: path,
        fileName: publication.fileName,
        documentLocation: publication.documentLocation);

final class _ImportOwnershipLost implements Exception {
  const _ImportOwnershipLost();
}
