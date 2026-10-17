import 'package:clever_music_player/src/domain/models/remote_library.dart';
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
        token: YandexAccessToken('synthetic-secret'), transport: transport);
  });
  tearDown(() => client.close());
  Future<List<YandexPlaylistDescriptor>> catalogue(
      {Object? own = const [], Object? saved = const []}) async {
    await client.verifyAccount();
    transport.onGet = (r, _) async =>
        r.endpoint == YandexReadEndpoint.playlists ? own : saved;
    return client.listPlaylists(yandexAccount);
  }

  Matcher issue(YandexResponseIssue value) =>
      throwsA(isA<YandexLibraryException>()
          .having((e) => e.responseIssue, 'issue', value));

  test(
      'own and saved playlists preserve real owner/kind even with equal titles and kind',
      () async {
    final result = await catalogue(own: [
      yandexList()
    ], saved: [
      {'playlist': yandexList(uid: 202), 'timestamp': 'synthetic-time'}
    ]);
    expect(result.map((p) => p.key.ownerId), ['101', '202']);
    expect(result.map((p) => p.key.externalId), ['1000', '1000']);
    expect(result.map((p) => p.title).toSet(), {'Мой плейлист'});
    expect(
        transport.requests.last.relativeUri.path, '/users/101/likes/playlists');
    expect(() => result.clear(), throwsUnsupportedError);
  });
  test('foreign owner returned explicitly by catalogue stays foreign',
      () async {
    final result = await catalogue(own: [yandexList(uid: 202)]);
    expect(result.single.key.ownerId, '202');
  });
  test('same identity repeated within and across sources is one choice',
      () async {
    final result = await catalogue(own: [
      yandexList(),
      yandexList()
    ], saved: [
      {'playlist': yandexList()},
      {'playlist': yandexList(uid: 202)},
      {'playlist': yandexList(uid: 202)}
    ]);
    expect(result.map((p) => p.key.ownerId), ['101', '202']);
  });
  test('different IDs with the same name remain separate', () async {
    final result = await catalogue(own: [yandexList(), yandexList(kind: 1001)]);
    expect(result, hasLength(2));
    expect(result[0].title, result[1].title);
    expect(result[0].key, isNot(result[1].key));
  });
  test('missing own owner uses explicit verified request scope', () async {
    final map = yandexList()
      ..remove('uid')
      ..remove('owner');
    expect((await catalogue(own: [map])).single.key.ownerId, '101');
  });
  test('nested owner alone is authoritative for a saved playlist', () async {
    final map = yandexList(uid: 202)..remove('uid');
    expect(
        (await catalogue(saved: [
          {'playlist': map}
        ]))
            .single
            .key
            .ownerId,
        '202');
  });
  test('missing saved owner is never replaced by current account', () async {
    final map = yandexList()
      ..remove('uid')
      ..remove('owner');
    await expectLater(
        catalogue(saved: [
          {'playlist': map}
        ]),
        issue(YandexResponseIssue.playlistOwner));
  });
  test('conflicting explicit owners fail with safe code', () async {
    final map = yandexList()..['owner'] = {'uid': 202};
    await expectLater(
        catalogue(own: [map]), issue(YandexResponseIssue.conflictingOwner));
  });
  for (final title in [null, '', ' \n\t ', 42]) {
    test(
        'optional title ${title.runtimeType}/${title == null ? 0 : 1} cannot block identity selection',
        () async {
      final result = await catalogue(own: [yandexList()..['title'] = title]);
      expect(result.single.title, 'Плейлист без названия');
      expect(result.single.key, yandexPlaylist);
    });
  }
  test('display title normalizes controls without changing identity', () async {
    final result = await catalogue(
        own: [yandexList()..['title'] = '  Rock\r\n\tMusic\u0000  ']);
    expect(result.single.title, 'Rock Music');
    expect(result.single.key, yandexPlaylist);
  });
  test('large emoji title is bounded in UTF-16 without a broken surrogate',
      () async {
    final result =
        await catalogue(own: [yandexList()..['title'] = '🎵' * 10000]);
    expect(result.single.title.length, 512);
    expect(result.single.title.runes.length, 256);
    validateRemoteDisplayName(result.single.title);
  });
  for (final count in [null, -1, '42', 2.5]) {
    test(
        'optional count $count is unknown rather than a complete empty playlist',
        () async {
      final result =
          await catalogue(own: [yandexList()..['trackCount'] = count]);
      expect(result.single.itemCount, isNull);
    });
  }
  test('catalogue count is advisory, content limits remain enforced', () async {
    final result =
        await catalogue(own: [yandexList()..['trackCount'] = 100001]);
    expect(result.single.itemCount, 100001);
    transport.onGet = (_, __) async => yandexList()..['trackCount'] = null;
    await expectLater(client.readCollection(yandexAccount, yandexPlaylist),
        throwsA(isA<YandexLibraryException>()));
  });
  for (final value in [null, {}, 42]) {
    test(
        'invalid own catalogue shape ${value.runtimeType} never claims success',
        () async {
      await expectLater(
          catalogue(own: value), issue(YandexResponseIssue.catalogueList));
    });
  }
  test(
      'saved wrapper without playlist has a diagnostic code, no guessed identity',
      () async {
    await expectLater(
        catalogue(saved: [
          {'id': '202:1000', 'playlist': null}
        ]),
        issue(YandexResponseIssue.savedPlaylistEntry));
  });
  test('malformed kind is rejected without exposing its value', () async {
    try {
      await catalogue(own: [yandexList(kind: 'private-title-token')]);
      fail('Must reject');
    } on YandexLibraryException catch (e) {
      expect(e.responseIssue, YandexResponseIssue.playlistId);
      expect(e.toString(), isNot(contains('private-title-token')));
    }
  });
  test('combined unique catalogue limit is enforced across both sources',
      () async {
    await client.close();
    client = YandexLibraryClient(
        token: YandexAccessToken('synthetic-secret'),
        transport: transport,
        limits: YandexLibraryLimits(maxPlaylists: 1));
    await expectLater(
        catalogue(own: [
          yandexList()
        ], saved: [
          {'playlist': yandexList(uid: 202)}
        ]),
        throwsA(isA<YandexLibraryException>().having(
            (e) => e.failure, 'failure', YandexLibraryFailure.tooLarge)));
  });
  test('selected saved playlist requests its owner and preserves track repeats',
      () async {
    final result = await catalogue(saved: [
      {'playlist': yandexList(uid: 202)}
    ]);
    transport.onGet = (r, _) async {
      expect(r.ownerId, '202');
      return yandexList(uid: 202);
    };
    final snapshot =
        await client.readCollection(yandexAccount, result.single.key);
    expect(snapshot.items.map((v) => v.externalId), ['001', '2', '001']);
    expect(snapshot.canCommit, isTrue);
  });
}
