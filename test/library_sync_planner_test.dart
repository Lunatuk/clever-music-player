import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/services/library_sync_planner.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const planner = LibrarySyncPlanner();
  group('pure library sync plan', () {
    test(
        'deduplicates exact identities while preserving source occurrence counts',
        () {
      final plan = planner.build(_input([
        _source(1, [_id('1'), _id('2'), _id('1')]),
        _source(2, [_id('2'), _id('1')])
      ]));
      expect(
          plan.items.map((item) => item.key.identity.externalId), ['1', '2']);
      expect(plan.sourceOccurrences, 5);
      expect(plan.items.first.memberships, [
        const LibrarySyncMembership(1, 2),
        const LibrarySyncMembership(2, 1)
      ]);
      expect(
          plan.items
              .every((item) => item.action == LibrarySyncAction.createJob),
          isTrue);
    });
    test('leading zeros, case and variants remain independent', () {
      final ids = [
        _id('0001'),
        _id('1'),
        _id('A'),
        _id('a'),
        _id('1', variant: 'live')
      ];
      final plan = planner.build(_input([_source(1, ids)]));
      expect(plan.items.map((item) => item.key.identity), ids);
    });
    test('unfetched collection blocks the entire plan including cancellations',
        () {
      final plan = planner.build(_input([
        _source(1, [_id('1')]),
        _source(2, null)
      ], jobs: [
        _job(id: 'obsolete')
      ]));
      expect(plan.blockers, [LibrarySyncBlocker.missingSnapshot]);
      expect(plan.blockedCollectionIds, [2]);
      expect(plan.items, isEmpty);
      expect(plan.obsoleteJobs, isEmpty);
    });
    test(
        'optional freshness cutoff rejects old content, accepts exact boundary',
        () {
      final source = _source(1, [_id('1')]);
      expect(
          planner
              .build(_input([source],
                  minimum: _time.add(const Duration(microseconds: 1))))
              .blockers,
          [LibrarySyncBlocker.staleSnapshot]);
      expect(planner.build(_input([source], minimum: _time)).isReady, isTrue);
      expect(planner.build(_input([source])).isReady, isTrue);
    });
    test('inactive accounts and disabled destinations never produce mutations',
        () {
      final inactive = planner.build(_input([_source(1, [])], active: false));
      final disabled = planner.build(_input([_source(1, [])], enabled: false));
      expect(inactive.blockers, [LibrarySyncBlocker.inactiveAccount]);
      expect(disabled.blockers, [LibrarySyncBlocker.disabledDestination]);
      expect(disabled.obsoleteJobs, isEmpty);
    });
    test('registered candidates require physical checks; actual quality wins',
        () {
      final higherRequest = _asset(requested: 'lossless');
      final plan = planner.build(_input([
        _source(1, [_id('1')])
      ], assets: [
        higherRequest
      ]));
      expect(plan.items.single.action, LibrarySyncAction.checkExisting);
      expect(plan.items.single.candidates, [higherRequest]);
      for (final asset in [
        _asset(actual: 'normal'),
        _asset(state: DownloadedAssetState.invalid)
      ]) {
        expect(
            planner
                .build(_input([
                  _source(1, [_id('1')])
                ], assets: [
                  asset
                ]))
                .items
                .single
                .action,
            LibrarySyncAction.createJob);
      }
    });
    test('ongoing work takes priority over a possibly old file candidate', () {
      for (final state in [
        DownloadJobState.queued,
        DownloadJobState.running,
        DownloadJobState.needsReconciliation,
        DownloadJobState.reconciling
      ]) {
        final plan = planner.build(_input([
          _source(1, [_id('1')])
        ], assets: [
          _asset()
        ], jobs: [
          _job(state: state)
        ]));
        expect(plan.items.single.action, LibrarySyncAction.joinJob);
      }
    });
    test('another session is never silently joined, rebound or cancelled', () {
      final foreign = _job(accountRevision: 99);
      final plan = planner.build(_input([
        _source(1, [_id('1')])
      ], jobs: [
        foreign
      ]));
      expect(plan.items.single.action, LibrarySyncAction.needsAction);
      expect(plan.items.single.reason, LibrarySyncItemReason.otherSession);
      expect(plan.obsoleteJobs, isEmpty);
    });
    test('terminal failures need explicit retry intent and retain their reason',
        () {
      for (final state in [
        DownloadJobState.failed,
        DownloadJobState.cancelled
      ]) {
        final snapshot = _input([
          _source(1, [_id('1')])
        ], jobs: [
          _job(state: state)
        ]);
        expect(planner.build(snapshot).items.single.action,
            LibrarySyncAction.needsAction);
        expect(
            planner
                .build(snapshot, retryTerminalJobs: true)
                .items
                .single
                .action,
            LibrarySyncAction.retryJob);
      }
    });
    test(
        'completed without proof needs repair, completed with candidates needs checking',
        () {
      final job = _job(state: DownloadJobState.completed);
      expect(
          planner
              .build(_input([
                _source(1, [_id('1')])
              ], jobs: [
                job
              ]))
              .items
              .single
              .action,
          LibrarySyncAction.repairCompleted);
      expect(
          planner
              .build(_input([
                _source(1, [_id('1')])
              ], jobs: [
                job
              ], assets: [
                _asset()
              ]))
              .items
              .single
              .action,
          LibrarySyncAction.checkExisting);
    });
    test(
        'quality changes cancel only obsolete current-session nonterminal work',
        () {
      final old = _job(quality: 'normal');
      final history = _job(id: 'history', state: DownloadJobState.failed);
      final otherSession = _job(id: 'other', accountRevision: 99);
      final plan = planner.build(_input([
        _source(1, [_id('1')])
      ], jobs: [
        old,
        history,
        otherSession
      ]));
      expect(plan.items.single.action, LibrarySyncAction.createJob);
      expect(plan.obsoleteJobs, [old]);
    });
    test(
        'explicit empty selection cancels pending work but never terminal history',
        () {
      final pending = _job();
      final plan = planner.build(_input([], jobs: [
        pending,
        _job(id: 'done', state: DownloadJobState.completed)
      ]));
      expect(plan.isReady, isTrue);
      expect(plan.items, isEmpty);
      expect(plan.obsoleteJobs, [pending]);
    });
    test('input and output lists are immutable defensive copies', () {
      final ids = [_id('1')];
      final sources = [_source(1, ids)];
      final snapshot = _input(sources);
      ids.clear();
      sources.clear();
      final plan = planner.build(snapshot);
      expect(plan.items, hasLength(1));
      expect(() => snapshot.collections.clear(), throwsUnsupportedError);
      expect(() => snapshot.collections.single.items!.clear(),
          throwsUnsupportedError);
      expect(() => plan.items.clear(), throwsUnsupportedError);
      expect(
          () => plan.items.single.memberships.clear(), throwsUnsupportedError);
      expect(plan, planner.build(snapshot));
      expect(plan.hashCode, planner.build(snapshot).hashCode);
    });
    test('collection and combined position bounds fail without truncating', () {
      expect(() => _input(List.generate(257, (i) => _source(i + 1, []))),
          throwsArgumentError);
      final many = List.filled(60000, _id('1'));
      expect(() => _input([_source(1, many), _source(2, many)]),
          throwsArgumentError);
      Iterable<DownloadJob> infinite() sync* {
        while (true) {
          yield _job();
        }
      }

      expect(
          () => LibrarySyncSnapshot(
              account: _account(),
              destination: _destination(),
              quality: 'high',
              collections: [],
              assets: [],
              jobs: infinite()),
          throwsArgumentError);
    });
    test('inconsistent collection/account and duplicate job keys are rejected',
        () {
      expect(
          () => _input([
                _source(1, [_id('1', provider: 'other')])
              ]),
          throwsArgumentError);
      expect(() => _input([], jobs: [_job(), _job()]), throwsArgumentError);
      expect(
          () => LibrarySyncCollection(
              collection: _source(1, []).collection, items: [_id('1')]),
          throwsArgumentError);
    });
    test('ten thousand unique tracks retain order and produce one action each',
        () {
      final ids = List.generate(10000, (i) => _id('$i'));
      final plan = planner.build(_input([_source(1, ids)]));
      expect(plan.items, hasLength(10000));
      expect(plan.items.last.key.identity, ids.last);
      expect(plan.sourceOccurrences, 10000);
    });
  });
  group('atomic sync planning with SQLite', () {
    late _Fixture f;
    setUp(() async {
      f = _Fixture();
      await f.initialize();
    });
    tearDown(() async {
      expect(await f.database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty);
      await f.database.close();
    });
    test('all selected sources share one job per exact track identity',
        () async {
      await f.store([_id('1'), _id('2'), _id('1')]);
      await f.store([_id('2'), _id('3')], key: _playlist());
      final plan = await f.plan();
      expect(plan.sourceOccurrences, 5);
      final result = await f.sync.apply(plan, now: f.now);
      expect(result.status, LibrarySyncApplyStatus.applied);
      expect(result.scheduledJobs, hasLength(3));
      expect(await f.jobs.listJobs(), hasLength(3));
      expect(await f.jobs.listAttempts(result.scheduledJobs.first.id), isEmpty);
    });
    test(
        'repeated fresh plans join jobs without resetting their attempt budgets',
        () async {
      await f.store([_id('1')]);
      final first = await f.plan();
      await f.sync.apply(first, now: f.now);
      expect((await f.sync.apply(first, now: f.now)).status,
          LibrarySyncApplyStatus.stale);
      final job = (await f.jobs.claimNext(f.account, now: f.now))!;
      final next = await f.plan();
      expect(next.items.single.action, LibrarySyncAction.joinJob);
      expect((await f.sync.apply(next, now: f.now)).scheduledJobs, isEmpty);
      expect(await f.jobs.findByKey(job.key), job);
    });
    test(
        'registered candidates are not treated as physically verified or queued',
        () async {
      await f.store([_id('1')]);
      final asset = await f.addAsset(_id('1'));
      final plan = await f.plan();
      expect(plan.items.single.action, LibrarySyncAction.checkExisting);
      expect((await f.sync.apply(plan, now: f.now)).scheduledJobs, isEmpty);
      expect(
          await f.repositories.downloadedAssets
              .findForTrack(asset.publication.trackId),
          asset);
      expect(await f.jobs.listJobs(), isEmpty);
    });
    test(
        'folder candidate lookup matches exact lookups and excludes invalid file properties',
        () async {
      await f.store([_id('1'), _id('2'), _id('3')]);
      final good = await f.addAsset(_id('1'));
      final changed = await f.addAsset(_id('2'));
      await f.database.customStatement(
          'UPDATE tracks SET file_size_bytes = 999 WHERE id = ?',
          [changed.publication.trackId]);
      await f.addAsset(_id('3'), actual: 'normal');
      final bulk = await f.repositories.downloadedAssets
          .findCandidatesForFolder(
              quality: 'high', libraryFolderId: f.folderId);
      final exact = await f.repositories.downloadedAssets.findCandidates(
          _id('1'),
          quality: 'high',
          libraryFolderId: f.folderId);
      expect(bulk, exact);
      expect(bulk, [good]);
      expect((await f.plan()).items.map((item) => item.action), [
        LibrarySyncAction.checkExisting,
        LibrarySyncAction.createJob,
        LibrarySyncAction.createJob
      ]);
    });
    test(
        'a valid copy in a different destination never satisfies this destination',
        () async {
      await f.store([_id('1')]);
      final other = await f.addFolder('/other');
      await f.addAsset(_id('1'), folderId: other);
      expect((await f.plan()).items.single.action, LibrarySyncAction.createJob);
    });
    test('missing selected snapshot blocks all queue changes', () async {
      await f.store([_id('1')]);
      await f.repositories.remoteLibrary
          .configureCollection(f.account, _playlist(), isSelected: true);
      final old = (await f.jobs
              .enqueue(f.account, [f.key(_id('obsolete'))], now: f.now))
          .single;
      final plan = await f.plan();
      expect(plan.blockers, [LibrarySyncBlocker.missingSnapshot]);
      expect((await f.sync.apply(plan, now: f.now)).status,
          LibrarySyncApplyStatus.blocked);
      expect(await f.jobs.listJobs(), [old]);
    });
    test(
        'freshness cutoff blocks cached lists until a complete refresh finishes',
        () async {
      await f.store([_id('1')]);
      final cutoff = f.tick();
      expect((await f.plan(minimum: cutoff)).blockers,
          [LibrarySyncBlocker.staleSnapshot]);
      await f.store([_id('1')]);
      expect((await f.plan(minimum: cutoff)).isReady, isTrue);
    });
    test(
        'changing selected lists invalidates old plans before any job is added',
        () async {
      await f.store([_id('1')]);
      final plan = await f.plan();
      await f.selectLiked(false);
      expect((await f.sync.apply(plan, now: f.now)).status,
          LibrarySyncApplyStatus.stale);
      expect(await f.jobs.listJobs(), isEmpty);
    });
    test(
        'beginning a newer refresh invalidates the earlier collection snapshot',
        () async {
      await f.store([_id('1')]);
      final plan = await f.plan();
      final source = (await f.repositories.remoteLibrary
              .listCollections(f.account.identity))
          .single;
      await f.repositories.remoteLibrary.beginRefresh(f.account, source);
      expect((await f.sync.apply(plan, now: f.now)).status,
          LibrarySyncApplyStatus.stale);
      expect(await f.jobs.listJobs(), isEmpty);
    });
    test('account reactivation invalidates an old plan', () async {
      await f.store([_id('1')]);
      final plan = await f.plan();
      await f.repositories.remoteLibrary.activateAccount(f.account.identity);
      expect((await f.sync.apply(plan, now: f.now)).status,
          LibrarySyncApplyStatus.stale);
      expect(await f.jobs.listJobs(), isEmpty);
    });
    test(
        'folder disable and path change invalidate plans without partial writes',
        () async {
      await f.store([_id('1')]);
      final plan = await f.plan();
      final folder =
          (await f.repositories.libraryFolders.findFolderByPath('/music'))!;
      await f.repositories.libraryFolders
          .upsertFolder(folder.copyWith(path: '/moved'));
      expect((await f.sync.apply(plan, now: f.now)).status,
          LibrarySyncApplyStatus.stale);
      final moved = await f.plan();
      await f.repositories.libraryFolders
          .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now);
      expect((await f.sync.apply(moved, now: f.now)).status,
          LibrarySyncApplyStatus.stale);
      final blocked = await f.plan();
      expect(blocked.blockers, [LibrarySyncBlocker.disabledDestination]);
      expect((await f.sync.apply(blocked, now: f.now)).status,
          LibrarySyncApplyStatus.blocked);
      expect(await f.jobs.listJobs(), isEmpty);
    });
    test('folder scan timestamps and local feedback do not invalidate a plan',
        () async {
      await f.store([_id('1')]);
      final asset = await f.addAsset(_id('1'));
      final plan = await f.plan();
      final folder =
          (await f.repositories.libraryFolders.findFolderByPath('/music'))!;
      await f.repositories.libraryFolders.upsertFolder(
          folder.copyWith(lastScannedAt: f.tick(), updatedAt: f.now));
      await f.repositories.trackUserState.toggleFeedback(
          asset.publication.trackId, TrackFeedback.like,
          updatedAt: f.now);
      expect((await f.sync.apply(plan, now: f.now)).status,
          LibrarySyncApplyStatus.applied);
      expect(
          (await f.repositories.trackUserState
                  .findByTrackId(asset.publication.trackId))!
              .isFavorite,
          isTrue);
    });
    test('new candidate or changed candidate state requires replanning',
        () async {
      await f.store([_id('1')]);
      final beforeAsset = await f.plan();
      final asset = await f.addAsset(_id('1'));
      expect((await f.sync.apply(beforeAsset, now: f.now)).status,
          LibrarySyncApplyStatus.stale);
      final withAsset = await f.plan();
      await f.repositories.downloadedAssets
          .invalidate(asset, DownloadedAssetState.missing);
      expect((await f.sync.apply(withAsset, now: f.now)).status,
          LibrarySyncApplyStatus.stale);
      expect((await f.plan()).items.single.action, LibrarySyncAction.createJob);
      expect(await f.jobs.listJobs(), isEmpty);
    });
    test(
        'a concurrent job claim invalidates a pending plan without creating other work',
        () async {
      await f.store([_id('1'), _id('2')]);
      await f.jobs.enqueue(f.account, [f.key(_id('1'))], now: f.now);
      final plan = await f.plan();
      await f.jobs.claimNext(f.account, now: f.now);
      expect((await f.sync.apply(plan, now: f.now)).status,
          LibrarySyncApplyStatus.stale);
      expect(await f.jobs.listJobs(), hasLength(1));
    });
    test('deselected playlist cancels only unshared pending tracks', () async {
      await f.store([_id('shared')]);
      await f.store([_id('shared'), _id('unshared')], key: _playlist());
      await f.sync.apply(await f.plan(), now: f.now);
      await f.repositories.remoteLibrary
          .configureCollection(f.account, _playlist(), isSelected: false);
      final plan = await f.plan();
      expect(plan.items.single.key.identity, _id('shared'));
      expect(plan.obsoleteJobs.single.key.identity, _id('unshared'));
      final result = await f.sync.apply(plan, now: f.now);
      expect(result.cancelledJobs.single.state, DownloadJobState.cancelled);
      expect((await f.jobs.findByKey(f.key(_id('shared'))))!.state,
          DownloadJobState.queued);
    });
    test(
        'zero selected collections revoke pending work without touching local data',
        () async {
      await f.store([_id('1')]);
      final asset = await f.addAsset(_id('1'));
      await f.repositories.trackUserState.toggleFeedback(
          asset.publication.trackId, TrackFeedback.like,
          updatedAt: f.now);
      await f.jobs.enqueue(f.account, [f.key(_id('1'))], now: f.now);
      final running = (await f.jobs.claimNext(f.account, now: f.now))!;
      await f.selectLiked(false);
      final before = await f.localRows();
      final result = await f.sync.apply(await f.plan(), now: f.now);
      expect(result.cancelledJobs.single.id, running.id);
      expect((await f.jobs.listAttempts(running.id)).single.outcome,
          DownloadAttemptOutcome.cancelled);
      expect(await f.localRows(), before);
    });
    test(
        'quality change cancels old quality and schedules the requested quality',
        () async {
      await f.store([_id('1')]);
      final old = (await f.jobs.enqueue(
              f.account, [f.key(_id('1'), quality: 'normal')],
              now: f.now))
          .single;
      await f.jobs.claimNext(f.account, now: f.now);
      final result = await f.sync.apply(await f.plan(), now: f.now);
      expect(result.cancelledJobs.single.id, old.id);
      expect(result.scheduledJobs.single.key.quality, 'high');
      expect(
          (await f.jobs.claimNext(f.account, now: f.now))!.key.quality, 'high');
    });
    test('other destinations and providers remain outside cancellation scope',
        () async {
      await f.store([]);
      final folder = await f.addFolder('/other');
      final elsewhere = (await f.jobs.enqueue(
              f.account,
              [
                DownloadJobKey(
                    libraryFolderId: folder,
                    identity: _id('1'),
                    quality: 'high')
              ],
              now: f.now))
          .single;
      final otherAccount = await f.repositories.remoteLibrary.activateAccount(
          RemoteAccountIdentity(provider: 'other', accountId: 'B'));
      final other = (await f.jobs.enqueue(
              otherAccount,
              [
                DownloadJobKey(
                    libraryFolderId: f.folderId,
                    identity: _id('1', provider: 'other'),
                    quality: 'high')
              ],
              now: f.now))
          .single;
      final result = await f.sync.apply(await f.plan(), now: f.now);
      expect(result.cancelledJobs, isEmpty);
      expect(await f.jobs.findByKey(elsewhere.key), elsewhere);
      expect(await f.jobs.findByKey(other.key), other);
    });
    test('default updates do not replenish failed budgets; explicit retry does',
        () async {
      await f.store([_id('1')]);
      await f.jobs
          .enqueue(f.account, [f.key(_id('1'))], now: f.now, maxAttempts: 1);
      final running = (await f.jobs.claimNext(f.account, now: f.now))!;
      final failed = (await f.jobs
          .fail(running, DownloadFailure.authorization, now: f.now))!;
      final ordinary = await f.plan();
      expect(ordinary.items.single.action, LibrarySyncAction.needsAction);
      expect((await f.sync.apply(ordinary, now: f.now)).scheduledJobs, isEmpty);
      expect(await f.jobs.findByKey(failed.key), failed);
      final retried = await f.sync.apply(await f.plan(retry: true), now: f.now);
      expect(retried.scheduledJobs.single.remainingAttempts, 1);
      expect(retried.scheduledJobs.single.state,
          DownloadJobState.needsReconciliation);
    });
    test(
        'completed resource losing its proof schedules reconciliation, not blind download',
        () async {
      await f.store([_id('1')]);
      await f.jobs.enqueue(f.account, [f.key(_id('1'))], now: f.now);
      var running = (await f.jobs.claimNext(f.account, now: f.now))!;
      for (final stage in DownloadJobStage.values.skip(1)) {
        running = (await f.jobs.advance(running, stage, now: f.tick()))!;
      }
      final asset = await f.addAsset(_id('1'));
      final completed = (await f.jobs.complete(running, asset, now: f.now))!;
      await f.repositories.downloadedAssets
          .invalidate(asset, DownloadedAssetState.missing);
      final plan = await f.plan();
      expect(plan.items.single.action, LibrarySyncAction.repairCompleted);
      final result = await f.sync.apply(plan, now: f.now);
      expect(result.scheduledJobs.single.id, completed.id);
      expect(result.scheduledJobs.single.stage, DownloadJobStage.importing);
      expect((await f.jobs.claimNext(f.account, now: f.now))!.state,
          DownloadJobState.reconciling);
    });
    test(
        'large enqueue failure rolls back earlier batches and obsolete attempt cancellation',
        () async {
      final old = (await f.jobs
              .enqueue(f.account, [f.key(_id('obsolete'))], now: f.now))
          .single;
      final running = (await f.jobs.claimNext(f.account, now: f.now))!;
      await f.store(List.generate(150, (i) => _id('$i')));
      final plan = await f.plan();
      await f.database.customStatement(
          "CREATE TRIGGER fail_plan BEFORE INSERT ON download_jobs WHEN NEW.external_id = '129' BEGIN SELECT RAISE(ABORT, 'simulated'); END");
      await expectLater(f.sync.apply(plan, now: f.now), throwsA(anything));
      expect(await f.jobs.listJobs(), [running]);
      expect((await f.jobs.listAttempts(old.id)).single.outcome,
          DownloadAttemptOutcome.running);
      await f.database.customStatement('DROP TRIGGER fail_plan');
      final result = await f.sync.apply(plan, now: f.now);
      expect(result.scheduledJobs, hasLength(150));
      expect(result.cancelledJobs.single.id, old.id);
      expect(
          await f.jobs.listForDestination(f.folderId, provider: 'yandex_music'),
          hasLength(151));
    });
    test('a late CAS refusal rolls back jobs created earlier in the same apply',
        () async {
      await f.jobs.enqueue(f.account, [f.key(_id('1'))], now: f.now);
      final running = (await f.jobs.claimNext(f.account, now: f.now))!;
      final failed = (await f.jobs
          .fail(running, DownloadFailure.authorization, now: f.now))!;
      await f.database.customStatement(
          'UPDATE download_jobs SET updated_at_micros = ? WHERE id = ?', [
        f.now.add(const Duration(hours: 1)).microsecondsSinceEpoch,
        failed.id
      ]);
      await f.store([_id('1'), _id('new')]);
      final plan = await f.plan(retry: true);
      expect((await f.sync.apply(plan, now: f.now)).status,
          LibrarySyncApplyStatus.stale);
      expect(await f.jobs.findByKey(f.key(_id('new'))), isNull);
      expect(
          (await f.jobs.findByKey(failed.key))!.state, DownloadJobState.failed);
    });
    test(
        'cancelled work from a previous account is rebound only on explicit retry',
        () async {
      await f.store([_id('shared'), _id('old-only')]);
      await f.sync.apply(await f.plan(), now: f.now);
      f.account = await f.repositories.remoteLibrary.activateAccount(
          RemoteAccountIdentity(provider: 'yandex_music', accountId: 'B'));
      await f.store([_id('shared')]);
      final ordinary = await f.plan();
      expect(ordinary.items, hasLength(1));
      expect(ordinary.items.single.action, LibrarySyncAction.needsAction);
      expect((await f.sync.apply(ordinary, now: f.now)).scheduledJobs, isEmpty);
      final retried = await f.sync.apply(await f.plan(retry: true), now: f.now);
      expect(retried.scheduledJobs.single.accountId, f.account.id);
      expect(retried.scheduledJobs.single.key.identity, _id('shared'));
      expect((await f.jobs.findByKey(f.key(_id('old-only'))))!.state,
          DownloadJobState.cancelled);
    });
    test('tampered commands cannot bypass canonical planning', () async {
      await f.store([_id('1')]);
      final plan = await f.plan();
      final tampered = LibrarySyncPlan(
          snapshot: plan.snapshot,
          retryTerminalJobs: false,
          blockers: [],
          blockedCollectionIds: [],
          items: [],
          obsoleteJobs: []);
      expect((await f.sync.apply(tampered, now: f.now)).status,
          LibrarySyncApplyStatus.stale);
      expect(await f.jobs.listJobs(), isEmpty);
    });
    test('invalid capture requests fail explicitly without mutating data',
        () async {
      expect(
          () => f.sync.capture(f.account, libraryFolderId: 0, quality: 'high'),
          throwsArgumentError);
      expect(
          () => f.sync
              .capture(f.account, libraryFolderId: f.folderId, quality: ''),
          throwsFormatException);
      expect(
          await f.sync
              .capture(f.account, libraryFolderId: 999, quality: 'high'),
          isNull);
      await expectLater(f.jobs.listForDestination(f.folderId, provider: 'Bad'),
          throwsArgumentError);
      expect(await f.jobs.listJobs(), isEmpty);
    });
  });
  test('file reopen preserves plan inputs without a schema upgrade', () async {
    final directory = await Directory.systemTemp.createTemp('cmp_sync_plan_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'library.sqlite'));
    final first = _Fixture(AppDatabase(NativeDatabase(file)));
    await first.initialize();
    await first.store([_id('1'), _id('1')]);
    final plan = await first.plan();
    final now = first.now;
    await first.database.close();
    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    expect(
        await repositories.librarySync.capture(plan.snapshot.account,
            libraryFolderId: plan.snapshot.destination.id, quality: 'high'),
        plan.snapshot);
    expect((await repositories.librarySync.apply(plan, now: now)).scheduledJobs,
        hasLength(1));
    expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        13);
  });
}

