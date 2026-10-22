import 'package:drift/drift.dart';

import '../../domain/models/download_job.dart';
import '../../domain/models/download_publication.dart';
import '../../domain/models/downloaded_asset.dart';
import '../../domain/models/document_publication_location.dart';
import '../../domain/models/audio_source_reference.dart';
import '../../domain/models/publication_cleanup.dart';
import '../../domain/repositories/publication_retention_repository.dart';
import '../drift/app_database.dart';
import 'drift_download_job_repository.dart';
import 'drift_downloaded_asset_repository.dart';
import 'drift_repositories.dart';

final class DriftPublicationRetentionRepository
    implements PublicationRetentionRepository {
  const DriftPublicationRetentionRepository(this.database);
  final AppDatabase database;

  @override
  Future<T?> withCleanupAuthority<T extends Object>(
          PublicationCleanupRequest request,
          {required DateTime notUpdatedAfter,
          required DateTime Function() clock,
          required Future<T> Function(String destinationPath) action}) =>
      database.transaction(() async {
        if (request.jobId <= 0 ||
            RegExp(r'^[0-9a-f]{64}$').stringMatch(request.publicationId) !=
                request.publicationId) {
          return null;
        }
        await database.customUpdate(
            'UPDATE download_jobs SET revision = revision WHERE id = ?',
            variables: [Variable.withInt(request.jobId)],
            updates: {});
        final job =
            await DriftDownloadJobRepository(database).findByKey(request.key);
        final now = clock();
        if (job == null ||
            job.id != request.jobId ||
            !job.isTerminal ||
            job.updatedAt.isAfter(notUpdatedAfter) ||
            notUpdatedAfter.isAfter(now)) {
          return null;
        }
        final folder = await (database.select(database.libraryFolders)
              ..where((t) => t.id.equals(request.key.libraryFolderId)))
            .getSingleOrNull();
        if (folder == null || !folder.isEnabled) return null;
        if (request.kind == PublicationCleanupKind.abandoned) {
          // Android abandoned/create intents need a separate provider policy.
          if (request.documentLocation != null ||
              AudioSourceReference.isContentUriValue(folder.path)) {
            return null;
          }
          if (job.state != DownloadJobState.failed &&
              job.state != DownloadJobState.cancelled) {
            return null;
          }
        } else {
          final proof = request.verification;
          if (job.state != DownloadJobState.completed ||
              job.completedTrackId == null ||
              proof == null ||
              proof.checkedAt.isAfter(now)) {
            return null;
          }
          final track = await DriftTrackRepository(database)
              .findById(job.completedTrackId!);
          final asset = await DriftDownloadedAssetRepository(database)
              .findForTrack(job.completedTrackId!);
          final fileName = 'cmp-${downloadPublicationResourceKey(request.key)}-'
              '${request.publicationId}.${proof.container}';
          if (track == null ||
              track.isMissing ||
              track.libraryFolderId != request.key.libraryFolderId ||
              !publicationSourceMatchesDestination(
                  source: track.source,
                  destination: folder.path,
                  fileName: fileName,
                  documentLocation: request.documentLocation) ||
              track.contentHash != proof.contentHash ||
              track.fileSizeBytes != proof.fileSizeBytes ||
              asset == null ||
              asset.state != DownloadedAssetState.verified ||
              asset.publication.publicationId != request.publicationId ||
              asset.publication.identity != request.key.identity ||
              asset.publication.requestedQuality != request.key.quality ||
              asset.publication.source != track.source ||
              !asset.verification.describesSameBytes(proof)) {
            return null;
          }
        }
        return action(folder.path);
      });
}
