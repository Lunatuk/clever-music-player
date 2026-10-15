import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('job keys retain exact identities/quality and require a managed folder',
      () {
    expect(() => _key(0), throwsArgumentError);
    expect(() => _key(1, quality: 'bad\nquality'), throwsFormatException);
    expect(_key(1, id: '0001'), isNot(_key(1, id: '1')));
    expect(_key(1), isNot(_key(2)));
    expect(_key(1), isNot(_key(1, variant: 'live')));
    expect(_key(1), isNot(_key(1, quality: 'lossless')));
  });
  group('durable download queue', () {
    late _Fixture f;
    setUp(() async {
      f = _Fixture();
      await f.initialize();
    });
    tearDown(() async {
      expect(await f.database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty);
      await f.database.close();
    });
    test('enqueue is bounded, snapshots inputs and deduplicates repeated keys',
        () async {
      final input = [f.key(), f.key()];
      final pending = f.repo.enqueue(f.account, input, now: f.now);
      input.clear();
      final jobs = await pending;
      expect(jobs, hasLength(1));
      expect(() => jobs.clear(), throwsUnsupportedError);
      expect(
          await f.repo
              .enqueue(f.account, [f.key()], now: f.tick(), maxAttempts: 10),
          [jobs.single]);
      Iterable<DownloadJobKey> infinite() sync* {
        while (true) {
          yield f.key();
        }
      }

      expect(() => f.repo.enqueue(f.account, infinite(), now: f.now),
          throwsArgumentError);
      expect(() => f.repo.enqueue(f.account, [], now: f.now, maxAttempts: 0),
          throwsArgumentError);
    });
    test('one invalid destination rolls back the whole enqueue batch',
        () async {
      await expectLater(
          f.repo.enqueue(f.account, [f.key(), _key(999)], now: f.now),
          throwsStateError);
      expect(await f.repo.listJobs(), isEmpty);
      expect(
          () => f.repo.enqueue(f.account, [_key(f.folderId, provider: 'other')],
              now: f.now),
          throwsArgumentError);
    });
    test('stale account cannot enqueue or claim work', () async {
      final job = await f.enqueue();
      await f.repositories.remoteLibrary.activateAccount(f.account.identity);
      await expectLater(f.repo.enqueue(f.account, [f.key()], now: f.tick()),
          throwsStateError);
      expect(await f.repo.claimNext(f.account, now: f.now), isNull);
      expect((await f.find(job)).state, DownloadJobState.cancelled);
    });
    test('concurrent enqueue attaches to one persisted job', () async {
      final results = await Future.wait([f.enqueue(), f.enqueue()]);
      expect(results[0], results[1]);
      expect(await f.repo.listJobs(), hasLength(1));
    });
    test('destinations, versions and qualities retain distinct keys', () async {
      final other = await f.addFolder('/other');
      await f.repo.enqueue(
          f.account,
          [
            f.key(),
            f.key(quality: 'lossless'),
            f.key(variant: 'live'),
            _key(other)
          ],
          now: f.now);
      expect(await f.repo.listJobs(), hasLength(4));
    });
    test('concurrent claims grant a single attempt and bounded lease',
        () async {
      final original = await f.enqueue();
      final claims = await Future.wait([
        f.repo.claimNext(f.account, now: f.now),
        f.repo.claimNext(f.account, now: f.now)
      ]);
      final claimed = claims.whereType<DownloadJob>().single;
      expect(claimed.id, original.id);
      expect(claimed.attemptCount, 1);
      expect(claimed.remainingAttempts, 2);
      expect(claimed.leaseUntil, f.now.add(const Duration(seconds: 30)));
      expect((await f.repo.listAttempts(claimed.id)).single.token,
          claimed.attemptToken);
    });
    test('quality variants serialize one target while unrelated work proceeds',
        () async {
      final jobs = await f.repo.enqueue(
          f.account, [f.key(), f.key(quality: 'lossless'), f.key(id: 'other')],
          now: f.now);
      final first = (await f.claim())!;
      final other = (await f.claim())!;
      expect(first.id, jobs[0].id);
      expect(other.id, jobs[2].id);
      expect(await f.claim(), isNull);
      await f.repo.cancel(first, now: f.tick());
      expect((await f.claim())!.id, jobs[1].id);
    });
    test('independent variants and destinations can execute concurrently',
        () async {
      final other = await f.addFolder('/other');
      await f.repo.enqueue(
          f.account, [f.key(), f.key(variant: 'live'), _key(other)],
          now: f.now);
      expect(await f.claim(), isNotNull);
      expect(await f.claim(), isNotNull);
      expect(await f.claim(), isNotNull);
    });
    test('lease and list limits reject invalid values', () async {
      expect(
          () =>
              f.repo.claimNext(f.account, now: f.now, leaseFor: Duration.zero),
          throwsArgumentError);
      expect(
          () => f.repo.claimNext(f.account,
              now: f.now, leaseFor: const Duration(minutes: 11)),
          throwsArgumentError);
      await expectLater(f.repo.listJobs(limit: 257), throwsArgumentError);
      await expectLater(f.repo.listAttempts(0), throwsArgumentError);
      await expectLater(f.repo.listAttempts(1, limit: 0), throwsArgumentError);
    });
    test('heartbeat extends lease and invalidates old snapshots', () async {
      await f.enqueue();
      final old = (await f.claim())!;
      final renewed = (await f.repo.renewLease(old,
          now: f.tick(), leaseFor: const Duration(minutes: 1)))!;
      expect(renewed.leaseUntil!.isAfter(old.leaseUntil!), isTrue);
      expect(await f.repo.advance(old, DownloadJobStage.metadata, now: f.now),
          isNull);
      expect(await f.repo.cancel(old, now: f.now), isNull);
      expect(
          await f.repo.advance(renewed, DownloadJobStage.metadata, now: f.now),
          isNotNull);
    });
    test('exact lease deadline fences old writes and requires reconciliation',
        () async {
      await f.enqueue();
      final old = (await f.claim())!;
      f.now = old.leaseUntil!;
      expect(await f.repo.renewLease(old, now: f.now), isNull);
      expect(await f.repo.advance(old, DownloadJobStage.metadata, now: f.now),
          isNull);
      expect(await f.repo.recoverExpired(now: f.now), 1);
      expect(await f.repo.recoverExpired(now: f.now), 0);
      final next = (await f.claim())!;
      expect(next.state, DownloadJobState.reconciling);
      expect(next.attemptToken, isNot(old.attemptToken));
      expect(next.attemptCount, 2);
      expect(await f.repo.advance(next, DownloadJobStage.metadata, now: f.now),
          isNull);
      expect(
          await f.repo.fail(old, DownloadFailure.network, now: f.now), isNull);
      expect((await f.repo.listAttempts(old.id)).last.outcome,
          DownloadAttemptOutcome.interrupted);
    });
    test('startup recovery never steals a live lease', () async {
      await f.enqueue();
      final job = (await f.claim())!;
      expect(await f.repo.recoverExpired(now: f.tick()), 0);
      expect(await f.find(job), job);
      expect(await f.claim(), isNull);
    });
    test('stage order cannot skip or go backwards during ordinary execution',
        () async {
      await f.enqueue();
      final job = (await f.claim())!;
      expect(
          () => f.repo.advance(job, DownloadJobStage.publication, now: f.now),
          throwsArgumentError);
      expect(() => f.repo.advance(job, DownloadJobStage.download, now: f.now),
          throwsArgumentError);
      final next = (await f.repo
          .advance(job, DownloadJobStage.metadata, now: f.tick()))!;
      expect(next.stage, DownloadJobStage.metadata);
      expect(next.attemptToken, job.attemptToken);
    });
    test('reconciliation preserves checkpoint and permits safe rewind only',
        () async {
      await f.enqueue();
      var job = (await f.claim())!;
      job = (await f.repo
          .advance(job, DownloadJobStage.metadata, now: f.tick()))!;
      job = (await f.repo
          .advance(job, DownloadJobStage.verification, now: f.tick()))!;
      f.now = job.leaseUntil!;
      final recovered = (await f.claim())!;
      expect(recovered.stage, DownloadJobStage.verification);
      expect(
          () => f.repo.resolveReconciliation(
              recovered, DownloadJobStage.publication,
              now: f.now),
          throwsArgumentError);
      final resumed = (await f.repo.resolveReconciliation(
          recovered, DownloadJobStage.download,
          now: f.now))!;
      expect(resumed.stage, DownloadJobStage.download);
      expect(resumed.state, DownloadJobState.running);
    });
    test('exhausted recovery stops until explicit retry replenishes budget',
        () async {
      final original = await f.enqueue(maxAttempts: 1);
      final first = (await f.claim())!;
      f.now = first.leaseUntil!;
      await f.repo.recoverExpired(now: f.now);
      final stopped = await f.find(original);
      expect(stopped.state, DownloadJobState.failed);
      expect(stopped.remainingAttempts, 0);
      expect(await f.claim(), isNull);
      final retried = (await f.repo.retry(stopped, f.account, now: f.now))!;
      expect(retried.remainingAttempts, 1);
      expect((await f.claim())!.attemptCount, 2);
      expect(await f.repo.retry(stopped, f.account, now: f.now), isNull);
    });
    test('retry timing and budget prevent unbounded automatic failures',
        () async {
      await f.enqueue(maxAttempts: 2);
      var job = (await f.claim())!;
      final due = f.now.add(const Duration(seconds: 5));
      final scheduled = (await f.repo
          .fail(job, DownloadFailure.rateLimited, now: f.now, retryAt: due))!;
      expect(scheduled.state, DownloadJobState.needsReconciliation);
      expect(await f.claim(), isNull);
      f.now = due;
      job = (await f.claim())!;
      expect(job.state, DownloadJobState.reconciling);
      final failed = (await f.repo.fail(job, DownloadFailure.network,
          now: f.now, retryAt: f.now.add(const Duration(seconds: 5))))!;
      expect(failed.state, DownloadJobState.failed);
      expect(failed.retryAt, isNull);
      expect(failed.remainingAttempts, 0);
      expect(await f.claim(), isNull);
    });
    test('authorization/media/storage errors never schedule an automatic retry',
        () async {
      await f.enqueue();
      final job = (await f.claim())!;
      for (final reason in [
        DownloadFailure.authorization,
        DownloadFailure.subscription,
        DownloadFailure.invalidMedia,
        DownloadFailure.noSpace,
        DownloadFailure.accessDenied
      ]) {
        expect(
            () => f.repo.fail(job, reason,
                now: f.now, retryAt: f.now.add(const Duration(seconds: 5))),
            throwsArgumentError);
      }
      expect(
          () => f.repo
              .fail(job, DownloadFailure.network, now: f.now, retryAt: f.now),
          throwsArgumentError);
      final failed =
          (await f.repo.fail(job, DownloadFailure.authorization, now: f.now))!;
      expect(failed.state, DownloadJobState.failed);
      expect(await f.claim(), isNull);
      expect((await f.repo.listAttempts(job.id)).single.failure,
          DownloadFailure.authorization);
    });
    test('queued cancellation is idempotent and requires explicit retry',
        () async {
      final job = await f.enqueue();
      final cancelled = (await f.repo.cancel(job, now: f.now))!;
      expect(cancelled.state, DownloadJobState.cancelled);
      expect(await f.repo.cancel(cancelled, now: f.now), isNull);
      expect(
          await f.repo.enqueue(f.account, [f.key()], now: f.now), [cancelled]);
      expect(await f.claim(), isNull);
    });
    test(
        'cancelling publication preserves checkpoint and rejects late importer',
        () async {
      await f.enqueue();
      var job = (await f.claim())!;
      for (final stage in [
        DownloadJobStage.metadata,
        DownloadJobStage.verification,
        DownloadJobStage.publication
      ]) {
        job = (await f.repo.advance(job, stage, now: f.tick()))!;
      }
      final cancelled = (await f.repo.cancel(job, now: f.now))!;
      expect(cancelled.stage, DownloadJobStage.publication);
      expect(cancelled.attemptToken, isNull);
      expect(await f.repo.advance(job, DownloadJobStage.importing, now: f.now),
          isNull);
      expect((await f.repo.listAttempts(job.id)).single.outcome,
          DownloadAttemptOutcome.cancelled);
      await f.repo.retry(cancelled, f.account, now: f.now);
      expect((await f.claim())!.state, DownloadJobState.reconciling);
    });
    test('completion requires import stage and exact fresh verified asset',
        () async {
      await f.enqueue();
      var job = (await f.claim())!;
      final asset = await f.asset(job);
      expect(await f.repo.complete(job, asset, now: f.now), isNull);
      job = await f.importStage(job);
      final completed = (await f.repo.complete(job, asset, now: f.now))!;
      expect(completed.state, DownloadJobState.completed);
      expect(completed.completedTrackId, asset.publication.trackId);
      expect((await f.repo.listAttempts(job.id)).single.outcome,
          DownloadAttemptOutcome.completed);
      expect(
          await f.repo.enqueue(f.account, [job.key], now: f.now), [completed]);
      expect(await f.repo.retry(completed, f.account, now: f.now), isNull);
      final repair = (await f.repo
          .retry(completed, f.account, now: f.now, repairCompleted: true))!;
      expect(repair.stage, DownloadJobStage.importing);
      expect(repair.state, DownloadJobState.needsReconciliation);
    });
    test('old proof, lower actual quality or unavailable asset cannot complete',
        () async {
      final original = await f.enqueue();
      final asset = await f.asset(original);
      f.tick();
      final job = await f.importStage((await f.claim())!);
      expect(await f.repo.complete(job, asset, now: f.now), isNull);
      final freshProof = f.proof();
      expect(await f.repositories.downloadedAssets.confirm(asset, freshProof),
          isTrue);
      final fresh = (await f.repositories.downloadedAssets
          .findForTrack(asset.publication.trackId))!;
      expect(
          await f.repositories.downloadedAssets
              .invalidate(fresh, DownloadedAssetState.accessDenied),
          isTrue);
      expect(await f.repo.complete(job, fresh, now: f.now), isNull);
    });
    test('completion rejects wrong actual quality and destination', () async {
      await f.enqueue();
      final job = await f.importStage((await f.claim())!);
      final lower = await f.asset(job, actualQuality: 'normal');
      expect(await f.repo.complete(job, lower, now: f.now), isNull);
      final otherFolder = await f.addFolder('/other');
      final other = await f.asset(job, folderId: otherFolder);
      expect(await f.repo.complete(job, other, now: f.now), isNull);
    });
    test('old clock values cannot mutate a newer revision', () async {
      await f.enqueue();
      final job = (await f.claim())!;
      expect(
          await f.repo.renewLease(job,
              now: f.now.subtract(const Duration(microseconds: 1))),
          isNull);
      expect(
          await f.repo.cancel(job,
              now: f.now.subtract(const Duration(microseconds: 1))),
          isNull);
    });
    test('account disconnect revokes queued and running attempts atomically',
        () async {
      await f.repo.enqueue(f.account, [f.key(), f.key(id: 'next')], now: f.now);
      final job = (await f.claim())!;
      expect(await f.repositories.remoteLibrary.disconnectAccount(f.account),
          isTrue);
      expect(
          (await f.repo.listJobs()).every((j) =>
              j.state == DownloadJobState.cancelled &&
              j.failure == DownloadFailure.accountChanged),
          isTrue);
      expect(await f.repo.renewLease(job, now: f.tick()), isNull);
      expect((await f.repo.listAttempts(job.id)).single.outcome,
          DownloadAttemptOutcome.cancelled);
    });
    test(
        'changing account keeps dedup key but requires explicit session rebind',
        () async {
      final job = await f.enqueue();
      final next = await f.repositories.remoteLibrary.activateAccount(
          RemoteAccountIdentity(provider: 'yandex_music', accountId: 'B'));
      final cancelled = await f.find(job);
      expect((await f.repo.enqueue(next, [job.key], now: f.tick())).single,
          cancelled);
      expect(await f.repo.claimNext(next, now: f.now), isNull);
      final retried = (await f.repo.retry(cancelled, next, now: f.now))!;
      expect(retried.accountId, next.id);
      expect((await f.repo.claimNext(next, now: f.now))!.state,
          DownloadJobState.reconciling);
    });
    test('folder disable revokes work and enabling alone never restarts it',
        () async {
      await f.enqueue();
      final job = (await f.claim())!;
      await f.repositories.libraryFolders
          .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now);
      final cancelled = await f.find(job);
      expect(cancelled.failure, DownloadFailure.destinationDisabled);
      expect(await f.repo.retry(cancelled, f.account, now: f.now), isNull);
      await f.repositories.libraryFolders
          .setFolderEnabled(f.folderId, isEnabled: true, updatedAt: f.now);
      expect(await f.claim(), isNull);
      expect(await f.repo.retry(cancelled, f.account, now: f.now), isNotNull);
    });
    test('folder upsert disable and changing its path revoke ownership',
        () async {
      await f.enqueue();
      final job = (await f.claim())!;
      final folder =
          (await f.repositories.libraryFolders.findFolderByPath('/music'))!;
      await f.repositories.libraryFolders
          .upsertFolder(folder.copyWith(path: '/moved', updatedAt: f.now));
      expect((await f.find(job)).state, DownloadJobState.cancelled);
      final cancelled = await f.find(job);
      await f.repo.retry(cancelled, f.account, now: f.now);
      final next = (await f.claim())!;
      await f.repositories.libraryFolders.upsertFolder(
          folder.copyWith(path: '/moved', isEnabled: false, updatedAt: f.now));
      expect((await f.find(next)).failure, DownloadFailure.destinationDisabled);
    });
    test('failed account activation rolls back job and attempt cancellation',
        () async {
      await f.enqueue();
      final job = (await f.claim())!;
      await f.database.customStatement(
          "CREATE TRIGGER fail_account BEFORE UPDATE ON remote_accounts BEGIN SELECT RAISE(ABORT, 'simulated'); END");
      await expectLater(
          f.repositories.remoteLibrary.activateAccount(f.account.identity),
          throwsA(anything));
      expect(await f.find(job), job);
      expect((await f.repo.listAttempts(job.id)).single.outcome,
          DownloadAttemptOutcome.running);
      expect(await f.repositories.remoteLibrary.findAccount(f.account.identity),
          f.account);
    });
    test('failed disable rolls back folder flag and attempt revocation',
        () async {
      await f.enqueue();
      final job = (await f.claim())!;
      await f.database.customStatement(
          "CREATE TRIGGER fail_job BEFORE UPDATE ON download_jobs BEGIN SELECT RAISE(ABORT, 'simulated'); END");
      await expectLater(
          f.repositories.libraryFolders
              .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now),
          throwsA(anything));
      expect(
          (await f.repositories.libraryFolders.findFolderByPath('/music'))!
              .isEnabled,
          isTrue);
      expect(await f.find(job), job);
      expect((await f.repo.listAttempts(job.id)).single.outcome,
          DownloadAttemptOutcome.running);
    });
    test('attempt insert failure rolls back claim and consumed budget',
        () async {
      final job = await f.enqueue();
      await f.database.customStatement(
          "CREATE TRIGGER fail_attempt BEFORE INSERT ON download_attempts BEGIN SELECT RAISE(ABORT, 'simulated'); END");
      await expectLater(f.claim(), throwsA(anything));
      expect(await f.find(job), job);
      expect(await f.repo.listAttempts(job.id), isEmpty);
    });
    test('checkpoint failure rolls back both job and attempt stage', () async {
      await f.enqueue();
      final job = (await f.claim())!;
      await f.database.customStatement(
          "CREATE TRIGGER fail_checkpoint BEFORE UPDATE ON download_jobs BEGIN SELECT RAISE(ABORT, 'simulated'); END");
      await expectLater(
          f.repo.advance(job, DownloadJobStage.metadata, now: f.tick()),
          throwsA(anything));
      expect(await f.find(job), job);
      expect((await f.repo.listAttempts(job.id)).single.stage,
          DownloadJobStage.download);
    });
    test('recovery failure rolls back attempt finish and ownership', () async {
      await f.enqueue();
      final job = (await f.claim())!;
      await f.database.customStatement(
          "CREATE TRIGGER fail_recovery BEFORE UPDATE ON download_jobs BEGIN SELECT RAISE(ABORT, 'simulated'); END");
      await expectLater(
          f.repo.recoverExpired(now: job.leaseUntil!), throwsA(anything));
      expect(await f.find(job), job);
      expect((await f.repo.listAttempts(job.id)).single.finishedAt, isNull);
    });
    test(
        'queue operations do not alter local music, ratings or remote snapshots',
        () async {
      await f.enqueue();
      final job = (await f.claim())!;
      final asset = await f.asset(job);
      await f.repositories.trackUserState.toggleFeedback(
          asset.publication.trackId, TrackFeedback.like,
          updatedAt: f.now);
      final before = await f.localRows();
      await f.repo.cancel(job, now: f.tick());
      await f.repositories.remoteLibrary.disconnectAccount(f.account);
      expect(await f.localRows(), before);
      await f.repositories.resetLearningState();
      expect(await f.repo.listJobs(), hasLength(1));
    });
    test(
        'direct folder deletion explicitly cleans attempts with enforcement off',
        () async {
      await f.enqueue();
      await f.claim();
      await f.database.customStatement('PRAGMA foreign_keys = OFF');
      await f.repositories.libraryFolders.deleteFolder(f.folderId);
      expect(await f.repo.listJobs(), isEmpty);
      expect(
          await f.database.select(f.database.downloadAttempts).get(), isEmpty);
    });
    test(
        'folder removal failure restores folder, job and deleted attempt history',
        () async {
      await f.enqueue();
      final job = (await f.claim())!;
      await f.repositories.libraryFolders
          .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now);
      final before = await f.find(job);
      await f.database.customStatement(
          "CREATE TRIGGER fail_delete BEFORE DELETE ON download_jobs BEGIN SELECT RAISE(ABORT, 'simulated'); END");
      await expectLater(
          (f.repositories.libraryFolders as LibraryFolderRemovalRepository)
              .removeDisabledFolder(f.folderId),
          throwsA(anything));
      expect(await f.find(job), before);
      expect(await f.repo.listAttempts(job.id), hasLength(1));
      expect(await f.repositories.libraryFolders.findFolderByPath('/music'),
          isNotNull);
    });
    test('completion failure rolls back attempt outcome and result linkage',
        () async {
      await f.enqueue();
      final job = await f.importStage((await f.claim())!);
      final asset = await f.asset(job);
      await f.database.customStatement(
          "CREATE TRIGGER fail_complete BEFORE UPDATE ON download_jobs WHEN NEW.state = 'completed' BEGIN SELECT RAISE(ABORT, 'simulated'); END");
      await expectLater(
          f.repo.complete(job, asset, now: f.now), throwsA(anything));
      expect(await f.find(job), job);
      expect((await f.repo.listAttempts(job.id)).single.outcome,
          DownloadAttemptOutcome.running);
      expect((await f.repo.listAttempts(job.id)).single.finishedAt, isNull);
    });
    test('unknown persisted state fails closed', () async {
      final job = await f.enqueue();
      await f.database.customStatement(
          "UPDATE download_jobs SET state = 'future' WHERE id = ?", [job.id]);
      await expectLater(f.find(job), throwsArgumentError);
    });
  });
  for (final enforce in [false, true]) {
    test('folder removal cleans job/attempt rows with foreign keys $enforce',
        () async {
      final f = _Fixture(enforce: enforce);
      await f.initialize();
      addTearDown(f.database.close);
      await f.enqueue();
      await f.claim();
      await f.repositories.libraryFolders
          .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now);
      await (f.repositories.libraryFolders as LibraryFolderRemovalRepository)
          .removeDisabledFolder(f.folderId);
      expect(await f.repo.listJobs(), isEmpty);
      expect(
          await f.database.select(f.database.downloadAttempts).get(), isEmpty);
      expect(await f.database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty);
    });
  }
  test('file reopen preserves checkpoint, attempt token and live lease fencing',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('cmp_download_jobs_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'library.sqlite'));
    final first = _Fixture(database: AppDatabase(NativeDatabase(file)));
    await first.initialize();
    await first.enqueue();
    final job = (await first.repo.advance(
        (await first.claim())!, DownloadJobStage.metadata,
        now: first.tick()))!;
    final account = first.account;
    await first.database.close();
    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    final repo = DriftRepositories(database).downloadJobs;
    expect(await repo.findByKey(job.key), job);
    expect(await repo.claimNext(account, now: job.updatedAt), isNull);
    final recovered = (await repo.claimNext(account, now: job.leaseUntil!))!;
    expect(recovered.state, DownloadJobState.reconciling);
    expect(recovered.stage, DownloadJobStage.metadata);
    expect(recovered.attemptCount, 2);
    expect(recovered.attemptToken, isNot(job.attemptToken));
    expect(await repo.renewLease(job, now: job.leaseUntil!), isNull);
  });
}