final _time =
    DateTime.fromMicrosecondsSinceEpoch(1893456000123456, isUtc: true);
ExternalTrackIdentity _id(String id,
        {String variant = '', String provider = 'yandex_music'}) =>
    ExternalTrackIdentity(
        provider: provider, externalId: id, variantKey: variant);
RemoteLibraryAccount _account({bool active = true}) => RemoteLibraryAccount(
    id: 1,
    identity: RemoteAccountIdentity(provider: 'yandex_music', accountId: 'A'),
    displayName: 'A',
    isActive: active,
    revision: 1);
LibrarySyncDestination _destination({bool enabled = true}) =>
    LibrarySyncDestination(id: 1, path: '/music', isEnabled: enabled);
RemoteCollectionKey _playlist() => RemoteCollectionKey(
    kind: RemoteCollectionKind.playlist, externalId: '0001', ownerId: 'owner');
LibrarySyncCollection _source(int id, List<ExternalTrackIdentity>? items) =>
    LibrarySyncCollection(
        collection: RemoteLibraryCollection(
            id: id,
            account: _account().identity,
            key: id == 1
                ? RemoteCollectionKey(kind: RemoteCollectionKind.liked)
                : RemoteCollectionKey(
                    kind: RemoteCollectionKind.playlist, externalId: '$id'),
            title: 'Same title',
            isSelected: true,
            revision: 1,
            itemCount: items?.length ?? 0,
            remoteRevision: items == null ? null : 'rev',
            completedAt: items == null ? null : _time),
        items: items);
