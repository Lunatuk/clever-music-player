import 'dart:async';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_client.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/yandex_fixture.dart';

void main() {
  late YandexTestTransport transport;
  late YandexLibraryClient client;
  setUp(() {
    transport = YandexTestTransport();
    client = YandexLibraryClient(
        token: YandexAccessToken('synthetic-secret'),
        transport: transport,
        clock: () => yandexNow);
  });
  tearDown(() => client.close());
  Matcher failure(YandexLibraryFailure value) => throwsA(
      isA<YandexLibraryException>().having((e) => e.failure, 'failure', value));
  Future<RemoteCollectionSnapshot> read([RemoteCollectionKey? key]) =>
      client.readCollection(yandexAccount, key ?? yandexLiked);
  test('requires verified token account, no network work on construction',
      () async {
    expect(transport.requests, isEmpty);
    await expectLater(read(), failure(YandexLibraryFailure.accountMismatch));
    expect(transport.requests, isEmpty);
    final profile = await client.verifyAccount();
    expect(profile.identity, yandexAccount);
    expect(profile.displayName, 'Музыка');
  });
  test('profile fallback ignores blank names without storing email', () async {
    transport.onGet = (_, __) async => {
          'account': {
            'uid': '101',
            'displayName': '',
            'firstName': '',
            'login': 'user',
            'defaultEmail': 'private'
          }
        };
    expect((await client.verifyAccount()).displayName, 'user');
  });
  test(
      'reverification cannot silently switch accounts in the same credential session',
      () async {
    await client.verifyAccount();
    transport.onGet = (_, __) async => yandexStatus(uid: 102);
    await expectLater(
        client.verifyAccount(), failure(YandexLibraryFailure.accountMismatch));
    expect(client.verifiedAccount, isNull);
  });
  test('inventory uses owner/kind and never uses display names for identity',
      () async {
    await client.verifyAccount();
    transport.onGet = (_, __) async => [yandexList(), yandexList(kind: 1001)];
    final result = await client.listPlaylists(yandexAccount);
    expect(result.map((e) => e.key.externalId), ['1000', '1001']);
    expect(result.map((e) => e.title).toSet(), {'Мой плейлист'});
    expect(() => result.clear(), throwsUnsupportedError);
  });
  test('empty inventory is explicit and valid', () async {
    await client.verifyAccount();
    transport.onGet = (_, __) async => [];
    expect(await client.listPlaylists(yandexAccount), isEmpty);
  });
  for (final response in [
    null,
    {},
    [yandexList(), yandexList()],
    [yandexList(uid: 102)]
  ]) {
    test('invalid/duplicate/foreign inventory rejected: $response', () async {
      await client.verifyAccount();
      transport.onGet = (_, __) async => response;
      await expectLater(client.listPlaylists(yandexAccount),
          throwsA(isA<YandexLibraryException>()));
    });
  }
  test(
      'liked list preserves order, repeats, leading zero ids and album context',
      () async {
    await client.verifyAccount();
    final snapshot = await read();
    expect(snapshot.items.map((e) => e.externalId), ['001', '2', '001']);
    expect(snapshot.items.map((e) => e.variantKey), ['009', '009', '009']);
    expect(snapshot.canCommit, isTrue);
    expect(snapshot.revisionAtStart, '1');
    expect(snapshot.completedAt, yandexNow);
    expect(
        transport.requests
            .where((r) => r.endpoint == YandexReadEndpoint.likedTracks),
        hasLength(2));
  });
  test('unavailable nested track is retained by its outer identity', () async {
    await client.verifyAccount();
    transport.onGet = (_, __) async => yandexLikes(tracks: [
          {
            ...yandexTrack('42', album: null),
            'track': {'id': '42', 'available': false}
          },
          {...yandexTrack('43', album: ''), 'track': null},
        ]);
    expect((await read()).items.map((e) => e.externalId), ['42', '43']);
    expect((await read()).items.every((e) => e.variantKey.isEmpty), isTrue);
  });
  test(
      'empty liked snapshot valid only with explicit empty tracks and revision',
      () async {
    await client.verifyAccount();
    transport.onGet = (_, __) async => yandexLikes(tracks: [], revision: 0);
    expect((await read()).items, isEmpty);
  });
  for (final response in [
    {},
    {
      'library': {'uid': 101, 'revision': 1}
    },
    yandexLikes(revision: null),
    yandexLikes(uid: 102),
    yandexLikes(tracks: [null]),
    yandexLikes(tracks: [
      {'id': true}
    ]),
    yandexLikes(tracks: [
      {'id': '1', 'albumId': 'bad'}
    ]),
    yandexLikes(tracks: [
      {
        'id': '1',
        'track': {'id': '2'}
      }
    ]),
  ]) {
    test(
        'malformed liked response never becomes empty complete snapshot: $response',
        () async {
      await client.verifyAccount();
      transport.onGet = (_, __) async => response;
      await expectLater(read(), throwsA(isA<YandexLibraryException>()));
    });
  }
  test(
      'liked declared count or completeness hints cannot hide a partial response',
      () async {
    await client.verifyAccount();
    transport.onGet = (_, __) async => {
          'library': {'uid': 101, 'revision': 1, 'tracks': [], 'trackCount': 3}
        };
    await expectLater(read(), failure(YandexLibraryFailure.incomplete));
    transport.onGet = (_, __) async => {
          'library': {'uid': 101, 'revision': 1, 'tracks': [], 'hasMore': true}
        };
    await expectLater(read(), failure(YandexLibraryFailure.incomplete));
  });
  test('liked revision change on second full observation rejects snapshot',
      () async {
    await client.verifyAccount();
    var reads = 0;
    transport.onGet = (_, __) async => yandexLikes(revision: ++reads);
    await expectLater(read(), failure(YandexLibraryFailure.changed));
  });
  test('same revision but reordered identities rejected', () async {
    await client.verifyAccount();
    var reads = 0;
    transport.onGet = (_, __) async => yandexLikes(
        tracks: ++reads == 1
            ? [yandexTrack('1'), yandexTrack('2')]
            : [yandexTrack('2'), yandexTrack('1')]);
    await expectLater(read(), failure(YandexLibraryFailure.changed));
  });
  test('playlist without pager must contain the entire declared count',
      () async {
    await client.verifyAccount();
    transport.onGet = (_, __) async => yandexList(tracks: [yandexTrack('1')]);
    await expectLater(
        read(yandexPlaylist), failure(YandexLibraryFailure.incomplete));
  });
  test('two full playlist reads support unavailable positions and empty lists',
      () async {
    await client.verifyAccount();
    transport.onGet = (_, __) async => yandexList(tracks: [], count: 0);
    final result = await read(yandexPlaylist);
    expect(result.canCommit, isTrue);
    expect(result.expectedItemCount, 0);
  });
  for (final base in [0, 1]) {
    test('paginated playlist observes all pages twice, base $base', () async {
      await client.verifyAccount();
      transport.onGet = (r, _) async {
        final page = r.page ?? base;
        return yandexList(
            tracks: page == base
                ? [yandexTrack('1'), yandexTrack('2')]
                : [yandexTrack('1')],
            pager: {'page': page, 'perPage': 2, 'total': 3});
      };
      final result = await read(yandexPlaylist);
      expect(result.items.map((e) => e.externalId), ['1', '2', '1']);
      final pages = transport.requests
          .where((r) => r.endpoint == YandexReadEndpoint.playlist)
          .toList();
      expect(pages.map((e) => e.page), [null, base + 1, null, base + 1]);
      expect(pages[1].relativeUri.queryParameters['pageSize'], '2');
    });
  }
  for (final reason in [
    'repeatPage',
    'countChanged',
    'revisionChanged',
    'shortPage',
    'wrongKind',
    'wrongOwner',
    'missingPager',
    'hasMore'
  ]) {
    test('bad later playlist page rejected: $reason', () async {
      await client.verifyAccount();
      transport.onGet = (r, _) async {
        if (r.page == null) {
          return yandexList(
              tracks: [yandexTrack('1'), yandexTrack('2')],
              pager: {'page': 0, 'perPage': 2, 'total': 3});
        }
        final result = yandexList(
            tracks: reason == 'shortPage' ? [] : [yandexTrack('3')],
            count: reason == 'countChanged' ? 4 : 3,
            revision: reason == 'revisionChanged' ? 2 : 1,
            kind: reason == 'wrongKind' ? 2000 : 1000,
            uid: reason == 'wrongOwner' ? 102 : 101,
            pager: reason == 'missingPager'
                ? null
                : {
                    'page': reason == 'repeatPage' ? 0 : 1,
                    'perPage': 2,
                    'total': 3
                  });
        if (reason == 'hasMore') result['hasMore'] = true;
        return result;
      };
      await expectLater(
          read(yandexPlaylist), throwsA(isA<YandexLibraryException>()));
    });
  }
  test('foreign selected playlist may be read with its explicit owner',
      () async {
    await client.verifyAccount();
    transport.onGet = (_, __) async => yandexList(uid: 202);
    final key = RemoteCollectionKey(
        kind: RemoteCollectionKind.playlist,
        ownerId: '202',
        externalId: '1000');
    expect((await read(key)).items, hasLength(3));
    expect(transport.requests.last.ownerId, '202');
  });
  test('playlist missing revision uses two identical full observations',
      () async {
    await client.verifyAccount();
    transport.onGet = (_, __) async => yandexList(revision: null);
    expect((await read(yandexPlaylist)).revisionAtStart, isNull);
  });
  test('unavailable playlist is not an empty collection', () async {
    await client.verifyAccount();
    transport.onGet = (_, __) async => {...yandexList(), 'available': false};
    await expectLater(
        read(yandexPlaylist), failure(YandexLibraryFailure.accessDenied));
  });
  test('item count bound rejects before second request', () async {
    await client.close();
    transport = YandexTestTransport();
    client = YandexLibraryClient(
        token: YandexAccessToken('test'),
        transport: transport,
        limits: YandexLibraryLimits(maxItems: 2));
    await client.verifyAccount();
    await expectLater(read(), failure(YandexLibraryFailure.tooLarge));
    expect(transport.requests, hasLength(2));
  });
  test('page bound rejects before following an excessive sequence', () async {
    await client.close();
    transport = YandexTestTransport();
    client = YandexLibraryClient(
        token: YandexAccessToken('test'),
        transport: transport,
        limits: YandexLibraryLimits(maxPages: 1));
    await client.verifyAccount();
    transport.onGet = (_, __) async => yandexList(
        tracks: [yandexTrack('1')],
        pager: {'page': 0, 'perPage': 1, 'total': 3});
    await expectLater(
        read(yandexPlaylist), failure(YandexLibraryFailure.tooLarge));
    expect(transport.requests, hasLength(2));
  });
  test('cancel before first request is reusable and sends nothing', () async {
    await expectLater(
        client.verifyAccount(control: LibraryScanControl()..cancel()),
        failure(YandexLibraryFailure.cancelled));
    expect(transport.requests, isEmpty);
    expect((await client.verifyAccount()).identity, yandexAccount);
  });
  test('cancellation after a page prevents all following requests', () async {
    await client.verifyAccount();
    final control = LibraryScanControl();
    transport.onGet = (_, __) async {
      control.cancel();
      return yandexLikes();
    };
    await expectLater(
        client.readCollection(yandexAccount, yandexLiked, control: control),
        failure(YandexLibraryFailure.cancelled));
    expect(transport.requests, hasLength(2));
  });
  test('close waits for accepted work, cancels result, closes reader once',
      () async {
    final gate = Completer<void>(), entered = Completer<void>();
    transport.onGet = (_, __) async {
      entered.complete();
      await gate.future;
      return yandexStatus();
    };
    final result = client.verifyAccount();
    await entered.future;
    await expectLater(
        client.verifyAccount(), failure(YandexLibraryFailure.busy));
    var closed = false;
    final closing = client.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    gate.complete();
    await expectLater(result, failure(YandexLibraryFailure.cancelled));
    await closing;
    expect(transport.closed, isTrue);
    await expectLater(
        client.verifyAccount(), failure(YandexLibraryFailure.closed));
  });
  test('overall operation timeout drains accepted transport work', () async {
    await client.close();
    transport = YandexTestTransport();
    client = YandexLibraryClient(
        token: YandexAccessToken('test'),
        transport: transport,
        limits: YandexLibraryLimits(
            operationTimeout: const Duration(milliseconds: 5)));
    transport.onGet = (_, __) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return yandexStatus();
    };
    await expectLater(
        client.verifyAccount(), failure(YandexLibraryFailure.timeout));
    expect(client.verifiedAccount, isNull);
  });
  test('raw transport error and token never appear in public exception',
      () async {
    transport.onGet =
        (_, __) async => throw StateError('synthetic-secret /private/path');
    try {
      await client.verifyAccount();
      fail('Must reject');
    } on YandexLibraryException catch (error) {
      expect(error.toString(), 'YandexLibraryException(network)');
      expect(YandexAccessToken('synthetic-secret').toString(),
          isNot(contains('synthetic-secret')));
    }
  });
}
