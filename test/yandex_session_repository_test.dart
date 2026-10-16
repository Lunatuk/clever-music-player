import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library_sync/yandex_credential_store.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/download_fixture.dart';
import 'support/yandex_connection_fixture.dart';
import 'support/yandex_fixture.dart';

void main() {
  late DownloadFixture f;
  late MemoryYandexCredentials credentials;
  setUp(() async {
    f = await DownloadFixture.open(persistent: true);
    credentials = MemoryYandexCredentials();
  });
  tearDown(() => f.close());
  Future<RemoteLibraryAccount?> connect(List<RemoteLibraryAccount> expected) =>
      f.repositories.yandexSessions.connect(expected, yandexAccount,
          displayName: 'Music',
          persist: (account) => credentials.write(YandexSavedCredential(
              account: account, token: YandexAccessToken('synthetic-secret'))));
  test(
      'connection persists only outside SQLite and changes the active revision',
      () async {
    final expected = await f.repositories.yandexSessions.capture();
    final account = (await connect(expected))!;
    expect(credentials.value!.matches(account), isTrue);
    expect(await f.repositories.yandexSessions.capture(), [account]);
    final rows =
        await f.database.customSelect('SELECT * FROM remote_accounts').get();
    expect(rows.map((row) => row.data).toString(),
        isNot(contains('synthetic-secret')));
  });
  test('stale competing connection never writes the credential slot', () async {
    final expected = await f.repositories.yandexSessions.capture();
    await f.repositories.remoteLibrary.activateAccount(yandexAccount);
    expect(await connect(expected), isNull);
    expect(credentials.writes, 0);
  });
  test('failed secure write rolls back account/job/attempt invalidation',
      () async {
    final job = await f.claim();
    final expected = await f.repositories.yandexSessions.capture();
    credentials.failWrite = true;
    await expectLater(
        connect(expected), throwsA(isA<YandexCredentialException>()));
    expect(await f.repositories.yandexSessions.capture(), expected);
    expect(await f.repositories.downloadJobs.findByKey(job.key), job);
    expect(
        (await f.repositories.downloadJobs.listAttempts(job.id)).single.outcome,
        DownloadAttemptOutcome.running);
  });
  test(
      'write succeeded then DB rollback leaves an unusable binding, never the wrong session',
      () async {
    final expected = await f.repositories.yandexSessions.capture();
    credentials.writeThenFail = true;
    await expectLater(
        connect(expected), throwsA(isA<YandexCredentialException>()));
    final current = await f.repositories.yandexSessions.capture();
    expect(current, expected);
    expect(current.any(credentials.value!.matches), isFalse);
  });
  test(
      'disconnect invalidates ownership, deletes one credential, keeps mirrors',
      () async {
    final account =
        (await connect(await f.repositories.yandexSessions.capture()))!;
    final collection = (await f.repositories.remoteLibrary
        .configureCollection(account, yandexLiked, isSelected: true))!;
    final ticket =
        (await f.repositories.remoteLibrary.beginRefresh(account, collection))!;
    await f.repositories.remoteLibrary.commitSnapshot(
        ticket,
        RemoteCollectionSnapshot(
            items: [], isComplete: true, completedAt: f.now));
    expect(
        await f.repositories.yandexSessions
            .disconnect([account], forget: credentials.delete),
        isTrue);
    expect(credentials.value, isNull);
    expect(credentials.deletes, 1);
    expect(
        await f.repositories.remoteLibrary
            .readContent(account.identity, yandexLiked),
        isNotNull);
    expect(await f.raw.readAsString(), 'abc');
  });
  test('failed secure deletion rolls back account revocation', () async {
    final account =
        (await connect(await f.repositories.yandexSessions.capture()))!;
    credentials.failDelete = true;
    await expectLater(
        f.repositories.yandexSessions
            .disconnect([account], forget: credentials.delete),
        throwsA(isA<YandexCredentialException>()));
    expect(await f.repositories.yandexSessions.capture(), [account]);
    expect(credentials.value!.matches(account), isTrue);
  });
  test('stale logout cannot erase a newer process credential', () async {
    final old = await f.repositories.yandexSessions.capture();
    final account = (await connect(old))!;
    expect(
        await f.repositories.yandexSessions
            .disconnect(old, forget: credentials.delete),
        isFalse);
    expect(credentials.deletes, 0);
    expect(credentials.value!.matches(account), isTrue);
  });
  test('two SQLite writers serialize, only one stale-free connection persists',
      () async {
    final other = AppDatabase(NativeDatabase.createInBackground(
        File(p.join(f.root.path, 'state.sqlite'))));
    await other.customStatement('PRAGMA busy_timeout = 5000');
    final expected = await f.repositories.yandexSessions.capture();
    var writes = 0;
    try {
      final results = await Future.wait([
        f.repositories.yandexSessions
            .connect(expected, yandexAccount, persist: (_) async => writes++),
        DriftRepositories(other)
            .yandexSessions
            .connect(expected, yandexAccount, persist: (_) async => writes++),
      ]);
      expect(results.whereType<RemoteLibraryAccount>(), hasLength(1));
      expect(writes, 1);
    } finally {
      await other.close();
    }
  });
  test('accepted storage callback fences another writer until commit',
      () async {
    final other = AppDatabase(NativeDatabase.createInBackground(
        File(p.join(f.root.path, 'state.sqlite'))));
    await other.customStatement('PRAGMA busy_timeout = 5000');
    final entered = Completer<void>(), release = Completer<void>();
    var revoked = false;
    try {
      final pending = f.repositories.yandexSessions
          .connect(await f.repositories.yandexSessions.capture(), yandexAccount,
              persist: (_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final writer = other
          .customStatement('UPDATE remote_accounts SET revision = revision + 1')
          .then((_) => revoked = true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(revoked, isFalse);
      release.complete();
      expect(await pending, isNotNull);
      await writer;
    } finally {
      if (!release.isCompleted) release.complete();
      await other.close();
    }
  });
  test(
      'session publication retains its binding after reopening persistent SQLite',
      () async {
    final account =
        (await connect(await f.repositories.yandexSessions.capture()))!;
    f = await f.reopen();
    expect(
        credentials.value!
            .matches((await f.repositories.yandexSessions.capture()).single),
        isTrue);
    expect((await f.repositories.yandexSessions.capture()).single, account);
  });
}
