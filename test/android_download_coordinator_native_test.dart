import 'dart:io';

import 'package:clever_music_player/src/android/android_download_coordinator.dart';
import 'package:clever_music_player/src/android/android_publication_journal.dart';
import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:clever_music_player/src/library_sync/bundled_media_helper.dart';
import 'package:clever_music_player/src/library_sync/download_coordination.dart';
import 'package:clever_music_player/src/library_sync/download_workspace.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata_preparer.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/android_download_provider.dart';
import 'support/android_publication_fixture.dart';

void main() {
  final bundle = Platform.environment['CMP_TEST_MEDIA_HELPER'];
  final skip = !Platform.isWindows || bundle == null
      ? 'Requires explicit qualified Windows helper via CMP_TEST_MEDIA_HELPER.'
      : false;
  const tags = {
    'title': 'Проверка 🎵',
    'artist': 'Артист / 漢字',
    'album': 'Альбом',
    'album_artist': 'Отдельный исполнитель альбома',
    'genre': 'Rock',
    'track': '2/10',
    'disc': '1/2',
    'date': '2026-10-23'
  };
  for (final format in ['mp3', 'm4a', 'flac']) {
    test(
        'real FFmpeg $format preparation -> file-backed SAF adapter -> atomic URI import',
        () async {
      final f = await androidPublicationFixture();
      final helper = BundledMediaHelper(directory: Directory(bundle!));
      final qualified = await helper.qualify();
      await helper.close();
      final working = await DownloadWorkspace.open(
          parent: f.root,
          maxReservedBytes: 64 * 1024 * 1024,
          preparedGrowthBytes: 65536);
      final journal =
          await AndroidPublicationJournal.open(privateParent: f.root);
      final provider =
          AndroidDownloadProvider(Directory('${f.root.path}/provider'));
      provider.metadata = (file, receipt) async {
        final m = await const EmbeddedAudioMetadataReaderService().read(file);
        expect(m.artwork,
            isNotNull); // Embedded PNG verified by the common preparer.
        return AudioDocumentMetadata(
            name: receipt.intent.fileName,
            title: m.title,
            artist: m.artist,
            album: m.album,
            albumArtist: m.albumArtist,
            genre: m.genre,
            duration: m.duration,
            size: m.fileSizeBytes,
            trackNumber: m.trackNumber,
            discNumber: m.discNumber,
            year: m.year);
      };
      final coordinator = AndroidDownloadCoordinator(
          jobs: f.repositories.downloadJobs,
          imports: f.repositories.downloadImports,
          retention: f.repositories.publicationRetention,
          preparer: DownloadedAudioMetadataPreparer(
              backend: qualified.createMetadataBackend(),
              temporaryParent: f.root,
              workspace: working,
              clock: f.clock),
          journal: journal,
          workspace: working,
          artworkCache: const NoopArtworkCacheService(),
          backendFactory: provider.backend,
          verifierFactory: provider.verifier,
          readDocument: provider.read,
          clock: f.clock);
      try {
        await File('assets/media_check/tone.$format').copy(f.raw.path);
        final expected = DownloadedAudioExpectation(
            quality: 'high',
            container: DownloadedAudioContainer.values.byName(format),
            codec: format == 'm4a'
                ? DownloadedAudioCodec.aac
                : DownloadedAudioCodec.values.byName(format),
            fileSizeBytes: await f.raw.length(),
            duration: const Duration(milliseconds: 600),
            minimumBitRate: format == 'flac' ? null : 96000,
            requireCover: true,
            tags: tags);
        final cover = EmbeddedCover(
            await File('assets/media_check/cover.png').readAsBytes(),
            EmbeddedCoverFormat.png);
        final result = await coordinator.processDownloadedFile(
            await f.claim(), FileAudioSource(f.raw.path), expected,
            cover: cover);
        expect(result.outcome, DownloadCoordinationOutcome.completed);
        expect(result.cleanupFailed, isFalse);
        final track = result.imported!.track;
        expect(track.title, tags['title']);
        expect(track.artist, tags['artist']);
        expect(track.albumArtist, tags['album_artist']);
        expect(track.trackNumber, 2);
        expect(track.discNumber, 1);
        expect(track.year, 2026);
        final bytes = await provider.files[track.filePath]!.readAsBytes();
        expect(sha256.convert(bytes).toString(), track.contentHash);
        expect(track.source, isA<ContentUriAudioSource>());
        expect(working.reservedBytes, 0);
        expect(working.reservedEntries, 0);
        expect(await journal.pending(), isEmpty);
        expect(await f.count('tracks'), 1);
      } finally {
        await coordinator.close();
        await journal.close();
        await working.close();
        await f.close();
      }
    }, skip: skip);
  }
  test(
      'persistent SQLite/receipt replay after losing private raw never republishes music',
      () async {
    var f = await androidPublicationFixture(persistent: true);
    final helper = BundledMediaHelper(directory: Directory(bundle!));
    final qualified = await helper.qualify();
    await helper.close();
    var journal = await AndroidPublicationJournal.open(privateParent: f.root);
    final provider =
        AndroidDownloadProvider(Directory('${f.root.path}/provider'));
    provider.metadata = (file, receipt) async {
      final m = await const EmbeddedAudioMetadataReaderService().read(file);
      return AudioDocumentMetadata(
          name: receipt.intent.fileName,
          title: m.title,
          artist: m.artist,
          albumArtist: m.albumArtist,
          size: m.fileSizeBytes,
          duration: m.duration);
    };
    AndroidDownloadCoordinator compose() => AndroidDownloadCoordinator(
        jobs: f.repositories.downloadJobs,
        imports: f.repositories.downloadImports,
        retention: f.repositories.publicationRetention,
        preparer: DownloadedAudioMetadataPreparer(
            backend: qualified.createMetadataBackend(),
            temporaryParent: f.root,
            clock: f.clock),
        journal: journal,
        artworkCache: const NoopArtworkCacheService(),
        backendFactory: provider.backend,
        verifierFactory: provider.verifier,
        readDocument: provider.read,
        clock: f.clock);
    var coordinator = compose();
    try {
      await File('assets/media_check/tone.m4a').copy(f.raw.path);
      await f.database.customStatement(
          "CREATE TRIGGER reject_import BEFORE INSERT ON downloaded_assets BEGIN SELECT RAISE(ABORT, 'test'); END");
      final result = await coordinator.processDownloadedFile(
          await f.claim(),
          FileAudioSource(f.raw.path),
          DownloadedAudioExpectation(
              quality: 'high',
              container: DownloadedAudioContainer.m4a,
              codec: DownloadedAudioCodec.aac,
              minimumBitRate: 96000,
              fileSizeBytes: await f.raw.length(),
              duration: const Duration(milliseconds: 600),
              tags: tags));
      expect(result.outcome, DownloadCoordinationOutcome.needsReconciliation);
      expect(await f.count('tracks'), 0);
      expect((await journal.pending()).length, 1);
      await coordinator.close();
      await journal.close();
      await f.raw.delete();
      f = await f.reopen();
      journal = await AndroidPublicationJournal.open(privateParent: f.root);
      coordinator = compose();
      await f.database.customStatement('DROP TRIGGER reject_import');
      final next =
          (await f.repositories.downloadJobs.claimNext(f.account, now: f.now))!;
      expect((await coordinator.recover(next)).outcome,
          DownloadCoordinationOutcome.completed);
      expect(provider.writes, 1);
      expect(await f.count('tracks'), 1);
      expect(await journal.pending(), isEmpty);
    } finally {
      await coordinator.close();
      await journal.close();
      await f.close();
    }
  }, skip: skip);
}
