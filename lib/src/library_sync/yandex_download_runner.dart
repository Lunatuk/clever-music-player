import 'dart:async';

import '../domain/models/models.dart';
import '../domain/repositories/download_job_repository.dart';
import '../domain/repositories/yandex_session_repository.dart';
import '../library/library_scan_control.dart';
import 'binary_download.dart';
import 'download_coordination.dart';
import 'downloaded_audio_validation.dart';
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
  cleanupFailed,
  completedWithFailures
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
      {this.bytes,
      this.attempt = 1,
      this.isFinalAttempt = false,
      this.deferred = 0});
  final YandexDownloadRunStage stage;
  final int started, completed;
  final BinaryDownloadProgress? bytes;
  final int attempt, deferred;
  final bool isFinalAttempt;
}

final class YandexDownloadRunResult {
  const YandexDownloadRunResult(this.outcome, this.started, this.completed,
      {this.failure,
      this.jobFailure,
      this.failed = 0,
      this.cleanupFailed = false,
      this.needsReconciliation = false});
  final YandexDownloadRunOutcome outcome;
  final int started, completed;
  final YandexDownloadRunFailure? failure;
  final DownloadFailure? jobFailure;
  final int failed;
  final bool cleanupFailed;
  final bool needsReconciliation;
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

/// Explicit bounded run of queued tracks, with three attempts per track followed
/// by one final pass over failures. The limit counts distinct tracks.
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
  static const attemptsPerTrack = 3;
  static const totalAttemptsPerTrack = attemptsPerTrack + 1;

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
    var attempt = 1;
    var isFinalAttempt = false;
    final deferred = <int, DownloadJob>{};
    DownloadJob? claimed;
    var outcome = YandexDownloadRunOutcome.completed;
    var needsReconciliation = false;
    YandexDownloadRunFailure? failure;
    DownloadFailure? jobFailure;
    void progress(YandexDownloadRunStage stage,
        [BinaryDownloadProgress? bytes]) {
      try {
        observer?.call(YandexDownloadRunProgress(stage, started, completed,
            bytes: bytes,
            attempt: attempt,
            isFinalAttempt: isFinalAttempt,
            deferred: deferred.length));
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

    Future<DownloadJob?> retryFailed(DownloadJob failed) async {
      final used = failed.maxAttempts - failed.remainingAttempts;
      if (used >= totalAttemptsPerTrack) return null;
      await verifySession();
      final requeued = await _jobs.retryFailedAttempt(failed, account,
          now: _clock(), maxAttempts: totalAttemptsPerTrack);
      if (requeued == null) {
        throw const YandexDownloadRunException(
            YandexDownloadRunFailure.pipeline);
      }
      await verifySession();
      final next = await _jobs.claimNext(account,
          now: _clock(),
          leaseFor: const Duration(seconds: 60),
          libraryFolderId: folder,
          quality: selection.resourceQuality,
          jobId: requeued.id);
      if (next == null) {
        throw const YandexDownloadRunException(
            YandexDownloadRunFailure.pipeline);
      }
      claimed = next;
      return next;
    }

    Future<bool> processTrack(DownloadJob job,
        {bool finalAttempt = false}) async {
      isFinalAttempt = finalAttempt;
      final usedBeforeClaim = job.maxAttempts - job.remainingAttempts - 1;
      final count = finalAttempt
          ? 1
          : (attemptsPerTrack - usedBeforeClaim).clamp(1, attemptsPerTrack);
      for (var index = 0; index < count; index++) {
        attempt = usedBeforeClaim + index + 1;
        claimed = job;
        await verifySession();
        final result = await _executeAttempt(pipeline!, job, account, selection,
            control: control, onProgress: progress);
        claimed = result.job;
        cleanupFailed = cleanupFailed || result.cleanupFailed;
        if (result.outcome == DownloadCoordinationOutcome.completed) {
          completed++;
          deferred.remove(job.id);
          claimed = null;
          if (cleanupFailed) outcome = YandexDownloadRunOutcome.cleanupFailed;
          return !cleanupFailed;
        }
        if (result.outcome != DownloadCoordinationOutcome.failed ||
            result.job.state != DownloadJobState.failed ||
            !_isTrackFailure(result.job) ||
            cleanupFailed) {
          needsReconciliation =
              result.outcome == DownloadCoordinationOutcome.needsReconciliation;
          jobFailure = result.failure;
          outcome = result.outcome == DownloadCoordinationOutcome.cancelled
              ? YandexDownloadRunOutcome.cancelled
              : result.outcome == DownloadCoordinationOutcome.ownershipLost
                  ? YandexDownloadRunOutcome.staleSession
                  : YandexDownloadRunOutcome.failed;
          failure = YandexDownloadRunFailure.pipeline;
          return false;
        }
        deferred[job.id] = result.job;
        claimed = null;
        if (index == count - 1) break;
        final next = await retryFailed(result.job);
        if (next == null) break;
        job = next;
      }
      return true;
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
      var canContinue = true;
      while (started < maxJobs) {
        await verifySession();
        final next = await _jobs.claimNext(account,
            now: _clock(),
            leaseFor: const Duration(seconds: 60),
            libraryFolderId: folder,
            quality: selection.resourceQuality);
        claimed = next;
        if (next == null) break;
        started++;
        canContinue = await processTrack(next);
        if (!canContinue) break;
      }
      if (canContinue) {
        for (final failed in deferred.values.toList()) {
          final next = await retryFailed(failed);
          if (next == null) continue;
          canContinue = await processTrack(next, finalAttempt: true);
          if (!canContinue) break;
        }
      }
      if (canContinue) {
        if (deferred.isNotEmpty) {
          outcome = YandexDownloadRunOutcome.completedWithFailures;
        } else if (started == maxJobs) {
          outcome = YandexDownloadRunOutcome.limited;
        }
      }
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
      final pending = claimed;
      if (pending != null) {
        try {
          final current = await _jobs.findByKey(pending.key);
          jobFailure ??= current?.failure;
          if (current != null &&
              current.isExecuting &&
              current.attemptToken == pending.attemptToken &&
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
            outcome == YandexDownloadRunOutcome.limited ||
            outcome == YandexDownloadRunOutcome.completedWithFailures)) {
      outcome = YandexDownloadRunOutcome.cleanupFailed;
    }
    if (jobFailure == null && deferred.isNotEmpty) {
      jobFailure = deferred.values.first.failure;
    }
    progress(YandexDownloadRunStage.finished);
    return YandexDownloadRunResult(outcome, started, completed,
        failure: failure,
        jobFailure: jobFailure,
        failed: deferred.length,
        cleanupFailed: cleanupFailed,
        needsReconciliation: needsReconciliation);
  }

  Future<DownloadCoordinationResult> _executeAttempt(
      YandexDownloadPipeline pipeline,
      DownloadJob job,
      RemoteLibraryAccount account,
      YandexAudioSelection selection,
      {required LibraryScanControl control,
      required void Function(YandexDownloadRunStage, BinaryDownloadProgress?)
          onProgress}) async {
    try {
      return await pipeline.execute(job, account, selection,
          control: control, onProgress: onProgress);
    } on Object catch (error) {
      control.throwIfCancelled();
      // The downloader persists its failure before throwing. Only that finished
      // attempt may be retried; an active or replacement owner is left alone.
      if (error is! YandexDownloadException &&
          error is! YandexLibraryException &&
          error is! BinaryDownloadException &&
          error is! AudioValidationException) {
        rethrow;
      }
      if (error is BinaryDownloadException &&
          (error.failure == BinaryDownloadFailure.storage ||
              error.failure == BinaryDownloadFailure.unsafePath ||
              error.failure == BinaryDownloadFailure.quotaExceeded)) {
        rethrow;
      }
      final current = await _jobs.findByKey(job.key);
      if (current == null ||
          current.state != DownloadJobState.failed ||
          current.attemptCount != job.attemptCount ||
          current.accountId != account.id ||
          current.accountRevision != account.revision ||
          !_isTrackFailure(current)) {
        rethrow;
      }
      return DownloadCoordinationResult(
          outcome: DownloadCoordinationOutcome.failed,
          job: current,
          failure: current.failure);
    }
  }

  static bool _isTrackFailure(DownloadJob job) => switch (job.failure) {
        DownloadFailure.network ||
        DownloadFailure.rateLimited ||
        DownloadFailure.unavailable ||
        DownloadFailure.invalidMedia =>
          true,
        DownloadFailure.accessDenied => job.stage == DownloadJobStage.download,
        _ => false,
      };

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
