import 'dart:async';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/library_sync/yandex_connection_controller.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_client.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/download_fixture.dart';
import 'support/yandex_connection_fixture.dart';
import 'support/yandex_fixture.dart';
import 'support/recording_diagnostics.dart';

void main() {
  late DownloadFixture f;
  late MemoryYandexCredentials store;
  late YandexConnectionController c;
  late List<YandexTestTransport> transports;
  late FakeYandexProbe probe;
  late RecordingDiagnostics diagnostics;
  YandexConnectionController create() => YandexConnectionController(
      repository: f.repositories.remoteLibrary,
      sessions: f.repositories.yandexSessions,
      credentials: store,
      diagnostics: diagnostics,
      probeFactory: () => probe,
      readerFactory: (token) {
        final t = YandexTestTransport();
        transports.add(t);
        return YandexLibraryClient(token: token, transport: t, clock: f.clock);
      });
  setUp(() async {
    f = await DownloadFixture.open();
    store = MemoryYandexCredentials();
    transports = [];
    probe = FakeYandexProbe();
    diagnostics = RecordingDiagnostics();
    c = create();
  });
  tearDown(() async {
    await c.close();
    await f.close();
  });
  Future<void> connected() async {
    await c.initialize();
    await c.connect('synthetic-token');
    expect(c.failure, isNull);
    expect(c.account!.identity, yandexAccount);
  }

  test('explicit probe creates no reader, DB session or credential access',
      () async {
    await c.probeConnection();
    expect(probe.calls, 1);
    expect(probe.closed, isTrue);
    expect(store.reads + store.writes + store.deletes, 0);
    expect(transports, isEmpty);
    expect(c.account, isNull);
    expect(c.message, contains('без токена'));
    expect(diagnostics.entries.map((e) => e.event), [
      DiagnosticEvent.yandexOperationStarted,
      DiagnosticEvent.yandexOperationCompleted
    ]);
    expect(diagnostics.entries.last.fields[DiagnosticField.remoteOperation],
        YandexConnectionActivity.probing.index);
  });
  test(
      'failed probe preserves an existing account and logs fixed failure codes',
      () async {
    await connected();
    final account = c.account, saved = store.value;
    probe.onProbe = (_) async => throw const YandexLibraryException(
        YandexLibraryFailure.timeout,
        stage: YandexRequestStage.connecting);
    await c.probeConnection();
    expect(c.account, account);
    expect(store.value, saved);
    expect(store.deletes, 0);
    expect(c.failureStage, YandexRequestStage.connecting);
    expect(c.failure, YandexConnectionFailure.timeout);
    expect(
        diagnostics.entries.last.event, DiagnosticEvent.yandexOperationFailed);
    expect(
        diagnostics
            .entries.last.fields[DiagnosticField.remoteConnectionFailure],
        YandexConnectionFailure.timeout.index);
    expect(
        diagnostics.entries
            .every((e) => e.fields.values.every((v) => v is num || v is bool)),
        isTrue);
  });
  test('closing cancels and drains an active probe before releasing its owner',
      () async {
    final entered = Completer<void>();
    probe.onProbe = (control) async {
      final done = Completer<void>();
      control.addCancellationListener(done.complete);
      entered.complete();
      await done.future;
      control.throwIfCancelled();
    };
    final operation = c.probeConnection();
    await entered.future;
    await c.close();
    await operation;
    expect(probe.closed, isTrue);
    expect(c.failure, YandexConnectionFailure.cancelled);
    expect(store.reads, 0);
    await c.probeConnection();
    expect(probe.calls, 1);
  });
  test('connection progress separates account, playlists and protected write',
      () async {
    final steps = <YandexConnectionStep>[];
    c.addListener(() {
      final step = c.connectionStep;
      if (c.isBusy && step != null && (steps.isEmpty || steps.last != step)) {
        steps.add(step);
      }
    });
    await connected();
    expect(steps, [
      YandexConnectionStep.verifyingAccount,
      YandexConnectionStep.savingCredential,
      YandexConnectionStep.loadingPlaylists
    ]);
  });
  test(
      'playlist failure retains HTTP stage and preserves the verified saved login',
      () async {
    await c.close();
    c = YandexConnectionController(
        repository: f.repositories.remoteLibrary,
        sessions: f.repositories.yandexSessions,
        credentials: store,
        diagnostics: diagnostics,
        readerFactory: (token) {
          final t = YandexTestTransport()
            ..onGet = ((request, _) async =>
                request.endpoint == YandexReadEndpoint.account
                    ? yandexStatus()
                    : throw const YandexLibraryException(
                        YandexLibraryFailure.timeout,
                        stage: YandexRequestStage.waitingForResponse));
          transports.add(t);
          return YandexLibraryClient(
              token: token, transport: t, clock: f.clock);
        });
    await c.connect('synthetic-token');
    expect(c.failureStage, YandexRequestStage.waitingForResponse);
    expect(store.writes, 1);
    expect(c.account!.identity, yandexAccount);
    expect(c.choices.single.key, yandexLiked);
    expect(diagnostics.entries.last.fields[DiagnosticField.remoteStage],
        YandexRequestStage.waitingForResponse.index);
  });
  test(
      'collection refresher preserves failure phase and previous completed mirror',
      () async {
    await connected();
    await c.checkCollections();
    final completed = c.choices.first.completedAt;
    transports.single.onGet = (_, __) async =>
        throw const YandexLibraryException(YandexLibraryFailure.timeout,
            stage: YandexRequestStage.receivingBody);
    await c.checkCollections();
    expect(c.failureStage, YandexRequestStage.receivingBody);
    expect(c.choices.first.completedAt, completed);
    expect(c.choices.first.itemCount, 3);
  });

  test('construction and restoring absent credentials never use the network',
      () async {
    expect(store.reads, 0);
    expect(transports, isEmpty);
    await c.initialize();
    await c.initialize();
    expect(store.reads, 1);
    expect(transports, isEmpty);
    expect(c.account, isNull);
  });
  test(
      'verified connection selects likes, keeps playlists opt-in and hides the secret',
      () async {
    await connected();
    expect(store.writes, 1);
    expect(store.value!.matches(c.account!), isTrue);
    expect(transports.single.requests.map((r) => r.endpoint), [
      YandexReadEndpoint.account,
      YandexReadEndpoint.playlists,
      YandexReadEndpoint.likedPlaylists
    ]);
    expect(c.choices.map((v) => v.isSelected), [true, false]);
    expect(c.message, isNot(contains('synthetic-token')));
  });
  test('restoration keeps selection with no HTTP; catalogue fetch is explicit',
      () async {
    await connected();
    await c.select(yandexPlaylist, true);
    await c.close();
    c = create();
    await c.initialize();
    expect(c.choices.map((v) => v.isSelected), [true, true]);
    expect(transports.last.requests, isEmpty);
    await c.loadPlaylists();
    expect(transports.last.requests, hasLength(3));
  });
  test('reconnection retains explicitly deselected likes', () async {
    await connected();
    await c.select(yandexLiked, false);
    await c.connect('replacement-token');
    expect(c.choices.first.isSelected, isFalse);
    expect(transports.first.closed, isTrue);
  });
  test('invalid candidate input preserves connected account and credential',
      () async {
    await connected();
    final account = c.account, saved = store.value;
    await c.connect('bad\ninput');
    expect(c.failure, YandexConnectionFailure.invalidToken);
    expect(c.account, account);
    expect(store.value, saved);
    expect(transports, hasLength(1));
  });
  for (final failure in [
    YandexLibraryFailure.unauthorized,
    YandexLibraryFailure.network
  ]) {
    test('candidate $failure does not log out an existing valid connection',
        () async {
      await connected();
      final account = c.account, saved = store.value;
      // Replace the factory with a failing candidate, while restoring the valid binding first.
      await c.close();
      c = YandexConnectionController(
          repository: f.repositories.remoteLibrary,
          sessions: f.repositories.yandexSessions,
          credentials: store,
          readerFactory: (token) {
            final t = YandexTestTransport()
              ..onGet =
                  ((_, __) async => throw YandexLibraryException(failure));
            transports.add(t);
            return YandexLibraryClient(
                token: token, transport: t, clock: f.clock);
          });
      await c.initialize();
      await c.connect('bad-candidate');
      expect(c.account, account);
      expect(store.value, saved);
      expect(store.deletes, 0);
      expect(transports.last.closed, isTrue);
    });
  }
  for (final afterWrite in [false, true]) {
    test(
        'secure store failure afterWrite=$afterWrite never activates unbound account',
        () async {
      await c.initialize();
      final before = await f.repositories.yandexSessions.capture();
      store.failWrite = !afterWrite;
      store.writeThenFail = afterWrite;
      await c.connect('synthetic-token');
      expect(c.failure, YandexConnectionFailure.storage);
      expect(c.account, isNull);
      expect(await f.repositories.yandexSessions.capture(), before);
      expect(transports.single.closed, isTrue);
      if (afterWrite) {
        await c.close();
        c = create();
        await c.initialize();
        expect(c.failure, YandexConnectionFailure.stale);
        expect(transports, hasLength(1));
      }
    });
  }
  test('wrong revision cannot restore credentials or create a client',
      () async {
    await connected();
    await c.close();
    await f.repositories.remoteLibrary.activateAccount(yandexAccount);
    c = create();
    await c.initialize();
    expect(c.failure, YandexConnectionFailure.stale);
    expect(c.account, isNull);
    expect(transports, hasLength(1));
  });
  test('storage read failure can be retried on reopening settings', () async {
    store.failRead = true;
    await c.initialize();
    expect(c.failure, YandexConnectionFailure.storage);
    store.failRead = false;
    await c.initialize();
    expect(c.failure, isNull);
    expect(store.reads, 2);
  });
  test(
      'checking selected collections persists complete mirrors, no download jobs',
      () async {
    await connected();
    await c.select(yandexPlaylist, true);
    await c.checkCollections();
    expect(c.failure, isNull);
    expect(c.choices.map((v) => v.itemCount), [3, 3]);
    expect(c.choices.every((v) => v.completedAt != null), isTrue);
    expect(await f.count('download_jobs'), 0);
    expect(c.message, contains('Позиций: 6'));
  });
  test('no selected collections means no network request', () async {
    await connected();
    await c.select(yandexLiked, false);
    final count = transports.single.requests.length;
    await c.checkCollections();
    expect(transports.single.requests.length, count);
    expect(c.message, contains('Выбери'));
  });
  for (final failure in [
    YandexLibraryFailure.network,
    YandexLibraryFailure.accessDenied,
    YandexLibraryFailure.incomplete
  ]) {
    test('$failure leaves the previous completed mirror and credential intact',
        () async {
      await connected();
      await c.checkCollections();
      final completed = c.choices.first.completedAt;
      transports.single.onGet =
          (_, __) async => throw YandexLibraryException(failure);
      await c.checkCollections();
      expect(c.failure, isNotNull);
      expect(c.choices.first.itemCount, 3);
      expect(c.choices.first.completedAt, completed);
      expect(c.account, isNotNull);
      expect(store.deletes, 0);
    });
  }
  test(
      'revoked current credential disconnects but preserves completed mirrors and music',
      () async {
    await connected();
    await c.checkCollections();
    final tracks = await f.count('tracks');
    transports.single.onGet = (_, __) async =>
        throw const YandexLibraryException(YandexLibraryFailure.unauthorized);
    await c.checkCollections();
    expect(c.failure, YandexConnectionFailure.unauthorized);
    expect(c.account, isNull);
    expect(store.value, isNull);
    expect(await f.count('remote_collection_items'), 3);
    expect(await f.count('tracks'), tracks);
    expect(await f.raw.exists(), isTrue);
  });
  test('failed logout keeps current connection usable', () async {
    await connected();
    final account = c.account;
    store.failDelete = true;
    await c.disconnect();
    expect(c.failure, YandexConnectionFailure.storage);
    expect(c.account, account);
    expect(store.value!.matches(account!), isTrue);
    store.failDelete = false;
    await c.checkCollections();
    expect(c.failure, isNull);
  });
  test(
      'stale process cannot delete a newer connection; reopen adopts it without HTTP',
      () async {
    await connected();
    final newer = create();
    await newer.connect('new-token');
    final saved = store.value;
    await c.disconnect();
    expect(c.failure, YandexConnectionFailure.stale);
    expect(store.value, saved);
    expect(store.deletes, 0);
    await c.initialize();
    expect(c.failure, isNull);
    expect(c.account, newer.account);
    expect(transports.last.requests, isEmpty);
    await newer.close();
  });
  test('cancel before persistence closes candidate without altering storage',
      () async {
    final entered = Completer<void>();
    await c.close();
    c = YandexConnectionController(
        repository: f.repositories.remoteLibrary,
        sessions: f.repositories.yandexSessions,
        credentials: store,
        readerFactory: (token) {
          final t = YandexTestTransport()
            ..onGet = ((_, control) async {
              entered.complete();
              final done = Completer<void>();
              control.addCancellationListener(done.complete);
              await done.future;
              control.throwIfCancelled();
              return null;
            });
          transports.add(t);
          return YandexLibraryClient(
              token: token, transport: t, clock: f.clock);
        });
    final operation = c.connect('synthetic-token');
    await entered.future;
    c.cancel();
    await operation;
    expect(c.failure, YandexConnectionFailure.cancelled);
    expect(store.writes, 0);
    expect(transports.single.closed, isTrue);
  });
  test('close drains an accepted credential commit before releasing reader',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    store.onWrite = () async {
      entered.complete();
      await release.future;
    };
    final operation = c.connect('synthetic-token');
    await entered.future;
    var closed = false;
    final closing = c.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    release.complete();
    await operation;
    await closing;
    expect(store.value!.matches(c.account!), isTrue);
    expect(transports.single.closed, isTrue);
    await c.connect('ignored');
    expect(store.writes, 1);
  });
}
