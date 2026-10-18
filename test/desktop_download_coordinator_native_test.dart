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
import 'package:clever_music_player/src/library_sync/yandex_audio_selection.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_protocol.dart';
import 'package:clever_music_player/src/library_sync/yandex_http_transport.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_client.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:clever_music_player/src/library_sync/yandex_track_downloader.dart';
import 'package:clever_music_player/src/library_sync/download_workspace.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/download_fixture.dart';
import 'support/binary_download_fixture.dart';
import 'support/yandex_download_fixture.dart';
import 'support/yandex_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global =
      null; // Real loopback IO, not the widget HTTP 400 stub.
  final bundle = Platform.environment['CMP_TEST_MEDIA_HELPER'];
  final skip = !Platform.isWindows || bundle == null
      ? 'Requires explicit qualified Windows helper via CMP_TEST_MEDIA_HELPER.'
      : false;
  late DownloadFixture f;
  late DesktopDownloadCoordinator coordinator;
  DownloadWorkspace? workingSet;
  final fixtureRoot =
      p.join(Directory.current.path, 'test', 'fixtures', 'media_helper');
  Future<DownloadedAudioExpectation> configure(String format,
      {bool persistent = false,
      bool managed = false,
      int growth = 65536}) async {
    f = await DownloadFixture.open(persistent: persistent);
    if (managed) {
      workingSet = await DownloadWorkspace.open(
          parent: f.root,
          maxReservedBytes: 64 * 1024 * 1024,
          preparedGrowthBytes: growth);
    }
    final helper = BundledMediaHelper(directory: Directory(bundle!));
    final qualified = await helper.qualify();
    await helper.close();
    await File(p.join(fixtureRoot, 'tone.$format')).copy(f.raw.path);
    coordinator = DesktopDownloadCoordinator(
        jobs: f.repositories.downloadJobs,
        imports: f.repositories.downloadImports,
        retention: f.repositories.publicationRetention,
        workspace: workingSet,
        clock: f.clock,
        preparer: DownloadedAudioMetadataPreparer(
            backend: qualified.createMetadataBackend(),
            workspace: workingSet,
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
    await workingSet?.close();
    workingSet = null;
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
  for (final (format, durationMs, growth) in [
    ('mp3', 2000, 65536),
    ('m4a', 2000, 65536),
    ('flac', 2000, 65536),
    ('flac', 180000, 65536),
    ('mp3', 2000, 0),
  ]) {
    test(
        'Yandex resolver -> shared budget $format -> real helper/cover -> ${durationMs != 2000 ? 'preview rejection' : growth == 0 ? 'budget rejection' : 'atomic import'}',
        () async {
      final fixtureExpected =
          await configure(format, managed: true, growth: growth);
      final selection = format == 'flac'
          ? yandexFlacSelection
          : YandexAudioSelection.lossy(
              quality: YandexFileQuality.hq,
              encoding: format == 'mp3'
                  ? YandexFileEncoding.mp3
                  : YandexFileEncoding.aacMp4,
              minimumDeclaredKbps: 128,
              minimumMeasuredBitRate: 96000);
      f.account =
          await f.repositories.remoteLibrary.activateAccount(yandexAccount);
      final server = await YandexDownloadTestServer.open(f.raw);
      server.selection = selection;
      server.metadata = yandexDownloadTrack(durationMs: durationMs);
      (server.metadata.single as Map)['coverUri'] = yandexCoverTemplate;
      server.cover = File(
          p.join(fixtureRoot, format == 'm4a' ? 'cover.jpg' : 'cover.png'));
      final pool = RawDownloadPool(
          parent: f.root,
          workspace: workingSet,
          maxReservedBytes:
              fixtureExpected.fileSizeBytes + maximumDownloadedCoverBytes);
      final reader = YandexLibraryClient(
          token: YandexAccessToken('synthetic-secret'),
          transport: YandexHttpTransport.loopbackForTesting(server.origin),
          downloadParser:
              YandexDownloadParser.loopbackForTesting(server.origin),
          clock: f.clock);
      final downloader = YandexTrackDownloader(
          reader: reader,
          transport: BinaryHttpDownloadTransport.loopbackForTesting(
              server.origin,
              pool: pool),
          jobs: f.repositories.downloadJobs,
          accounts: f.repositories.remoteLibrary,
          clock: f.clock);
      YandexDownloadedTrack? downloaded;
      try {
        await reader.verifyAccount();
        await f.repositories.downloadJobs.enqueue(
            f.account,
            [
              DownloadJobKey(
                  libraryFolderId: f.folderId,
                  identity: yandexDownloadIdentity,
                  quality: selection.resourceQuality)
            ],
            now: f.now);
        final job = (await f.repositories.downloadJobs
            .claimNext(f.account, now: f.now))!;
        downloaded = await downloader.download(job, f.account, selection,
            maxBytes: fixtureExpected.fileSizeBytes);
        final expected = downloaded.expectation;
        expect(expected.requireCover, isTrue);
        expect(downloaded.cover, isNotNull);
        final artworkRequest = server.requests
            .singleWhere((r) => r.path.startsWith('/get-music-content/'));
        expect(artworkRequest.authorization, isNull);
        expect(artworkRequest.path, endsWith('/600x600'));
        final result = await coordinator.processDownloadedFile(
            downloaded.job, downloaded.raw.source, expected,
            cover: downloaded.cover);
        if (durationMs != 2000 || growth == 0) {
          // A valid, fully received short audio file is not the full song.
          expect(result.outcome, DownloadCoordinationOutcome.failed);
          expect(await f.count('tracks'), 0);
          expect(await f.count('downloaded_assets'), 0);
          expect(await f.count('external_track_refs'), 0);
          expect((await f.repositories.downloadJobs.findByKey(job.key))!.state,
              DownloadJobState.failed);
          await downloaded.close();
          expect(pool.reservedBytes, 0);
          expect(workingSet!.reservedBytes, 0);
          return;
        }
        expect(result.outcome, DownloadCoordinationOutcome.completed);
        expect(result.cleanupFailed, isFalse);
        expect(result.imported!.track.title, expected.tags['title']);
        expect(
            result.imported!.track.albumArtist, expected.tags['album_artist']);
        expect(result.imported!.asset.publication.identity,
            yandexDownloadIdentity);
        expect(result.imported!.asset.verification.actualQuality,
            selection.resourceQuality);
        expect(result.imported!.track.artworkHash,
            sha256.convert(await server.cover!.readAsBytes()).toString());
        expect(await f.count('tracks'), 1);
        expect(await f.count('external_track_refs'), 1);
        expect(await f.count('downloaded_assets'), 1);
        expect((await f.repositories.downloadJobs.findByKey(job.key))!.state,
            DownloadJobState.completed);
        await downloaded.close();
        expect(pool.reservedBytes, 0);
        expect(workingSet!.reservedBytes, 0);
      } finally {
        await downloader.close();
        await downloaded?.close();
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
