import 'dart:convert';

import '../domain/models/download_job.dart';
import '../domain/models/downloaded_asset.dart';
import '../domain/models/external_track_ref.dart';
import '../library/sha256_digest.dart';

enum PublicationFailure {
  ownershipLost,
  busy,
  collision,
  unsafePath,
  invalidJournal,
  invalidStaging,
  changed,
  needsReconciliation,
  unsupported,
  io,
}

final class PublicationException implements Exception {
  const PublicationException(this.reason);
  final PublicationFailure reason;
}

String publicationResourceKey(DownloadJobKey key) =>
    sha256Hex(utf8.encode(jsonEncode([
      'cmp-publication-v1',
      key.identity.provider,
      key.identity.externalId,
      key.identity.variantKey
    ])));

bool isPublicationId(String value) =>
    RegExp(r'^[0-9a-f]{64}$').stringMatch(value) == value;

/// Immutable intent, before the physical effect. No absolute paths/URLs/secrets.
final class PublicationIntent {
  PublicationIntent(
      {required this.publicationId,
      required this.jobId,
      required this.key,
      required this.verification}) {
    if (!isPublicationId(publicationId) ||
        jobId <= 0 ||
        verification.actualQuality != key.quality ||
        verification.fileSizeBytes > 8 * 1024 * 1024 * 1024 ||
        verification.duration > const Duration(hours: 12) ||
        !const {'mp3': 'mp3', 'm4a': 'aac', 'flac': 'flac'}.entries.any(
            (entry) =>
                entry.key == verification.container &&
                entry.value == verification.codec)) {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
  }
  final String publicationId;
  final int jobId;
  final DownloadJobKey key;
  final DownloadedAssetVerification verification;
  String get resourceKey => publicationResourceKey(key);
  String get operationName => '$resourceKey-$publicationId';
  String get fileName =>
      'cmp-$resourceKey-$publicationId.${verification.container}';

  String encode() => jsonEncode({
        'version': 1,
        'publicationId': publicationId,
        'jobId': jobId,
        'folderId': key.libraryFolderId,
        'provider': key.identity.provider,
        'externalId': key.identity.externalId,
        'variantKey': key.identity.variantKey,
        'quality': key.quality,
        'container': verification.container,
        'codec': verification.codec,
        'sizeBytes': verification.fileSizeBytes,
        'durationMs': verification.duration.inMilliseconds,
        'sha256': verification.contentHash,
        'checkedAtUs': verification.checkedAt.microsecondsSinceEpoch,
      });

  static PublicationIntent decode(String value) {
    try {
      if (utf8.encode(value).length > 16384) throw const FormatException();
      final decoded = jsonDecode(value);
      const keys = {
        'version',
        'publicationId',
        'jobId',
        'folderId',
        'provider',
        'externalId',
        'variantKey',
        'quality',
        'container',
        'codec',
        'sizeBytes',
        'durationMs',
        'sha256',
        'checkedAtUs'
      };
      if (decoded is! Map<String, dynamic> ||
          decoded.length != keys.length ||
          !decoded.keys.every(keys.contains) ||
          decoded['version'] is! int ||
          decoded['version'] != 1) {
        throw const FormatException();
      }
      int number(String key) {
        final n = decoded[key];
        if (n is! int || n <= 0) throw const FormatException();
        return n;
      }

      String string(String key) {
        final text = decoded[key];
        if (text is! String) throw const FormatException();
        return text;
      }

      final result = PublicationIntent(
          publicationId: string('publicationId'),
          jobId: number('jobId'),
          key: DownloadJobKey(
              libraryFolderId: number('folderId'),
              identity: ExternalTrackIdentity(
                  provider: string('provider'),
                  externalId: string('externalId'),
                  variantKey: string('variantKey')),
              quality: string('quality')),
          verification: DownloadedAssetVerification(
              actualQuality: string('quality'),
              container: string('container'),
              codec: string('codec'),
              fileSizeBytes: number('sizeBytes'),
              duration: Duration(milliseconds: number('durationMs')),
              contentHash: string('sha256'),
              checkedAt: DateTime.fromMicrosecondsSinceEpoch(
                  number('checkedAtUs'),
                  isUtc: true)));
      if (result.encode() != value) throw const FormatException();
      return result;
    } on Object {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
  }
}

/// Filesystem publication only. The job/Track/asset import remains a later step.
final class PublicationReceipt {
  const PublicationReceipt(
      {required this.intent,
      required this.filePath,
      required this.verification,
      required this.recovered});
  final PublicationIntent intent;
  final String filePath;
  final DownloadedAssetVerification verification;
  final bool recovered;
}