DownloadJobKey _key(int folder,
        {String id = '0001',
        String variant = '',
        String quality = 'high',
        String provider = 'yandex_music'}) =>
    DownloadJobKey(
        libraryFolderId: folder,
        identity: ExternalTrackIdentity(
            provider: provider, externalId: id, variantKey: variant),
        quality: quality);

final class _Fixture {
  _Fixture({AppDatabase? database, bool enforce = true})
      : database = database ??
            AppDatabase(NativeDatabase.memory(
                setup: (raw) => raw.execute(
                    'PRAGMA foreign_keys = ${enforce ? 'ON' : 'OFF'}')));
  final AppDatabase database;
  late final repositories = DriftRepositories(database);
  late final repo = repositories.downloadJobs;
  late RemoteLibraryAccount account;
  late int folderId;
  var now = DateTime.fromMicrosecondsSinceEpoch(1893456000123456, isUtc: true);
  DateTime tick() => now = now.add(const Duration(seconds: 1));
  Future<void> initialize() async {
    account = await repositories.remoteLibrary.activateAccount(
        RemoteAccountIdentity(provider: 'yandex_music', accountId: 'A'));
    folderId = await addFolder('/music');
  }

  Future<int> addFolder(String path) =>
      repositories.libraryFolders.upsertFolder(LibraryFolder(
          path: path,
          isEnabled: true,
          isRecursive: true,
          createdAt: now,
          updatedAt: now));
  DownloadJobKey key(
          {String id = '0001', String variant = '', String quality = 'high'}) =>
      _key(folderId, id: id, variant: variant, quality: quality);
  Future<DownloadJob> enqueue({int maxAttempts = 3}) async =>
      (await repo.enqueue(account, [key()], now: now, maxAttempts: maxAttempts))
          .single;
  Future<DownloadJob?> claim() => repo.claimNext(account, now: now);
  Future<DownloadJob> find(DownloadJob job) async =>
      (await repo.findByKey(job.key))!;
  Future<DownloadJob> importStage(DownloadJob job) async {
    for (final stage in DownloadJobStage.values.skip(1)) {
      job = (await repo.advance(job, stage, now: tick()))!;
    }
    return job;
  }

