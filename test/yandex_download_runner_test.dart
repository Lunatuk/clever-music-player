import 'dart:async';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/yandex_session_repository.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/binary_download.dart';
import 'package:clever_music_player/src/library_sync/desktop_download_coordinator.dart';
import 'package:clever_music_player/src/library_sync/yandex_audio_selection.dart';
import 'package:clever_music_player/src/library_sync/yandex_credential_store.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_protocol.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_runner.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/download_fixture.dart';
import 'support/yandex_download_fixture.dart';
import 'support/yandex_fixture.dart';

void main() {
  late DownloadFixture f;
  late _Credentials credentials;
  late _Sessions sessions;
  late YandexDownloadRunner runner;
  final readers = <_Reader>[];
  final pipelines = <_Pipeline>[];
  final events = <YandexDownloadRunProgress>[];
  void Function(_Reader)? onReader;
  Future<void> Function(_Pipeline, LibraryScanControl)? onFactory;
  setUp(() async {
    f = await DownloadFixture.open();
    f.account =
        await f.repositories.remoteLibrary.activateAccount(yandexAccount);
    credentials = _Credentials()
      ..value = YandexSavedCredential(
          account: f.account,
          token: YandexAccessToken('PRIVATE_SYNTHETIC_TOKEN'));
    sessions = _Sessions(f.repositories.yandexSessions);
    readers.clear();
    pipelines.clear();
    events.clear();
    onFactory = null;
    onReader = null;
    runner = YandexDownloadRunner(
        sessions: sessions,
        credentials: credentials,
        jobs: f.repositories.downloadJobs,
        clock: f.clock,
        sessionCheckEvery: const Duration(milliseconds: 20),
        readerFactory: (token) {
          final reader = _Reader(f.account.identity);
          token.authorize((header) => reader.header = header);
          readers.add(reader);
          onReader?.call(reader);
          return reader;
        },
        pipelineFactory: (reader, control) async {
          final pipeline = _Pipeline(f);
          pipelines.add(pipeline);
          await onFactory?.call(pipeline, control);
          return pipeline;
        });
  });
  tearDown(() async {
    await runner.close();
    await f.close();
  });
  DownloadJobKey key(int id, {int? folder, String? quality}) => DownloadJobKey(
      libraryFolderId: folder ?? f.folderId,
      identity:
          ExternalTrackIdentity(provider: 'yandex_music', externalId: '$id'),
      quality: quality ?? yandexMp3Selection.resourceQuality);
  Future<void> enqueue(int count) => f.repositories.downloadJobs
      .enqueue(f.account, List.generate(count, (i) => key(i + 1)), now: f.now);
  Future<YandexDownloadRunResult> run(
      {int maxJobs = 3,
      LibraryScanControl? control,
      void Function(YandexDownloadRunProgress)? progress}) {
    return runner.run(
        account: f.account,
        libraryFolderId: f.folderId,
        selection: yandexMp3Selection,
        maxJobs: maxJobs,
        control: control,
        onProgress: progress ?? events.add);
  }

  Future<DownloadJob> stored(int id) async =>
      (await f.repositories.downloadJobs.findByKey(key(id)))!;

  test('construction and idle waiting do not read credentials, DB or network',
      () async {
    expect(credentials.reads, 0);
    expect(sessions.calls, 0);
    expect(readers, isEmpty);
    expect(pipelines, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sessions.calls, 0);
  });
  test(
      'bounded FIFO execution commits at most maxJobs and leaves the rest queued',
      () async {
    await enqueue(4);
    final result = await run(maxJobs: 2);
    expect(result.outcome, YandexDownloadRunOutcome.limited);
    expect(result.started, 2);
    expect(result.completed, 2);
    expect(await f.count('tracks'), 2);
    expect((await stored(3)).state, DownloadJobState.queued);
    expect((await stored(3)).attemptCount, 0);
    expect(credentials.reads, 1);
    expect(readers.single.verifications, 1);
    expect(readers.single.closes, 1);
    expect(pipelines.single.closes, 1);
    expect(events.first.stage, YandexDownloadRunStage.authenticating);
    expect(events.last.stage, YandexDownloadRunStage.finished);
    expect(events.any((e) => e.stage == YandexDownloadRunStage.processing),
        isTrue);
    expect(events.every((e) => e.completed <= e.started), isTrue);
    expect(runner.isBusy, isFalse);
  });
  test('empty matching queue ends without claiming unrelated quality or folder',
      () async {
    final other = await f.repositories.libraryFolders.upsertFolder(
        LibraryFolder(
            path: '${f.root.path}/other', createdAt: f.now, updatedAt: f.now));
    await f.repositories.downloadJobs.enqueue(
        f.account, [key(1, folder: other), key(2, quality: 'other')],
        now: f.now);
    final result = await run();
    expect(result.outcome, YandexDownloadRunOutcome.completed);
    expect(result.started, 0);
    expect(pipelines.single.calls, 0);
    expect(
        (await f.repositories.downloadJobs.listJobs())
            .every((j) => j.attemptCount == 0),
        isTrue);
  });
  for (final kind in ['missing', 'old revision', 'other uid', 'read failure']) {
    test('$kind credential prevents even client creation and job claims',
        () async {
      await enqueue(1);
      switch (kind) {
        case 'missing':
          credentials.value = null;
        case 'old revision':
          final old = credentials.value!;
          f.account =
              await f.repositories.remoteLibrary.activateAccount(yandexAccount);
          credentials.value = old;
        case 'other uid':
          credentials.value = YandexSavedCredential(
              account: RemoteLibraryAccount(
                  id: f.account.id,
                  identity: RemoteAccountIdentity(
                      provider: 'yandex_music', accountId: '999'),
                  displayName: null,
                  isActive: true,
                  revision: f.account.revision),
              token: YandexAccessToken('OTHER_PRIVATE_TOKEN'));
        case 'read failure':
          credentials.onRead =
              () async => throw const YandexCredentialException();
      }
      final result = await run();
      expect(result.outcome, YandexDownloadRunOutcome.failed);
      expect(result.failure, YandexDownloadRunFailure.credential);
      expect(readers, isEmpty);
      expect(pipelines, isEmpty);
      expect((await stored(1)).attemptCount, 0);
    });
  }
  test(
      'session changed while OS credential read is pending cannot authenticate',
      () async {
    await enqueue(1);
    credentials.onRead = () async {
      await f.repositories.remoteLibrary.activateAccount(yandexAccount);
    };
    final result = await run();
    expect(result.outcome, YandexDownloadRunOutcome.staleSession);
    expect(readers, isEmpty);
    expect(pipelines, isEmpty);
    expect((await stored(1)).attemptCount, 0);
  });
  test(
      'session capture failure is storage failure, no credential or network read',
      () async {
    sessions.beforeCapture =
        (_) async => throw StateError('PRIVATE_DATABASE_ERROR');
    final result = await run();
    expect(result.outcome, YandexDownloadRunOutcome.failed);
    expect(result.failure, YandexDownloadRunFailure.storage);
    expect(credentials.reads, 0);
    expect(readers, isEmpty);
  });
  test('provider UID mismatch cannot create pipeline or claim jobs', () async {
    await enqueue(1);
    onReader = (reader) {
      reader.identity =
          RemoteAccountIdentity(provider: 'yandex_music', accountId: '999');
    };
    final result = await run();
    expect(result.outcome, YandexDownloadRunOutcome.staleSession);
    expect(pipelines, isEmpty);
    expect((await stored(1)).attemptCount, 0);
    expect(readers.single.closes, 1);
  });
  for (final apiFailure in [
    YandexLibraryFailure.unauthorized,
    YandexLibraryFailure.accessDenied,
    YandexLibraryFailure.timeout
  ]) {
    test('provider $apiFailure leaves jobs untouched and closes the client',
        () async {
      await enqueue(1);
      onReader = (reader) {
        reader.onVerify = (_) async => throw YandexLibraryException(apiFailure);
      };
      final result = await run();
      expect(result.outcome, YandexDownloadRunOutcome.failed);
      expect(
          result.failure,
          apiFailure == YandexLibraryFailure.timeout
              ? YandexDownloadRunFailure.network
              : YandexDownloadRunFailure.authorization);
      expect(readers.single.closes, 1);
      expect(pipelines, isEmpty);
      expect((await stored(1)).attemptCount, 0);
      expect(credentials.value,
          isNotNull); // Never delete a possibly newer credential.
    });
  }
  test('factory failure closes its credential reader without claiming work',
      () async {
    await enqueue(1);
    onFactory = (_, __) async => throw StateError('PRIVATE_FACTORY_ERROR');
    final result = await run();
    expect(result.outcome, YandexDownloadRunOutcome.failed);
    expect(readers.single.closes, 1);
    expect((await stored(1)).attemptCount, 0);
  });
  for (final kind in ['session', 'database']) {
    test(
        '$kind invalidation while provider verification is pending revokes accepted work',
        () async {
      await enqueue(1);
      final entered = Completer<void>();
      final release = Completer<void>();
      onReader = (reader) {
        reader.onVerify = (control) async {
          entered.complete();
          control.addCancellationListener(() {
            if (!release.isCompleted) release.complete();
          });
          await release.future;
          control.throwIfCancelled();
        };
      };
      final operation = run();
      await entered.future.timeout(const Duration(seconds: 3));
      if (kind == 'session') {
        await f.repositories.remoteLibrary.disconnectAccount(f.account);
      } else {
        sessions.beforeCapture =
            (_) async => throw StateError('PRIVATE_READ_FAILURE');
      }
      final result = await operation.timeout(const Duration(seconds: 3));
      expect(
          result.outcome,
          kind == 'session'
              ? YandexDownloadRunOutcome.staleSession
              : YandexDownloadRunOutcome.failed);
      expect(
          result.failure,
          kind == 'session'
              ? YandexDownloadRunFailure.session
              : YandexDownloadRunFailure.storage);
      expect(pipelines, isEmpty);
      expect(readers.single.closes, 1);
      expect((await stored(1)).attemptCount, 0);
    });
  }
  test('pre-cancelled invocation does not touch OS storage or DB', () async {
    final result = await run(control: LibraryScanControl()..cancel());
    expect(result.outcome, YandexDownloadRunOutcome.cancelled);
    expect(sessions.calls, 0);
    expect(credentials.reads, 0);
  });
  test(
      'late cancellation during pipeline factory drains and closes both owners',
      () async {
    await enqueue(1);
    final entered = Completer<void>(), release = Completer<void>();
    onFactory = (_, __) async {
      entered.complete();
      await release.future;
    };
    final control = LibraryScanControl();
    final operation = run(control: control);
    await entered.future;
    control.cancel();
    expect(runner.isBusy, isTrue);
    release.complete();
    expect((await operation).outcome, YandexDownloadRunOutcome.cancelled);
    expect(pipelines.single.closes, 1);
    expect(readers.single.closes, 1);
    expect((await stored(1)).attemptCount, 0);
  });
  test('failure stops the batch and never retries terminal work', () async {
    await enqueue(3);
    onFactory = (pipeline, _) async {
      pipeline.mode = 'fail';
    };
    final result = await run();
    expect(result.outcome, YandexDownloadRunOutcome.failed);
    expect(result.jobFailure, DownloadFailure.unavailable);
    expect(result.started, 1);
    expect((await stored(1)).state, DownloadJobState.failed);
    expect((await stored(1)).attemptCount, 1);
    expect((await stored(2)).attemptCount, 0);
    expect(await f.count('tracks'), 0);
  });
  for (final mode in ['busy', 'throw after renewal', 'reconciliation']) {
    test('$mode releases only the current latest attempt for reconciliation',
        () async {
      await enqueue(2);
      onFactory = (pipeline, _) async {
        pipeline.mode = mode;
      };
      final result = await run();
      expect(result.outcome, YandexDownloadRunOutcome.failed);
      expect(result.started, 1);
      expect((await stored(1)).state, DownloadJobState.needsReconciliation);
      expect((await stored(1)).attemptCount, 1);
      expect((await stored(2)).state, DownloadJobState.queued);
    });
  }
  test('cleanup failure after commit preserves completion and stops next claim',
      () async {
    await enqueue(2);
    onFactory = (pipeline, _) async {
      pipeline.cleanup = true;
      pipeline.failClose = true;
    };
    final result = await run();
    expect(result.outcome, YandexDownloadRunOutcome.cleanupFailed);
    expect(result.completed, 1);
    expect(result.cleanupFailed, isTrue);
    expect((await stored(1)).state, DownloadJobState.completed);
    expect((await stored(2)).attemptCount, 0);
    expect(readers.single.closes, 1);
  });
  test('another claimant cannot be interrupted by cleanup of an older attempt',
      () async {
    await enqueue(1);
    onFactory = (pipeline, _) async {
      pipeline.mode = 'replace attempt';
    };
    final result = await run();
    expect(result.outcome, YandexDownloadRunOutcome.failed);
    final current = await stored(1);
    expect(current.state, DownloadJobState.reconciling);
    expect(current.attemptCount, 2);
    expect(current.attemptToken, isNotNull);
  });
  for (final limit in [0, -1, 100001]) {
    test('invalid batch limit $limit rejected before storage or authentication',
        () async {
      await expectLater(run(maxJobs: limit), throwsArgumentError);
      expect(sessions.calls, 0);
      expect(credentials.reads, 0);
      expect(runner.isBusy, isFalse);
    });
  }
  test('new explicit run reads fresh credential, never reuses a closed reader',
      () async {
    await enqueue(1);
    await run(maxJobs: 1);
    f.account =
        await f.repositories.remoteLibrary.activateAccount(yandexAccount);
    credentials.value = YandexSavedCredential(
        account: f.account, token: YandexAccessToken('NEW_PRIVATE_TOKEN'));
    await f.repositories.downloadJobs.enqueue(f.account, [key(2)], now: f.now);
    await run(maxJobs: 1);
    expect(credentials.reads, 2);
    expect(readers, hasLength(2));
    expect(readers.map((r) => r.header).toSet(), hasLength(2));
    expect(readers.every((r) => r.closes == 1), isTrue);
  });
  test(
      'busy admission rejects a second run; close cancels and drains the first',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    onFactory = (_, control) async {
      entered.complete();
      control.addCancellationListener(release.complete);
      await release.future;
    };
    final first = run();
    await entered.future;
    await expectLater(
        run(),
        throwsA(isA<YandexLibraryException>()
            .having((e) => e.failure, 'failure', YandexLibraryFailure.busy)));
    await runner.close();
    expect((await first).outcome, YandexDownloadRunOutcome.cancelled);
    expect(readers.single.closes, 1);
    expect(pipelines.single.closes, 1);
    await expectLater(
        run(),
        throwsA(isA<YandexLibraryException>()
            .having((e) => e.failure, 'failure', YandexLibraryFailure.closed)));
  });
  test('reentrant close and hostile progress observer cannot bypass drain',
      () async {
    final result = await run(progress: (_) {
      unawaited(runner.close());
      throw StateError('PRIVATE_UI_ERROR');
    });
    expect(result.outcome, YandexDownloadRunOutcome.cancelled);
    expect(credentials.reads, 0);
    expect(runner.isBusy, isFalse);
  });
  test('progress during successful execution tolerates throwing observers',
      () async {
    await enqueue(1);
    final result =
        await run(progress: (_) => throw StateError('PRIVATE_UI_ERROR'));
    expect(result.completed, 1);
    expect(result.outcome, YandexDownloadRunOutcome.completed);
    expect(pipelines.single.closes, 1);
  });
  test('all progress and failure values expose only typed codes and counts',
      () {
    expect(
        const YandexDownloadRunException(YandexDownloadRunFailure.credential)
            .toString(),
        'YandexDownloadRunException(credential)');
  });
}

