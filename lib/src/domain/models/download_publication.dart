import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'audio_source_reference.dart';
import 'download_job.dart';
import 'downloaded_asset.dart';
import 'document_publication_location.dart';
import 'metadata_source.dart';
import 'track.dart';

String downloadPublicationResourceKey(DownloadJobKey key) => sha256
    .convert(utf8.encode(jsonEncode([
      'cmp-publication-v1',
      key.identity.provider,
      key.identity.externalId,
      key.identity.variantKey,
    ])))
    .toString();

/// Prepared metadata and current file evidence. No file IO in the repository.
/// Caller holds its publication owner through the atomic commit. SAF evidence
/// is a fresh provider readback; it does not promise an OS byte seal.
final class DownloadedTrackImport {
  DownloadedTrackImport({
    required this.jobId,
    required this.key,
    required this.publicationId,
    required this.track,
    required this.verification,
    this.documentLocation,
  }) {
    if (jobId <= 0 ||
        publicationId.length != 64 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(publicationId) ||
        verification.actualQuality != key.quality ||
        !const {'mp3': 'mp3', 'm4a': 'aac', 'flac': 'flac'}.entries.any(
            (entry) =>
                entry.key == verification.container &&
                entry.value == verification.codec) ||
        track.id != null ||
        track.libraryFolderId != key.libraryFolderId ||
        (track.source is ContentUriAudioSource
            ? documentLocation == null ||
                documentLocation!.document != track.source ||
                documentLocation!.displayName != fileName
            : documentLocation != null) ||
        track.contentHash != verification.contentHash ||
        track.fileSizeBytes != verification.fileSizeBytes ||
        track.duration != verification.duration ||
        track.codec != verification.container ||
        track.isMissing ||
        track.metadataSource == MetadataSource.manual ||
        track.customArtworkPath != null ||
        track.customArtworkHash != null ||
        track.customArtworkMimeType != null) {
      throw ArgumentError('Некорректная подготовленная публикация.');
    }
  }

  final int jobId;
  final DownloadJobKey key;
  final String publicationId;
  final Track track;
  final DownloadedAssetVerification verification;
  final DocumentPublicationLocation? documentLocation;
  String get fileName => 'cmp-${downloadPublicationResourceKey(key)}-'
      '$publicationId.${verification.container}';
}

final class DownloadImportResult {
  const DownloadImportResult(
      {required this.job,
      required this.track,
      required this.asset,
      required this.replayed});
  final DownloadJob job;
  final Track track;
  final DownloadedAsset asset;
  final bool replayed;
}