LibrarySyncSnapshot _input(List<LibrarySyncCollection> sources,
        {List<DownloadedAsset> assets = const [],
        List<DownloadJob> jobs = const [],
        bool active = true,
        bool enabled = true,
        DateTime? minimum}) =>
    LibrarySyncSnapshot(
        account: _account(active: active),
        destination: _destination(enabled: enabled),
        quality: 'high',
        collections: sources,
        assets: assets,
        jobs: jobs,
        minimumCompletedAt: minimum);
DownloadJob _job(
        {String id = '1',
        String quality = 'high',
        DownloadJobState state = DownloadJobState.queued,
        int accountRevision = 1}) =>
    DownloadJob(
        id: 1,
        key: DownloadJobKey(
            libraryFolderId: 1, identity: _id(id), quality: quality),
        accountId: 1,
        accountRevision: accountRevision,
        state: state,
        stage: DownloadJobStage.download,
        revision: 1,
        attemptCount: 0,
        maxAttempts: 3,
        remainingAttempts: 3,
        createdAt: _time,
        updatedAt: _time,
        attemptToken: state == DownloadJobState.running ||
                state == DownloadJobState.reconciling
            ? 'token'
            : null,
        leaseUntil: state == DownloadJobState.running ||
                state == DownloadJobState.reconciling
            ? _time.add(const Duration(seconds: 30))
            : null,
        retryAt: null,
        failure: null,
        completedTrackId: null);
