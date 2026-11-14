import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/track_repository.dart';
import 'package:clever_music_player/src/library/file_content_hasher.dart';
import 'package:clever_music_player/src/library/exact_track_copies.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/downloaded_asset_checker.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/download_fixture.dart';

void main() {
  late DownloadFixture f;
  late DownloadJob job;
  setUp(() async {
    f = await DownloadFixture.open();
    job = await f.claim(stage: DownloadJobStage.importing);
  });
  tearDown(() async {
    expect(await f.database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty);
    await f.close();
  });
  Future<DownloadImportResult> commit() async =>
      (await f.repositories.downloadImports
          .commit(job, f.publication(job), clock: f.clock))!;
  Future<List<DownloadedAsset>> candidates() =>
      f.repositories.downloadedAssets.findCandidates(job.key.identity,
          quality: job.key.quality, libraryFolderId: f.folderId);

  test(
      'legacy prepared input is normalized without changing verification evidence',
      () {
    final publication = f.publication(job);
    expect(publication.track.contentHash, f.proof().fileContentKey);
    expect(publication.verification.contentHash, f.proof().contentHash);
    expect(publication.verification.contentHash, hasLength(64));
    expect(
        () => f.publication(job,
            track: publication.track.copyWith(contentHash: 'b' * 64)),
        throwsArgumentError);
  });
  test(
      'download commit and full-file scanner produce the same identity immediately',
      () async {
    final publication = f.publication(job);
    final audio = await f.raw.copy(publication.track.filePath);
    final imported = (await f.repositories.downloadImports
        .commit(job, publication, clock: f.clock))!;
    final scanned = await const Sha256FileContentHasher().hashFile(audio);
    expect(imported.track.contentHash, scanned.storageKey);
    expect(imported.asset.verification.contentHash, scanned.digest);
    final copy = await audio.copy('${f.destination.path}/exact-copy.mp3');
    final copied = await const Sha256FileContentHasher().hashFile(copy);
    final copyId = await f.repositories.tracks.upsertTrack(Track(
        filePath: copy.path,
        libraryFolderId: f.folderId,
        title: 'A different filename',
        contentHash: copied.storageKey,
        fileSizeBytes: copied.sizeBytes,
        addedAt: f.now,
        updatedAt: f.now));
    final tracks = [
      imported.track,
      (await f.repositories.tracks.findById(copyId))!
    ];
    expect(tracks, hasLength(2));
    expect(withoutExactTrackCopies(tracks), [imported.track]);
    await copy.writeAsString('abd'); // Equal size, different bytes.
    final changed = await const Sha256FileContentHasher().hashFile(copy);
    expect(changed.storageKey, isNot(scanned.storageKey));
  });
  test(
      'rescanning a known publication keeps it eligible for the download checker',
      () async {
    final publication = f.publication(job);
    final audio = await f.raw.copy(publication.track.filePath);
    final imported = (await f.repositories.downloadImports
        .commit(job, publication, clock: f.clock))!;
    final hash = await const Sha256FileContentHasher().hashFile(audio);
    await (f.repositories.tracks as TrackImportRepository).upsertScannedTracks([
      imported.track.copyWith(contentHash: hash.storageKey),
    ]);
    expect(await candidates(), [imported.asset]);
    final checker = DownloadedAssetChecker(
        repository: f.repositories.downloadedAssets,
        probe: FileSourceFingerprintProbe(),
        clock: f.clock);
    try {
      expect(await checker.check(imported.asset), AssetCheckOutcome.confirmed);
      expect(await candidates(), [imported.asset]);
    } finally {
      await checker.close();
    }
  });
  test(
      'raw fingerprint protocol still returns SHA-256 rather than a storage key',
      () async {
    final probe = FileSourceFingerprintProbe();
    try {
      final result = await probe.fingerprint(FileAudioSource(f.raw.path),
          expectedSize: 3, control: LibraryScanControl());
      expect(result.digest, f.proof().contentHash);
      expect(result.digest, hasLength(64));
    } finally {
      await probe.close();
    }
  });
  test(
      'completed import replay accepts the canonical Track without a second row',
      () async {
    final result = await commit();
    final replay = (await f.repositories.downloadImports
        .commit(result.job, f.publication(result.job), clock: f.clock))!;
    expect(replay.replayed, isTrue);
    expect(replay.track.contentHash, result.track.contentHash);
    expect(await f.count('tracks'), 1);
    expect(await f.count('download_attempts'), 1);
  });
  test(
      'unavailable legacy evidence normalizes only after successful physical confirmation',
      () async {
    final result = await commit();
    await f.repositories.downloadedAssets
        .invalidate(result.asset, DownloadedAssetState.accessDenied);
    final legacy = result.track
        .copyWith(contentHash: result.asset.verification.contentHash);
    await f.repositories.tracks.upsertTrack(legacy);
    final expected =
        (await f.repositories.downloadedAssets.findForTrack(result.track.id!))!;
    expect(
        await f.repositories.downloadedAssets
            .confirm(expected, expected.verification),
        isTrue);
    expect((await f.repositories.tracks.findById(legacy.id!))!.contentHash,
        expected.verification.fileContentKey);
    expect((await candidates()).single.state, DownloadedAssetState.verified);
  });
  test(
      'mismatched canonical content and size cannot become a download candidate',
      () async {
    final result = await commit();
    await f.repositories.tracks.upsertTrack(result.track.copyWith(
        contentHash:
            'file-sha256-v1:4:${result.asset.verification.contentHash}'));
    expect(await candidates(), isEmpty);
    expect(
        await f.repositories.downloadedAssets
            .confirm(result.asset, result.asset.verification),
        isFalse);
    expect(
        (await f.repositories.tracks.findById(result.track.id!))!.contentHash,
        startsWith('file-sha256-v1:4:'));
  });
  test(
      'failed canonical stamping rolls back asset registration and permits retry',
      () async {
    final prepared = f.publication(job);
    final track = prepared.track.copyWith(contentHash: f.proof().contentHash);
    final id = await f.repositories.tracks.upsertTrack(track);
    await f.repositories.externalTracks.linkAll([
      ExternalTrackRef(
          trackId: id,
          identity: job.key.identity,
          origin: ExternalTrackRefOrigin.providerResponse,
          linkedAt: f.now)
    ]);
    final publication = DownloadedAssetPublication(
        trackId: id,
        identity: job.key.identity,
        source: track.source,
        publicationId: 'registry-stamp',
        requestedQuality: job.key.quality);
    await f.database.customStatement(
        '''CREATE TRIGGER fail_hash_stamp BEFORE UPDATE OF content_hash ON tracks
      BEGIN SELECT RAISE(FAIL, 'synthetic-hash-write'); END''');
    await expectLater(
        f.repositories.downloadedAssets
            .registerVerified(publication, f.proof()),
        throwsA(predicate(
            (error) => error.toString().contains('synthetic-hash-write'))));
    expect(await f.repositories.downloadedAssets.findForTrack(id), isNull);
    expect((await f.repositories.tracks.findById(id))!.contentHash,
        f.proof().contentHash);
    await f.database.customStatement('DROP TRIGGER fail_hash_stamp');
    final asset = await f.repositories.downloadedAssets
        .registerVerified(publication, f.proof());
    expect(asset.state, DownloadedAssetState.verified);
    expect((await f.repositories.tracks.findById(id))!.contentHash,
        f.proof().fileContentKey);
  });

  test('size mismatch also rejects a bare legacy digest', () async {
    final result = await commit();
    await f.repositories.tracks.upsertTrack(result.track.copyWith(
        contentHash: result.asset.verification.contentHash, fileSizeBytes: 4));
    expect(await candidates(), isEmpty);
    expect(
        await f.repositories.downloadedAssets
            .confirm(result.asset, result.asset.verification),
        isFalse);
  });
}
