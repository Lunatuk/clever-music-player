import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
  Future<DownloadImportResult?> commit(
          {DownloadedTrackImport? publication,
          DownloadJob? expected,
          DateTime Function()? clock}) =>
      f.repositories.downloadImports.commit(
          expected ?? job, publication ?? f.publication(job),
          clock: clock ?? f.clock);
  Future<void> empty() async {
    for (final table in [
      'tracks',
      'external_track_refs',
      'downloaded_assets'
    ]) {
      expect(await f.count(table), 0, reason: table);
    }
    expect(await f.repositories.downloadJobs.findByKey(job.key), job);
    expect(
        (await f.repositories.downloadJobs.listAttempts(job.id)).single.outcome,
        DownloadAttemptOutcome.running);
  }

  test('one transaction creates Track/ref/asset and completes the same attempt',
      () async {
    final result = (await commit())!;
    expect(result.job.state, DownloadJobState.completed);
    expect(result.job.completedTrackId, result.track.id);
    expect(result.replayed, isFalse);
    expect(result.track.title, 'Provider title');
    expect(result.track.albumArtist, 'Album artist');
    expect(result.asset.publication.trackId, result.track.id);
    expect(result.asset.publication.identity, job.key.identity);
    expect(result.asset.verification, f.proof());
    final refs =
        await f.repositories.externalTracks.listForTrack(result.track.id!);
    expect(refs.single.origin, ExternalTrackRefOrigin.providerResponse);
    expect(refs.single.identity, job.key.identity);
    expect(
        (await f.repositories.downloadJobs.listAttempts(job.id)).single.outcome,
        DownloadAttemptOutcome.completed);
  });
  for (final failure in [
    ('tracks', 'INSERT', ''),
    ('external_track_refs', 'INSERT', ''),
    ('downloaded_assets', 'INSERT', ''),
    ('download_attempts', 'UPDATE', "WHEN NEW.outcome = 'completed'"),
    ('download_jobs', 'UPDATE', "WHEN NEW.state = 'completed'"),
  ]) {
    test('failure at ${failure.$1} rolls back every import row and completion',
        () async {
      await f.database.customStatement(
          'CREATE TRIGGER reject_commit BEFORE ${failure.$2} ON ${failure.$1} ${failure.$3} BEGIN SELECT RAISE(ABORT, \'synthetic\'); END');
      await expectLater(commit(), throwsA(anything));
      await empty();
      await f.database.customStatement('DROP TRIGGER reject_commit');
      expect((await commit())!.job.state, DownloadJobState.completed);
    });
  }
  test(
      'expiry after Track writes rolls everything back instead of returning a partial null',
      () async {
    var calls = 0;
    expect(await commit(clock: () => ++calls < 3 ? f.now : job.leaseUntil!),
        isNull);
    expect(calls, 3);
    await empty();
  });
  for (final revoked in ['lease', 'revision', 'account', 'folder']) {
    test('$revoked revocation rejects all import writes', () async {
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
      expect(await commit(), isNull);
      for (final table in [
        'tracks',
        'external_track_refs',
        'downloaded_assets'
      ]) {
        expect(await f.count(table), 0);
      }
    });
  }
  test('a path outside the current folder never imports', () async {
    await expectLater(
        commit(
            publication:
                f.publication(job, path: p.join(f.root.path, 'other.mp3'))),
        throwsStateError);
    await empty();
  });
  test('changed folder address rejects the previously prepared import',
      () async {
    final command = f.publication(job);
    await f.database.customStatement(
        'UPDATE library_folders SET path = ? WHERE id = ?',
        [p.join(f.root.path, 'other'), f.folderId]);
    await expectLater(commit(publication: command), throwsStateError);
    await empty();
  });
  test('source already owned by another folder is preserved', () async {
    final command = f.publication(job);
    final other = await f.repositories.libraryFolders.upsertFolder(
        LibraryFolder(path: f.root.path, createdAt: f.now, updatedAt: f.now));
    final id = await f.repositories.tracks
        .upsertTrack(command.track.copyWith(libraryFolderId: other));
    await expectLater(commit(publication: command), throwsStateError);
    expect((await f.repositories.tracks.findById(id))!.libraryFolderId, other);
    expect(await f.count('external_track_refs'), 0);
    expect(await f.count('downloaded_assets'), 0);
  });
  test(
      'metadata signature does not merge another path or another provider track',
      () async {
    final command = f.publication(job);
    final original = await f.repositories.tracks.upsertTrack(command.track
        .copyWith(filePath: p.join(f.destination.path, 'other.mp3')));
    final result = (await commit())!;
    expect(result.track.id, isNot(original));
    expect(await f.count('tracks'), 2);
    expect((await f.repositories.tracks.findById(original))!.filePath,
        endsWith('other.mp3'));
  });
  test(
      'already scanned publication keeps its ID, cleared manual fields, custom cover and history',
      () async {
    final command = f.publication(job);
    final id = await f.repositories.tracks.upsertTrack(Track(
        filePath: command.track.filePath,
        libraryFolderId: f.folderId,
        contentHash: command.track.contentHash,
        fileSizeBytes: 3,
        duration: const Duration(seconds: 3),
        codec: 'mp3',
        metadataSource: MetadataSource.manual,
        stableId: 'manual',
        customArtworkPath: p.join(f.root.path, 'custom.jpg'),
        customArtworkHash: 'custom',
        addedAt: f.now.subtract(const Duration(days: 1)),
        updatedAt: f.now));
    await f.repositories.trackUserState.upsertState(
        TrackUserState(trackId: id, playCount: 9, updatedAt: f.now));
    final result = (await commit())!;
    expect(result.track.id, id);
    expect(result.track.title, isNull);
    expect(result.track.artist, isNull);
    expect(result.track.stableId, 'manual');
    expect(result.track.customArtworkHash, 'custom');
    expect(
        (await f.repositories.trackUserState.findByTrackId(id))!.playCount, 9);
    expect(
        result.track.addedAt.toUtc(), f.now.subtract(const Duration(days: 1)));
  });
  test('acknowledgement replay changes no rows, revisions or manual edits',
      () async {
    final first = (await commit())!;
    final id = first.track.id!;
    await f.repositories.tracks.updateTrackMetadata(TrackMetadataUpdate(
        trackId: id,
        title: 'My title',
        artist: null,
        album: null,
        albumArtist: null,
        genre: null,
        year: null,
        trackNumber: null,
        discNumber: null,
        updatedAt: f.now));
    f.now = f.now.add(const Duration(seconds: 1));
    final repeated = (await commit())!;
    expect(repeated.replayed, isTrue);
    expect(repeated.track.id, id);
    expect(repeated.track.title, 'My title');
    expect(repeated.job, first.job);
    expect(repeated.asset, first.asset);
    expect(await f.count('tracks'), 1);
    expect(await f.count('external_track_refs'), 1);
    expect(await f.count('downloaded_assets'), 1);
    expect(await f.count('download_attempts'), 1);
    expect((await commit(expected: first.job))!.replayed, isTrue);
  });
  test('replay cannot substitute different publication bytes or ID', () async {
    await commit();
    expect(await commit(publication: f.publication(job, id: 'b' * 64)), isNull);
    final bad = DownloadedAssetVerification(
        actualQuality: 'high',
        container: 'mp3',
        codec: 'mp3',
        duration: const Duration(seconds: 3),
        fileSizeBytes: 3,
        contentHash: 'b' * 64,
        checkedAt: f.now);
    expect(await commit(publication: f.publication(job, verification: bad)),
        isNull);
  });
  test('replay after a new account session is rejected', () async {
    await commit();
    await f.repositories.remoteLibrary.activateAccount(f.account.identity);
    expect(await commit(), isNull);
  });
  test('future or pre-attempt evidence rolls back the import', () async {
    for (final checkedAt in [
      f.now.subtract(const Duration(seconds: 1)),
      f.now.add(const Duration(seconds: 1))
    ]) {
      expect(
          await commit(
              publication: f.publication(job,
                  verification: f.proof(checkedAt: checkedAt))),
          isNull);
      await empty();
    }
  });
  test(
      'atomic repair refreshes existing same-publication evidence for this attempt',
      () async {
    final command = f.publication(job);
    final id = await f.repositories.tracks.upsertTrack(command.track);
    await f.repositories.externalTracks.linkAll([
      ExternalTrackRef(
          trackId: id,
          identity: job.key.identity,
          origin: ExternalTrackRefOrigin.embeddedTag,
          linkedAt: f.now)
    ]);
    final old = await f.repositories.downloadedAssets.registerVerified(
        DownloadedAssetPublication(
            trackId: id,
            identity: job.key.identity,
            source: command.track.source,
            publicationId: command.publicationId,
            requestedQuality: 'high'),
        f.proof(checkedAt: f.now.subtract(const Duration(days: 1))));
    await f.repositories.downloadedAssets
        .invalidate(old, DownloadedAssetState.invalid);
    final result = (await commit())!;
    expect(result.track.id, id);
    expect(result.asset.state, DownloadedAssetState.verified);
    expect(result.asset.verification.checkedAt, f.now);
  });
  test(
      'duplicate publication ID on a different resource rolls back the second import',
      () async {
    await commit();
    final second = await f.claim(
        externalId: 'different', stage: DownloadJobStage.importing);
    await expectLater(
        commit(expected: second, publication: f.publication(second)),
        throwsStateError);
    expect(await f.count('tracks'), 1);
    expect(await f.count('downloaded_assets'), 1);
    expect(await f.count('external_track_refs'), 1);
    expect(await f.repositories.downloadJobs.findByKey(second.key), second);
  });
  test(
      'two SQLite connections import once; the other gets acknowledgement replay',
      () async {
    await f.close();
    f = await DownloadFixture.open(persistent: true);
    job = await f.claim(stage: DownloadJobStage.importing);
    final other = AppDatabase(NativeDatabase.createInBackground(
        File(p.join(f.root.path, 'state.sqlite'))));
    try {
      await other.customStatement('PRAGMA busy_timeout = 5000');
      final command = f.publication(job);
      final results = await Future.wait([
        commit(publication: command),
        DriftRepositories(other)
            .downloadImports
            .commit(job, command, clock: f.clock),
      ]);
      expect(results.where((r) => r?.replayed == false), hasLength(1));
      expect(results.where((r) => r?.replayed == true), hasLength(1));
      expect(results.map((r) => r!.track.id).toSet(), hasLength(1));
      expect(await f.count('tracks'), 1);
      expect(await f.count('external_track_refs'), 1);
      expect(await f.count('downloaded_assets'), 1);
    } finally {
      await other.close();
    }
  });
}
