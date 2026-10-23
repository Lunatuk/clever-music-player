import 'dart:async';

import 'package:clever_music_player/src/android/android_audio_publisher.dart';
import 'package:clever_music_player/src/android/android_audio_publication_backend.dart';
import 'package:clever_music_player/src/android/android_publication_importer.dart';
import 'package:clever_music_player/src/android/android_publication_journal.dart';
import 'package:clever_music_player/src/android/android_publication_receipt.dart';
import 'package:clever_music_player/src/android/android_publication_verifier.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/download_lease_owner.dart';
import 'package:clever_music_player/src/library_sync/native_publication_files.dart';
import 'package:clever_music_player/src/library_sync/publication_intent.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/android_publication_fixture.dart';
import 'support/download_fixture.dart';

void main() {
  late DownloadFixture f;
  late DownloadJob job;
  late DownloadLeaseOwner owner;
  late AndroidPublicationJournal journal;
  late AndroidAudioPublisher publisher;
  late _Backend backend;
  late _Verifier verifier;
  late AndroidPublicationReceipt receipt;
  setUp(() async {
    f = await androidPublicationFixture();
    job = await f.claim(stage: DownloadJobStage.publication);
    owner = DownloadLeaseOwner(
        job: job, jobs: f.repositories.downloadJobs, clock: f.clock);
    await owner.start();
    journal = await AndroidPublicationJournal.open(privateParent: f.root);
    receipt = androidReceipt(f, job);
    backend = _Backend(receipt);
    verifier = _Verifier(receipt);
    publisher = AndroidAudioPublisher(
        journal: journal, backend: backend, verifier: verifier, clock: f.clock);
  });
  tearDown(() async {
    await publisher.close();
    await owner.close();
    await journal.close();
    await f.close();
  });
  Future<AndroidPublicationReceipt> publish([LibraryScanControl? control]) =>
      publisher.publish(
          owner: owner,
          intent: receipt.intent,
          prepared: FileAudioSource(f.raw.path),
          control: control);
  test(
      'source stays sealed until durable receipt, then native ledger is acknowledged',
      () async {
    backend.onWrite = () async {
      await expectLater(const NativePublicationFiles().lock(f.raw.path),
          throwsA(isA<PublicationFileException>()));
      await owner.withCurrent((_) async {
        await f.database
            .customSelect('SELECT COUNT(*) FROM download_jobs')
            .get();
      });
    };
    backend.onAck = () async {
      expect((await journal.pending()).single.encode(), receipt.encode());
    };
    expect((await publish()).encode(), receipt.encode());
    expect(backend.calls, ['prepare', 'write', 'ack']);
    expect(backend.saved, isEmpty);
    final released = await const NativePublicationFiles().lock(f.raw.path);
    await released.close();
    expect(
        await f.count('tracks'), 0); // publication alone never completes a job
  });
  test('late cancellation preserves a completed native result in Dart journal',
      () async {
    final control = LibraryScanControl();
    backend.onWrite = () async {
      control.cancel();
    };
    expect((await publish(control)).encode(), receipt.encode());
    expect((await journal.pending()).length, 1);
    expect(backend.saved, isEmpty);
  });
  test(
      'source-free recovery after native acknowledgement rechecks current bytes',
      () async {
    await publish();
    await f.raw.delete();
    expect((await publisher.pending(owner)).single.encode(),
        receipt.intent.encode());
    expect(
        (await publisher.reconcile(owner: owner, intent: receipt.intent))
            .encode(),
        receipt.encode());
    expect(verifier.calls, 1);
    expect(backend.writes, 1);
    await expectLater(publish(), throwsA(isA<AudioPublicationException>()));
  });
  test(
      'failed native ack leaves both ledgers; read-only recovery never recopies',
      () async {
    backend.failAck = true;
    await expectLater(publish(), throwsA(isA<AudioPublicationException>()));
    expect((await journal.pending()).length, 1);
    expect(backend.saved.length, 1);
    expect((await publisher.pending(owner)).length, 1);
    backend.failAck = false;
    expect(
        (await publisher.reconcile(owner: owner, intent: receipt.intent))
            .encode(),
        receipt.encode());
    expect(backend.writes, 1);
    expect(backend.reconciles, 1);
    expect(backend.saved, isEmpty);
  });
  test('account revoked during provider IO cannot persist an imported result',
      () async {
    backend.onWrite = () async {
      await f.repositories.remoteLibrary.activateAccount(f.account.identity);
    };
    await expectLater(publish(), throwsA(anything));
    expect(await journal.pending(), isEmpty);
    expect(backend.saved.length, 1);
    expect(await f.count('tracks'), 0);
  });
  test('lost access or short write never yields a receipt', () async {
    backend.failWrite = AudioPublicationStatus.noSpace;
    await expectLater(publish(), throwsA(isA<AudioPublicationException>()));
    expect(await journal.pending(), isEmpty);
    expect(backend.calls, ['prepare', 'write']);
  });
  test(
      'close waits for cancelled provider work and keeps unresolved native admission',
      () async {
    final entered = Completer<void>(), finish = Completer<void>();
    backend.onWrite = () async {
      entered.complete();
      await finish.future;
      throw const LibraryScanCancelled();
    };
    final action = publish();
    final error = expectLater(action, throwsA(isA<LibraryScanCancelled>()));
    await entered.future;
    var closed = false;
    final closing = publisher.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(backend.control!.isCancellationRequested, isTrue);
    expect(closed, isFalse);
    expect(backend.closed, isFalse);
    finish.complete();
    await error;
    await closing;
    expect(backend.closed, isTrue);
    expect(backend.saved.length, 1);
    expect(await journal.pending(), isEmpty);
  });
  test(
      'two publishers sharing a journal cannot race across native acknowledgement',
      () async {
    final entered = Completer<void>(), finish = Completer<void>();
    backend.onWrite = () async {
      entered.complete();
      await finish.future;
    };
    final action = publish();
    await entered.future;
    final other = AndroidAudioPublisher(
        journal: journal,
        backend: _Backend(receipt),
        verifier: _Verifier(receipt),
        clock: f.clock);
    await expectLater(
        other.publish(
            owner: owner,
            intent: receipt.intent,
            prepared: FileAudioSource(f.raw.path)),
        throwsStateError);
    await other.close();
    finish.complete();
    await action;
  });
  test('changed receipt-only document is preserved and not rewritten',
      () async {
    await publish();
    verifier.changed = true;
    await expectLater(publisher.reconcile(owner: owner, intent: receipt.intent),
        throwsA(isA<PublicationException>()));
    expect(backend.writes, 1);
    expect((await journal.pending()).length, 1);
  });
  test('publication connects to existing atomic importer and cleanup',
      () async {
    final result = await publish();
    await owner.advance(DownloadJobStage.importing);
    final importer = AndroidPublicationImporter(
        journal: journal,
        imports: f.repositories.downloadImports,
        retention: f.repositories.publicationRetention,
        verifier: _Verifier(receipt),
        clock: f.clock);
    try {
      final imported = await importer.importReceipt(
          owner: owner,
          receipt: result,
          preparedTrack: androidPreparedTrack(f, job, receipt));
      expect(imported.imported.job.state, DownloadJobState.completed);
      expect(imported.cleanupFailed, isFalse);
      expect(await journal.pending(), isEmpty);
      expect(backend.writes, 1);
      expect(await f.count('tracks'), 1);
    } finally {
      await importer.close();
    }
  });
  test('pre-cancelled operation does not reserve or write', () async {
    await expectLater(publish(LibraryScanControl()..cancel()),
        throwsA(isA<LibraryScanCancelled>()));
    expect(backend.calls, isEmpty);
    expect(await journal.pending(), isEmpty);
  });
  Future<void> reclaim() async {
    await owner.interrupt(DownloadFailure.internalError);
    await owner.close();
    job = (await f.repositories.downloadJobs.claimNext(f.account, now: f.now))!;
    expect(job.state, DownloadJobState.reconciling);
    owner = DownloadLeaseOwner(
        job: job, jobs: f.repositories.downloadJobs, clock: f.clock);
    await owner.start();
  }

  test(
      'uncreated release needs no raw file and never imports or changes checkpoint',
      () async {
    backend.saved.add(receipt.intent);
    await f.raw.delete();
    final before = owner.current;
    await publisher.releaseUncreated(owner: owner, intent: receipt.intent);
    expect(backend.calls, ['release']);
    expect(backend.saved, isEmpty);
    expect(owner.current, before);
    expect(await journal.pending(), isEmpty);
    expect(await f.count('tracks'), 0);
  });
  test('durable receipt blocks release even if the native ledger disappeared',
      () async {
    await publish();
    backend.calls.clear();
    await expectLater(
        publisher.releaseUncreated(owner: owner, intent: receipt.intent),
        throwsA(isA<AudioPublicationException>()));
    expect(backend.calls, isEmpty);
    expect((await journal.pending()).length, 1);
  });
  test('revoked destination cannot release its native admission', () async {
    backend.saved.add(receipt.intent);
    await f.repositories.remoteLibrary.activateAccount(f.account.identity);
    await expectLater(
        publisher.releaseUncreated(owner: owner, intent: receipt.intent),
        throwsA(anything));
    expect(backend.calls, isEmpty);
    expect(backend.saved.length, 1);
  });
  test('pre-cancelled release never reaches the native journal', () async {
    await expectLater(
        publisher.releaseUncreated(
            owner: owner,
            intent: receipt.intent,
            control: LibraryScanControl()..cancel()),
        throwsA(isA<LibraryScanCancelled>()));
    expect(backend.calls, isEmpty);
  });
  test('close drains an accepted private release before closing backend',
      () async {
    final entered = Completer<void>(), finish = Completer<void>();
    backend.onRelease = () async {
      entered.complete();
      await finish.future;
    };
    final action =
        publisher.releaseUncreated(owner: owner, intent: receipt.intent);
    await entered.future;
    var closed = false;
    final closing = publisher.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(backend.closed, isFalse);
    finish.complete();
    await action;
    await closing;
    expect(backend.closed, isTrue);
  });
  test('recovery rejects an ordinary running job', () async {
    await expectLater(publisher.recover(owner), throwsArgumentError);
    expect(backend.calls, isEmpty);
  });
  test('reclaimed attempt with no publication can download again', () async {
    await reclaim();
    final result = await publisher.recover(owner);
    expect(result.status, AndroidPublicationRecoveryStatus.requiresDownload);
    expect(result.receipt, isNull);
    expect(owner.current.state, DownloadJobState.reconciling);
    expect(backend.writes, 0);
  });
  test('reclaimed uncreated intent is released under the current owner',
      () async {
    backend.saved.add(receipt.intent);
    await reclaim();
    await f.raw.delete();
    final result = await publisher.recover(owner);
    expect(result.status, AndroidPublicationRecoveryStatus.requiresDownload);
    expect(backend.calls, ['release']);
    expect(backend.saved, isEmpty);
    expect(owner.current.state, DownloadJobState.reconciling);
  });
  test(
      'complete native publication recovers without a raw source or another write',
      () async {
    backend.saved.add(receipt.intent);
    backend.uncreated = false;
    await reclaim();
    await f.raw.delete();
    final result = await publisher.recover(owner);
    expect(result.status, AndroidPublicationRecoveryStatus.published);
    expect(result.receipt!.encode(), receipt.encode());
    expect(backend.reconciles, 1);
    expect(backend.writes, 0);
    expect((await journal.pending()).length, 1);
    expect(backend.saved, isEmpty);
  });
  for (final status in [
    AudioPublicationStatus.changed,
    AudioPublicationStatus.needsReconciliation,
    AudioPublicationStatus.accessDenied,
    AudioPublicationStatus.collision
  ]) {
    test(
        'unresolved publication $status remains retained without a duplicate write',
        () async {
      backend.saved.add(receipt.intent);
      backend.uncreated = false;
      backend.failReconcile = status;
      await reclaim();
      final result = await publisher.recover(owner);
      expect(result.status, AndroidPublicationRecoveryStatus.retained);
      expect(result.reason, status);
      expect(result.receipt, isNull);
      expect(backend.saved.length, 1);
      expect(backend.writes, 0);
      expect(await journal.pending(), isEmpty);
      expect(await f.count('tracks'), 0);
    });
  }
  test('receipt-only recovery rechecks bytes and never releases native state',
      () async {
    await publish();
    backend.calls.clear();
    await reclaim();
    final result = await publisher.recover(owner);
    expect(result.status, AndroidPublicationRecoveryStatus.published);
    expect(verifier.calls, 1);
    expect(backend.calls, isEmpty);
  });
  test('changed receipt-only recovery remains retained', () async {
    await publish();
    verifier.changed = true;
    await reclaim();
    final result = await publisher.recover(owner);
    expect(result.status, AndroidPublicationRecoveryStatus.retained);
    expect(result.reason, AudioPublicationStatus.changed);
    expect((await journal.pending()).length, 1);
    expect(backend.writes, 1);
  });
  test('multiple candidates cannot discard one intent and create a duplicate',
      () async {
    backend.saved.addAll([
      receipt.intent,
      PublicationIntent(
          publicationId: 'd' * 64,
          jobId: job.id,
          key: job.key,
          verification: f.proof())
    ]);
    await reclaim();
    final result = await publisher.recover(owner);
    expect(result.status, AndroidPublicationRecoveryStatus.retained);
    expect(backend.calls, isEmpty);
    expect(backend.saved.length, 2);
  });
  test(
      'unrecognized native failure is not converted to permission to redownload',
      () async {
    backend.saved.add(receipt.intent);
    backend.uncreated = false;
    backend.failReconcile = AudioPublicationStatus.io;
    await reclaim();
    await expectLater(
        publisher.recover(owner), throwsA(isA<AudioPublicationException>()));
    expect(backend.saved.length, 1);
    expect(backend.writes, 0);
  });
}

