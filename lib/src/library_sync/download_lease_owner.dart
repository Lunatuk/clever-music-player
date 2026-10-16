import 'dart:async';

import '../domain/models/download_job.dart';
import '../domain/repositories/download_job_repository.dart';
import '../domain/repositories/publication_job_access.dart';
import '../library/library_scan_control.dart';
import 'publication_intent.dart';

/// One attempt; never adopts another session/token. Serializes heartbeat and
/// short DB fences, not hashing, decoding, metadata extraction or file streams.
final class DownloadLeaseOwner implements PublicationJobAccess {
  DownloadLeaseOwner(
      {required DownloadJob job,
      required DownloadJobRepository jobs,
      required DateTime Function() clock,
      this.leaseFor = const Duration(seconds: 60),
      this.heartbeatEvery = const Duration(seconds: 20)})
      : _current = job,
        _jobs = jobs,
        _clock = clock {
    if (!job.isExecuting ||
        job.attemptToken == null ||
        job.leaseUntil == null ||
        leaseFor < const Duration(seconds: 1) ||
        leaseFor > const Duration(minutes: 10) ||
        heartbeatEvery <= Duration.zero ||
        heartbeatEvery * 2 > leaseFor) {
      throw ArgumentError('Некорректное владение попыткой.');
    }
  }
  final DownloadJobRepository _jobs;
  final DateTime Function() _clock;
  final Duration leaseFor, heartbeatEvery;
  DownloadJob _current;
  DownloadJob get current => _current;
  final lossControl = LibraryScanControl();
  bool get lost => lossControl.isCancellationRequested;
  Future<void> _tail = Future.value();
  Timer? _timer;
  bool _started = false, _closed = false, _pulsePending = false;
  Future<void>? _closing;

  Future<T> _serial<T>(Future<T> Function() action) {
    if (_closed) return Future.error(StateError('Владение закрыто.'));
    final result = _tail.then((_) async {
      if (lost) {
        throw const PublicationException(PublicationFailure.ownershipLost);
      }
      return action();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    result.ignore();
    return result;
  }

  DownloadJob _adopt(DownloadJob? job) {
    if (job == null ||
        job.id != _current.id ||
        job.key != _current.key ||
        job.accountId != _current.accountId ||
        job.accountRevision != _current.accountRevision ||
        job.attemptCount != _current.attemptCount ||
        (job.isExecuting && job.attemptToken != _current.attemptToken)) {
      return _lose();
    }
    _current = job;
    if (!job.isExecuting) _timer?.cancel();
    return job;
  }

  Never _lose() {
    lossControl.cancel();
    throw const PublicationException(PublicationFailure.ownershipLost);
  }

  Future<void> start() async {
    if (_started) throw StateError('Владение уже запущено.');
    _started = true;
    await _serial(() async => _adopt(
        await _jobs.renewLease(_current, now: _clock(), leaseFor: leaseFor)));
    if (_closed) return;
    _timer = Timer.periodic(heartbeatEvery, (_) {
      if (_pulsePending || !_current.isExecuting) return;
      _pulsePending = true;
      final pulse = _serial(() async {
        if (_current.isExecuting) {
          _adopt(await _jobs.renewLease(_current,
              now: _clock(), leaseFor: leaseFor));
        }
      });
      unawaited(pulse.then<void>((_) {}, onError: (Object _, StackTrace __) {
        // Without a successful current lease proof, stop media/file work.
        lossControl.cancel();
      }).whenComplete(() => _pulsePending = false));
    });
  }

  Future<DownloadJob> advance(DownloadJobStage stage) => _serial(
      () async => _adopt(await _jobs.advance(_current, stage, now: _clock())));
  Future<DownloadJob> resolve(DownloadJobStage stage) =>
      _serial(() async => _adopt(
          await _jobs.resolveReconciliation(_current, stage, now: _clock())));

  Future<T> withCurrent<T>(Future<T> Function(DownloadJob job) action) =>
      _serial(() => action(_current));

  Future<T> finish<T extends Object>(
          Future<(T, DownloadJob)?> Function(DownloadJob job) action) =>
      _serial(() async {
        final result = await action(_current);
        if (result == null) _lose();
        _adopt(result.$2);
        return result.$1;
      });

  @override
  Future<T?> withOwnedDestination<T extends Object>(DownloadJob expected,
          {required DateTime Function() clock,
          required Future<T> Function(String destinationPath) action}) =>
      _serial(() async {
        if (expected.id != _current.id ||
            expected.key != _current.key ||
            expected.attemptToken != _current.attemptToken ||
            expected.accountId != _current.accountId ||
            expected.accountRevision != _current.accountRevision ||
            expected.stage != _current.stage ||
            !expected.isExecuting) {
          throw const PublicationException(PublicationFailure.ownershipLost);
        }
        // Heartbeat revisions may advance during long hash IO. Only this owner
        // can substitute them, under its serialized gate, in the same attempt.
        final result = await _jobs.withOwnedDestination(_current,
            clock: _clock, action: action);
        if (result == null) _lose();
        return result;
      });

  @override
  Future<List<DownloadAttempt>> listAttempts(int jobId, {int limit = 50}) =>
      _jobs.listAttempts(jobId, limit: limit);

  Future<DownloadJob?> interrupt(DownloadFailure reason) => _serial(() async {
        final result =
            await _jobs.interrupt(_current, now: _clock(), reason: reason);
        _adopt(result);
        return result;
      });
  Future<DownloadJob?> fail(DownloadFailure reason, {bool cancelled = false}) =>
      _serial(() async {
        final result = cancelled
            ? await _jobs.cancel(_current, now: _clock())
            : await _jobs.fail(_current, reason, now: _clock());
        _adopt(result);
        return result;
      });

  Future<void> close() {
    _closed = true;
    _timer?.cancel();
    return _closing ??= _tail;
  }
}