DownloadedAsset _asset(
        {String actual = 'high',
        String requested = 'high',
        DownloadedAssetState state = DownloadedAssetState.verified}) =>
    DownloadedAsset(
        publication: DownloadedAssetPublication(
            trackId: 1,
            identity: _id('1'),
            source: FileAudioSource('/music/1.mp3'),
            publicationId: 'asset-1',
            requestedQuality: requested),
        verification: DownloadedAssetVerification(
            actualQuality: actual,
            container: 'mp3',
            codec: 'mp3',
            fileSizeBytes: 123,
            duration: const Duration(seconds: 60),
            contentHash: 'a' * 64,
            checkedAt: _time),
        state: state,
        revision: 1);

final class _Fixture {
  _Fixture([AppDatabase? database])
      : database = database ??
            AppDatabase(NativeDatabase.memory(
                setup: (raw) => raw.execute('PRAGMA foreign_keys = ON')));
  final AppDatabase database;
  late final repositories = DriftRepositories(database);
  late final sync = repositories.librarySync;
  late final jobs = repositories.downloadJobs;
  late RemoteLibraryAccount account;
  late int folderId;
  var now = _time;
  var serial = 0;
  DateTime tick() => now = now.add(const Duration(seconds: 1));
  Future<void> initialize() async {
    account =
        await repositories.remoteLibrary.activateAccount(_account().identity);
    folderId = await addFolder('/music');
  }

