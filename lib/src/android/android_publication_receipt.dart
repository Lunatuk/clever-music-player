import 'dart:convert';

import '../domain/models/models.dart';
import '../library_sync/publication_intent.dart';

/// Durable evidence of a completed provider write, never evidence that the
/// current bytes still match. Recovery must re-read the document before import.
final class AndroidPublicationReceipt {
  AndroidPublicationReceipt({required this.intent, required this.location}) {
    if (location.displayName != intent.fileName) {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
  }
  final PublicationIntent intent;
  final DocumentPublicationLocation location;
  String get recordName => '${intent.operationName}.json';
  String encode() => jsonEncode({
        'version': 1,
        'intent': intent.encode(),
        'tree': location.tree.storageValue,
        'document': location.document.storageValue,
        'displayName': location.displayName,
      });

  static AndroidPublicationReceipt decode(String value) {
    try {
      if (utf8.encode(value).length > 65536) throw const FormatException();
      final data = jsonDecode(value) as Map<String, dynamic>;
      if (data['version'] is! int || data['version'] != 1) {
        throw const FormatException();
      }
      final receipt = AndroidPublicationReceipt(
          intent: PublicationIntent.decode(data['intent'] as String),
          location: DocumentPublicationLocation(
              tree: ContentUriAudioSource(data['tree'] as String),
              document: ContentUriAudioSource(data['document'] as String),
              displayName: data['displayName'] as String));
      if (receipt.encode() != value) throw const FormatException();
      return receipt;
    } on Object {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
  }

  DownloadedTrackImport importTrack(
      Track track, DownloadedAssetVerification currentVerification) {
    if (!intent.verification.describesSameBytes(currentVerification) ||
        currentVerification.checkedAt.isBefore(intent.verification.checkedAt)) {
      throw const PublicationException(PublicationFailure.changed);
    }
    return DownloadedTrackImport(
        jobId: intent.jobId,
        key: intent.key,
        publicationId: intent.publicationId,
        verification: currentVerification,
        documentLocation: location,
        track: track);
  }
}
