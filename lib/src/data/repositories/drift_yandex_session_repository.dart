import 'package:drift/drift.dart';

import '../../domain/models/remote_library.dart';
import '../../domain/repositories/yandex_session_repository.dart';
import '../drift/app_database.dart';
import 'drift_remote_library_repository.dart';

final class DriftYandexSessionRepository implements YandexSessionRepository {
  const DriftYandexSessionRepository(this.database);
  final AppDatabase database;
  @override
  Future<List<RemoteLibraryAccount>> capture() async => List.unmodifiable(
      (await DriftRemoteLibraryRepository(database).listAccounts())
          .where((a) => a.identity.provider == 'yandex_music' && a.isActive));

  Future<bool> _reserve(List<RemoteLibraryAccount> expected) async {
    if (expected
            .any((a) => !a.isActive || a.identity.provider != 'yandex_music') ||
        expected.toSet().length != expected.length) {
      throw ArgumentError('Неверная сессия.');
    }
    await database.customUpdate(
        'UPDATE remote_accounts SET revision = revision WHERE provider = ?',
        variables: [Variable.withString('yandex_music')],
        updates: {});
    final current = await capture();
    return current.length == expected.length &&
        current.toSet().containsAll(expected);
  }

  @override
  Future<RemoteLibraryAccount?> connect(
      List<RemoteLibraryAccount> expected, RemoteAccountIdentity identity,
      {String? displayName,
      required Future<void> Function(RemoteLibraryAccount account) persist}) {
    if (identity.provider != 'yandex_music') {
      throw ArgumentError('Другой источник.');
    }
    return database.transaction(() async {
      if (!await _reserve(expected)) return null;
      final account = await DriftRemoteLibraryRepository(database)
          .activateAccount(identity, displayName: displayName);
      await persist(account);
      return account;
    });
  }

  @override
  Future<bool> disconnect(List<RemoteLibraryAccount> expected,
          {required Future<void> Function() forget}) =>
      database.transaction(() async {
        if (!await _reserve(expected)) return false;
        final repository = DriftRemoteLibraryRepository(database);
        for (final account in expected) {
          if (!await repository.disconnectAccount(account)) {
            throw StateError('Сессия изменилась.');
          }
        }
        await forget();
        return true;
      });
}
