import 'dart:async';

import '../domain/models/models.dart';
import '../domain/repositories/download_job_repository.dart';
import '../domain/repositories/yandex_session_repository.dart';
import '../library/library_scan_control.dart';
import 'binary_download.dart';
import 'desktop_download_coordinator.dart';
import 'yandex_audio_selection.dart';
import 'yandex_credential_store.dart';
import 'yandex_download_protocol.dart';
import 'yandex_library_protocol.dart';

enum YandexDownloadRunStage {
  authenticating,
  preparing,
  recovering,
  downloading,
  processing,
  finished
}

enum YandexDownloadRunOutcome {
  completed,
  limited,
  cancelled,
  staleSession,
  failed,
  cleanupFailed
}

enum YandexDownloadRunFailure {
  credential,
  authorization,
  session,
  network,
  pipeline,
  storage
}

final class YandexDownloadRunException implements Exception {
  const YandexDownloadRunException(this.failure);
  final YandexDownloadRunFailure failure;
  @override
  String toString() => 'YandexDownloadRunException(${failure.name})';
}

/// Numeric-only view state. No credential, URL, file path, track title or raw
/// exception crosses the runner/UI boundary.
final class YandexDownloadRunProgress {
  const YandexDownloadRunProgress(this.stage, this.started, this.completed,
      {this.bytes});
  final YandexDownloadRunStage stage;
  final int started, completed;
  final BinaryDownloadProgress? bytes;
}

final class YandexDownloadRunResult {
  const YandexDownloadRunResult(this.outcome, this.started, this.completed,
      {this.failure, this.jobFailure, this.cleanupFailed = false});
  final YandexDownloadRunOutcome outcome;
  final int started, completed;
  final YandexDownloadRunFailure? failure;
  final DownloadFailure? jobFailure;
  final bool cleanupFailed;
}

/// Factory receives a BORROWED reader; closing a pipeline must not close it.
/// Runner closes that credential owner after all pipeline readers have drained.
abstract interface class YandexDownloadPipeline {
  Future<DownloadCoordinationResult> execute(DownloadJob job,
      RemoteLibraryAccount account, YandexAudioSelection selection,
      {required LibraryScanControl control,
      required void Function(YandexDownloadRunStage, BinaryDownloadProgress?)
          onProgress});
  Future<void> close();
}

/// Explicit bounded run of already queued jobs. Never plans, enqueues, retries
/// terminal jobs, switches credentials mid-run or starts work at application boot.
abstract interface class YandexDownloadRunService {
  bool get isBusy;
  Future<YandexDownloadRunResult> run(
      {required RemoteLibraryAccount account,
      required int libraryFolderId,
      required YandexAudioSelection selection,
      int maxJobs = 3,
      LibraryScanControl? control,
      void Function(YandexDownloadRunProgress)? onProgress});
  void cancel();
  Future<void> close();
}

final class YandexDownloadRunner implements YandexDownloadRunService {
  YandexDownloadRunner(
      {required YandexSessionRepository sessions,
      required YandexCredentialStore credentials,
      required DownloadJobRepository jobs,
      required YandexDownloadSessionReader Function(YandexAccessToken)
          readerFactory,
      required Future<YandexDownloadPipeline> Function(
              YandexDownloadSessionReader, LibraryScanControl)
          pipelineFactory,
      DateTime Function()? clock,
      this.sessionCheckEvery = const Duration(seconds: 1)})
      : _sessions = sessions,
        _credentials = credentials,
        _jobs = jobs,
        _readerFactory = readerFactory,
        _pipelineFactory = pipelineFactory,
        _clock = clock ?? DateTime.now {
    if (sessionCheckEvery < const Duration(milliseconds: 10) ||
        sessionCheckEvery > const Duration(seconds: 5)) {
      throw ArgumentError('Некорректный интервал проверки сессии.');
    }
  }
  final YandexSessionRepository _sessions;
  final YandexCredentialStore _credentials;
  final DownloadJobRepository _jobs;
  final YandexDownloadSessionReader Function(YandexAccessToken) _readerFactory;
  final Future<YandexDownloadPipeline> Function(
      YandexDownloadSessionReader, LibraryScanControl) _pipelineFactory;
  final DateTime Function() _clock;
  final Duration sessionCheckEvery;
  LibraryScanControl? _control;
  Future<YandexDownloadRunResult>? _active;
  Future<void>? _closing;
  bool _closed = false;
  @override
  bool get isBusy => _active != null;

