import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library_sync/bundled_media_helper.dart';
import 'package:clever_music_player/src/library_sync/binary_http_download_transport.dart';
import 'package:clever_music_player/src/library_sync/raw_download_pool.dart';
import 'package:clever_music_player/src/library_sync/desktop_download_coordinator.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata_preparer.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/download_fixture.dart';
import 'support/binary_download_fixture.dart';

void main() {
  final bundle = Platform.environment['CMP_TEST_MEDIA_HELPER'];
  final skip = !Platform.isWindows || bundle == null
      ? 'Requires explicit qualified Windows helper via CMP_TEST_MEDIA_HELPER.'
      : false;
  late DownloadFixture f;
  late DesktopDownloadCoordinator coordinator;
  final fixtureRoot =
      p.join(Directory.current.path, 'test', 'fixtures', 'media_helper');
  Future<DownloadedAudioExpectation> configure(String format,
      {bool persistent = false}) async {
    f = await DownloadFixture.open(persistent: persistent);
    final helper = BundledMediaHelper(directory: Directory(bundle!));
    final qualified = await helper.qualify();
    await helper.close();
    await File(p.join(fixtureRoot, 'tone.$format')).copy(f.raw.path);
    coordinator = DesktopDownloadCoordinator(
        jobs: f.repositories.downloadJobs,
        imports: f.repositories.downloadImports,
        retention: f.repositories.publicationRetention,
        clock: f.clock,
        preparer: DownloadedAudioMetadataPreparer(
            backend: qualified.createMetadataBackend(),
            clock: f.clock,
            temporaryParent: f.root),
        artworkCache: AppSupportArtworkCacheService(
            artworkDirectory: Directory(p.join(f.root.path, 'covers'))));
    return DownloadedAudioExpectation(
        quality: 'high',
        container: DownloadedAudioContainer.values.byName(format),
        codec: format == 'm4a'
            ? DownloadedAudioCodec.aac
            : DownloadedAudioCodec.values.byName(format),
        fileSizeBytes: await f.raw.length(),
        duration: const Duration(seconds: 2),
        minimumBitRate: format == 'flac' ? null : 96000,
        minimumSampleRate: 48000,
        requireCover: true,
        tags: const {
          'title': 'Проверка "\$()" 🎵',
          'artist': 'Артист / 漢字',
          'album': 'Альбом',
          'album_artist': 'Исполнитель альбома',
          'genre': 'Rock',
          'track': '2/10',
          'disc': '1/2',
          'date': '2026-10-16'
        });
  }

  Future<EmbeddedCover> cover() async => EmbeddedCover(
      await File(p.join(fixtureRoot, 'cover.png')).readAsBytes(),
      EmbeddedCoverFormat.png);
  Future<void> close() async {
    await coordinator.close();
    await f.close();
  }

  for (final format in ['mp3', 'm4a', 'flac']) {
    test(
        'real HTTP + bundled helper $format: tags/cover -> publication -> atomic Track/ref/asset/completion',
        () async {
      final expected = await configure(format);
      final server = await TestBinaryDownloadServer.open(f.raw);
      final pool = RawDownloadPool(
          parent: f.root, maxReservedBytes: expected.fileSizeBytes);
      final transport = BinaryHttpDownloadTransport.loopbackForTesting(
          server.origin,
          pool: pool);
      RawDownloadedAudio? raw;
      try {
        raw = await transport.download(server.address,
            maxBytes: expected.fileSizeBytes,
            expectedBytes: expected.fileSizeBytes);
        final job = await f.claim();
        final result = await coordinator.processDownloadedFile(
            job, raw.source, expected,
            cover: await cover());
        expect(result.outcome, DownloadCoordinationOutcome.completed);
        expect(result.cleanupFailed, isFalse);
        final track = result.imported!.track;
        expect(track.title, expected.tags['title']);
        expect(track.artist, expected.tags['artist']);
        expect(track.albumArtist, expected.tags['album_artist']);
        expect(track.artworkHash,
            sha256.convert((await cover()).bytes).toString());
        expect(await File(track.artworkPath!).exists(), isTrue);
        expect(await File(track.filePath).length(), track.fileSizeBytes);
        expect(
            sha256.convert(await File(track.filePath).readAsBytes()).toString(),
            track.contentHash);
        expect(result.imported!.asset.publication.identity, job.key.identity);
        expect(await f.count('tracks'), 1);
        expect(await f.count('external_track_refs'), 1);
        expect(await f.count('downloaded_assets'), 1);
        expect(
            (await f.repositories.downloadJobs.listAttempts(job.id))
                .single
                .outcome,
            DownloadAttemptOutcome.completed);
        await raw.close();
        expect(pool.reservedBytes, 0);
        expect(await File(track.filePath).exists(), isTrue);
      } finally {
        await transport.close();
        await raw?.close();
        await server.close();
        await close();
      }
    }, skip: skip);
  }
  test(
      'real helper + SQLite rollback recovers the actual published file with a new coordinator',
      () async {
    final expected = await configure('mp3', persistent: true);
    try {
      final job = await f.claim();
      await f.database.customStatement(
          "CREATE TRIGGER reject_import BEFORE INSERT ON downloaded_assets BEGIN SELECT RAISE(ABORT, 'synthetic'); END");
      final failed = await coordinator.processDownloadedFile(
          job, FileAudioSource(f.raw.path), expected,
          cover: await cover());
      expect(failed.outcome, DownloadCoordinationOutcome.needsReconciliation);
      expect(await f.count('tracks'), 0);
      await f.database.customStatement('DROP TRIGGER reject_import');
      await coordinator.close();
      f = await f.reopen();
      // Recovery needs no helper process or raw download: file/journal retain
      // validated evidence. Backend below must never be invoked by this path.
      coordinator = DesktopDownloadCoordinator(
          jobs: f.repositories.downloadJobs,
          imports: f.repositories.downloadImports,
          retention: f.repositories.publicationRetention,
          clock: f.clock,
          preparer: DownloadedAudioMetadataPreparer(
              backend: DownloadTestBackend()..reject = true,
              clock: f.clock,
              temporaryParent: f.root),
          artworkCache: AppSupportArtworkCacheService(
              artworkDirectory: Directory(p.join(f.root.path, 'covers'))));
      final reclaimed =
          (await f.repositories.downloadJobs.claimNext(f.account, now: f.now))!;
      final result = await coordinator.recover(reclaimed);
      expect(result.outcome, DownloadCoordinationOutcome.completed);
      expect(result.imported!.track.title, expected.tags['title']);
      expect(await f.count('tracks'), 1);
      expect(await f.count('downloaded_assets'), 1);
    } finally {
      await close();
    }
  }, skip: skip);
}
