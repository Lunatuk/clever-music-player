import 'download_job.dart';
import 'downloaded_asset.dart';
import 'document_publication_location.dart';

enum PublicationCleanupKind { imported, abandoned }

/// Deletes only a publication's private journal/staging, never its final audio.
final class PublicationCleanupRequest {
  const PublicationCleanupRequest({
    required this.jobId,
    required this.key,
    required this.publicationId,
    required this.kind,
    this.verification,
    this.documentLocation,
  });
  final int jobId;
  final DownloadJobKey key;
  final String publicationId;
  final PublicationCleanupKind kind;
  final DownloadedAssetVerification? verification;
  final DocumentPublicationLocation? documentLocation;
}
