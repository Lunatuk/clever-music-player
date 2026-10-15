import 'package:drift/drift.dart';

import '../../domain/models/external_track_ref.dart';
import '../../domain/models/remote_library.dart';
import '../../domain/models/download_job.dart';
import '../../domain/repositories/remote_library_repository.dart';
import '../drift/app_database.dart';
import 'drift_download_job_repository.dart';

final class DriftRemoteLibraryRepository implements RemoteLibraryRepository {
  const DriftRemoteLibraryRepository(this.database);
  final AppDatabase database;

  @override
  Future<RemoteLibraryAccount> activateAccount(RemoteAccountIdentity identity,
      {String? displayName}) {
    validateRemoteDisplayName(displayName);
    return database.transaction(() async {
      final table = database.remoteAccounts;
      final active = await (database.select(table)
            ..where((t) =>
                t.provider.equals(identity.provider) &
                t.isActive.equals(true) &
                t.accountId.equals(identity.accountId).not()))
          .get();
      for (final row in active) {
        await invalidateDownloadJobs(database,
            accountId: row.id, reason: DownloadFailure.accountChanged);
        await (database.update(table)..where((t) => t.id.equals(row.id))).write(
            RemoteAccountsCompanion(
                isActive: const Value(false),
                revision: Value(row.revision + 1)));
      }
      // Reactivating the same account also gets a fresh revision.
      // No token, subscription or authentication state here.
      final current = await _accountRow(identity);
      if (current == null) {
        await database.into(table).insert(RemoteAccountsCompanion.insert(
            provider: identity.provider,
            accountId: identity.accountId,
            displayName: Value(displayName),
            isActive: true,
            revision: 1));
      } else {
        await invalidateDownloadJobs(database,
            accountId: current.id, reason: DownloadFailure.accountChanged);
        await (database.update(table)..where((t) => t.id.equals(current.id)))
            .write(RemoteAccountsCompanion(
                displayName: Value(displayName),
                isActive: const Value(true),
                revision: Value(current.revision + 1)));
      }
      return _account((await _accountRow(identity))!);
    });
  }

  @override
  Future<RemoteLibraryAccount?> findAccount(
      RemoteAccountIdentity identity) async {
    final row = await _accountRow(identity);
    return row == null ? null : _account(row);
  }

  @override
  Future<List<RemoteLibraryAccount>> listAccounts() async {
    final rows = await (database.select(database.remoteAccounts)
          ..orderBy([
            (t) => OrderingTerm(expression: t.provider),
            (t) => OrderingTerm(expression: t.accountId)
          ]))
        .get();
    return List.unmodifiable(rows.map(_account));
  }

  @override
  Future<bool> disconnectAccount(RemoteLibraryAccount expected) =>
      database.transaction(() async {
        if (!await _isCurrentAccount(expected)) return false;
        await invalidateDownloadJobs(database,
            accountId: expected.id, reason: DownloadFailure.accountChanged);
        await (database.update(database.remoteAccounts)
              ..where((t) => t.id.equals(expected.id)))
            .write(RemoteAccountsCompanion(
                isActive: const Value(false),
                revision: Value(expected.revision + 1)));
        return true;
      });

  @override
  Future<RemoteLibraryCollection?> configureCollection(
      RemoteLibraryAccount account, RemoteCollectionKey key,
      {String? title, required bool isSelected}) {
    validateRemoteDisplayName(title);
    return database.transaction(() async {
      if (!await _isCurrentAccount(account)) return null;
      final row = await _collectionRow(account.id, key);
      if (row == null) {
        await database.into(database.remoteCollections).insert(
            RemoteCollectionsCompanion.insert(
                accountId: account.id,
                kind: key.kind.name,
                externalId: key.externalId,
                ownerId: key.ownerId,
                title: Value(title),
                isSelected: isSelected,
                revision: 1));
      } else if (row.title != title || row.isSelected != isSelected) {
        await (database.update(database.remoteCollections)
              ..where((t) => t.id.equals(row.id)))
            .write(RemoteCollectionsCompanion(
                title: Value(title),
                isSelected: Value(isSelected),
                revision: Value(row.revision + 1)));
      }
      return _collection(
          (await _collectionRow(account.id, key))!, account.identity);
    });
  }

