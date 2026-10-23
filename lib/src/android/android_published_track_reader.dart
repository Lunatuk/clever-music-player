import '../domain/models/models.dart';
import '../library/artwork_cache_service.dart';
import '../library/library_scan_control.dart';
import '../library/metadata_enrichment.dart';
import '../library/stable_track_id.dart';
import '../library_sync/publication_intent.dart';
import 'android_publication_receipt.dart';
import 'audio_documents.dart';

/// Metadata from the published document, never guesses from its opaque name.
/// Caller must freshly verify document bytes AFTER this read and before commit.
final class AndroidPublishedTrackReader {
  AndroidPublishedTrackReader(
      {required this.artworkCache,
      Future<AudioDocumentMetadata> Function(ContentUriAudioSource)?
          readDocument})
      : _read = readDocument ?? AndroidAudioDocuments().readAudio;
  final ArtworkCacheService artworkCache;
  final Future<AudioDocumentMetadata> Function(ContentUriAudioSource) _read;

  Future<Track> read(AndroidPublicationReceipt receipt, DateTime now,
      LibraryScanControl control) async {
    control.throwIfCancelled();
    // The existing Android reader drains MediaMetadataRetriever/release before
    // replying. Cancellation does not abandon an accepted platform call.
    final metadata = await _read(receipt.location.document);
    control.throwIfCancelled();
    final proof = receipt.intent.verification;
    if (metadata.name != receipt.location.displayName ||
        metadata.size != proof.fileSizeBytes ||
        metadata.duration == null ||
        metadata.duration! <= Duration.zero ||
        (metadata.duration! - proof.duration).abs() >
            const Duration(milliseconds: 500)) {
      throw const PublicationException(PublicationFailure.changed);
    }
    var characters = 0;
    String? tag(String? value) {
      if (value == null) return null;
      characters += value.length;
      if (value.length > 4096 ||
          characters > 8192 ||
          value.contains('\u0000')) {
        throw const PublicationException(PublicationFailure.changed);
      }
      final text = value.trim();
      return text.isEmpty ? null : text;
    }

    final title = tag(metadata.title);
    final artist = tag(metadata.artist), album = tag(metadata.album);
    final albumArtist = tag(metadata.albumArtist), genre = tag(metadata.genre);
    if (title == null) {
      throw const PublicationException(PublicationFailure.changed);
    }
    for (final value in [metadata.trackNumber, metadata.discNumber]) {
      if (value != null && (value <= 0 || value > 1000000)) {
        throw const PublicationException(PublicationFailure.changed);
      }
    }
    if (metadata.year != null &&
            (metadata.year! <= 0 || metadata.year! > 9999) ||
        metadata.artwork != null && metadata.artwork!.length > 256 * 1024) {
      throw const PublicationException(PublicationFailure.changed);
    }
    final art = await artworkCache.saveEmbeddedArtwork(metadata.artwork == null
        ? null
        : EmbeddedArtwork(bytes: metadata.artwork!, mimeType: 'image/webp'));
    control.throwIfCancelled();
    return Track.fromSource(
        source: receipt.location.document,
        libraryFolderId: receipt.intent.key.libraryFolderId,
        stableId: generateStableTrackId(
            filePath: receipt.location.document.storageValue,
            title: title,
            artist: artist,
            album: album,
            fileSizeBytes: proof.fileSizeBytes,
            durationMs: proof.duration.inMilliseconds),
        title: title,
        artist: artist,
        album: album,
        albumArtist: albumArtist,
        genre: genre,
        trackNumber: metadata.trackNumber,
        discNumber: metadata.discNumber,
        year: metadata.year,
        duration: proof.duration,
        codec: proof.container,
        contentHash: proof.contentHash,
        fileSizeBytes: proof.fileSizeBytes,
        artworkPath: art?.path,
        artworkHash: art?.hash,
        artworkMimeType: art?.mimeType,
        metadataSource: MetadataSource.embeddedTags,
        metadataConfidence: 1,
        addedAt: now,
        updatedAt: now,
        lastSeenAt: now);
  }
}