final class _Backend implements AudioPublicationBackend {
  _Backend(this.receipt);
  final AndroidPublicationReceipt receipt;
  final calls = <String>[];
  final saved = <PublicationIntent>[];
  Future<void> Function()? onWrite, onAck, onRelease;
  bool uncreated = true;
  AudioPublicationStatus? failWrite, failReconcile;
  bool failAck = false, closed = false;
  int writes = 0, reconciles = 0;
  LibraryScanControl? control;
  @override
  Future<void> prepare(AudioPublicationRequest request) async {
    calls.add('prepare');
    saved.add(request.intent);
  }

  @override
  Future<void> releaseUncreated(AudioPublicationRequest request) async {
    calls.add('release');
    await onRelease?.call();
    if (!uncreated) {
      throw const AudioPublicationException(
          AudioPublicationStatus.needsReconciliation);
    }
    saved.clear();
  }

  @override
  Future<AndroidPublicationReceipt> publish(AudioPublicationRequest request,
      FileAudioSource source, LibraryScanControl control) async {
    calls.add('write');
    writes++;
    this.control = control;
    await onWrite?.call();
    if (failWrite != null) {
      throw AudioPublicationException(failWrite!);
    }
    return receipt;
  }

  @override
  Future<AndroidPublicationReceipt> reconcile(
      AudioPublicationRequest request, LibraryScanControl control) async {
    reconciles++;
    if (failReconcile != null) throw AudioPublicationException(failReconcile!);
    return receipt;
  }

  @override
  Future<List<PublicationIntent>> pending(ContentUriAudioSource tree) async =>
      List.of(saved);
  @override
  Future<void> acknowledge(
      AudioPublicationRequest request, ContentUriAudioSource document) async {
    calls.add('ack');
    await onAck?.call();
    if (failAck) {
      throw const AudioPublicationException(AudioPublicationStatus.io);
    }
    saved.clear();
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

final class _Verifier implements PublicationDocumentVerifier {
  _Verifier(this.receipt);
  final AndroidPublicationReceipt receipt;
  int calls = 0;
  bool changed = false;
  @override
  Future<SourceFingerprintResult> verify(
      AndroidPublicationReceipt receipt, LibraryScanControl control) async {
    calls++;
    return changed
        ? SourceFingerprintResult.failure(SourceFingerprintStatus.changed)
        : SourceFingerprintResult.fingerprinted(
            receipt.intent.verification.fileSizeBytes,
            receipt.intent.verification.contentHash);
  }

  @override
  Future<void> close() async {}
}
