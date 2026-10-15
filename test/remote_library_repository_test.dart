import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('remote library contract', () {
    test('IDs retain leading zeros, case and account/provider scope', () {
      expect(_identity('000A'), isNot(_identity('A')));
      expect(_identity('A'), isNot(_identity('a')));
      expect(_identity('A'), isNot(_identity('A', provider: 'other')));
      for (final value in ['', ' ', 'a\n', 'a' * 513]) {
        expect(() => _identity(value), throwsFormatException);
      }
      for (final value in ['', 'Yandex', 'provider/', 'other\n']) {
        expect(() => _identity('a', provider: value), throwsFormatException);
      }
    });
    test('playlist owner distinguishes keys; liked has no external ID', () {
      expect(_playlist(owner: 'a'), isNot(_playlist(owner: 'b')));
      expect(() => RemoteCollectionKey(kind: RemoteCollectionKind.playlist),
          throwsFormatException);
      expect(
          () => RemoteCollectionKey(
              kind: RemoteCollectionKind.liked, externalId: 'id'),
          throwsFormatException);
      expect(
          () => RemoteCollectionKey(
              kind: RemoteCollectionKind.liked, ownerId: 'id'),
          throwsFormatException);
      expect(() => _playlist(owner: 'owner\n'), throwsFormatException);
    });
    test('snapshot copies ordered items and preserves microseconds', () {
      final items = [_track('1'), _track('2'), _track('1')];
      final snapshot = _snapshot(items);
      items.clear();
      expect(snapshot.items.map((item) => item.externalId), ['1', '2', '1']);
      expect(() => snapshot.items.clear(), throwsUnsupportedError);
      expect(snapshot.completedAt.isUtc, isTrue);
      expect(snapshot.completedAt.microsecondsSinceEpoch,
          _time.microsecondsSinceEpoch);
    });
    test('incomplete counts or changing/one-sided revisions cannot commit', () {
      expect(_snapshot([], complete: false).canCommit, isFalse);
      expect(_snapshot([_track('1')], expectedCount: 2).canCommit, isFalse);
      expect(_snapshot([], start: 'a', end: 'b').canCommit, isFalse);
      expect(_snapshot([], start: null, end: 'b').canCommit, isFalse);
      expect(_snapshot([], start: null, end: null).canCommit, isTrue);
      expect(() => _snapshot([], expectedCount: -1), throwsArgumentError);
      expect(() => _snapshot([], start: ''), throwsFormatException);
    });
    test('oversized and unbounded input stops instead of growing indefinitely',
        () {
      Iterable<ExternalTrackIdentity> input() sync* {
        while (true) {
          yield _track('1');
        }
      }

      expect(() => _snapshot(input()), throwsArgumentError);
    });
  });

  group('remote library persistence', () {
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
    test('new collections have no manufactured successful content', () async {
      expect(await f.repo.readContent(f.account.identity, f.collection.key),
          isNull);
      expect(f.collection.itemCount, 0);
      expect(f.collection.completedAt, isNull);
      expect(await f.repo.findAccount(_identity('unknown')), isNull);
      expect(await f.repo.listCollections(_identity('unknown')), isEmpty);
    });
    test(
        'one active account per provider, historical selections remain separate',
        () async {
      final next = await f.repo.activateAccount(_identity('B'));
      expect((await f.repo.findAccount(f.account.identity))!.isActive, isFalse);
      expect(next.isActive, isTrue);
      expect(await f.repo.listCollections(next.identity), isEmpty);
      expect(await f.repo.listCollections(f.account.identity), hasLength(1));
      expect(
          await f.repo
              .configureCollection(f.account, _playlist(), isSelected: true),
          isNull);
      final accounts = await f.repo.listAccounts();
      expect(accounts.where((account) => account.isActive), hasLength(1));
      expect(() => accounts.clear(), throwsUnsupportedError);
    });
    test('other providers can be active independently', () async {
      await f.repo.activateAccount(_identity('B', provider: 'other'));
      expect((await f.repo.listAccounts()).where((account) => account.isActive),
          hasLength(2));
    });
    test('invalid display names cannot partially change account or collection',
        () async {
      for (final text in ['', 'bad\nname', 'a' * 513]) {
        expect(() => f.repo.activateAccount(_identity('B'), displayName: text),
            throwsFormatException);
        expect(
            () => f.repo.configureCollection(f.account, f.collection.key,
                title: text, isSelected: false),
            throwsFormatException);
      }
      expect(await f.repo.findAccount(f.account.identity), f.account);
      expect((await f.repo.listCollections(f.account.identity)).single,
          f.collection);
    });
    test(
        'same playlist under different accounts has isolated successful content',
        () async {
      await f.save([_track('A-song')]);
      final other = await f.repo.activateAccount(_identity('B'));
      final otherCollection = (await f.repo
          .configureCollection(other, f.collection.key, isSelected: true))!;
      final ticket = (await f.repo.beginRefresh(other, otherCollection))!;
      expect(await f.repo.commitSnapshot(ticket, _snapshot([_track('B-song')])),
          isTrue);
      expect((await f.content())!.items, [_track('A-song')]);
      expect(
          (await f.repo.readContent(other.identity, otherCollection.key))!
              .items,
          [_track('B-song')]);
    });
    test('renaming keeps saved membership and invalidates an in-flight request',
        () async {
      await f.save([_track('old')]);
      final ticket = (await f.begin())!;
      final renamed = (await f.repo.configureCollection(
          f.account, f.collection.key,
          title: 'Renamed', isSelected: true))!;
      expect(renamed.id, f.collection.id);
      expect((await f.content())!.items, [_track('old')]);
      expect(await f.repo.commitSnapshot(ticket, _snapshot([_track('stale')])),
          isFalse);
    });
    test(
        'new refresh of identical content replaces rather than appends membership',
        () async {
      final items = [_track('1'), _track('2'), _track('1')];
      await f.save(items);
      await f.save(items);
      expect((await f.content())!.items, items);
      expect(await f.database.select(f.database.remoteCollectionItems).get(),
          hasLength(3));
    });
    test('reactivation invalidates previous account work even for same ID',
        () async {
      final ticket = (await f.begin())!;
      final next = await f.repo
          .activateAccount(f.account.identity, displayName: 'Renamed');
      expect(next.id, f.account.id);
      expect(next.revision, f.account.revision + 1);
      expect(await f.repo.disconnectAccount(f.account), isFalse);
      expect(await f.repo.commitSnapshot(ticket, _snapshot([_track('1')])),
          isFalse);
    });
    test(
        'disconnect invalidates pending work but keeps last successful content',
        () async {
      await f.save([_track('old')]);
      final ticket = (await f.begin())!;
      expect(await f.repo.disconnectAccount(f.account), isTrue);
      expect(await f.repo.disconnectAccount(f.account), isFalse);
      expect(await f.repo.commitSnapshot(ticket, _snapshot([_track('new')])),
          isFalse);
      expect((await f.content())!.items, [_track('old')]);
      expect(await f.repo.beginRefresh(f.account, ticket.collection), isNull);
    });
    test('switch away and back never accepts a previous session response',
        () async {
      final ticket = (await f.begin())!;
      await f.repo.activateAccount(_identity('B'));
      f.account = await f.repo.activateAccount(f.account.identity);
      expect(await f.repo.commitSnapshot(ticket, _snapshot([_track('new')])),
          isFalse);
      expect(await f.begin(), isNotNull);
    });
    test('configuration is idempotent and titles do not define identity',
        () async {
      final same = await f.repo.configureCollection(f.account, f.collection.key,
          title: 'Liked', isSelected: true);
      expect(same, f.collection);
      final renamed = (await f.repo.configureCollection(
          f.account, f.collection.key,
          title: 'New name', isSelected: true))!;
      expect(renamed.id, f.collection.id);
      expect(renamed.revision, f.collection.revision + 1);
      expect(await f.repo.listCollections(f.account.identity), hasLength(1));
    });
    test('same playlist IDs under different owners remain distinct', () async {
      final first = await f.repo.configureCollection(
          f.account, _playlist(owner: 'first'),
          title: 'Same', isSelected: true);
      final second = await f.repo.configureCollection(
          f.account, _playlist(owner: 'second'),
          title: 'Same', isSelected: true);
      expect(first!.id, isNot(second!.id));
      expect(await f.repo.listCollections(f.account.identity), hasLength(3));
    });
    test('selected filter and deselection preserve saved content', () async {
      await f.save([_track('1')]);
      final ticket = (await f.begin())!;
      await f.configure(false);
      expect(
          await f.repo.listCollections(f.account.identity, selectedOnly: true),
          isEmpty);
      expect((await f.content())!.items, [_track('1')]);
      expect(await f.repo.commitSnapshot(ticket, _snapshot([])), isFalse);
      expect(await f.begin(), isNull);
      await f.configure(true);
      expect(await f.repo.commitSnapshot(ticket, _snapshot([])), isFalse);
    });
    test('begin requires current collection and matching account snapshots',
        () async {
      final other =
          await f.repo.activateAccount(_identity('B', provider: 'other'));
      expect(
          () => f.repo.beginRefresh(other, f.collection), throwsArgumentError);
      final old = f.collection;
      await f.configure(false);
      expect(await f.repo.beginRefresh(f.account, old), isNull);
    });
    test('new refresh invalidates the old request before either completes',
        () async {
      final first = (await f.begin())!;
      expect(await f.repo.beginRefresh(f.account, f.collection), isNull);
      final second = (await f.begin())!;
      expect(await f.repo.commitSnapshot(first, _snapshot([_track('old')])),
          isFalse);
      expect(await f.repo.commitSnapshot(second, _snapshot([_track('new')])),
          isTrue);
      expect((await f.content())!.items, [_track('new')]);
    });
    test('completed snapshot retains order, repeats and version distinctions',
        () async {
      final items = [
        _track('0001'),
        _track('2', variant: 'live'),
        _track('0001'),
        _track('2')
      ];
      await f.save(items);
      final content = (await f.content())!;
      expect(content.items, items);
      expect(content.collection.itemCount, 4);
      expect(content.collection.remoteRevision, 'rev1');
      expect(content.collection.completedAt, _time);
      expect(() => content.items.clear(), throwsUnsupportedError);
    });
    test(
        'same track can belong to liked and several playlists without local imports',
        () async {
      final items = [_track('1')];
      await f.save(items);
      final playlist = (await f.repo
          .configureCollection(f.account, _playlist(), isSelected: true))!;
      final ticket = (await f.repo.beginRefresh(f.account, playlist))!;
      expect(await f.repo.commitSnapshot(ticket, _snapshot(items)), isTrue);
      expect((await f.content())!.items, items);
      expect(
          (await f.repo.readContent(f.account.identity, playlist.key))!.items,
          items);
      expect(await f.repositories.tracks.listTracks(), isEmpty);
      expect(
          await f.database.select(f.database.externalTrackRefs).get(), isEmpty);
      expect(
          await f.database.select(f.database.downloadedAssets).get(), isEmpty);
    });
    for (final failure in [
      'partial',
      'count',
      'revision',
      'one-sided',
      'older'
    ]) {
      test('$failure response leaves previous successful snapshot intact',
          () async {
        await f.save([_track('old')]);
        final ticket = (await f.begin())!;
        final result = _snapshot([_track('new')],
            complete: failure != 'partial',
            expectedCount: failure == 'count' ? 2 : 1,
            start: failure == 'one-sided' ? null : 'rev2',
            end: failure == 'revision' ? 'rev3' : 'rev2',
            time: failure == 'older'
                ? _time.subtract(const Duration(microseconds: 1))
                : _time);
        expect(await f.repo.commitSnapshot(ticket, result), isFalse);
        final content = (await f.content())!;
        expect(content.items, [_track('old')]);
        expect(content.collection.remoteRevision, 'rev1');
        expect(content.collection.completedAt, _time);
        // A failed response does not invalidate the ticket itself.
        expect(
            await f.repo.commitSnapshot(ticket, _snapshot([_track('retry')])),
            isTrue);
      });
    }
    test(
        'complete empty snapshot clears membership without removing local data',
        () async {
      final trackId = await f.repositories.tracks.upsertTrack(Track(
          filePath: '/music/song.mp3',
          title: 'Manual',
          metadataSource: MetadataSource.manual,
          addedAt: _time,
          updatedAt: _time));
      await f.repositories.trackUserState
          .toggleFeedback(trackId, TrackFeedback.like, updatedAt: _time);
      final playlistId = await f.repositories.playlists.createPlaylist('Local');
      await f.repositories.playlists.addTrackToPlaylist(playlistId, trackId);
      await f.database.customStatement(
          "INSERT INTO playback_events (track_id, event_type, occurred_at) VALUES (?, 'started', 1)",
          [trackId]);
      final before = await f.localRows();
      await f.save([_track('1')]);
      await f.save([]);
      expect((await f.content())!.items, isEmpty);
      expect(await f.localRows(), before);
      final remoteBefore = await f.content();
      await f.repositories.resetLearningState();
      expect((await f.content())!.collection, remoteBefore!.collection);
    });
    test('foreign provider is rejected without changing saved snapshot',
        () async {
      final ticket = (await f.begin())!;
      expect(
          () => f.repo.commitSnapshot(
              ticket, _snapshot([_track('1', provider: 'other')])),
          throwsArgumentError);
      expect(await f.content(), isNull);
    });
    test('replaying successful ticket is stale and cannot duplicate items',
        () async {
      final ticket = (await f.begin())!;
      final result = _snapshot([_track('1')]);
      expect(await f.repo.commitSnapshot(ticket, result), isTrue);
      expect(await f.repo.commitSnapshot(ticket, result), isFalse);
      expect((await f.content())!.items, [_track('1')]);
    });
    test(
        'snapshot insert failure rolls back deletion, all batches and metadata',
        () async {
      await f.save([_track('old')]);
      final ticket = (await f.begin())!;
      await f.database.customStatement(
          "CREATE TRIGGER fail_remote_insert BEFORE INSERT ON remote_collection_items WHEN NEW.position = 300 BEGIN SELECT RAISE(ABORT, 'simulated'); END");
      final items = List.generate(600, (i) => _track('$i'));
      await expectLater(
          f.repo.commitSnapshot(ticket, _snapshot(items)), throwsA(anything));
      expect((await f.content())!.items, [_track('old')]);
      expect((await f.content())!.collection, ticket.collection);
      await f.database.customStatement('DROP TRIGGER fail_remote_insert');
      expect(await f.repo.commitSnapshot(ticket, _snapshot(items)), isTrue);
      expect((await f.content())!.items, items);
    });
    test('snapshot metadata failure rolls back the item replacement', () async {
      await f.save([_track('old')]);
      final ticket = (await f.begin())!;
      await f.database.customStatement(
          "CREATE TRIGGER fail_remote_finish BEFORE UPDATE ON remote_collections WHEN NEW.remote_revision = 'fail' BEGIN SELECT RAISE(ABORT, 'simulated'); END");
      await expectLater(
          f.repo.commitSnapshot(
              ticket, _snapshot([_track('new')], start: 'fail', end: 'fail')),
          throwsA(anything));
      expect((await f.content())!.items, [_track('old')]);
      expect((await f.content())!.collection, ticket.collection);
    });
    test('failed account switch rolls back previous account deactivation',
        () async {
      await f.database.customStatement(
          "CREATE TRIGGER fail_remote_account BEFORE INSERT ON remote_accounts BEGIN SELECT RAISE(ABORT, 'simulated'); END");
      await expectLater(
          f.repo.activateAccount(_identity('B')), throwsA(anything));
      expect(await f.repo.findAccount(f.account.identity), f.account);
      expect(await f.repo.listAccounts(), hasLength(1));
    });
    test('concurrent refreshes and commits accept only the newest ticket',
        () async {
      final first = (await f.begin())!;
      final current = (await f.repo.listCollections(f.account.identity)).single;
      final attempts = await Future.wait([
        f.repo.beginRefresh(f.account, current),
        f.repo.beginRefresh(f.account, current)
      ]);
      expect(attempts.whereType<RemoteCollectionRefresh>(), hasLength(1));
      final next = attempts.whereType<RemoteCollectionRefresh>().single;
      final results = await Future.wait([
        f.repo.commitSnapshot(first, _snapshot([_track('old')])),
        f.repo.commitSnapshot(next, _snapshot([_track('new')]))
      ]);
      expect(results, [false, true]);
    });
    test(
        'schema enforces one active account per provider and cascades ownership',
        () async {
      await f.save([_track('1')]);
      await expectLater(
          f.database.customStatement(
              "INSERT INTO remote_accounts (provider, account_id, is_active, revision) VALUES ('yandex_music', 'duplicate', 1, 1)"),
          throwsA(anything));
      await f.database.customStatement(
          'DELETE FROM remote_accounts WHERE id = ?', [f.account.id]);
      expect(
          await f.database.select(f.database.remoteCollections).get(), isEmpty);
      expect(await f.database.select(f.database.remoteCollectionItems).get(),
          isEmpty);
    });
    test('selected collection lookup uses its index', () async {
      final plan = await f.database.customSelect(
          'EXPLAIN QUERY PLAN SELECT id FROM remote_collections WHERE account_id = ? AND is_selected = 1 ORDER BY id',
          variables: [Variable.withInt(f.account.id)]).get();
      expect(plan.map((row) => row.read<String>('detail')).join(' '),
          contains('idx_remote_collections_selected'));
    });
    test(
        'corrupt saved order fails visibly instead of silently changing playlist',
        () async {
      await f.save([_track('1')]);
      await f.database
          .customStatement('UPDATE remote_collection_items SET position = 4');
      await expectLater(f.content(), throwsStateError);
    });
  });

  test(
      'file reopen preserves account revisions, selection, snapshot and stale protection',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('cmp_remote_library_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'library.sqlite'));
    final first = _Fixture(AppDatabase(NativeDatabase(file)));
    await first.initialize();
    await first.save([_track('1'), _track('1')]);
    final oldTicket = (await first.begin())!;
    final account = first.account;
    await first.database.close();
    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    final repo = DriftRepositories(database).remoteLibrary;
    expect(await repo.findAccount(account.identity), account);
    final content =
        (await repo.readContent(account.identity, oldTicket.collection.key))!;
    expect(content.items, [_track('1'), _track('1')]);
    expect(content.collection, oldTicket.collection);
    expect(content.collection.completedAt!.microsecondsSinceEpoch,
        _time.microsecondsSinceEpoch);
    await repo.beginRefresh(account, content.collection);
    expect(await repo.commitSnapshot(oldTicket, _snapshot([_track('old')])),
        isFalse);
  });
}