final class _Credentials implements YandexCredentialStore {
  YandexSavedCredential? value;
  int reads = 0;
  Future<void> Function()? onRead;
  @override
  Future<YandexSavedCredential?> read() async {
    reads++;
    await onRead?.call();
    return value;
  }

  @override
  Future<void> write(YandexSavedCredential value) async => this.value = value;
  @override
  Future<void> delete() async => value = null;
}

final class _Sessions implements YandexSessionRepository {
  _Sessions(this.inner);
  final YandexSessionRepository inner;
  int calls = 0;
  Future<void> Function(int)? beforeCapture;
  @override
  Future<List<RemoteLibraryAccount>> capture() async {
    calls++;
    await beforeCapture?.call(calls);
    return inner.capture();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected session mutation');
}

final class _Reader implements YandexDownloadSessionReader {
  _Reader(this.identity);
  RemoteAccountIdentity identity;
  String? header;
  int verifications = 0, closes = 0;
  Future<void> Function(LibraryScanControl)? onVerify;
  @override
  Future<YandexAccountProfile> verifyAccount(
      {LibraryScanControl? control}) async {
    verifications++;
    await onVerify?.call(control!);
    control?.throwIfCancelled();
    return YandexAccountProfile(identity: identity, displayName: null);
  }

  @override
  Future<void> close() async {
    closes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected download in unit reader');
}

final class _Pipeline implements YandexDownloadPipeline {
  _Pipeline(this.f);
  final DownloadFixture f;
  String mode = 'complete';
  int calls = 0, closes = 0;
  bool cleanup = false, failClose = false;
  @override
  Future<DownloadCoordinationResult> execute(DownloadJob job,
      RemoteLibraryAccount account, YandexAudioSelection selection,
      {required LibraryScanControl control,
      required void Function(YandexDownloadRunStage, BinaryDownloadProgress?)
          onProgress}) async {
    calls++;
    control.throwIfCancelled();
    onProgress(YandexDownloadRunStage.processing, null);
    if (mode == 'throw after renewal') {
      await f.repositories.downloadJobs.renewLease(job, now: f.now);
      throw StateError('PRIVATE_PIPELINE_ERROR');
    }
    if (mode == 'replace attempt') {
      await f.repositories.downloadJobs.interrupt(job, now: f.now);
      await f.repositories.downloadJobs.claimNext(account,
          now: f.now,
          libraryFolderId: job.key.libraryFolderId,
          quality: job.key.quality);
      throw StateError('OLD_ATTEMPT_FAILED');
    }
    if (mode == 'busy' || mode == 'reconciliation') {
      return DownloadCoordinationResult(
          job: job,
          outcome: mode == 'busy'
              ? DownloadCoordinationOutcome.busy
              : DownloadCoordinationOutcome.needsReconciliation);
    }
    if (mode == 'fail') {
      final failed = (await f.repositories.downloadJobs
          .fail(job, DownloadFailure.unavailable, now: f.now))!;
      return DownloadCoordinationResult(
          job: failed,
          outcome: DownloadCoordinationOutcome.failed,
          failure: DownloadFailure.unavailable);
    }
    var current = job;
    if (current.state == DownloadJobState.reconciling) {
      current = (await f.repositories.downloadJobs.resolveReconciliation(
          current, DownloadJobStage.download,
          now: f.now))!;
    }
    while (current.stage != DownloadJobStage.importing) {
      current = (await f.repositories.downloadJobs.advance(
          current, DownloadJobStage.values[current.stage.index + 1],
          now: f.now))!;
    }
    final proof = DownloadedAssetVerification(
        actualQuality: selection.resourceQuality,
        container: 'mp3',
        codec: 'mp3',
        fileSizeBytes: 3,
        duration: const Duration(seconds: 3),
        contentHash: f.proof().contentHash,
        checkedAt: f.now);
    final imported = (await f.repositories.downloadImports.commit(
        current,
        f.publication(current,
            id: job.id.toRadixString(16).padLeft(64, '0'), verification: proof),
        clock: f.clock))!;
    return DownloadCoordinationResult(
        outcome: DownloadCoordinationOutcome.completed,
        job: imported.job,
        imported: imported,
        cleanupFailed: cleanup);
  }

  @override
  Future<void> close() async {
    closes++;
    if (failClose) throw StateError('PRIVATE_CLEANUP_ERROR');
  }
}