  @override
  Future<YandexDownloadRunResult> run(
      {required RemoteLibraryAccount account,
      required int libraryFolderId,
      required YandexAudioSelection selection,
      int maxJobs = 3,
      LibraryScanControl? control,
      void Function(YandexDownloadRunProgress)? onProgress}) {
    if (_closed || isBusy) {
      return Future.error(YandexLibraryException(
          _closed ? YandexLibraryFailure.closed : YandexLibraryFailure.busy));
    }
    if (libraryFolderId <= 0 ||
        maxJobs <= 0 ||
        maxJobs > LibrarySyncSnapshot.maxEntries ||
        !account.isActive ||
        account.identity.provider != 'yandex_music') {
      return Future.error(ArgumentError('Некорректные границы запуска.'));
    }
    // Register before a synchronous observer can re-enter run/close.
    final accepted = Completer<YandexDownloadRunResult>();
    final current = LibraryScanControl();
    _control = current;
    final operation = accepted.future.whenComplete(() {
      _active = null;
      _control = null;
    });
    operation.ignore();
    _active = operation;
    control?.addCancellationListener(current.cancel);
    unawaited(Future.sync(() => _execute(
            account, libraryFolderId, selection, maxJobs, current, onProgress))
        .whenComplete(() => control?.removeCancellationListener(current.cancel))
        .then(accepted.complete, onError: accepted.completeError));
    return operation;
  }

