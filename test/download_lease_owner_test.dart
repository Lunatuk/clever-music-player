import 'dart:async';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library_sync/download_lease_owner.dart';
import 'package:clever_music_player/src/library_sync/publication_intent.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/download_fixture.dart';
import 'support/recording_download_jobs.dart';

void main() {
  late DownloadFixture f;
  late DownloadJob job;
  late RecordingDownloadJobs jobs;
  late DownloadLeaseOwner owner;
  setUp(() async {
    f = await DownloadFixture.open();
    job = await f.claim();
    jobs = RecordingDownloadJobs(f.repositories.downloadJobs);
    owner = DownloadLeaseOwner(
        job: job,
        jobs: jobs,
        clock: f.clock,
        leaseFor: const Duration(seconds: 2),
        heartbeatEvery: const Duration(milliseconds: 30));
  });
  tearDown(() async {
    await owner.close();
    await f.close();
  });
  Matcher lost() => throwsA(isA<PublicationException>()
      .having((e) => e.reason, 'reason', PublicationFailure.ownershipLost));
  test('start proves current ownership before work and starts the heartbeat',
      () async {
    expect(jobs.renewals, 0);
    await owner.start();
    expect(jobs.renewals, 1);
    await jobs.nextRenewal();
    expect(jobs.renewals, 2);
    expect(owner.current.attemptToken, job.attemptToken);
    expect(owner.current.revision, greaterThan(job.revision));
    await expectLater(owner.start(), throwsStateError);
  });
  test(
      'same-attempt old publisher snapshot is fenced using current heartbeat revision',
      () async {
    await owner.start();
    final snapshot = owner.current;
    await jobs.nextRenewal();
    expect(
        await owner.withOwnedDestination(snapshot,
            clock: f.clock, action: (_) async => 7),
        7);
    expect(
        await f.repositories.downloadJobs.withOwnedDestination(snapshot,
            clock: f.clock, action: (_) async => 7),
        isNull);
  });
  test('a snapshot from before a stage change cannot be substituted', () async {
    await owner.start();
    final snapshot = owner.current;
    await owner.advance(DownloadJobStage.metadata);
    await expectLater(
        owner.withOwnedDestination(snapshot,
            clock: f.clock, action: (_) async => true),
        lost());
  });
  for (final revocation in ['account', 'folder', 'expiry']) {
    test('$revocation change revokes the owner before its next file effect',
        () async {
      await owner.start();
      if (revocation == 'account') {
        await f.repositories.remoteLibrary.activateAccount(f.account.identity);
      }
      if (revocation == 'folder') {
        await f.repositories.libraryFolders
            .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now);
      }
      if (revocation == 'expiry') f.now = owner.current.leaseUntil!;
      var called = false;
      await expectLater(
          owner.withOwnedDestination(owner.current, clock: f.clock,
              action: (_) async {
            called = true;
            return true;
          }),
          lost());
      expect(called, isFalse);
      expect(owner.lost, isTrue);
    });
  }
  test('close drains a pending renewal and prevents a timer restart', () async {
    final entered = Completer<void>(), gate = Completer<void>();
    jobs.beforeRenew = () async {
      entered.complete();
      await gate.future;
    };
    final starting = owner.start();
    await entered.future;
    var closed = false;
    final closing = owner.close().then((_) => closed = true);
    expect(identical(owner.close(), owner.close()), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    gate.complete();
    await starting;
    await closing;
    expect(jobs.renewals, 1);
    await expectLater(
        owner.advance(DownloadJobStage.metadata), throwsStateError);
  });
  test('heartbeat failure signals lease loss without an unhandled future',
      () async {
    jobs.failRenewal = 2;
    final lostSignal = Completer<void>();
    owner.lossControl.addCancellationListener(lostSignal.complete);
    await owner.start();
    await lostSignal.future;
    expect(owner.lost, isTrue);
    await expectLater(owner.advance(DownloadJobStage.metadata), lost());
  });
  test(
      'interrupt preserves checkpoint/budget, clears token and enables reconciliation',
      () async {
    await owner.start();
    await owner.advance(DownloadJobStage.metadata);
    final interrupted = (await owner.interrupt(DownloadFailure.internalError))!;
    expect(interrupted.state, DownloadJobState.needsReconciliation);
    expect(interrupted.stage, DownloadJobStage.metadata);
    expect(interrupted.remainingAttempts, 2);
    expect(interrupted.attemptToken, isNull);
    expect(interrupted.leaseUntil, isNull);
    final attempt = (await jobs.listAttempts(job.id)).single;
    expect(attempt.outcome, DownloadAttemptOutcome.interrupted);
    expect(attempt.failure, DownloadFailure.internalError);
  });
  test('exhausted interrupt fails without resetting the finite attempt budget',
      () async {
    await owner.close();
    await f.repositories.downloadJobs.cancel(job, now: f.now);
    final second = await f.claim(externalId: 'single');
    await f.database.customStatement(
        'UPDATE download_jobs SET remaining_attempts = 0 WHERE id = ?',
        [second.id]);
    final current = (await f.repositories.downloadJobs.findByKey(second.key))!;
    owner = DownloadLeaseOwner(job: current, jobs: jobs, clock: f.clock);
    await owner.start();
    final result = (await owner.interrupt(DownloadFailure.interrupted))!;
    expect(result.state, DownloadJobState.failed);
    expect(result.remainingAttempts, 0);
  });
}
