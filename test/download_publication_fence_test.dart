import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library_sync/desktop_publication_store.dart';
import 'package:clever_music_player/src/library_sync/publication_intent.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/publication_fixture.dart';

void main() {
  late Directory temp;
  late AppDatabase database;
  late DriftRepositories repositories;
  late RemoteLibraryAccount account;
  late DownloadJob job;
  late int folder;
  DateTime now = publicationNow;
  setUp(() async {
    now = publicationNow;
    temp = await Directory.systemTemp.createTemp('cmp_fence_');
    database = AppDatabase(NativeDatabase.memory());
    repositories = DriftRepositories(database);
    account = await repositories.remoteLibrary.activateAccount(
        RemoteAccountIdentity(provider: 'yandex_music', accountId: 'A'));
    folder = await repositories.libraryFolders.upsertFolder(
        LibraryFolder(path: temp.path, createdAt: now, updatedAt: now));
    await repositories.downloadJobs.enqueue(
        account,
        [
          DownloadJobKey(
              libraryFolderId: folder,
              identity: publicationJob().key.identity,
              quality: 'high')
        ],
        now: now);
    job = (await repositories.downloadJobs.claimNext(account, now: now))!;
    for (final stage in [
      DownloadJobStage.metadata,
      DownloadJobStage.verification,
      DownloadJobStage.publication
    ]) {
      job = (await repositories.downloadJobs.advance(job, stage, now: now))!;
    }
  });
  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });
  test('fence returns persisted destination and leaves snapshot unchanged',
      () async {
    final result = await repositories.downloadJobs.withOwnedDestination(job,
        clock: () => now,
        action: (path) async {
          expect(path, temp.path);
          return 42;
        });
    expect(result, 42);
    expect(await repositories.downloadJobs.findByKey(job.key), job);
  });
  test('expired and stale snapshots never invoke the physical effect',
      () async {
    var called = false;
    Future<bool> action(String path) async {
      called = true;
      return true;
    }

    expect(
        await repositories.downloadJobs.withOwnedDestination(job,
            clock: () => job.leaseUntil!, action: action),
        isNull);
    final newer = (await repositories.downloadJobs.renewLease(job, now: now))!;
    expect(
        await repositories.downloadJobs
            .withOwnedDestination(job, clock: () => now, action: action),
        isNull);
    expect(called, isFalse);
    expect(await repositories.downloadJobs.findByKey(job.key), newer);
  });
  test('clock rechecked immediately before acceptance', () async {
    var clocks = 0, called = false;
    expect(
        await repositories.downloadJobs.withOwnedDestination(job,
            clock: () => ++clocks == 1 ? now : job.leaseUntil!,
            action: (_) async {
              called = true;
              return true;
            }),
        isNull);
    expect(called, isFalse);
    expect(clocks, 2);
  });
  for (final change in ['folder', 'account']) {
    test('$change revocation fences the old owner', () async {
      if (change == 'folder') {
        await repositories.libraryFolders
            .setFolderEnabled(folder, isEnabled: false, updatedAt: now);
      } else {
        await repositories.remoteLibrary.activateAccount(account.identity);
      }
      var called = false;
      expect(
          await repositories.downloadJobs.withOwnedDestination(job,
              clock: () => now,
              action: (_) async {
                called = true;
                return true;
              }),
          isNull);
      expect(called, isFalse);
    });
  }
  test('reservation failure never invokes action', () async {
    await database.customStatement(
        "CREATE TRIGGER reject_fence BEFORE UPDATE ON download_jobs BEGIN SELECT RAISE(ABORT, 'test'); END");
    var called = false;
    await expectLater(
        repositories.downloadJobs.withOwnedDestination(job,
            clock: () => now,
            action: (_) async {
              called = true;
              return true;
            }),
        throwsA(anything));
    expect(called, isFalse);
    expect(await repositories.downloadJobs.findByKey(job.key), job);
  });
  test('callback failure does not change ownership', () async {
    await expectLater(
        repositories.downloadJobs.withOwnedDestination<bool>(job,
            clock: () => now,
            action: (_) async {
              throw StateError('failed');
            }),
        throwsStateError);
    expect(await repositories.downloadJobs.findByKey(job.key), job);
    expect(
        await repositories.downloadJobs.withOwnedDestination(job,
            clock: () => now, action: (_) async => true),
        isTrue);
  });
  test('cancel serializes after an accepted effect', () async {
    final entered = Completer<void>(), gate = Completer<void>();
    final effect = repositories.downloadJobs.withOwnedDestination(job,
        clock: () => now,
        action: (_) async {
          entered.complete();
          await gate.future;
          return true;
        });
    await entered.future;
    var cancelled = false;
    final cancellation =
        repositories.downloadJobs.cancel(job, now: now).then((result) {
      cancelled = true;
      return result;
    });
    await Future<void>.delayed(Duration.zero);
    expect(cancelled, isFalse);
    gate.complete();
    expect(await effect, isTrue);
    expect((await cancellation)!.state, DownloadJobState.cancelled);
  });
  test(
      'a second SQLite connection waits for reservation then checks current clock',
      () async {
    await database.close();
    database =
        AppDatabase(NativeDatabase(File(p.join(temp.path, 'fence.sqlite'))));
    repositories = DriftRepositories(database);
    account =
        await repositories.remoteLibrary.activateAccount(account.identity);
    folder = await repositories.libraryFolders.upsertFolder(
        LibraryFolder(path: temp.path, createdAt: now, updatedAt: now));
    await repositories.downloadJobs.enqueue(
        account,
        [
          DownloadJobKey(
              libraryFolderId: folder,
              identity: job.key.identity,
              quality: 'high')
        ],
        now: now);
    job = (await repositories.downloadJobs.claimNext(account, now: now))!;
    final other = AppDatabase(NativeDatabase.createInBackground(
        File(p.join(temp.path, 'fence.sqlite')),
        setup: (raw) => raw.execute('PRAGMA busy_timeout=5000')));
    final otherRepo = DriftRepositories(other);
    final entered = Completer<void>(), gate = Completer<void>();
    final first = repositories.downloadJobs.withOwnedDestination(job,
        clock: () => now,
        action: (_) async {
          entered.complete();
          await gate.future;
          return true;
        });
    await entered.future;
    var clocks = 0, called = false;
    final second = otherRepo.downloadJobs.withOwnedDestination(job, clock: () {
      clocks++;
      return now;
    }, action: (_) async {
      called = true;
      return true;
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(clocks, 0);
      now = job.leaseUntil!;
      gate.complete();
      expect(await first, isTrue);
      expect(await second, isNull);
      expect(called, isFalse);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await first;
      await other.close();
    }
  });
  test('real SQLite and filesystem publish without prematurely completing job',
      () async {
    final store = DesktopPublicationStore(
        jobs: repositories.downloadJobs, clock: () => now);
    try {
      final receipt = await store.run(job, (workspace) async {
        await workspace.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3);
        return workspace.publish(job, publicationProof());
      });
      expect(await File(receipt.filePath).readAsString(), 'abc');
      expect(await repositories.downloadJobs.findByKey(job.key), job);
      expect(
          await repositories.downloadedAssets.findCandidates(job.key.identity,
              quality: 'high', libraryFolderId: folder),
          isEmpty);
      await repositories.downloadJobs.cancel(job, now: now);
      await expectLater(
          store.run(
              job,
              (workspace) =>
                  workspace.reconcile(job, receipt.intent.publicationId)),
          throwsA(isA<PublicationException>().having(
              (e) => e.reason, 'reason', PublicationFailure.ownershipLost)));
      expect(await File(receipt.filePath).readAsString(), 'abc');
    } finally {
      await store.close();
    }
  });
}
