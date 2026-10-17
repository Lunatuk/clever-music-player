import 'dart:io';

import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library_sync/binary_http_download_transport.dart';
import 'package:clever_music_player/src/library_sync/desktop_download_coordinator.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata_preparer.dart';
import 'package:clever_music_player/src/library_sync/raw_download_pool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/binary_download_fixture.dart';
import 'support/download_fixture.dart';

void main() {
  for (final reject in [false, true]) {
    test(
        'HTTP raw -> metadata/verification -> ${reject ? "rejection" : "atomic import"}',
        () async {
      final f = await DownloadFixture.open();
      final server = await TestBinaryDownloadServer.open(f.raw);
      final pool = RawDownloadPool(parent: f.root, maxReservedBytes: 3);
      final transport = BinaryHttpDownloadTransport.loopbackForTesting(
          server.origin,
          pool: pool);
      final backend = DownloadTestBackend()..reject = reject;
      backend.onWrite = (_) async => expect(pool.reservedBytes, 3);
      final coordinator = DesktopDownloadCoordinator(
          jobs: f.repositories.downloadJobs,
          imports: f.repositories.downloadImports,
          retention: f.repositories.publicationRetention,
          metadataReader: DownloadTestMetadataReader(),
          clock: f.clock,
          preparer: DownloadedAudioMetadataPreparer(
              backend: backend, clock: f.clock, temporaryParent: f.root),
          artworkCache: AppSupportArtworkCacheService(
              artworkDirectory: Directory(p.join(f.root.path, 'covers'))));
      RawDownloadedAudio? raw;
      try {
        raw = await transport.download(server.address,
            maxBytes: 3, expectedBytes: 3);
        final job = await f.claim();
        final result = await coordinator.processDownloadedFile(
            job, raw.source, downloadExpectation());
        expect(
            result.outcome,
            reject
                ? DownloadCoordinationOutcome.failed
                : DownloadCoordinationOutcome.completed);
        expect(result.cleanupFailed, isFalse);
        expect(await f.count('tracks'), reject ? 0 : 1);
        expect(await f.count('downloaded_assets'), reject ? 0 : 1);
        expect(pool.reservedBytes, 3);
        await raw.close();
        expect(pool.reservedBytes, 0);
        if (!reject) {
          expect(await File(result.imported!.track.filePath).readAsString(),
              'abc');
        }
      } finally {
        await coordinator.close();
        await transport.close();
        await raw?.close();
        await server.close();
        await f.close();
      }
    });
  }
}