final _time =
    DateTime.fromMicrosecondsSinceEpoch(1792020000123456, isUtc: true);
RemoteAccountIdentity _identity(String id,
        {String provider = 'yandex_music'}) =>
    RemoteAccountIdentity(provider: provider, accountId: id);
ExternalTrackIdentity _track(String id,
        {String provider = 'yandex_music', String variant = ''}) =>
    ExternalTrackIdentity(
        provider: provider, externalId: id, variantKey: variant);
RemoteCollectionKey _playlist({String owner = 'owner'}) => RemoteCollectionKey(
    kind: RemoteCollectionKind.playlist, externalId: '0001', ownerId: owner);
RemoteCollectionSnapshot _snapshot(Iterable<ExternalTrackIdentity> items,
        {bool complete = true,
        int? expectedCount,
        String? start = 'rev1',
        String? end = 'rev1',
        DateTime? time}) =>
    RemoteCollectionSnapshot(
        items: items,
        isComplete: complete,
        completedAt: time ?? _time,
        expectedItemCount: expectedCount,
        revisionAtStart: start,
        revisionAtEnd: end);

final class _Fixture {
  _Fixture([AppDatabase? database])
      : database = database ??
            AppDatabase(NativeDatabase.memory(
                setup: (raw) => raw.execute('PRAGMA foreign_keys = ON')));
  final AppDatabase database;
  late final repositories = DriftRepositories(database);
  late final repo = repositories.remoteLibrary;
  late RemoteLibraryAccount account;
  late RemoteLibraryCollection collection;
  Future<void> initialize() async {
    account = await repo.activateAccount(_identity('000A'), displayName: 'A');
    collection = (await repo.configureCollection(
        account, RemoteCollectionKey(kind: RemoteCollectionKind.liked),
        title: 'Liked', isSelected: true))!;
  }

  Future<RemoteCollectionRefresh?> begin() async {
    final current = (await repo.listCollections(account.identity))
        .firstWhere((item) => item.id == collection.id);
    return repo.beginRefresh(account, current);
  }

  Future<void> save(List<ExternalTrackIdentity> items) async {
    final ticket = (await begin())!;
    expect(await repo.commitSnapshot(ticket, _snapshot(items)), isTrue);
  }

  Future<void> configure(bool selected) async {
    collection = (await repo.configureCollection(account, collection.key,
        title: 'Liked', isSelected: selected))!;
  }

  Future<RemoteCollectionContent?> content() =>
      repo.readContent(account.identity, collection.key);
  Future<Map<String, List<Map<String, Object?>>>> localRows() async => {
        for (final table in [
          'tracks',
          'track_user_state',
          'playlists',
          'playlist_tracks',
          'playback_events',
          'external_track_refs',
          'downloaded_assets'
        ])
          table: [
            for (final row
                in await database.customSelect('SELECT * FROM $table').get())
              row.data
          ]
      };
}
