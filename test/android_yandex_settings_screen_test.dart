import 'dart:async';

import 'package:clever_music_player/src/android/android_download_storage_controller.dart';
import 'package:clever_music_player/src/android/android_media_check_controller.dart';
import 'package:clever_music_player/src/android/android_yandex_settings_screen.dart';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/library_update_fixture.dart';

void main() {
  late LibraryUpdateFixture x;
  late AndroidDownloadStorageController storage;
  late AndroidMediaCheckController media;
  setUp(() async {
    x = await LibraryUpdateFixture.open();
    storage = AndroidDownloadStorageController(
        settings: x.f.repositories.settings,
        onUseDestination: (_, __) async {},
        checkWorkspace: (_) async {});
    await storage.initialize();
    media = AndroidMediaCheckController(
        diagnostics: const NoopDiagnosticsService(),
        check: (_, __) async => '7.1.5');
  });
  tearDown(() async {
    await storage.close();
    storage.dispose();
    await media.close();
    media.dispose();
    await x.close();
  });
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (done()) return;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    fail('Expected state was not reached');
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.4)),
            child: child!),
        home: AndroidYandexSettingsScreen(
            connection: x.connection,
            updates: x.updates,
            storage: storage,
            media: media)));
    await until(tester, () => !x.updates.isBusy && !x.connection.isBusy);
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String label) =>
      tester
          .widget<ButtonStyleButton>(find
              .ancestor(
                  of: find.text(label),
                  matching:
                      find.byWidgetPredicate((w) => w is ButtonStyleButton))
              .first)
          .onPressed !=
      null;

  testWidgets(
      'opening route restores offline with enlarged narrow layout and one Android destination control',
      (tester) async {
    final before = x.transport.requests.length;
    await pump(tester);
    expect(x.updates.initialized, isTrue);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('yandex-update-folder')), findsNothing);
    expect(find.textContaining('Хранилище загрузок'), findsWidgets);
    expect(find.textContaining('ещё готовится'), findsNothing);
    expect(x.transport.requests.length, before);
    expect(x.fakeRunner.calls, 0);
    await tester.ensureVisible(find.text('Проверить теги и обложки'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'private check blocks update, folder changes and media check while its stop remains active',
      (tester) async {
    await storage.close();
    storage.dispose();
    final release = Completer<void>();
    storage = AndroidDownloadStorageController(
        settings: x.f.repositories.settings,
        onUseDestination: (_, __) async {},
        checkWorkspace: (_) => release.future);
    await storage.initialize();
    await pump(tester);
    final checking = storage.checkWorkspace();
    await tester.pump();
    expect(enabled(tester, 'Обновить библиотеку'), isFalse);
    expect(enabled(tester, 'Выбрать папку загрузок'), isFalse);
    expect(enabled(tester, 'Проверить теги и обложки'), isFalse);
    expect(enabled(tester, 'Остановить проверку'), isTrue);
    release.complete();
    await checking;
    await tester.pumpAndSettle();
    expect(enabled(tester, 'Выбрать папку загрузок'), isTrue);
  });
  testWidgets(
      'accepted update blocks storage but survives closing settings and exposes stop',
      (tester) async {
    await x.ready();
    final entered = Completer<void>(), release = Completer<void>();
    x.fakeRunner.onRun = (control, progress) async {
      entered.complete();
      await release.future;
      return const YandexDownloadRunResult(
          YandexDownloadRunOutcome.completed, 1, 1);
    };
    await pump(tester);
    await tester
        .ensureVisible(find.byKey(const ValueKey('yandex-update-start')));
    await tester.pump();
    await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('yandex-update-start'))));
    await until(tester, () => entered.isCompleted);
    expect(enabled(tester, 'Выбрать папку загрузок'), isFalse);
    expect(enabled(tester, 'Проверить теги и обложки'), isFalse);
    expect(enabled(tester, 'Остановить обновление'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(x.updates.isBusy, isTrue);
    expect(x.fakeRunner.cancellations, 0);
    release.complete();
    await until(tester, () => !x.updates.isBusy);
    expect(x.updates.failure, isNull);
  });
  testWidgets(
      'retained publication displays recovery instruction rather than invalid audio text',
      (tester) async {
    await x.ready();
    x.fakeRunner.onRun = (_, __) async => const YandexDownloadRunResult(
        YandexDownloadRunOutcome.failed, 1, 0,
        failure: YandexDownloadRunFailure.pipeline, needsReconciliation: true);
    await tester.runAsync(x.updates.start);
    await pump(tester);
    expect(
        find.textContaining('Осталась незавершённая запись'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
