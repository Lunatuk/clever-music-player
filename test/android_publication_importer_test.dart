import 'dart:async';

import 'package:clever_music_player/src/android/android_publication_importer.dart';
import 'package:clever_music_player/src/android/android_publication_journal.dart';
import 'package:clever_music_player/src/android/android_publication_receipt.dart';
import 'package:clever_music_player/src/android/android_publication_verifier.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/download_lease_owner.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/android_publication_fixture.dart';
import 'support/download_fixture.dart';

void main() {
  late DownloadFixture f;
  late DownloadJob job;
  late AndroidPublicationReceipt receipt;
  late DownloadLeaseOwner owner;
  late AndroidPublicationJournal journal;
  late AndroidPublicationImporter importer;
  late _Verifier verifier;
  setUp(() async {
    f = await androidPublicationFixture();
    job = await f.claim(stage: DownloadJobStage.importing);
    receipt = androidReceipt(f, job);
    owner = DownloadLeaseOwner(
        job: job, jobs: f.repositories.downloadJobs, clock: f.clock);
    await owner.start();
    journal = await AndroidPublicationJournal.open(privateParent: f.root);
    verifier = _Verifier(receipt);
    importer = AndroidPublicationImporter(
        journal: journal,
        imports: f.repositories.downloadImports,
        retention: f.repositories.publicationRetention,
        verifier: verifier,
        clock: f.clock);
  });
  tearDown(() async {
    await importer.close();
    await owner.close();
    await journal.close();
    await f.close();
  });
  Future<AndroidPublicationImportResult> run({LibraryScanControl? control}) =>
      importer.importReceipt(
          owner: owner,
          receipt: receipt,
          preparedTrack: androidPreparedTrack(f, job, receipt),
          control: control);
  test('fresh provider evidence atomically imports and retires private receipt',
      () async {
    f.now = f.now.add(const Duration(seconds: 1));
    final result = await run();
    expect(result.imported.job.state, DownloadJobState.completed);
    expect(result.imported.asset.verification.checkedAt, f.now);
    expect(result.cleanupFailed, isFalse);
    expect(await journal.pending(), isEmpty);
    expect(await f.count('tracks'), 1);
    expect(verifier.calls, 1);
  });
  for (final status in [
    SourceFingerprintStatus.changed,
    SourceFingerprintStatus.missing,
    SourceFingerprintStatus.accessDenied,
    SourceFingerprintStatus.unreadable
  ]) {
    test('$status preserves receipt and performs no DB import', () async {
      verifier.result = SourceFingerprintResult.failure(status);
      await expectLater(
          run(), throwsA(isA<AndroidPublicationVerificationException>()));
      expect(await f.count('tracks'), 0);
      expect((await journal.pending()).length, 1);
      expect(owner.current.state, DownloadJobState.running);
    });
  }
  test('producer or verifier cannot substitute different bytes', () async {
    verifier.result = SourceFingerprintResult.fingerprinted(3, 'b' * 64);
    await expectLater(
        run(), throwsA(isA<AndroidPublicationVerificationException>()));
    expect(await f.count('tracks'), 0);
    expect((await journal.pending()).length, 1);
  });
  test('lease can renew during provider IO; import uses current revision',
      () async {
    await owner.close();
    owner = DownloadLeaseOwner(
        job: (await f.repositories.downloadJobs.findByKey(job.key))!,
        jobs: f.repositories.downloadJobs,
        clock: f.clock,
        heartbeatEvery: const Duration(milliseconds: 10));
    await owner.start();
    verifier.action = () async {
      final before = owner.current.revision;
      f.now = f.now.add(const Duration(seconds: 1));
      await Future.doWhile(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return owner.current.revision == before;
      }).timeout(const Duration(seconds: 3));
      expect(owner.current.revision, greaterThan(before));
    };
    final result = await run();
    expect(result.imported.job.state, DownloadJobState.completed);
  });
  test(
      'account changes during readback prevent completion and preserve receipt',
      () async {
    verifier.action = () async {
      await f.repositories.remoteLibrary.activateAccount(f.account.identity);
    };
    await expectLater(run(), throwsA(anything));
    expect(await f.count('tracks'), 0);
    expect((await journal.pending()).length, 1);
  });
  test('SQL import failure preserves physical receipt for a later retry',
      () async {
    await f.database.customStatement(
        "CREATE TRIGGER reject BEFORE INSERT ON downloaded_assets BEGIN SELECT RAISE(ABORT, 'test'); END");
    await expectLater(run(), throwsA(anything));
    expect(await f.count('tracks'), 0);
    expect((await journal.pending()).length, 1);
    await f.database.customStatement('DROP TRIGGER reject');
    expect((await run()).imported.job.state, DownloadJobState.completed);
  });
  test('close cancels provider IO, drains it and only then closes verifier',
      () async {
    final entered = Completer<void>(), finish = Completer<void>();
    verifier.action = () async {
      entered.complete();
      await finish.future;
    };
    final running = run();
    final rejected = expectLater(running, throwsA(isA<LibraryScanCancelled>()));
    await entered.future;
    var closed = false;
    final closing = importer.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(verifier.control!.isCancellationRequested, isTrue);
    expect(closed, isFalse);
    expect(verifier.closed, isFalse);
    finish.complete();
    await rejected;
    await closing;
    expect(verifier.closed, isTrue);
    expect((await journal.pending()).length, 1);
    expect(await f.count('tracks'), 0);
    await expectLater(run(), throwsStateError);
  });
  test('completed import stays completed if private receipt cleanup fails',
      () async {
    // Revoke cleanup authority immediately after the completed DB write.
    // Completion must not be retried or rolled back due to private cleanup.
    verifier.action = () async {
      await f.database.customStatement(
          "CREATE TRIGGER after_complete AFTER UPDATE ON download_jobs WHEN NEW.state = 'completed' BEGIN UPDATE library_folders SET is_enabled = 0 WHERE id = NEW.library_folder_id; END");
    };
    final result = await run();
    expect(result.imported.job.state, DownloadJobState.completed);
    expect(result.cleanupFailed, isTrue);
    expect((await journal.pending()).length, 1);
  });
  test(
      'persistent receipt and queue recover after process loss without a new publication',
      () async {
    await importer.close();
    await owner.close();
    await journal.close();
    await f.close();
    f = await androidPublicationFixture(persistent: true);
    job = await f.claim(stage: DownloadJobStage.importing);
    receipt = androidReceipt(f, job);
    journal = await AndroidPublicationJournal.open(privateParent: f.root);
    await journal.record(receipt,
        job: job,
        jobs: f.repositories.downloadJobs,
        clock: f.clock,
        control: LibraryScanControl());
    await journal.close();
    f.now = job.leaseUntil!.add(const Duration(microseconds: 1));
    f = await f.reopen();
    expect(await f.repositories.downloadJobs.recoverExpired(now: f.now), 1);
    final claimed =
        (await f.repositories.downloadJobs.claimNext(f.account, now: f.now))!;
    expect(claimed.state, DownloadJobState.reconciling);
    job = (await f.repositories.downloadJobs.resolveReconciliation(
        claimed, DownloadJobStage.importing,
        now: f.now))!;
    owner = DownloadLeaseOwner(
        job: job, jobs: f.repositories.downloadJobs, clock: f.clock);
    await owner.start();
    journal = await AndroidPublicationJournal.open(privateParent: f.root);
    receipt = (await journal.pending()).single;
    verifier = _Verifier(receipt);
    importer = AndroidPublicationImporter(
        journal: journal,
        imports: f.repositories.downloadImports,
        retention: f.repositories.publicationRetention,
        verifier: verifier,
        clock: f.clock);
    final result = await run();
    expect(result.imported.asset.publication.publicationId,
        receipt.intent.publicationId);
    expect(result.imported.asset.verification.checkedAt, f.now);
    expect((await f.repositories.downloadJobs.listAttempts(job.id)).length, 2);
    expect(await f.count('tracks'), 1);
    expect(await journal.pending(), isEmpty);
  });
}

final class _Verifier implements PublicationDocumentVerifier {
  _Verifier(AndroidPublicationReceipt receipt)
      : result = SourceFingerprintResult.fingerprinted(
            receipt.intent.verification.fileSizeBytes,
            receipt.intent.verification.contentHash);
  SourceFingerprintResult result;
  Future<void> Function()? action;
  LibraryScanControl? control;
  int calls = 0;
  bool closed = false;
  @override
  Future<SourceFingerprintResult> verify(
      AndroidPublicationReceipt receipt, LibraryScanControl control) async {
    calls++;
    this.control = control;
    await action?.call();
    return result;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
