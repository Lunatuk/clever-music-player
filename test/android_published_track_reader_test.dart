import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clever_music_player/src/android/android_published_track_reader.dart';
import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/metadata_enrichment.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/publication_intent.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/android_publication_fixture.dart';

void main() {
  test('embedded document metadata retains roles, numbers and proof duration',
      () async {
    final f = await androidPublicationFixture();
    try {
      final receipt = androidReceipt(f, await f.claim());
      final art = _Art();
      final reader = AndroidPublishedTrackReader(
          artworkCache: art,
          readDocument: (source) async {
            expect(source, receipt.location.document);
            return AudioDocumentMetadata(
                name: receipt.intent.fileName,
                size: 3,
                title: ' Title 🎵 ',
                artist: 'Performer',
                albumArtist: 'Album performer',
                album: 'Album',
                genre: 'Rock',
                duration: const Duration(milliseconds: 3020),
                trackNumber: 2,
                discNumber: 1,
                year: 2026,
                artwork: Uint8List.fromList([1, 2, 3]));
          });
      final track = await reader.read(receipt, f.now, LibraryScanControl());
      expect(track.title, 'Title 🎵');
      expect(track.artist, 'Performer');
      expect(track.albumArtist, 'Album performer');
      expect(track.album, 'Album');
      expect(track.duration, receipt.intent.verification.duration);
      expect(track.trackNumber, 2);
      expect(track.discNumber, 1);
      expect(track.year, 2026);
      expect(track.metadataSource, MetadataSource.embeddedTags);
      expect(track.artworkPath, 'cover');
      expect(art.last!.mimeType, 'image/webp');
      receipt.importTrack(track, receipt.intent.verification);
    } finally {
      await f.close();
    }
  });
  final bad = <String, AudioDocumentMetadata Function(String)>{
    'missing title': (n) => AudioDocumentMetadata(
        name: n, size: 3, duration: const Duration(seconds: 3)),
    'blank title': (n) => AudioDocumentMetadata(
        name: n, title: ' ', size: 3, duration: const Duration(seconds: 3)),
    'different name': (n) => const AudioDocumentMetadata(
        name: 'other', title: 'T', size: 3, duration: Duration(seconds: 3)),
    'missing size': (n) => AudioDocumentMetadata(
        name: n, title: 'T', duration: const Duration(seconds: 3)),
    'changed size': (n) => AudioDocumentMetadata(
        name: n, title: 'T', size: 4, duration: const Duration(seconds: 3)),
    'missing duration': (n) =>
        AudioDocumentMetadata(name: n, title: 'T', size: 3),
    'changed duration': (n) => AudioDocumentMetadata(
        name: n, title: 'T', size: 3, duration: const Duration(seconds: 4)),
    'NUL': (n) => AudioDocumentMetadata(
        name: n,
        title: 'T\u0000',
        size: 3,
        duration: const Duration(seconds: 3)),
    'oversized tag': (n) => AudioDocumentMetadata(
        name: n,
        title: 'T' * 4097,
        size: 3,
        duration: const Duration(seconds: 3)),
    'oversized total': (n) => AudioDocumentMetadata(
        name: n,
        title: 'T' * 4096,
        artist: 'A' * 4096,
        album: 'B',
        size: 3,
        duration: const Duration(seconds: 3)),
    'invalid track': (n) => AudioDocumentMetadata(
        name: n,
        title: 'T',
        trackNumber: 0,
        size: 3,
        duration: const Duration(seconds: 3)),
    'invalid disc': (n) => AudioDocumentMetadata(
        name: n,
        title: 'T',
        discNumber: 1000001,
        size: 3,
        duration: const Duration(seconds: 3)),
    'invalid year': (n) => AudioDocumentMetadata(
        name: n,
        title: 'T',
        year: 10000,
        size: 3,
        duration: const Duration(seconds: 3)),
    'oversized cover': (n) => AudioDocumentMetadata(
        name: n,
        title: 'T',
        artwork: Uint8List(256 * 1024 + 1),
        size: 3,
        duration: const Duration(seconds: 3)),
  };
  for (final entry in bad.entries) {
    test('${entry.key} cannot become a track from an opaque filename',
        () async {
      final f = await androidPublicationFixture();
      try {
        final receipt = androidReceipt(f, await f.claim());
        final art = _Art();
        final reader = AndroidPublishedTrackReader(
            artworkCache: art,
            readDocument: (_) async => entry.value(receipt.intent.fileName));
        await expectLater(reader.read(receipt, f.now, LibraryScanControl()),
            throwsA(isA<PublicationException>()));
        expect(art.calls, 0);
      } finally {
        await f.close();
      }
    });
  }
  test(
      'cancellation drains the accepted metadata call and skips artwork saving',
      () async {
    final f = await androidPublicationFixture();
    try {
      final receipt = androidReceipt(f, await f.claim());
      final complete = Completer<AudioDocumentMetadata>();
      final art = _Art();
      final reader = AndroidPublishedTrackReader(
          artworkCache: art, readDocument: (_) => complete.future);
      final control = LibraryScanControl();
      final action = reader.read(receipt, f.now, control);
      final failure = expectLater(action, throwsA(isA<LibraryScanCancelled>()));
      control.cancel();
      expect(art.calls, 0);
      complete.complete(AudioDocumentMetadata(
          name: receipt.intent.fileName,
          title: 'T',
          size: 3,
          duration: const Duration(seconds: 3)));
      await failure;
      expect(art.calls, 0);
    } finally {
      await f.close();
    }
  });
}

final class _Art implements ArtworkCacheService {
  int calls = 0;
  EmbeddedArtwork? last;
  @override
  Future<CachedArtwork?> saveEmbeddedArtwork(EmbeddedArtwork? artwork) async {
    calls++;
    last = artwork;
    return const CachedArtwork(
        path: 'cover', hash: 'a', mimeType: 'image/webp');
  }

  @override
  Future<CachedArtwork> saveCustomArtworkFile(File imageFile) =>
      throw UnimplementedError();
}
