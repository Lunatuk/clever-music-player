import 'dart:async';

import 'package:clever_music_player/src/domain/models/download_job.dart';
import 'package:clever_music_player/src/domain/repositories/download_job_repository.dart';

final class RecordingDownloadJobs implements DownloadJobRepository {
  RecordingDownloadJobs(this.inner);
  final DownloadJobRepository inner;
  int renewals = 0;
  int? failRenewal;
  Future<void> Function()? beforeRenew;
  final _waiters = <(int, Completer<void>)>[];
  Future<void> nextRenewal() {
    final done = Completer<void>();
    _waiters.add((renewals + 1, done));
    return done.future;
  }

  @override
  Future<DownloadJob?> renewLease(DownloadJob expected,
      {required DateTime now,
      Duration leaseFor = const Duration(seconds: 30)}) async {
    await beforeRenew?.call();
    if (renewals + 1 == failRenewal) throw StateError('synthetic DB failure');
    final result =
        await inner.renewLease(expected, now: now, leaseFor: leaseFor);
    renewals++;
    for (final waiter in List.of(_waiters)) {
      if (renewals >= waiter.$1) {
        waiter.$2.complete();
        _waiters.remove(waiter);
      }
    }
    return result;
  }

  @override
  Future<List<DownloadAttempt>> listAttempts(int jobId, {int limit = 50}) =>
      inner.listAttempts(jobId, limit: limit);
  @override
  Future<T?> withOwnedDestination<T extends Object>(DownloadJob expected,
          {required DateTime Function() clock,
          required Future<T> Function(String) action}) =>
      inner.withOwnedDestination(expected, clock: clock, action: action);
  @override
  Future<DownloadJob?> advance(DownloadJob expected, DownloadJobStage next,
          {required DateTime now}) =>
      inner.advance(expected, next, now: now);
  @override
  Future<DownloadJob?> resolveReconciliation(
          DownloadJob expected, DownloadJobStage stage,
          {required DateTime now}) =>
      inner.resolveReconciliation(expected, stage, now: now);
  @override
  Future<DownloadJob?> interrupt(DownloadJob expected,
          {required DateTime now,
          DownloadFailure reason = DownloadFailure.interrupted}) =>
      inner.interrupt(expected, now: now, reason: reason);
  @override
  Future<DownloadJob?> fail(DownloadJob expected, DownloadFailure reason,
          {required DateTime now, DateTime? retryAt}) =>
      inner.fail(expected, reason, now: now, retryAt: retryAt);
  @override
  Future<DownloadJob?> cancel(DownloadJob expected, {required DateTime now}) =>
      inner.cancel(expected, now: now);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected test call');
}