  DownloadedAssetVerification proof({String actualQuality = 'high'}) =>
      DownloadedAssetVerification(
          actualQuality: actualQuality,
          container: 'mp3',
          codec: 'mp3',
          fileSizeBytes: 123,
          duration: const Duration(seconds: 60),
          contentHash: 'a' * 64,
          checkedAt: now);
  Future<DownloadedAsset> asset(DownloadJob job,
      {String actualQuality = 'high', int? folderId}) async {
    final path =
        '/music/${job.id}-$actualQuality-${folderId ?? this.folderId}.mp3';
    final id = await repositories.tracks.upsertTrack(Track(
        libraryFolderId: folderId ?? this.folderId,
        filePath: path,
        contentHash: 'a' * 64,
        fileSizeBytes: 123,
        title: 'Manual',
        metadataSource: MetadataSource.manual,
        addedAt: now,
        updatedAt: now));
    await repositories.externalTracks.linkAll([
      ExternalTrackRef(
          trackId: id,
          identity: job.key.identity,
          origin: ExternalTrackRefOrigin.providerResponse,
          linkedAt: now)
    ]);
    return repositories.downloadedAssets.registerVerified(
        DownloadedAssetPublication(
            trackId: id,
            identity: job.key.identity,
            source: FileAudioSource(path),
            publicationId:
                'job-${job.id}-$actualQuality-${folderId ?? this.folderId}',
            requestedQuality: job.key.quality),
        proof(actualQuality: actualQuality));
  }

  Future<Map<String, List<Map<String, Object?>>>> localRows() async => {
        for (final table in [
          'tracks',
          'track_user_state',
          'external_track_refs',
          'downloaded_assets',
          'remote_collections',
          'remote_collection_items'
        ])
          table: [
            for (final row
                in await database.customSelect('SELECT * FROM $table').get())
              row.data
          ]
      };
}
