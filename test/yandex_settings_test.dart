import 'dart:async';
import 'package:clever_music_player/src/library_sync/yandex_connection_controller.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_client.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:clever_music_player/src/ui/yandex_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/download_fixture.dart';
import 'support/yandex_connection_fixture.dart';
import 'support/yandex_fixture.dart';

void main() {
  late DownloadFixture f;
  late YandexConnectionController c;
  late YandexTestTransport transport;
  late MemoryYandexCredentials store;
  late FakeYandexProbe probe;
  setUp(() async {
    f = await DownloadFixture.open();
    store = MemoryYandexCredentials();
    transport = YandexTestTransport();
    probe = FakeYandexProbe();
    c = YandexConnectionController(
        repository: f.repositories.remoteLibrary,
        sessions: f.repositories.yandexSessions,
        credentials: store,
        probeFactory: () => probe,
        readerFactory: (token) => YandexLibraryClient(
            token: token, transport: transport, clock: f.clock));
  });
  tearDown(() async {
    await c.close();
    await f.close();
  });
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 200 && c.isBusy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.isBusy, isFalse);
    });
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester,
      {Future<void> Function()? help, double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child:
                            YandexSettings(controller: c, openHelp: help)))))));
    await settle(tester);
  }

  testWidgets('connection probe works with an empty token field',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('yandex-probe')));
    await settle(tester);
    expect(probe.calls, 1);
    expect(probe.closed, isTrue);
    expect(store.reads, 1);
    expect(store.writes, 0);
    expect(transport.requests, isEmpty);
    expect(find.textContaining('API Яндекс Музыки доступен.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
  });
  testWidgets('connect timeout explains the failed network phase',
      (tester) async {
    probe.onProbe = (_) async => throw const YandexLibraryException(
        YandexLibraryFailure.timeout,
        stage: YandexRequestStage.connecting);
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('yandex-probe')));
    await settle(tester);
    expect(find.textContaining('Не удалось установить соединение с API'),
        findsOneWidget);
    expect(find.textContaining('Токен недействителен'), findsNothing);
  });
  testWidgets('header timeout after connection gets a different explanation',
      (tester) async {
    probe.onProbe = (_) async => throw const YandexLibraryException(
        YandexLibraryFailure.timeout,
        stage: YandexRequestStage.waitingForResponse);
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('yandex-probe')));
    await settle(tester);
    expect(find.textContaining('Соединение с Яндексом установлено'),
        findsOneWidget);
  });
  testWidgets('busy login displays playlist step after account verification',
      (tester) async {
    final entered = Completer<void>();
    transport.onGet = (request, control) async {
      if (request.endpoint == YandexReadEndpoint.account) return yandexStatus();
      final done = Completer<void>();
      control.addCancellationListener(done.complete);
      entered.complete();
      await done.future;
      control.throwIfCancelled();
      return null;
    };
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'synthetic-token');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('yandex-connect')));
    await tester.runAsync(() => entered.future);
    await tester.pump();
    expect(find.text('Получаю список плейлистов…'), findsOneWidget);
    await tester.ensureVisible(find.text('Отмена'));
    await tester.tap(find.text('Отмена'));
    await settle(tester);
    expect(c.failure, YandexConnectionFailure.cancelled);
    expect(store.writes, 1);
  });
  testWidgets('token is masked and cleared, account and opt-in choices appear',
      (tester) async {
    await pump(tester);
    final field = find.byKey(const ValueKey('yandex-token'));
    final input = tester.widget<TextField>(field);
    expect(input.obscureText, isTrue);
    expect(input.enableSuggestions, isFalse);
    expect(input.autocorrect, isFalse);
    await tester.enterText(field, 'synthetic-token');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('yandex-connect')));
    await settle(tester);
    expect(find.text('Подключён: Музыка'), findsOneWidget);
    expect(c.choices.map((v) => v.isSelected), [true, false]);
    await tester.tap(find.byKey(const ValueKey('yandex-disconnect')));
    await settle(tester);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(store.value, isNull);
  });
  testWidgets('checkbox saves choice; collection check shows persisted counts',
      (tester) async {
    await pump(tester);
    await tester.runAsync(() => c.connect('synthetic-token'));
    await settle(tester);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Мой плейлист'));
    await settle(tester);
    expect(c.choices.last.isSelected, isTrue);
    await tester.tap(find.byKey(const ValueKey('yandex-check')));
    await settle(tester);
    expect(find.textContaining('Позиций: 6'), findsOneWidget);
    expect(find.text('Сохранённый состав: 3 позиций'), findsNWidgets(2));
  });
  testWidgets('invalid input shows sanitized error and clears submitted secret',
      (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byType(TextField), 'https://evil.test/#access_token=secret-value');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('yandex-connect')));
    await settle(tester);
    expect(find.byKey(const ValueKey('yandex-error')), findsOneWidget);
    expect(find.textContaining('secret-value'), findsNothing);
    expect(transport.requests, isEmpty);
  });
  testWidgets(
      'token help opens only on explicit action and has a failure fallback',
      (tester) async {
    var opened = 0;
    await pump(tester, help: () async {
      opened++;
      throw StateError('browser-unavailable-secret');
    });
    expect(opened, 0);
    await tester.tap(find.text('Как получить токен'));
    await settle(tester);
    expect(opened, 1);
    expect(
        find.text('Инструкция: https://ym.marshal.dev/token/'), findsOneWidget);
    expect(find.textContaining('browser-unavailable-secret'), findsNothing);
  });
  testWidgets('narrow screen with enlarged text supports long playlist names',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    transport.onGet = (request, _) async =>
        request.endpoint == YandexReadEndpoint.likedPlaylists
            ? []
            : request.endpoint == YandexReadEndpoint.account
                ? yandexStatus()
                : [
                    yandexList()
                      ..['title'] = 'Очень длинное название плейлиста ' * 15
                  ];
    await pump(tester, scale: 2);
    await tester.runAsync(() => c.connect('synthetic-token'));
    await settle(tester);
    expect(c.failure, isNull);
    expect(find.textContaining('Очень длинное название плейлиста'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(c.disconnect);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'catalogue error keeps verified account visible and retry needs no token',
      (tester) async {
    transport.onGet = (request, _) async =>
        request.endpoint == YandexReadEndpoint.account
            ? yandexStatus()
            : [yandexList(kind: 'invalid')];
    await pump(tester);
    await tester.runAsync(() => c.connect('synthetic-token'));
    await settle(tester);
    expect(find.byKey(const ValueKey('yandex-account')), findsOneWidget);
    expect(find.text('Мне нравится'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('yandex-error')), findsOneWidget);
    expect(store.writes, 1);
    transport.onGet = null;
    await tester.tap(find.byKey(const ValueKey('yandex-catalogue')));
    await settle(tester);
    expect(find.byKey(const ValueKey('yandex-error')), findsNothing);
    expect(find.text('Мой плейлист'), findsOneWidget);
    expect(store.writes, 1);
  });
  testWidgets('saved foreign playlist is a separate unselected choice',
      (tester) async {
    transport.onGet = (r, _) async => switch (r.endpoint) {
          YandexReadEndpoint.account => yandexStatus(),
          YandexReadEndpoint.playlists => [yandexList()],
          YandexReadEndpoint.likedPlaylists => [
              {'playlist': yandexList(uid: 202)}
            ],
          _ => throw StateError('Unexpected request'),
        };
    await pump(tester);
    await tester.runAsync(() => c.connect('synthetic-token'));
    await settle(tester);
    expect(find.text('Мой плейлист'), findsNWidgets(2));
    final saved = find.widgetWithText(
        CheckboxListTile, 'Сохранённый плейлист\nПозиций в плейлисте: 3');
    expect(tester.widget<CheckboxListTile>(saved).value, isFalse);
    await tester.tap(saved);
    await settle(tester);
    expect(
        c.choices
            .singleWhere((choice) => choice.key.ownerId == '202')
            .isSelected,
        isTrue);
  });
  testWidgets('large playlist catalogue builds only a bounded viewport',
      (tester) async {
    transport.onGet = (request, _) async =>
        request.endpoint == YandexReadEndpoint.likedPlaylists
            ? []
            : request.endpoint == YandexReadEndpoint.account
                ? yandexStatus()
                : List.generate(2000, (i) => yandexList(kind: i + 1));
    await pump(tester);
    await tester.runAsync(() => c.connect('synthetic-token'));
    await settle(tester);
    expect(c.choices, hasLength(2001));
    expect(find.byType(CheckboxListTile).evaluate().length, lessThan(25));
    await tester.drag(find.byKey(const ValueKey('yandex-collections')),
        const Offset(0, -20000));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(CheckboxListTile).evaluate().length, lessThan(25));
  });
  testWidgets('leaving screen cancels connection without closing service',
      (tester) async {
    transport.onGet = (_, control) async {
      final done = Completer<void>();
      control.addCancellationListener(done.complete);
      await done.future;
      control.throwIfCancelled();
      return null;
    };
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'synthetic-token');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('yandex-connect')));
    await tester.pump();
    expect(c.isBusy, isTrue);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('yandex-connect')))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(c.failure, YandexConnectionFailure.cancelled);
    expect(store.writes, 0);
    transport.onGet = null;
    await tester.runAsync(() => c.connect('synthetic-token'));
    expect(c.account, isNotNull);
  });
}
