import 'dart:math';

import 'package:drift/drift.dart';

import '../../domain/models/download_job.dart';
import '../../domain/models/downloaded_asset.dart';
import '../../domain/models/external_track_ref.dart';
import '../../domain/models/remote_library.dart';
import '../../domain/repositories/download_job_repository.dart';
import '../drift/app_database.dart';
import 'drift_downloaded_asset_repository.dart';
import 'drift_remote_library_repository.dart';

final class DriftDownloadJobRepository implements DownloadJobRepository {
  const DriftDownloadJobRepository(this.database);
  final AppDatabase database;
  static final _random = Random.secure();

  @override
  Future<List<DownloadJob>> enqueue(
      RemoteLibraryAccount account, Iterable<DownloadJobKey> keys,
      {required DateTime now, int maxAttempts = 3}) {
    if (maxAttempts < 1 || maxAttempts > 10) {
      throw ArgumentError('От 1 до 10 попыток.');
    }
    final copy = <DownloadJobKey>[];
    for (final key in keys) {
      if (copy.length == 64) {
        throw ArgumentError('Не более 64 заданий за одну команду.');
      }
      if (key.identity.provider != account.identity.provider) {
        throw ArgumentError('Другой провайдер.');
      }
      copy.add(key);
    }
    return database.transaction(() async {
      if (!await _currentAccount(account)) {
        throw StateError('Аккаунт уже изменён.');
      }
      final result = <DownloadJob>[];
      for (final key in copy.toSet()) {
        if (!await _enabledFolder(key.libraryFolderId)) {
          throw StateError('Папка назначения недоступна.');
        }
        final existing = await findByKey(key);
        if (existing != null) {
          result.add(existing);
          continue;
        }
        final id = await database.into(database.downloadJobs).insert(
            DownloadJobsCompanion.insert(
                libraryFolderId: key.libraryFolderId,
                provider: key.identity.provider,
                externalId: key.identity.externalId,
                variantKey: key.identity.variantKey,
                quality: key.quality,
                accountId: account.id,
                accountRevision: account.revision,
                state: DownloadJobState.queued.name,
                stage: DownloadJobStage.download.name,
                revision: 1,
                maxAttempts: maxAttempts,
                remainingAttempts: maxAttempts,
                createdAtMicros: now.microsecondsSinceEpoch,
                updatedAtMicros: now.microsecondsSinceEpoch));
        result.add((await _find(id))!);
      }
      return List.unmodifiable(result);
    });
  }

  @override
  Future<DownloadJob?> findByKey(DownloadJobKey key) async {
    final row = await (database.select(database.downloadJobs)
          ..where((t) =>
              t.libraryFolderId.equals(key.libraryFolderId) &
              t.provider.equals(key.identity.provider) &
              t.externalId.equals(key.identity.externalId) &
              t.variantKey.equals(key.identity.variantKey) &
              t.quality.equals(key.quality)))
        .getSingleOrNull();
    return row == null ? null : _job(row);
  }

  @override
  Future<List<DownloadJob>> listJobs(
      {DownloadJobState? state, int limit = 100}) async {
    _limit(limit);
    final query = database.select(database.downloadJobs)
      ..orderBy([(t) => OrderingTerm(expression: t.id)])
      ..limit(limit);
    if (state != null) query.where((t) => t.state.equals(state.name));
    return List.unmodifiable((await query.get()).map(_job));
  }

  @override
  Future<List<DownloadJob>> listForDestination(int libraryFolderId,
      {required String provider}) async {
    if (libraryFolderId <= 0 ||
        RegExp(r'^[a-z][a-z0-9._-]{0,63}$').stringMatch(provider) != provider) {
      throw ArgumentError('Некорректное назначение или провайдер.');
    }
    final rows = await (database.select(database.downloadJobs)
          ..where((t) =>
              t.libraryFolderId.equals(libraryFolderId) &
              t.provider.equals(provider))
          ..orderBy([(t) => OrderingTerm(expression: t.id)])
          ..limit(100001))
        .get();
    if (rows.length > 100000) {
      throw StateError('Слишком много заданий для одного снимка.');
    }
    return List.unmodifiable(rows.map(_job));
  }