  Future<int> addFolder(String path) => repositories.libraryFolders
      .upsertFolder(LibraryFolder(path: path, createdAt: now, updatedAt: now));
  DownloadJobKey key(ExternalTrackIdentity identity,
          {String quality = 'high'}) =>
      DownloadJobKey(
          libraryFolderId: folderId, identity: identity, quality: quality);
  Future<void> store(List<ExternalTrackIdentity> items,
      {RemoteCollectionKey? key}) async {
    final source = (await repositories.remoteLibrary.configureCollection(
        account, key ?? RemoteCollectionKey(kind: RemoteCollectionKind.liked),
        title: 'Source', isSelected: true))!;
    final ticket =
        (await repositories.remoteLibrary.beginRefresh(account, source))!;
    expect(
        await repositories.remoteLibrary.commitSnapshot(
            ticket,
            RemoteCollectionSnapshot(
                items: items,
                isComplete: true,
                completedAt: now,
                expectedItemCount: items.length,
                revisionAtStart: 'rev',
                revisionAtEnd: 'rev')),
        isTrue);
  }

  Future<void> selectLiked(bool selected) => repositories.remoteLibrary
      .configureCollection(
          account, RemoteCollectionKey(kind: RemoteCollectionKind.liked),
          title: 'Source', isSelected: selected)
      .then((_) {});
  Future<LibrarySyncPlan> plan({DateTime? minimum, bool retry = false}) async =>
      const LibrarySyncPlanner().build(
          (await sync.capture(account,
              libraryFolderId: folderId,
              quality: 'high',
              minimumCompletedAt: minimum))!,
          retryTerminalJobs: retry);
  Future<DownloadedAsset> addAsset(ExternalTrackIdentity identity,
      {int? folderId, String actual = 'high'}) async {
    serial++;
    final path = '/music/asset-$serial.mp3';
    final trackId = await repositories.tracks.upsertTrack(Track(
        libraryFolderId: folderId ?? this.folderId,
        filePath: path,
        title: 'Manual title',
        metadataSource: MetadataSource.manual,
        fileSizeBytes: 123,
        contentHash: 'a' * 64,
        addedAt: now,
        updatedAt: now));
    await repositories.externalTracks.linkAll([
      ExternalTrackRef(
          trackId: trackId,
          identity: identity,
          origin: ExternalTrackRefOrigin.providerResponse,
          linkedAt: now)
    ]);
    return repositories.downloadedAssets.registerVerified(
        DownloadedAssetPublication(
            trackId: trackId,
            identity: identity,
            source: FileAudioSource(path),
            publicationId: 'asset-$serial',
            requestedQuality: 'high'),
        DownloadedAssetVerification(
            actualQuality: actual,
            container: 'mp3',
            codec: 'mp3',
            fileSizeBytes: 123,
            duration: const Duration(seconds: 60),
            contentHash: 'a' * 64,
            checkedAt: now));
  }

  Future<Map<String, List<Map<String, Object?>>>> localRows() async => {
        for (final table in [
          'tracks',
          'track_user_state',
          'external_track_refs',
          'downloaded_assets',
          'remote_collections',
          'remote_collection_items'
        ])
          table: [
            for (final row
                in await database.customSelect('SELECT * FROM $table').get())
              row.data
          ]
      };
}
