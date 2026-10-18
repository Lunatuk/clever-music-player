import 'dart:async';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/library_sync/yandex_connection_controller.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_client.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/download_fixture.dart';
import 'support/recording_diagnostics.dart';
import 'support/yandex_connection_fixture.dart';
import 'support/yandex_fixture.dart';

void main() {
  late DownloadFixture f;
  late MemoryYandexCredentials store;
  late RecordingDiagnostics diagnostics;
  late YandexTestTransport transport;
  late YandexConnectionController c;
  YandexConnectionController create() => YandexConnectionController(
      repository: f.repositories.remoteLibrary,
      sessions: f.repositories.yandexSessions,
      credentials: store,
      diagnostics: diagnostics,
      readerFactory: (token) => YandexLibraryClient(
          token: token, transport: transport, clock: f.clock));
  setUp(() async {
    f = await DownloadFixture.open();
    store = MemoryYandexCredentials();
    diagnostics = RecordingDiagnostics();
    transport = YandexTestTransport();
    c = create();
  });
  tearDown(() async {
    await c.close();
    await f.close();
  });

  test('verified credential is saved before optional playlist requests',
      () async {
    var catalogueRequests = 0;
    transport.onGet = (r, _) async {
      if (r.endpoint == YandexReadEndpoint.account) {
        expect(store.writes, 0);
        return yandexStatus();
      }
      expect(store.value!.matches(c.account!), isTrue);
      catalogueRequests++;
      return [];
    };
    await c.connect('synthetic-secret');
    expect(c.failure, isNull);
    expect(catalogueRequests, 2);
    expect(store.writes, 1);
  });
  test(
      'malformed catalogue cannot undo login; restore and retry require no new credential',
      () async {
    transport.onGet = (r, _) async => r.endpoint == YandexReadEndpoint.account
        ? yandexStatus()
        : [yandexList(kind: 'PRIVATE-bad-kind')];
    await c.connect('synthetic-secret');
    expect(c.failure, YandexConnectionFailure.invalidResponse);
    expect(c.account!.identity, yandexAccount);
    expect(store.value!.matches(c.account!), isTrue);
    expect(c.choices.single.key, yandexLiked);
    final entry = diagnostics.entries.last;
    expect(entry.fields[DiagnosticField.remoteFailure],
        YandexLibraryFailure.invalidResponse.index);
    expect(entry.fields[DiagnosticField.remoteResponseIssue],
        YandexResponseIssue.playlistId.index);
    expect(entry.fields.toString(), isNot(contains('PRIVATE-bad-kind')));
    await c.close();
    transport = YandexTestTransport();
    c = create();
    await c.initialize();
    expect(c.account, isNotNull);
    expect(transport.requests, isEmpty);
    await c.checkCollections();
    expect(c.failure, isNull);
    expect(c.choices.single.itemCount, 3);
    await c.loadPlaylists();
    expect(c.failure, isNull);
    expect(c.choices, hasLength(2));
    expect(store.writes, 1);
  });
  test(
      '401 during catalogue revokes the newly saved session instead of retaining an invalid token',
      () async {
    transport.onGet = (r, _) async => r.endpoint == YandexReadEndpoint.account
        ? yandexStatus()
        : throw const YandexLibraryException(YandexLibraryFailure.unauthorized);
    await c.connect('synthetic-secret');
    expect(c.failure, YandexConnectionFailure.unauthorized);
    expect(c.account, isNull);
    expect(store.value, isNull);
    expect(store.writes, 1);
    expect(store.deletes, 1);
    expect(await f.repositories.yandexSessions.capture(), isEmpty);
  });
  test(
      'cancelling discovery retains committed login and prevents saved-playlist request',
      () async {
    final entered = Completer<void>();
    transport.onGet = (r, control) async {
      if (r.endpoint == YandexReadEndpoint.account) return yandexStatus();
      final release = Completer<void>();
      control.addCancellationListener(release.complete);
      entered.complete();
      await release.future;
      control.throwIfCancelled();
      return [];
    };
    final operation = c.connect('synthetic-secret');
    await entered.future;
    expect(store.writes, 1);
    c.cancel();
    await operation;
    expect(c.failure, YandexConnectionFailure.cancelled);
    expect(c.account, isNotNull);
    expect(store.value!.matches(c.account!), isTrue);
    expect(
        transport.requests
            .where((r) => r.endpoint == YandexReadEndpoint.likedPlaylists),
        isEmpty);
  });
  test('protected write failure never begins catalogue discovery', () async {
    final before = await f.repositories.yandexSessions.capture();
    store.failWrite = true;
    await c.connect('synthetic-secret');
    expect(c.failure, YandexConnectionFailure.storage);
    expect(c.account, isNull);
    expect(transport.requests.map((r) => r.endpoint),
        [YandexReadEndpoint.account]);
    expect(await f.repositories.yandexSessions.capture(), before);
  });
  test(
      'saved foreign selection snapshots and restart preserve owner, order and repeat positions',
      () async {
    transport.onGet = (r, _) async => switch (r.endpoint) {
          YandexReadEndpoint.account => yandexStatus(),
          YandexReadEndpoint.playlists => [yandexList()],
          YandexReadEndpoint.likedPlaylists => [
              {'playlist': yandexList(uid: 202)}
            ],
          YandexReadEndpoint.likedTracks => yandexLikes(),
          YandexReadEndpoint.playlist => yandexList(uid: r.ownerId),
          YandexReadEndpoint.track ||
          YandexReadEndpoint.fileInfo =>
            throw StateError('Unexpected download request'),
        };
    await c.connect('synthetic-secret');
    expect(c.failure, isNull);
    final key =
        c.choices.singleWhere((choice) => choice.key.ownerId == '202').key;
    expect(c.choices.singleWhere((choice) => choice.key == key).isSelected,
        isFalse);
    await c.select(key, true);
    await c.checkCollections();
    expect(c.failure, isNull);
    expect(c.choices.singleWhere((choice) => choice.key == key).itemCount, 3);
    expect(await f.count('download_jobs'), 0);
    expect(
        transport.requests
            .where((r) => r.endpoint == YandexReadEndpoint.playlist)
            .every((r) => r.ownerId == '202'),
        isTrue);
    await c.close();
    transport = YandexTestTransport();
    c = create();
    await c.initialize();
    final restored = c.choices.singleWhere((choice) => choice.key == key);
    expect(restored.isSelected, isTrue);
    expect(restored.itemCount, 3);
    expect(transport.requests, isEmpty);
  });
}