  @override
  Future<List<DownloadAttempt>> listAttempts(int jobId,
      {int limit = 50}) async {
    _limit(limit);
    if (jobId <= 0) throw ArgumentError('Требуется ID задания.');
    final rows = await (database.select(database.downloadAttempts)
          ..where((t) => t.jobId.equals(jobId))
          ..orderBy([(t) => OrderingTerm.desc(t.number)])
          ..limit(limit))
        .get();
    return List.unmodifiable(rows.map((r) => DownloadAttempt(
        jobId: r.jobId,
        number: r.number,
        token: r.token,
        accountId: r.accountId,
        accountRevision: r.accountRevision,
        stage: DownloadJobStage.values.byName(r.stage),
        outcome: DownloadAttemptOutcome.values.byName(r.outcome),
        startedAt: _date(r.startedAtMicros),
        finishedAt: _optionalDate(r.finishedAtMicros),
        failure: _failure(r.failure))));
  }

  @override
  Future<DownloadJob?> claimNext(RemoteLibraryAccount account,
      {required DateTime now,
      Duration leaseFor = const Duration(seconds: 30),
      int? libraryFolderId,
      String? quality}) {
    _lease(leaseFor);
    if (libraryFolderId != null && libraryFolderId <= 0) {
      throw ArgumentError('Требуется папка назначения.');
    }
    if (quality != null) validateAssetQuality(quality);
    return database.transaction(() async {
      if (!await _currentAccount(account)) return null;
      await _recover(now);
      final rows = await database.customSelect(
          'SELECT j.* FROM download_jobs j JOIN library_folders f ON f.id = j.library_folder_id '
          "WHERE j.account_id = ? AND j.account_revision = ? AND j.state IN ('queued', 'needsReconciliation') "
          '${libraryFolderId == null ? '' : 'AND j.library_folder_id = ? '}'
          '${quality == null ? '' : 'AND j.quality = ? '}'
          'AND j.remaining_attempts > 0 AND f.is_enabled = 1 AND j.updated_at_micros <= ? '
          'AND (j.retry_at_micros IS NULL OR j.retry_at_micros <= ?) '
          'AND NOT EXISTS (SELECT 1 FROM download_jobs busy WHERE busy.library_folder_id = j.library_folder_id '
          'AND busy.provider = j.provider AND busy.external_id = j.external_id AND busy.variant_key = j.variant_key '
          "AND busy.state IN ('running', 'reconciling') AND busy.lease_until_micros > ?) ORDER BY j.id LIMIT 1",
          variables: [
            Variable.withInt(account.id),
            Variable.withInt(account.revision),
            if (libraryFolderId != null) Variable.withInt(libraryFolderId),
            if (quality != null) Variable.withString(quality),
            for (var i = 0; i < 3; i++)
              Variable.withInt(now.microsecondsSinceEpoch)
          ],
          readsFrom: {
            database.downloadJobs,
            database.libraryFolders
          }).get();
      if (rows.isEmpty) return null;
      final current = _job(database.downloadJobs.map(rows.single.data));
      final token = List.generate(
              32, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      final state = current.state == DownloadJobState.queued
          ? DownloadJobState.running
          : DownloadJobState.reconciling;
      await database.into(database.downloadAttempts).insert(
          DownloadAttemptsCompanion.insert(
              jobId: current.id,
              number: current.attemptCount + 1,
              token: token,
              accountId: account.id,
              accountRevision: account.revision,
              stage: current.stage.name,
              outcome: DownloadAttemptOutcome.running.name,
              startedAtMicros: now.microsecondsSinceEpoch));
      return _write(
          current,
          now,
          DownloadJobsCompanion(
              state: Value(state.name),
              attemptCount: Value(current.attemptCount + 1),
              remainingAttempts: Value(current.remainingAttempts - 1),
              attemptToken: Value(token),
              leaseUntilMicros: Value(now.add(leaseFor).microsecondsSinceEpoch),
              retryAtMicros: const Value(null)));
    });
  }

  @override
  Future<DownloadJob?> renewLease(DownloadJob expected,
      {required DateTime now,
      Duration leaseFor = const Duration(seconds: 30)}) {
    _lease(leaseFor);
    return database.transaction(() async {
      if (!await _owned(expected, now)) return null;
      final deadline = now.add(leaseFor);
      return _write(
          expected,
          now,
          DownloadJobsCompanion(
              leaseUntilMicros: Value((deadline.isAfter(expected.leaseUntil!)
                      ? deadline
                      : expected.leaseUntil!)
                  .microsecondsSinceEpoch)));
    });
  }

  @override
  Future<DownloadJob?> advance(DownloadJob expected, DownloadJobStage next,
      {required DateTime now}) {
    if (next.index != expected.stage.index + 1) {
      throw ArgumentError('Этапы нельзя пропускать.');
    }
    return database.transaction(() async {
      if (expected.state != DownloadJobState.running ||
          !await _owned(expected, now)) {
        return null;
      }
      await _attemptStage(expected, next);
      return _write(
          expected, now, DownloadJobsCompanion(stage: Value(next.name)));
    });
  }

  @override
  Future<DownloadJob?> resolveReconciliation(
      DownloadJob expected, DownloadJobStage resumeAt,
      {required DateTime now}) {
    if (resumeAt.index > expected.stage.index) {
      throw ArgumentError('Сверка не может пропускать этапы.');
    }
    return database.transaction(() async {
      if (expected.state != DownloadJobState.reconciling ||
          !await _owned(expected, now)) {
        return null;
      }
      await _attemptStage(expected, resumeAt);
      return _write(
          expected,
          now,
          DownloadJobsCompanion(
              state: Value(DownloadJobState.running.name),
              stage: Value(resumeAt.name)));
    });
  }

  @override
  Future<DownloadJob?> complete(DownloadJob expected, DownloadedAsset asset,
          {required DateTime now}) =>
      database.transaction(() async {
        if (expected.state != DownloadJobState.running ||
            expected.stage != DownloadJobStage.importing ||
            !await _owned(expected, now)) {
          return null;
        }
        final attempts = await listAttempts(expected.id, limit: 1);
        if (asset.verification.checkedAt.isBefore(attempts.single.startedAt) ||
            asset.verification.checkedAt.isAfter(now.toUtc())) {
          return null;
        }
        final candidates = await DriftDownloadedAssetRepository(database)
            .findCandidates(expected.key.identity,
                quality: expected.key.quality,
                libraryFolderId: expected.key.libraryFolderId);
        if (!candidates.contains(asset)) return null;
        await _finishAttempt(
            expected, now, DownloadAttemptOutcome.completed, null);
        return _write(
            expected,
            now,
            DownloadJobsCompanion(
                state: Value(DownloadJobState.completed.name),
                attemptToken: const Value(null),
                leaseUntilMicros: const Value(null),
                failure: const Value(null),
                completedTrackId: Value(asset.publication.trackId)));
      });

  @override
  Future<DownloadJob?> fail(DownloadJob expected, DownloadFailure reason,
      {required DateTime now, DateTime? retryAt}) {
    if (retryAt != null &&
        (!retryAt.isAfter(now) ||
            (reason != DownloadFailure.network &&
                reason != DownloadFailure.rateLimited))) {
      throw ArgumentError(
          'Автоповтор допустим лишь для временной сетевой ошибки с будущим временем.');
    }
    return database.transaction(() async {
      if (!await _owned(expected, now)) return null;
      final scheduled = retryAt != null && expected.remainingAttempts > 0;
      await _finishAttempt(
          expected, now, DownloadAttemptOutcome.failed, reason);
      return _write(
          expected,
          now,
          DownloadJobsCompanion(
              state: Value((scheduled
                      ? DownloadJobState.needsReconciliation
                      : DownloadJobState.failed)
                  .name),
              attemptToken: const Value(null),
              leaseUntilMicros: const Value(null),
              retryAtMicros:
                  Value(scheduled ? retryAt.microsecondsSinceEpoch : null),
              failure: Value(reason.name)));
    });
  }

  @override
  Future<DownloadJob?> cancel(DownloadJob expected, {required DateTime now}) =>
      database.transaction(() async {
        if (expected.isTerminal || !await _matches(expected, now)) return null;
        if (expected.isExecuting) {
          await _finishAttempt(expected, now, DownloadAttemptOutcome.cancelled,
              DownloadFailure.cancelled);
        }
        return _write(
            expected,
            now,
            DownloadJobsCompanion(
                state: Value(DownloadJobState.cancelled.name),
                attemptToken: const Value(null),
                leaseUntilMicros: const Value(null),
                retryAtMicros: const Value(null),
                failure: Value(DownloadFailure.cancelled.name)));
      });

  @override
  Future<DownloadJob?> interrupt(DownloadJob expected,
          {required DateTime now,
          DownloadFailure reason = DownloadFailure.interrupted}) =>
      database.transaction(() async {
        if (!await _owned(expected, now)) return null;
        await _finishAttempt(
            expected, now, DownloadAttemptOutcome.interrupted, reason);
        return _write(
            expected,
            now,
            DownloadJobsCompanion(
                state: Value((expected.remainingAttempts > 0
                        ? DownloadJobState.needsReconciliation
                        : DownloadJobState.failed)
                    .name),
                attemptToken: const Value(null),
                leaseUntilMicros: const Value(null),
                retryAtMicros: const Value(null),
                failure: Value(reason.name)));
      });

  @override
  Future<DownloadJob?> retry(DownloadJob expected, RemoteLibraryAccount account,
          {required DateTime now, bool repairCompleted = false}) =>
      database.transaction(() async {
        if (!expected.isTerminal ||
            (expected.state == DownloadJobState.completed &&
                !repairCompleted) ||
            account.identity.provider != expected.key.identity.provider ||
            !await _currentAccount(account) ||
            !await _enabledFolder(expected.key.libraryFolderId) ||
            !await _matches(expected, now)) {
          return null;
        }
        return _write(
            expected,
            now,
            DownloadJobsCompanion(
                accountId: Value(account.id),
                accountRevision: Value(account.revision),
                state: Value(DownloadJobState.needsReconciliation.name),
                remainingAttempts: Value(expected.maxAttempts),
                retryAtMicros: const Value(null),
                failure: const Value(null),
                completedTrackId: const Value(null)));
      });

  @override
  Future<int> recoverExpired({required DateTime now}) =>
      database.transaction(() => _recover(now));

  @override
  Future<T?> withOwnedDestination<T extends Object>(DownloadJob expected,
          {required DateTime Function() clock,
          required Future<T> Function(String destinationPath) action}) =>
      database.transaction(() async {
        // A deferred read transaction alone does not fence other connections.
        // Acquire the SQLite writer reservation before reading ownership.
        await database.customUpdate(
            'UPDATE download_jobs SET revision = revision WHERE id = ?',
            variables: [Variable.withInt(expected.id)],
            updates: {});
        if (!await _owned(expected, clock())) return null;
        final folder = await (database.select(database.libraryFolders)
              ..where((t) => t.id.equals(expected.key.libraryFolderId)))
            .getSingle();
        final acceptedAt = clock();
        if (acceptedAt.isBefore(expected.updatedAt) ||
            !expected.leaseUntil!.isAfter(acceptedAt)) {
          return null;
        }
        return action(folder.path);
      });

  Future<int> _recover(DateTime now) async {
    final rows = await (database.select(database.downloadJobs)
          ..where((t) =>
              t.state.isIn([
                DownloadJobState.running.name,
                DownloadJobState.reconciling.name
              ]) &
              t.leaseUntilMicros
                  .isSmallerOrEqualValue(now.microsecondsSinceEpoch)))
        .get();
    for (final row in rows) {
      final job = _job(row);
      await _finishAttempt(job, now, DownloadAttemptOutcome.interrupted,
          DownloadFailure.interrupted);
      await _write(
          job,
          now,
          DownloadJobsCompanion(
              state: Value((job.remainingAttempts > 0
                      ? DownloadJobState.needsReconciliation
                      : DownloadJobState.failed)
                  .name),
              attemptToken: const Value(null),
              leaseUntilMicros: const Value(null),
              failure: Value(DownloadFailure.interrupted.name)));
    }
    return rows.length;
  }

  Future<bool> _matches(DownloadJob expected, DateTime now) async =>
      !now.isBefore(expected.updatedAt) && await _find(expected.id) == expected;
  Future<bool> _owned(DownloadJob expected, DateTime now) async {
    if (!expected.isExecuting ||
        !expected.leaseUntil!.isAfter(now) ||
        !await _matches(expected, now) ||
        !await _enabledFolder(expected.key.libraryFolderId)) {
      return false;
    }
    final account = await (database.select(database.remoteAccounts)
          ..where((t) => t.id.equals(expected.accountId)))
        .getSingleOrNull();
    return account != null &&
        account.isActive &&
        account.revision == expected.accountRevision &&
        account.provider == expected.key.identity.provider;
  }

  Future<bool> _currentAccount(RemoteLibraryAccount account) async =>
      account.isActive &&
      await DriftRemoteLibraryRepository(database)
              .findAccount(account.identity) ==
          account;
  Future<bool> _enabledFolder(int id) async =>
      (await (database.select(database.libraryFolders)
            ..where((t) => t.id.equals(id) & t.isEnabled.equals(true)))
          .getSingleOrNull()) !=
      null;
  Future<DownloadJob?> _find(int id) async {
    final row = await (database.select(database.downloadJobs)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _job(row);
  }

  Future<DownloadJob> _write(
      DownloadJob expected, DateTime now, DownloadJobsCompanion values) async {
    await (database.update(database.downloadJobs)
          ..where((t) => t.id.equals(expected.id)))
        .write(values.copyWith(
            revision: Value(expected.revision + 1),
            updatedAtMicros: Value(now.microsecondsSinceEpoch)));
    return (await _find(expected.id))!;
  }

  Future<void> _attemptStage(DownloadJob job, DownloadJobStage stage) =>
      (database.update(database.downloadAttempts)
            ..where((t) => t.token.equals(job.attemptToken!)))
          .write(DownloadAttemptsCompanion(stage: Value(stage.name)))
          .then((_) {});
  Future<void> _finishAttempt(DownloadJob job, DateTime now,
          DownloadAttemptOutcome outcome, DownloadFailure? failure) =>
      (database.update(database.downloadAttempts)
            ..where((t) => t.token.equals(job.attemptToken!)))
          .write(DownloadAttemptsCompanion(
              outcome: Value(outcome.name),
              finishedAtMicros: Value(now.microsecondsSinceEpoch),
              failure: Value(failure?.name),
              stage: Value(job.stage.name)))
          .then((_) {});
  static void _limit(int value) {
    if (value < 1 || value > 256) throw ArgumentError('Лимит от 1 до 256.');
  }

  static void _lease(Duration value) {
    if (value < const Duration(seconds: 1) ||
        value > const Duration(minutes: 10)) {
      throw ArgumentError('Срок владения от секунды до десяти минут.');
    }
  }

  static DateTime _date(int micros) =>
      DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
  static DateTime? _optionalDate(int? micros) =>
      micros == null ? null : _date(micros);
  static DownloadFailure? _failure(String? value) =>
      value == null ? null : DownloadFailure.values.byName(value);
  static DownloadJob _job(DownloadJobRow r) => DownloadJob(
      id: r.id,
      key: DownloadJobKey(
          libraryFolderId: r.libraryFolderId,
          identity: ExternalTrackIdentity(
              provider: r.provider,
              externalId: r.externalId,
              variantKey: r.variantKey),
          quality: r.quality),
      accountId: r.accountId,
      accountRevision: r.accountRevision,
      state: DownloadJobState.values.byName(r.state),
      stage: DownloadJobStage.values.byName(r.stage),
      revision: r.revision,
      attemptCount: r.attemptCount,
      maxAttempts: r.maxAttempts,
      remainingAttempts: r.remainingAttempts,
      createdAt: _date(r.createdAtMicros),
      updatedAt: _date(r.updatedAtMicros),
      attemptToken: r.attemptToken,
      leaseUntil: _optionalDate(r.leaseUntilMicros),
      retryAt: _optionalDate(r.retryAtMicros),
      failure: _failure(r.failure),
      completedTrackId: r.completedTrackId);
}

/// Revokes DB ownership in the same transaction as account/folder changes.
/// The future runner must also stop IO and fence physical publication separately.
Future<void> invalidateDownloadJobs(AppDatabase database,
    {int? accountId, int? folderId, required DownloadFailure reason}) async {
  if ((accountId == null) == (folderId == null)) {
    throw ArgumentError('Один владелец для отмены.');
  }
  final rows = await (database.select(database.downloadJobs)
        ..where((t) =>
            (accountId != null
                ? t.accountId.equals(accountId)
                : t.libraryFolderId.equals(folderId!)) &
            t.state.isIn(
                ['queued', 'running', 'needsReconciliation', 'reconciling'])))
      .get();
  for (final row in rows) {
    final now = max(DateTime.now().microsecondsSinceEpoch, row.updatedAtMicros);
    if (row.attemptToken != null) {
      await (database.update(database.downloadAttempts)
            ..where((t) => t.token.equals(row.attemptToken!)))
          .write(DownloadAttemptsCompanion(
              outcome: Value(DownloadAttemptOutcome.cancelled.name),
              finishedAtMicros: Value(now),
              failure: Value(reason.name)));
    }
    await (database.update(database.downloadJobs)
          ..where((t) => t.id.equals(row.id)))
        .write(DownloadJobsCompanion(
            state: Value(DownloadJobState.cancelled.name),
            revision: Value(row.revision + 1),
            updatedAtMicros: Value(now),
            attemptToken: const Value(null),
            leaseUntilMicros: const Value(null),
            retryAtMicros: const Value(null),
            failure: Value(reason.name)));
  }
}

Future<void> deleteDownloadJobsForFolder(
    AppDatabase database, int folderId) async {
  final jobs = await (database.select(database.downloadJobs)
        ..where((t) => t.libraryFolderId.equals(folderId)))
      .get();
  for (final job in jobs) {
    await (database.delete(database.downloadAttempts)
          ..where((t) => t.jobId.equals(job.id)))
        .go();
  }
  await (database.delete(database.downloadJobs)
        ..where((t) => t.libraryFolderId.equals(folderId)))
      .go();
}
