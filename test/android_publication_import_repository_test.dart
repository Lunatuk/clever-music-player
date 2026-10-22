import 'package:clever_music_player/src/android/android_publication_receipt.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/android_publication_fixture.dart';
import 'support/download_fixture.dart';

void main() {
  late DownloadFixture f;
  late DownloadJob job;
  late AndroidPublicationReceipt receipt;
  setUp(() async {
    f = await androidPublicationFixture();
    job = await f.claim(stage: DownloadJobStage.importing);
    receipt = androidReceipt(f, job);
  });
  tearDown(() async {
    expect(await f.database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty);
    await f.close();
  });
  DownloadedTrackImport command([AndroidPublicationReceipt? value]) {
    final r = value ?? receipt;
    return r.importTrack(
        androidPreparedTrack(f, job, r), r.intent.verification);
  }

  Future<DownloadImportResult?> commit(
          {DownloadedTrackImport? publication,
          DownloadJob? expected,
          DateTime Function()? clock}) =>
      f.repositories.downloadImports.commit(
          expected ?? job, publication ?? command(),
          clock: clock ?? f.clock);
  Future<void> noImport() async {
    for (final name in ['tracks', 'external_track_refs', 'downloaded_assets']) {
      expect(await f.count(name), 0, reason: name);
    }
  }

  test('opaque document ID imports Track/ref/asset/job in one transaction',
      () async {
    final result = (await commit())!;
    expect(result.track.source, receipt.location.document);
    expect(result.track.filePath, isNot(contains(receipt.intent.fileName)));
    expect(result.job.state, DownloadJobState.completed);
    expect(result.asset.publication.source, result.track.source);
    expect(
        (await f.repositories.externalTracks.listForTrack(result.track.id!))
            .single
            .identity,
        job.key.identity);
    expect(
        (await f.repositories.downloadJobs.listAttempts(job.id)).single.outcome,
        DownloadAttemptOutcome.completed);
  });
  for (final table in [
    'tracks',
    'external_track_refs',
    'downloaded_assets',
    'download_jobs'
  ]) {
    test('failure in $table rolls back the entire document import', () async {
      final event = table == 'download_jobs' ? 'UPDATE' : 'INSERT';
      final condition =
          table == 'download_jobs' ? "WHEN NEW.state = 'completed'" : '';
      await f.database.customStatement(
          "CREATE TRIGGER reject BEFORE $event ON $table $condition BEGIN SELECT RAISE(ABORT, 'test'); END");
      await expectLater(commit(), throwsA(anything));
      await noImport();
      expect(await f.repositories.downloadJobs.findByKey(job.key), job);
    });
  }
  test('URI without provider membership/name evidence is rejected before SQL',
      () async {
    final c = command();
    expect(
        () => DownloadedTrackImport(
            jobId: c.jobId,
            key: c.key,
            publicationId: c.publicationId,
            track: c.track,
            verification: c.verification),
        throwsArgumentError);
    await noImport();
  });
  test('wrong provider display name is rejected even if URI and bytes match',
      () {
    final c = command();
    expect(
        () => DownloadedTrackImport(
            jobId: c.jobId,
            key: c.key,
            publicationId: c.publicationId,
            track: c.track,
            verification: c.verification,
            documentLocation: DocumentPublicationLocation(
                tree: receipt.location.tree,
                document: receipt.location.document,
                displayName: 'other.mp3')),
        throwsArgumentError);
  });
  test('different selected tree never imports despite a valid provider URI',
      () async {
    final other = androidReceipt(f, job,
        tree: ContentUriAudioSource('content://music.documents/tree/other'));
    await expectLater(commit(publication: command(other)), throwsStateError);
    await noImport();
  });
  for (final revoked in ['lease', 'revision', 'account', 'folder', 'address']) {
    test('$revoked change rejects a prepared document import', () async {
      if (revoked == 'lease') f.now = job.leaseUntil!;
      if (revoked == 'revision') {
        await f.repositories.downloadJobs.renewLease(job, now: f.now);
      }
      if (revoked == 'account') {
        await f.repositories.remoteLibrary.activateAccount(f.account.identity);
      }
      if (revoked == 'folder') {
        await f.repositories.libraryFolders
            .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now);
      }
      if (revoked == 'address') {
        await f.database.customStatement(
            'UPDATE library_folders SET path = ? WHERE id = ?',
            ['content://music.documents/tree/new', f.folderId]);
      }
      if (revoked == 'address') {
        await expectLater(commit(), throwsStateError);
      } else {
        expect(await commit(), isNull);
      }
      await noImport();
    });
  }
  test('lease expiry at completion rolls back already written document rows',
      () async {
    var calls = 0;
    expect(await commit(clock: () => ++calls < 3 ? f.now : job.leaseUntil!),
        isNull);
    await noImport();
  });
  test('lost acknowledgement replay preserves track ID and manual changes',
      () async {
    final first = (await commit())!;
    await f.repositories.tracks.updateTrackMetadata(TrackMetadataUpdate(
        trackId: first.track.id!,
        title: 'Mine',
        artist: null,
        album: null,
        albumArtist: null,
        genre: null,
        year: null,
        trackNumber: null,
        discNumber: null,
        updatedAt: f.now));
    final replay = (await commit())!;
    expect(replay.replayed, isTrue);
    expect(replay.track.id, first.track.id);
    expect(replay.track.title, 'Mine');
    expect(replay.asset, first.asset);
    expect(await f.count('tracks'), 1);
    expect((await commit(expected: first.job))!.replayed, isTrue);
  });
  test('completed replay still binds to the current folder URI', () async {
    await commit();
    await f.database.customStatement(
        'UPDATE library_folders SET path = ? WHERE id = ?',
        ['content://music.documents/tree/new', f.folderId]);
    expect(await commit(), isNull);
  });
  test('cleanup authority accepts only the same completed document publication',
      () async {
    final imported = (await commit())!;
    Future<bool?> cleanup(
            {DocumentPublicationLocation? location, String? id}) =>
        f.repositories.publicationRetention.withCleanupAuthority(
            PublicationCleanupRequest(
                jobId: job.id,
                key: job.key,
                publicationId: id ?? receipt.intent.publicationId,
                kind: PublicationCleanupKind.imported,
                verification: f.proof(),
                documentLocation: location),
            notUpdatedAfter: imported.job.updatedAt,
            clock: f.clock, action: (path) async {
          expect(path, receipt.location.tree.storageValue);
          return true;
        });
    expect(await cleanup(), isNull);
    expect(await cleanup(location: receipt.location, id: 'b' * 64), isNull);
    expect(await cleanup(location: receipt.location), isTrue);
    await f.repositories.downloadedAssets
        .invalidate(imported.asset, DownloadedAssetState.invalid);
    expect(await cleanup(location: receipt.location), isNull);
  });
  test('receipt codec is strict and cannot substitute different byte evidence',
      () {
    final encoded = receipt.encode();
    expect(AndroidPublicationReceipt.decode(encoded).encode(), encoded);
    for (final value in [
      '$encoded ',
      encoded.replaceFirst('"version":1', '"version":2'),
      encoded.replaceFirst('"version":1', '"extra":0,"version":1'),
      '{}',
      'x' * 65537
    ]) {
      expect(() => AndroidPublicationReceipt.decode(value), throwsA(anything));
    }
    final changed = DownloadedAssetVerification(
        actualQuality: 'high',
        container: 'mp3',
        codec: 'mp3',
        fileSizeBytes: 3,
        duration: const Duration(seconds: 3),
        contentHash: 'b' * 64,
        checkedAt: f.now);
    expect(
        () =>
            receipt.importTrack(androidPreparedTrack(f, job, receipt), changed),
        throwsA(anything));
  });
  test('desktop abandoned cleanup never receives an Android tree as a path',
      () async {
    job = (await f.repositories.downloadJobs.cancel(job, now: f.now))!;
    var called = false;
    expect(
        await f.repositories.publicationRetention.withCleanupAuthority(
            PublicationCleanupRequest(
                jobId: job.id,
                key: job.key,
                publicationId: receipt.intent.publicationId,
                kind: PublicationCleanupKind.abandoned),
            notUpdatedAfter: job.updatedAt,
            clock: f.clock, action: (_) async {
          called = true;
          return true;
        }),
        isNull);
    expect(called, isFalse);
  });
  for (final document in [
    'content://foreign/tree/primary%3AMusic/document/x',
    'content://music.documents/tree/other/document/x',
    'content://music.documents/tree/primary%3AMusic/document/primary%3AMusic',
    'content://music.documents/tree/primary%3AMusic/document/x?query=1',
    'content://music.documents/tree/primary%3AMusic/document/x%00'
  ]) {
    test('rejects invalid document boundary $document', () {
      expect(
          () => DocumentPublicationLocation(
              tree: receipt.location.tree,
              document: ContentUriAudioSource(document),
              displayName: receipt.intent.fileName),
          throwsFormatException);
    });
  }
}
