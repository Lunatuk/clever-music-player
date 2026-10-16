import 'dart:async';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/remote_library_repository.dart';
import 'package:clever_music_player/src/domain/services/library_sync_planner.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/yandex_collection_refresher.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_client.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/download_fixture.dart';
import 'support/yandex_fixture.dart';

void main() {
  late DownloadFixture f;
  late RemoteLibraryCollection collection;
  late YandexTestTransport transport;
  late YandexLibraryClient client;
  late YandexCollectionRefresher refresher;
  setUp(() async {
    f = await DownloadFixture.open();
    f.account =
        await f.repositories.remoteLibrary.activateAccount(yandexAccount);
    collection = (await f.repositories.remoteLibrary
        .configureCollection(f.account, yandexLiked, isSelected: true))!;
    final ticket = (await f.repositories.remoteLibrary
        .beginRefresh(f.account, collection))!;
    await f.repositories.remoteLibrary.commitSnapshot(
        ticket,
        RemoteCollectionSnapshot(
            items: [
              ExternalTrackIdentity(provider: 'yandex_music', externalId: 'old')
            ],
            isComplete: true,
            completedAt: f.now.subtract(const Duration(days: 1)),
            revisionAtStart: '0',
            revisionAtEnd: '0'));
    collection =
        (await f.repositories.remoteLibrary.listCollections(yandexAccount))
            .single;
    transport = YandexTestTransport();
    client = YandexLibraryClient(
        token: YandexAccessToken('synthetic-secret'),
        transport: transport,
        clock: f.clock);
    await client.verifyAccount();
    refresher = YandexCollectionRefresher(
        repository: f.repositories.remoteLibrary, reader: client);
  });
  tearDown(() async {
    await refresher.close();
    await f.close();
  });
  Future<YandexRefreshResult> refresh({LibraryScanControl? control}) =>
      refresher.refresh(f.account, collection, control: control);
  Future<void> oldPreserved() async {
    final saved = (await f.repositories.remoteLibrary
        .readContent(yandexAccount, yandexLiked))!;
    expect(saved.items.map((e) => e.externalId), ['old']);
    expect(
        saved.collection.completedAt, f.now.subtract(const Duration(days: 1)));
  }

  test('complete verified snapshot atomically replaces the old mirror',
      () async {
    final result = await refresh();
    expect(result.outcome, YandexRefreshOutcome.updated);
    expect(result.itemCount, 3);
    final saved = (await f.repositories.remoteLibrary
        .readContent(yandexAccount, yandexLiked))!;
    expect(saved.items.map((e) => e.externalId), ['001', '2', '001']);
    expect(saved.collection.completedAt, f.now);
    expect(await f.count('tracks'), 0);
    expect(await f.count('download_jobs'), 0);
  });
  for (final failure in [
    YandexLibraryFailure.network,
    YandexLibraryFailure.unauthorized,
    YandexLibraryFailure.accessDenied,
    YandexLibraryFailure.rateLimited
  ]) {
    test('$failure preserves old mirror and never queues work', () async {
      transport.onGet = (_, __) async => throw YandexLibraryException(failure);
      final result = await refresh();
      expect(result.outcome, YandexRefreshOutcome.failed);
      expect(result.failure, failure);
      await oldPreserved();
      expect(await f.count('download_jobs'), 0);
    });
  }
  test('changed collection between observations preserves previous content',
      () async {
    var reads = 0;
    transport.onGet = (_, __) async => yandexLikes(revision: ++reads);
    expect((await refresh()).failure, YandexLibraryFailure.changed);
    await oldPreserved();
  });
  test('empty successful snapshot removes only mirror positions', () async {
    transport.onGet = (_, __) async => yandexLikes(tracks: []);
    expect((await refresh()).outcome, YandexRefreshOutcome.updated);
    expect(
        (await f.repositories.remoteLibrary
                .readContent(yandexAccount, yandexLiked))!
            .items,
        isEmpty);
    expect(await f.raw.readAsString(), 'abc');
    expect(await f.count('tracks'), 0);
  });
  test('account session replacement during network rejects late commit',
      () async {
    var replaced = false;
    transport.onGet = (_, __) async {
      if (!replaced) {
        replaced = true;
        await f.repositories.remoteLibrary.activateAccount(yandexAccount);
      }
      return yandexLikes();
    };
    expect((await refresh()).outcome, YandexRefreshOutcome.stale);
    await oldPreserved();
  });
  test('deselected collection during network rejects late commit', () async {
    var changed = false;
    transport.onGet = (_, __) async {
      if (!changed) {
        changed = true;
        await f.repositories.remoteLibrary
            .configureCollection(f.account, yandexLiked, isSelected: false);
      }
      return yandexLikes();
    };
    expect((await refresh()).outcome, YandexRefreshOutcome.stale);
    await oldPreserved();
  });
  test('newer refresh ticket during network invalidates the older result',
      () async {
    var changed = false;
    transport.onGet = (_, __) async {
      if (!changed) {
        changed = true;
        final current =
            (await f.repositories.remoteLibrary.listCollections(yandexAccount))
                .single;
        await f.repositories.remoteLibrary.beginRefresh(f.account, current);
      }
      return yandexLikes();
    };
    expect((await refresh()).outcome, YandexRefreshOutcome.stale);
    await oldPreserved();
  });
  test(
      'stale initial collection does not make an authenticated network request',
      () async {
    await f.repositories.remoteLibrary.beginRefresh(f.account, collection);
    expect((await refresh()).outcome, YandexRefreshOutcome.stale);
    expect(transport.requests, hasLength(1));
    await oldPreserved();
  });
  test('pre-cancel and cancellation during reading preserve the old mirror',
      () async {
    expect((await refresh(control: LibraryScanControl()..cancel())).outcome,
        YandexRefreshOutcome.cancelled);
    final control = LibraryScanControl();
    transport.onGet = (_, __) async {
      control.cancel();
      return yandexLikes();
    };
    expect((await refresh(control: control)).outcome,
        YandexRefreshOutcome.cancelled);
    await oldPreserved();
  });
  test('wrong verified account rejects before acquiring a refresh revision',
      () async {
    final account = await f.repositories.remoteLibrary.activateAccount(
        RemoteAccountIdentity(provider: 'yandex_music', accountId: '202'));
    final other = (await f.repositories.remoteLibrary
        .configureCollection(account, yandexLiked, isSelected: true))!;
    expect((await refresher.refresh(account, other)).failure,
        YandexLibraryFailure.accountMismatch);
    expect(transport.requests, hasLength(1));
    await oldPreserved();
  });
  test(
      'SQLite failure rolls back content replacement and exposes only storage code',
      () async {
    await f.database.customStatement(
        "CREATE TRIGGER reject_mirror BEFORE DELETE ON remote_collection_items BEGIN SELECT RAISE(ABORT, 'synthetic-secret'); END");
    final result = await refresh();
    expect(result.outcome, YandexRefreshOutcome.failed);
    expect(result.failure, YandexLibraryFailure.storage);
    await oldPreserved();
    expect(await f.count('remote_collection_items'), 1);
  });
  test(
      'accepted DB commit drains on close and reports the actual successful result',
      () async {
    final gate = _CommitGate(f.repositories.remoteLibrary);
    // Reader already verified; replace only the idle owner, retaining this reader.
    refresher = YandexCollectionRefresher(repository: gate, reader: client);
    final result = refresh();
    await gate.entered.future;
    var closed = false;
    final closing = refresher.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    gate.release.complete();
    expect((await result).outcome, YandexRefreshOutcome.updated);
    await closing;
    expect(transport.closed, isTrue);
    expect(
        (await f.repositories.remoteLibrary
                .readContent(yandexAccount, yandexLiked))!
            .items,
        hasLength(3));
  });
  test(
      'complete adapter snapshots feed the existing deduplicating durable planner',
      () async {
    expect((await refresh()).outcome, YandexRefreshOutcome.updated);
    final snapshot = (await f.repositories.librarySync.capture(f.account,
        libraryFolderId: f.folderId,
        quality: 'high',
        minimumCompletedAt: f.now))!;
    final plan = const LibrarySyncPlanner().build(snapshot);
    expect(plan.isReady, isTrue);
    expect(plan.sourceOccurrences, 3);
    expect(plan.items, hasLength(2));
    final applied = await f.repositories.librarySync.apply(plan, now: f.now);
    expect(applied.status, LibrarySyncApplyStatus.applied);
    expect(applied.scheduledJobs, hasLength(2));
    expect(await f.count('download_jobs'), 2);
    expect(await f.count('tracks'), 0);
  });
}

final class _CommitGate implements RemoteLibraryRepository {
  _CommitGate(this.delegate);
  final RemoteLibraryRepository delegate;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<RemoteCollectionRefresh?> beginRefresh(
          RemoteLibraryAccount account, RemoteLibraryCollection collection) =>
      delegate.beginRefresh(account, collection);
  @override
  Future<bool> commitSnapshot(RemoteCollectionRefresh refresh,
      RemoteCollectionSnapshot snapshot) async {
    entered.complete();
    await release.future;
    return delegate.commitSnapshot(refresh, snapshot);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