  @override
  Future<List<RemoteLibraryCollection>> listCollections(
      RemoteAccountIdentity account,
      {bool selectedOnly = false}) async {
    final owner = await _accountRow(account);
    if (owner == null) return const [];
    final rows = await (database.select(database.remoteCollections)
          ..where((t) =>
              t.accountId.equals(owner.id) &
              (selectedOnly ? t.isSelected.equals(true) : const Constant(true)))
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    return List.unmodifiable(rows.map((row) => _collection(row, account)));
  }

  @override
  Future<RemoteCollectionContent?> readContent(
          RemoteAccountIdentity account, RemoteCollectionKey key) =>
      database.transaction(() async {
        final owner = await _accountRow(account);
        if (owner == null) return null;
        final row = await _collectionRow(owner.id, key);
        if (row == null || row.completedAtMicros == null) return null;
        final items = await (database.select(database.remoteCollectionItems)
              ..where((t) => t.collectionId.equals(row.id))
              ..orderBy([(t) => OrderingTerm(expression: t.position)]))
            .get();
        if (items.length != row.itemCount ||
            items.indexed.any((entry) => entry.$1 != entry.$2.position)) {
          throw StateError('Нарушен порядок сохранённой коллекции.');
        }
        return RemoteCollectionContent(
            collection: _collection(row, account),
            items: items.map((item) => ExternalTrackIdentity(
                provider: account.provider,
                externalId: item.externalId,
                variantKey: item.variantKey)));
      });

  @override
  Future<RemoteCollectionRefresh?> beginRefresh(
      RemoteLibraryAccount account, RemoteLibraryCollection collection) {
    if (account.identity != collection.account) {
      throw ArgumentError('Коллекция другого аккаунта.');
    }
    return database.transaction(() async {
      if (!await _isCurrentAccount(account)) return null;
      final row = await _collectionRow(account.id, collection.key);
      if (row == null ||
          !row.isSelected ||
          _collection(row, account.identity) != collection) {
        return null;
      }
      await (database.update(database.remoteCollections)
            ..where((t) => t.id.equals(row.id)))
          .write(RemoteCollectionsCompanion(revision: Value(row.revision + 1)));
      return RemoteCollectionRefresh(
          account: account,
          collection: _collection(
              (await _collectionRow(account.id, collection.key))!,
              account.identity));
    });
  }

  @override
  Future<bool> commitSnapshot(
      RemoteCollectionRefresh refresh, RemoteCollectionSnapshot snapshot) {
    if (refresh.account.identity != refresh.collection.account ||
        snapshot.items.any(
            (item) => item.provider != refresh.account.identity.provider)) {
      throw ArgumentError('Ответ другого аккаунта или провайдера.');
    }
    if (!snapshot.canCommit) return Future.value(false);
    return database.transaction(() async {
      if (!await _isCurrentAccount(refresh.account)) return false;
      final expected = refresh.collection;
      final row = await _collectionRow(refresh.account.id, expected.key);
      if (row == null ||
          !row.isSelected ||
          _collection(row, expected.account) != expected ||
          (expected.completedAt != null &&
              snapshot.completedAt.isBefore(expected.completedAt!))) {
        return false;
      }
      final items = database.remoteCollectionItems;
      await (database.delete(items)
            ..where((t) => t.collectionId.equals(row.id)))
          .go();
      const batchSize = 256;
      for (var start = 0; start < snapshot.items.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, snapshot.items.length);
        await database.batch((batch) {
          for (var position = start; position < end; position++) {
            final item = snapshot.items[position];
            batch.insert(
                items,
                RemoteCollectionItemsCompanion.insert(
                    collectionId: row.id,
                    position: position,
                    externalId: item.externalId,
                    variantKey: item.variantKey));
          }
        });
      }
      await (database.update(database.remoteCollections)
            ..where((t) => t.id.equals(row.id)))
          .write(RemoteCollectionsCompanion(
              revision: Value(row.revision + 1),
              itemCount: Value(snapshot.items.length),
              remoteRevision: Value(snapshot.revisionAtEnd),
              completedAtMicros:
                  Value(snapshot.completedAt.microsecondsSinceEpoch)));
      return true;
    });
  }

  Future<RemoteAccountRow?> _accountRow(RemoteAccountIdentity identity) =>
      (database.select(database.remoteAccounts)
            ..where((t) =>
                t.provider.equals(identity.provider) &
                t.accountId.equals(identity.accountId)))
          .getSingleOrNull();
  Future<RemoteCollectionRow?> _collectionRow(
          int accountId, RemoteCollectionKey key) =>
      (database.select(database.remoteCollections)
            ..where((t) =>
                t.accountId.equals(accountId) &
                t.kind.equals(key.kind.name) &
                t.externalId.equals(key.externalId) &
                t.ownerId.equals(key.ownerId)))
          .getSingleOrNull();
  Future<bool> _isCurrentAccount(RemoteLibraryAccount expected) async {
    final current = await findAccount(expected.identity);
    return current != null && current.isActive && current == expected;
  }

  static RemoteLibraryAccount _account(RemoteAccountRow row) =>
      RemoteLibraryAccount(
          id: row.id,
          identity: RemoteAccountIdentity(
              provider: row.provider, accountId: row.accountId),
          displayName: row.displayName,
          isActive: row.isActive,
          revision: row.revision);
  static RemoteLibraryCollection _collection(
          RemoteCollectionRow row, RemoteAccountIdentity account) =>
      RemoteLibraryCollection(
          id: row.id,
          account: account,
          key: RemoteCollectionKey(
              kind: RemoteCollectionKind.values.byName(row.kind),
              externalId: row.externalId,
              ownerId: row.ownerId),
          title: row.title,
          isSelected: row.isSelected,
          revision: row.revision,
          itemCount: row.itemCount,
          remoteRevision: row.remoteRevision,
          completedAt: row.completedAtMicros == null
              ? null
              : DateTime.fromMicrosecondsSinceEpoch(row.completedAtMicros!,
                  isUtc: true));
}
