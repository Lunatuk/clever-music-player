import 'package:clever_music_player/src/android/android_publication_receipt.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library_sync/publication_intent.dart';

import 'download_fixture.dart';

final androidPublicationTree =
    ContentUriAudioSource('content://music.documents/tree/primary%3AMusic');

Future<DownloadFixture> androidPublicationFixture(
    {bool persistent = false}) async {
  final f = await DownloadFixture.open(persistent: persistent);
  await f.database.customStatement(
      'UPDATE library_folders SET path = ? WHERE id = ?',
      [androidPublicationTree.storageValue, f.folderId]);
  return f;
}

AndroidPublicationReceipt androidReceipt(DownloadFixture f, DownloadJob job,
    {String? id,
    ContentUriAudioSource? tree,
    String documentId = 'opaque-123'}) {
  final intent = PublicationIntent(
      publicationId: id ?? 'a' * 64,
      jobId: job.id,
      key: job.key,
      verification: f.proof());
  final root = tree ?? androidPublicationTree;
  final document = ContentUriAudioSource(Uri(
      scheme: 'content',
      host: root.uri.authority,
      pathSegments: [
        'tree',
        root.uri.pathSegments[1],
        'document',
        documentId
      ]).toString());
  return AndroidPublicationReceipt(
      intent: intent,
      location: DocumentPublicationLocation(
          tree: root, document: document, displayName: intent.fileName));
}

Track androidPreparedTrack(DownloadFixture f, DownloadJob job,
        AndroidPublicationReceipt receipt) =>
    f
        .publication(job)
        .track
        .copyWith(filePath: receipt.location.document.storageValue);
