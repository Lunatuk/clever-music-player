import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/desktop_download_coordinator.dart';
import 'package:clever_music_player/src/library_sync/desktop_publication_store.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata_preparer.dart';
import 'package:clever_music_player/src/library_sync/native_publication_files.dart';
import 'package:clever_music_player/src/library_sync/publication_intent.dart';
import 'package:clever_music_player/src/library_sync/publication_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/download_fixture.dart';
import 'support/recording_download_jobs.dart';

void main() {
  late DownloadFixture f;
  late DownloadJob job;
  late DesktopDownloadCoordinator coordinator;
  late DownloadTestBackend backend;
  late DownloadTestMetadataReader reader;
  late RecordingDownloadJobs jobs;
  late _Files files;
  setUp(() async {
    f = await DownloadFixture.open();
    job = await f.claim();
    backend = DownloadTestBackend();
    reader = DownloadTestMetadataReader();
    jobs = RecordingDownloadJobs(f.repositories.downloadJobs);
    files = _Files();
    coordinator = DesktopDownloadCoordinator(
        jobs: jobs,
        imports: f.repositories.downloadImports,
        retention: f.repositories.publicationRetention,
        preparer: DownloadedAudioMetadataPreparer(
            backend: backend, temporaryParent: f.root, clock: f.clock),
        metadataReader: reader,
        artworkCache: const NoopArtworkCacheService(),
        files: files,
        clock: f.clock,
        leaseFor: const Duration(seconds: 2),
        heartbeatEvery: const Duration(milliseconds: 30));
  });
  tearDown(() async {
    await coordinator.close();
    await f.close();
  });
  Future<DownloadCoordinationResult> run(
          {DownloadJob? current, LibraryScanControl? control}) =>
      coordinator.processDownloadedFile(
          current ?? job, FileAudioSource(f.raw.path), downloadExpectation(),
          control: control);
  Future<List<File>> published() async => (await f.destination.list().toList())
      .whereType<File>()
      .where((file) => file.path.endsWith('.mp3'))
      .toList();
  Future<void> rejectImport() => f.database.customStatement(
      "CREATE TRIGGER reject_import BEFORE INSERT ON downloaded_assets BEGIN SELECT RAISE(ABORT, 'synthetic'); END");
  Future<DownloadJob> recoverable() async =>
      (await f.repositories.downloadJobs.claimNext(f.account, now: f.now))!;
  Future<void> noImport() async {
    for (final table in [
      'tracks',
      'external_track_refs',
      'downloaded_assets'
    ]) {
      expect(await f.count(table), 0, reason: table);
    }
  }

  test('preparation/publication/atomic import completes one real attempt',
      () async {
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.completed);
    expect(result.job.state, DownloadJobState.completed);
    expect(result.cleanupFailed, isFalse);
    expect(result.imported!.track.title, 'Provider title');
    expect(result.imported!.track.albumArtist, 'Album artist');
    expect((await published()).single.path, result.imported!.track.filePath);
    expect(await f.raw.readAsString(), 'abc');
    expect(backend.writes, 1);
    expect(await f.count('tracks'), 1);
    expect(await f.count('external_track_refs'), 1);
    expect(await f.count('downloaded_assets'), 1);
  });
  test('pre-cancel creates no publication or workspace', () async {
    final result = await run(control: LibraryScanControl()..cancel());
    expect(result.outcome, DownloadCoordinationOutcome.cancelled);
    expect(result.job.state, DownloadJobState.cancelled);
    expect(await published(), isEmpty);
    expect(
        await Directory(p.join(f.destination.path, '.cmp-publications-v1'))
            .exists(),
        isFalse);
    expect(backend.writes, 0);
    await noImport();
  });
  test('next coordinated job cleans a completed journal and keeps both songs',
      () async {
    final first = await run();
    final operation = Directory(p.join(
        f.destination.path,
        '.cmp-publications-v1',
        'operations',
        '${publicationResourceKey(job.key)}-${first.imported!.asset.publication.publicationId}'));
    expect(await operation.exists(), isTrue);
    final second = await f.claim(externalId: '002');
    expect((await run(current: second)).outcome,
        DownloadCoordinationOutcome.completed);
    expect(await operation.exists(), isFalse);
    expect(await published(), hasLength(2));
    expect(await f.count('tracks'), 2);
  });
  test(
      'quota failure reports noSpace without partial import or touching raw file',
      () async {
    await coordinator.close();
    backend = DownloadTestBackend();
    coordinator = DesktopDownloadCoordinator(
        jobs: jobs,
        imports: f.repositories.downloadImports,
        retention: f.repositories.publicationRetention,
        preparer: DownloadedAudioMetadataPreparer(
            backend: backend, temporaryParent: f.root, clock: f.clock),
        metadataReader: reader,
        artworkCache: const NoopArtworkCacheService(),
        clock: f.clock,
        retentionPolicy: PublicationRetentionPolicy(maxStagingBytes: 2));
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.failed);
    expect(result.failure, DownloadFailure.noSpace);
    expect(await f.raw.readAsString(), 'abc');
    expect(await published(), isEmpty);
    await noImport();
  });
  test(
      'quota lock contention after preparation reconciles before retrying download',
      () async {
    // Initialize the owned state without any publication operation.
    final initializer = DesktopPublicationStore(jobs: jobs, clock: f.clock);
    await initializer.run(job, (_) async {});
    await initializer.close();
    final path = p.join(
        f.destination.path, '.cmp-publications-v1', 'locks', 'quota.lock');
    await File(path).create();
    final held = await const NativePublicationFiles().lock(path);
    try {
      final result = await run();
      expect(result.outcome, DownloadCoordinationOutcome.needsReconciliation);
      expect(result.job.state, DownloadJobState.needsReconciliation);
    } finally {
      await held.close();
    }
    final recovery =
        (await f.repositories.downloadJobs.claimNext(f.account, now: f.now))!;
    final result = await coordinator.recover(recovery);
    expect(result.outcome, DownloadCoordinationOutcome.requiresDownload);
    expect(result.job.stage, DownloadJobStage.download);
    expect((await run(current: result.job)).outcome,
        DownloadCoordinationOutcome.completed);
  });
  test('invalid source/media fails without changing source or sibling files',
      () async {
    backend.reject = true;
    final sentinel = await File(p.join(f.destination.path, 'foreign.txt'))
        .writeAsString('keep');
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.failed);
    expect(result.job.failure, DownloadFailure.invalidMedia);
    expect(result.job.state, DownloadJobState.failed);
    expect(await sentinel.readAsString(), 'keep');
    expect(await f.raw.readAsString(), 'abc');
    expect(await published(), isEmpty);
    await noImport();
  });
  test('short/wrong-size downloaded file cannot publish', () async {
    await f.raw.writeAsString('ab');
    expect((await run()).outcome, DownloadCoordinationOutcome.failed);
    expect(await published(), isEmpty);
    await noImport();
  });
  test('cancellation while preparing drains and cancels current attempt',
      () async {
    final entered = Completer<void>(), gate = Completer<void>();
    backend.onWrite = (_) async {
      entered.complete();
      await gate.future;
    };
    final control = LibraryScanControl();
    final pending = run(control: control);
    await entered.future;
    control.cancel();
    gate.complete();
    final result = await pending;
    expect(result.outcome, DownloadCoordinationOutcome.cancelled);
    expect(result.job.state, DownloadJobState.cancelled);
    expect(await published(), isEmpty);
    await noImport();
  });
  test(
      'heartbeat during a publisher seal uses the fresh revision of the same attempt',
      () async {
    var waited = false;
    files.onSeal = (_) async {
      if (!waited) {
        waited = true;
        await jobs.nextRenewal();
      }
    };
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.completed);
    expect(jobs.renewals, greaterThanOrEqualTo(2));
    expect(result.job.attemptCount, 1);
  });
  test(
      'busy OS lock retains the same attempt and can retry without a new claim',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    final holder = DesktopPublicationStore(
        jobs: f.repositories.downloadJobs, clock: f.clock);
    final held = holder.run(job, (_) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final busy = await run();
    expect(busy.outcome, DownloadCoordinationOutcome.busy);
    expect(busy.job.attemptCount, 1);
    expect(backend.writes, 0);
    release.complete();
    await held;
    await holder.close();
    final result = await run(current: busy.job);
    expect(result.outcome, DownloadCoordinationOutcome.completed);
    expect(result.job.attemptCount, 1);
  });
  test('close rejects new work and drains a forgotten accepted future',
      () async {
    final entered = Completer<void>(), gate = Completer<void>();
    backend.onWrite = (_) async {
      entered.complete();
      await gate.future;
    };
    final pending = run();
    await entered.future;
    await expectLater(run(), throwsStateError);
    var closed = false;
    final closing = coordinator.close().then((_) => closed = true);
    expect(identical(coordinator.close(), coordinator.close()), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    gate.complete();
    await closing;
    expect(backend.closed, isTrue);
    expect((await pending).outcome, DownloadCoordinationOutcome.cancelled);
    await expectLater(run(), throwsStateError);
  });
  test(
      'DB failure after move leaves a recoverable file, then imports without downloading again',
      () async {
    await rejectImport();
    final failed = await run();
    expect(failed.outcome, DownloadCoordinationOutcome.needsReconciliation);
    expect(failed.job.state, DownloadJobState.needsReconciliation);
    expect(failed.job.stage, DownloadJobStage.importing);
    expect(await published(), hasLength(1));
    await noImport();
    await f.database.customStatement('DROP TRIGGER reject_import');
    f.now = f.now.add(const Duration(seconds: 1));
    final recovered = await coordinator.recover(await recoverable());
    expect(recovered.outcome, DownloadCoordinationOutcome.completed);
    expect(recovered.job.attemptCount, 2);
    expect(backend.writes, 1);
    expect(await published(), hasLength(1));
    expect(await f.count('tracks'), 1);
  });
  test('late cancel after accepted move drains successful import', () async {
    final control = LibraryScanControl();
    files.afterMove = (source, target) async {
      if (p.basename(source) == 'audio.part' && target.endsWith('.mp3')) {
        control.cancel();
      }
    };
    final result = await run(control: control);
    expect(control.isCancellationRequested, isTrue);
    expect(result.outcome, DownloadCoordinationOutcome.completed);
    expect(result.job.state, DownloadJobState.completed);
    expect(await f.count('tracks'), 1);
  });
  test('changed published bytes are never imported during recovery', () async {
    await rejectImport();
    await run();
    await f.database.customStatement('DROP TRIGGER reject_import');
    await (await published()).single.writeAsString('bad');
    final result = await coordinator.recover(await recoverable());
    expect(result.outcome, DownloadCoordinationOutcome.needsReconciliation);
    await noImport();
    expect(await (await published()).single.readAsString(), 'bad');
  });
  test(
      'missing publication rewinds to download; next run creates only one new result',
      () async {
    await rejectImport();
    await run();
    await f.database.customStatement('DROP TRIGGER reject_import');
    await (await published()).single.delete();
    final recovered = await coordinator.recover(await recoverable());
    expect(recovered.outcome, DownloadCoordinationOutcome.requiresDownload);
    expect(recovered.job.stage, DownloadJobStage.download);
    final result = await run(current: recovered.job);
    expect(result.outcome, DownloadCoordinationOutcome.completed);
    expect(await published(), hasLength(1));
    expect(await f.count('tracks'), 1);
  });
  test(
      'two published journal candidates are retained and never guessed between',
      () async {
    await rejectImport();
    await run();
    await f.database.customStatement('DROP TRIGGER reject_import');
    final intent = PublicationIntent(
        publicationId: 'b' * 64,
        jobId: job.id,
        key: job.key,
        verification: f.proof());
    final operation = Directory(p.join(f.destination.path,
        '.cmp-publications-v1', 'operations', intent.operationName));
    await operation.create();
    await File(p.join(operation.path, 'intent.json'))
        .writeAsString(intent.encode());
    await File(p.join(f.destination.path, intent.fileName))
        .writeAsString('abc');
    final result = await coordinator.recover(await recoverable());
    expect(result.outcome, DownloadCoordinationOutcome.needsReconciliation);
    expect(await published(), hasLength(2));
    await noImport();
  });
  for (final revocation in ['account', 'folder']) {
    test('$revocation change during preparation fences the old owner',
        () async {
      backend.onWrite = (_) async {
        if (revocation == 'account') {
          await f.repositories.remoteLibrary
              .activateAccount(f.account.identity);
        } else {
          await f.repositories.libraryFolders
              .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now);
        }
      };
      final result = await run();
      expect(result.outcome, DownloadCoordinationOutcome.ownershipLost);
      expect(await published(), isEmpty);
      await noImport();
    });
  }
  test(
      'folder revocation after publication preserves file but prevents all import rows',
      () async {
    reader.onRead = (_) async => f.repositories.libraryFolders
        .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now);
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.ownershipLost);
    expect(await published(), hasLength(1));
    await noImport();
  });
  test(
      'tag reader failure leaves recovery pending, never filename-derived metadata',
      () async {
    reader.fail = true;
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.needsReconciliation);
    await noImport();
    reader.fail = false;
    expect((await coordinator.recover(await recoverable())).outcome,
        DownloadCoordinationOutcome.completed);
  });
  test(
      'a busy final-file seal after publication requires reconciliation, not a fresh download retry',
      () async {
    files.onSeal = (path) async {
      if (path.endsWith('.mp3')) {
        throw const PublicationFileException(PublicationFileFailure.busy);
      }
    };
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.needsReconciliation);
    expect(result.job.state, DownloadJobState.needsReconciliation);
    expect(await published(), hasLength(1));
    await noImport();
  });
  test('a failed DB release retains its checkpoint for expiry recovery',
      () async {
    await rejectImport();
    reader.onRead = (_) async {
      await f.database.customStatement(
          "CREATE TRIGGER reject_release BEFORE UPDATE ON download_jobs WHEN NEW.state = 'needsReconciliation' BEGIN SELECT RAISE(ABORT, 'synthetic'); END");
    };
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.needsReconciliation);
    expect(result.job.state, DownloadJobState.running);
    expect(result.job.stage, DownloadJobStage.importing);
    expect(await published(), hasLength(1));
    await noImport();
    await f.database.customStatement('DROP TRIGGER reject_release');
    await f.database.customStatement('DROP TRIGGER reject_import');
    f.now = result.job.leaseUntil!;
    expect(await f.repositories.downloadJobs.recoverExpired(now: f.now), 1);
    expect((await f.repositories.downloadJobs.findByKey(job.key))!.state,
        DownloadJobState.needsReconciliation);
  });
  test(
      'lease expiry before final import retains file without a stale completion',
      () async {
    reader.onRead = (_) async {
      final current = (await f.repositories.downloadJobs.findByKey(job.key))!;
      f.now = current.leaseUntil!;
    };
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.ownershipLost);
    expect(await published(), hasLength(1));
    await noImport();
  });
  test(
      'heartbeat DB failure cancels processing instead of letting an unproven lease publish',
      () async {
    jobs.failRenewal = 2;
    backend.onWrite = (control) async {
      final cancelled = Completer<void>();
      control.addCancellationListener(cancelled.complete);
      await cancelled.future;
    };
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.ownershipLost);
    expect(await published(), isEmpty);
    await noImport();
  });
  test('one coordinator handles sequential jobs without title-based merging',
      () async {
    expect((await run()).outcome, DownloadCoordinationOutcome.completed);
    final second = await f.claim(externalId: '002');
    expect((await run(current: second)).outcome,
        DownloadCoordinationOutcome.completed);
    expect(await f.count('tracks'), 2);
    expect(await published(), hasLength(2));
  });
}

final class _Files implements PublicationFiles {
  final inner = const NativePublicationFiles();
  Future<void> Function(String)? onSeal;
  Future<void> Function(String, String)? afterMove;
  @override
  Future<bool> createDirectory(String path) => inner.createDirectory(path);
  @override
  Future<PublicationFileLock> lock(String path, {bool seal = false}) async {
    final value = await inner.lock(path, seal: seal);
    if (seal) {
      try {
        await onSeal?.call(path);
      } on Object {
        await value.close();
        rethrow;
      }
    }
    return value;
  }

  @override
  Future<void> moveNoReplace(String source, String target) async {
    await inner.moveNoReplace(source, target);
    await afterMove?.call(source, target);
  }
}
