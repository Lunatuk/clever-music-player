import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/android/android_download_coordinator.dart';
import 'package:clever_music_player/src/android/android_audio_publication_backend.dart';
import 'package:clever_music_player/src/android/android_publication_journal.dart';
import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/download_coordination.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata_preparer.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:clever_music_player/src/library_sync/publication_intent.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/android_download_provider.dart';
import 'support/android_publication_fixture.dart';
import 'support/download_fixture.dart';
import 'support/recording_download_jobs.dart';

void main() {
  late DownloadFixture f;
  late DownloadJob job;
  late AndroidDownloadCoordinator coordinator;
  late AndroidPublicationJournal journal;
  late DownloadTestBackend media;
  late AndroidDownloadProvider provider;
  late RecordingDownloadJobs jobs;
  AndroidDownloadCoordinator compose({bool failingFactory = false}) =>
      AndroidDownloadCoordinator(
          jobs: jobs,
          imports: f.repositories.downloadImports,
          retention: f.repositories.publicationRetention,
          preparer: DownloadedAudioMetadataPreparer(
              backend: media, temporaryParent: f.root, clock: f.clock),
          journal: journal,
          artworkCache: const NoopArtworkCacheService(),
          backendFactory: provider.backend,
          verifierFactory: failingFactory
              ? () => throw StateError('synthetic factory failure')
              : provider.verifier,
          readDocument: provider.read,
          clock: f.clock,
          heartbeatEvery: const Duration(milliseconds: 20));
  setUp(() async {
    f = await androidPublicationFixture();
    job = await f.claim();
    jobs = RecordingDownloadJobs(f.repositories.downloadJobs);
    journal = await AndroidPublicationJournal.open(privateParent: f.root);
    media = DownloadTestBackend();
    provider = AndroidDownloadProvider(Directory('${f.root.path}/provider'));
    coordinator = compose();
  });
  tearDown(() async {
    await coordinator.close();
    await journal.close();
    await f.close();
  });
  Future<DownloadCoordinationResult> run({LibraryScanControl? control}) =>
      coordinator.processDownloadedFile(
          job, FileAudioSource(f.raw.path), downloadExpectation(),
          control: control);
  Future<DownloadJob> reclaim() async =>
      (await f.repositories.downloadJobs.claimNext(f.account, now: f.now))!;
  Future<void> rejectImport() => f.database.customStatement(
      "CREATE TRIGGER reject_import BEFORE INSERT ON downloaded_assets BEGIN SELECT RAISE(ABORT, 'synthetic'); END");

  test(
      'prepared bytes -> opaque document -> atomic Track/ref/asset/completed job',
      () async {
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.completed);
    expect(result.job.state, DownloadJobState.completed);
    expect(result.imported!.track.source, isA<ContentUriAudioSource>());
    expect(result.imported!.track.title, 'Provider title');
    expect(result.imported!.track.albumArtist, 'Album artist');
    expect(result.cleanupFailed, isFalse);
    expect(await journal.pending(), isEmpty);
    expect(provider.intents, isEmpty);
    expect(await f.count('tracks'), 1);
    expect(await f.count('external_track_refs'), 1);
    expect(await f.count('downloaded_assets'), 1);
    expect(media.writes, 1);
    expect(provider.writes, 1);
    expect(provider.backendCloses, 1);
    expect(provider.verifierCloses, 2);
    expect(await f.raw.readAsString(), 'abc');
  });
  test(
      'SQLite rollback leaves receipt and recovers without raw or another write',
      () async {
    await rejectImport();
    final first = await run();
    expect(first.outcome, DownloadCoordinationOutcome.needsReconciliation);
    expect(await f.count('tracks'), 0);
    expect((await journal.pending()).length, 1);
    await f.database.customStatement('DROP TRIGGER reject_import');
    await f.raw.delete();
    final result = await coordinator.recover(await reclaim());
    expect(result.outcome, DownloadCoordinationOutcome.completed);
    expect(provider.writes, 1);
    expect(media.writes, 1);
    expect(provider.reconciles, 0); // native ack had already completed
    expect(await journal.pending(), isEmpty);
  });
  test('native ack failure recovers both ledgers without copying again',
      () async {
    provider.failAck = true;
    expect(
        (await run()).outcome, DownloadCoordinationOutcome.needsReconciliation);
    expect((await journal.pending()).length, 1);
    expect(provider.intents.length, 1);
    provider.failAck = false;
    await f.raw.delete();
    expect((await coordinator.recover(await reclaim())).outcome,
        DownloadCoordinationOutcome.completed);
    expect(provider.writes, 1);
    expect(provider.reconciles, 1);
  });
  test(
      'partial provider write stays quarantined and cannot import or redownload',
      () async {
    provider.partial = true;
    provider.failWrite = AudioPublicationStatus.noSpace;
    final first = await run();
    expect(first.failure, DownloadFailure.noSpace);
    expect(first.outcome, DownloadCoordinationOutcome.needsReconciliation);
    provider.failWrite = null;
    await f.raw.delete();
    final result = await coordinator.recover(await reclaim());
    expect(result.outcome, DownloadCoordinationOutcome.needsReconciliation);
    expect(result.failure, DownloadFailure.invalidMedia);
    expect(provider.writes, 1);
    expect(media.writes, 1);
    expect(provider.intents.length, 1);
    expect(await provider.files.values.single.readAsString(), 'a');
    expect(await f.count('tracks'), 0);
  });
  test(
      'uncreated admission can rewind to download; cleanup failure remains visible',
      () async {
    provider.failPrepare = AudioPublicationStatus.noSpace;
    expect(
        (await run()).outcome, DownloadCoordinationOutcome.needsReconciliation);
    provider.failPrepare = null;
    provider.failClose = true;
    final result = await coordinator.recover(await reclaim());
    expect(result.outcome, DownloadCoordinationOutcome.requiresDownload);
    expect(result.job.stage, DownloadJobStage.download);
    expect(result.job.state, DownloadJobState.running);
    expect(result.cleanupFailed, isTrue);
    expect(provider.writes, 0);
  });
  test('bad audio fails before any provider mutation', () async {
    media.reject = true;
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.failed);
    expect(result.failure, DownloadFailure.invalidMedia);
    expect(result.job.state, DownloadJobState.failed);
    expect(provider.preparations, 0);
    expect(provider.writes, 0);
  });
  test('pre-cancelled call closes admission without touching provider',
      () async {
    final result = await run(control: LibraryScanControl()..cancel());
    expect(result.outcome, DownloadCoordinationOutcome.cancelled);
    expect(provider.writes, 0);
    expect(provider.backendCloses, 0);
  });
  test('cancellation during preparation never publishes', () async {
    media.onWrite = (control) async {
      control.cancel();
    };
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.cancelled);
    expect(provider.writes, 0);
  });
  test('accepted publication drains import after late caller cancellation',
      () async {
    final control = LibraryScanControl();
    provider.onWrite = (_) async {
      control.cancel();
    };
    final result = await run(control: control);
    expect(result.outcome, DownloadCoordinationOutcome.completed);
    expect(result.job.state, DownloadJobState.completed);
    expect(await journal.pending(), isEmpty);
  });
  test(
      'closing coordinator drains accepted publication before closing preparer',
      () async {
    final entered = Completer<void>(), finish = Completer<void>();
    provider.onWrite = (_) async {
      entered.complete();
      await finish.future;
    };
    final action = run();
    await entered.future;
    var closed = false;
    final closing = coordinator.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(media.closed, isFalse);
    finish.complete();
    expect((await action).outcome, DownloadCoordinationOutcome.completed);
    await closing;
    expect(media.closed, isTrue);
    await expectLater(run(), throwsStateError);
  });
  test('a second job cannot interleave publication or metadata reading',
      () async {
    final entered = Completer<void>(), finish = Completer<void>();
    provider.onWrite = (_) async {
      entered.complete();
      await finish.future;
    };
    final action = run();
    await entered.future;
    await expectLater(run(), throwsStateError);
    finish.complete();
    expect((await action).outcome, DownloadCoordinationOutcome.completed);
    expect(provider.writes, 1);
  });
  for (final moment in ['pending', 'metadata', 'verification']) {
    test('account revoked during $moment prevents completion', () async {
      Future<void> revoke() async {
        await f.repositories.remoteLibrary.activateAccount(f.account.identity);
      }

      if (moment == 'pending') provider.onPending = revoke;
      if (moment == 'metadata') provider.onMetadata = revoke;
      if (moment == 'verification') provider.onVerify = revoke;
      final result = await run();
      expect(result.outcome, DownloadCoordinationOutcome.ownershipLost);
      expect(await f.count('tracks'), 0);
      expect(provider.writes, moment == 'pending' ? 0 : 1);
    });
  }
  for (final status in [
    SourceFingerprintStatus.changed,
    SourceFingerprintStatus.accessDenied,
    SourceFingerprintStatus.missing,
    SourceFingerprintStatus.unreadable
  ]) {
    test('fresh $status after metadata keeps receipt instead of completing',
        () async {
      provider.failVerify = status;
      final result = await run();
      expect(result.outcome, DownloadCoordinationOutcome.needsReconciliation);
      expect((await journal.pending()).length, 1);
      expect(await f.count('tracks'), 0);
    });
  }
  test('opaque generated filename is never substituted for unreadable tags',
      () async {
    provider.metadata = (file, receipt) async => AudioDocumentMetadata(
        name: receipt.intent.fileName,
        size: await file.length(),
        duration: receipt.intent.verification.duration);
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.needsReconciliation);
    expect(await f.count('tracks'), 0);
    provider.metadata = null;
    expect((await coordinator.recover(await reclaim())).outcome,
        DownloadCoordinationOutcome.completed);
    expect(provider.writes, 1);
  });
  test(
      'factory failure closes the already-created backend and releases attempt',
      () async {
    await coordinator.close();
    media = DownloadTestBackend();
    coordinator = compose(failingFactory: true);
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.failed);
    expect(provider.backendCloses, 1);
    expect(provider.writes, 0);
  });
  test('backend cleanup failure cannot turn committed music into another retry',
      () async {
    provider.failClose = true;
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.completed);
    expect(result.job.state, DownloadJobState.completed);
    expect(result.cleanupFailed, isTrue);
    expect(provider.verifierCloses, 2);
  });
  test(
      'heartbeat progresses while reading published metadata outside SQLite fence',
      () async {
    provider.onMetadata = () async {
      f.now = f.now.add(const Duration(milliseconds: 100));
      await jobs.nextRenewal().timeout(const Duration(seconds: 3));
    };
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.completed);
    expect(jobs.renewals, greaterThan(1));
  });
  test(
      'disabled destination after publication preserves receipt without import',
      () async {
    provider.onMetadata = () async {
      await f.database.customStatement(
          'UPDATE library_folders SET is_enabled = 0 WHERE id = ?',
          [f.folderId]);
    };
    final result = await run();
    expect(result.outcome, DownloadCoordinationOutcome.ownershipLost);
    expect(await f.count('tracks'), 0);
    expect((await journal.pending()).length, 1);
  });
  test('proven INTENT without create rewinds under the new claimed owner',
      () async {
    for (final stage in [
      DownloadJobStage.metadata,
      DownloadJobStage.verification,
      DownloadJobStage.publication
    ]) {
      job =
          (await f.repositories.downloadJobs.advance(job, stage, now: f.now))!;
    }
    final intent = PublicationIntent(
        publicationId: 'a' * 64,
        jobId: job.id,
        key: job.key,
        verification: f.proof());
    provider.intents[intent.publicationId] = intent;
    await f.repositories.downloadJobs.interrupt(job, now: f.now);
    final result = await coordinator.recover(await reclaim());
    expect(result.outcome, DownloadCoordinationOutcome.requiresDownload);
    expect(result.job.stage, DownloadJobStage.download);
    expect(provider.releases, 1);
    expect(provider.writes, 0);
    expect(media.writes, 0);
    expect(provider.intents, isEmpty);
  });
}