  Future<YandexDownloadRunResult> _execute(
      RemoteLibraryAccount account,
      int folder,
      YandexAudioSelection selection,
      int maxJobs,
      LibraryScanControl control,
      void Function(YandexDownloadRunProgress)? observer) async {
    YandexDownloadSessionReader? reader;
    YandexDownloadPipeline? pipeline;
    Timer? timer;
    Future<void>? checking;
    var stale = false, checkFailed = false, cleanupFailed = false;
    var started = 0, completed = 0;
    DownloadJob? claimed;
    var outcome = YandexDownloadRunOutcome.completed;
    YandexDownloadRunFailure? failure;
    DownloadFailure? jobFailure;
    void progress(YandexDownloadRunStage stage,
        [BinaryDownloadProgress? bytes]) {
      try {
        observer?.call(
            YandexDownloadRunProgress(stage, started, completed, bytes: bytes));
      } on Object {/* Observers cannot abandon accepted work or cleanup. */}
    }

    Future<void> verifySession() async {
      control.throwIfCancelled();
      final List<RemoteLibraryAccount> current;
      try {
        current = await _sessions.capture();
      } on Object {
        if (!control.isCancellationRequested) checkFailed = true;
        control.cancel();
        throw const YandexDownloadRunException(
            YandexDownloadRunFailure.storage);
      }
      if (current.length != 1 || current.single != account) {
        stale = true;
        control.cancel();
        throw const YandexDownloadRunException(
            YandexDownloadRunFailure.session);
      }
      control.throwIfCancelled();
    }

    try {
      progress(YandexDownloadRunStage.authenticating);
      await verifySession();
      final credential = await _credentials.read();
      control.throwIfCancelled();
      if (credential == null || !credential.matches(account)) {
        throw const YandexDownloadRunException(
            YandexDownloadRunFailure.credential);
      }
      await verifySession();
      reader = _readerFactory(credential.token);
      // Serialized polling: never queue unbounded DB reads. Failure revokes
      // permission conservatively; each network/job boundary also has a fence.
      timer = Timer.periodic(sessionCheckEvery, (_) {
        if (checking != null || control.isCancellationRequested) return;
        final operation = verifySession().catchError((Object _) {
          if (!stale && !control.isCancellationRequested) checkFailed = true;
          control.cancel();
        }).whenComplete(() => checking = null);
        operation.ignore();
        checking = operation;
      });
      final profile = await reader.verifyAccount(control: control);
      await verifySession();
      if (profile.identity != account.identity) {
        stale = true;
        throw const YandexDownloadRunException(
            YandexDownloadRunFailure.session);
      }
      progress(YandexDownloadRunStage.preparing);
      control.throwIfCancelled();
      pipeline = await _pipelineFactory(reader, control);
      await verifySession();
      while (started < maxJobs) {
        await verifySession();
        claimed = await _jobs.claimNext(account,
            now: _clock(),
            leaseFor: const Duration(seconds: 60),
            libraryFolderId: folder,
            quality: selection.resourceQuality);
        if (claimed == null) break;
        started++;
        await verifySession();
        final result = await pipeline.execute(claimed, account, selection,
            control: control, onProgress: progress);
        claimed = result.job;
        cleanupFailed = cleanupFailed || result.cleanupFailed;
        if (result.outcome == DownloadCoordinationOutcome.completed) {
          completed++;
          claimed = null;
          if (cleanupFailed) {
            outcome = YandexDownloadRunOutcome.cleanupFailed;
            break;
          }
        } else {
          jobFailure = result.failure;
          outcome = result.outcome == DownloadCoordinationOutcome.cancelled
              ? YandexDownloadRunOutcome.cancelled
              : result.outcome == DownloadCoordinationOutcome.ownershipLost
                  ? YandexDownloadRunOutcome.staleSession
                  : YandexDownloadRunOutcome.failed;
          failure = YandexDownloadRunFailure.pipeline;
          break; // No immediate reclaim/retry loop on busy or reconciliation.
        }
      }
      if (completed == maxJobs) outcome = YandexDownloadRunOutcome.limited;
    } on Object catch (error) {
      if (stale) {
        outcome = YandexDownloadRunOutcome.staleSession;
        failure = YandexDownloadRunFailure.session;
      } else if (checkFailed) {
        outcome = YandexDownloadRunOutcome.failed;
        failure = YandexDownloadRunFailure.storage;
      } else if (control.isCancellationRequested ||
          error is LibraryScanCancelled) {
        outcome = YandexDownloadRunOutcome.cancelled;
      } else {
        outcome = YandexDownloadRunOutcome.failed;
        failure = switch (error) {
          YandexCredentialException() => YandexDownloadRunFailure.credential,
          YandexDownloadRunException(:final failure) => failure,
          YandexLibraryException(
            failure: YandexLibraryFailure.unauthorized ||
                YandexLibraryFailure.accessDenied
          ) =>
            YandexDownloadRunFailure.authorization,
          YandexLibraryException() ||
          BinaryDownloadException() =>
            YandexDownloadRunFailure.network,
          _ => YandexDownloadRunFailure.pipeline,
        };
      }
    } finally {
      timer?.cancel();
      await checking;
      // A pipeline may have left a claimed attempt at a recoverable checkpoint,
      // or thrown after its heartbeat stopped. Do not use an old CAS snapshot.
      if (claimed != null) {
        try {
          final current = await _jobs.findByKey(claimed.key);
          jobFailure ??= current?.failure;
          if (current != null &&
              current.isExecuting &&
              current.attemptToken == claimed.attemptToken &&
              current.accountId == account.id &&
              current.accountRevision == account.revision) {
            await _jobs.interrupt(current, now: _clock());
          }
        } on Object {
          cleanupFailed = true;
        }
      }
      for (final close in <Future<void> Function()>[
        if (pipeline != null) pipeline.close,
        if (reader != null) reader.close,
      ]) {
        try {
          await close();
        } on Object {
          cleanupFailed = true;
        }
      }
    }
    if (stale) {
      outcome = YandexDownloadRunOutcome.staleSession;
      failure = YandexDownloadRunFailure.session;
    } else if (checkFailed) {
      outcome = YandexDownloadRunOutcome.failed;
      failure = YandexDownloadRunFailure.storage;
    } else if (control.isCancellationRequested &&
        outcome != YandexDownloadRunOutcome.failed) {
      outcome = YandexDownloadRunOutcome.cancelled;
    }
    if (cleanupFailed &&
        (outcome == YandexDownloadRunOutcome.completed ||
            outcome == YandexDownloadRunOutcome.limited)) {
      outcome = YandexDownloadRunOutcome.cleanupFailed;
    }
    progress(YandexDownloadRunStage.finished);
    return YandexDownloadRunResult(outcome, started, completed,
        failure: failure, jobFailure: jobFailure, cleanupFailed: cleanupFailed);
  }

  @override
  void cancel() => _control?.cancel();
  @override
  Future<void> close() {
    _closed = true;
    cancel();
    return _closing ??= _drain();
  }

  Future<void> _drain() async {
    await _active;
  }
}
