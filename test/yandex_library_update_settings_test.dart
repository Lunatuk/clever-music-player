import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clever_music_player/src/library_sync/yandex_download_runner.dart';
import 'package:clever_music_player/src/app/clever_music_player_app.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_update_controller.dart';
import 'package:clever_music_player/src/ui/yandex_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/library_update_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['CMP_EXPORT_UI_QA'] == null ||
        !Platform.isWindows) {
      return;
    }
    final font = FontLoader('UIQA');
    for (final file in ['segoeui.ttf', 'segoeuib.ttf']) {
      font.addFont(File('C:/Windows/Fonts/$file')
          .readAsBytes()
          .then((v) => ByteData.sublistView(v)));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then((v) => ByteData.sublistView(v)));
    await icons.load();
  });
  late LibraryUpdateFixture x;
  setUp(() async {
    x = await LibraryUpdateFixture.open();
    await x.ready();
  });
  tearDown(() async {
    await x.close();
  });

  Future<void> until(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (condition()) return;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    fail(
        'Expected progress: update=${x.updates.stage}, connection=${x.connection.activity}, requests=${x.transport.requests.length}, captures=${x.plans.captures}, applies=${x.plans.applies}');
  }

  Future<void> settle(WidgetTester tester) async {
    await until(tester, () => !x.updates.isBusy && !x.connection.isBusy);
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester,
      {double width = 900, double scale = 1, GlobalKey? boundary}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1100);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: CleverMusicPlayerApp.createDarkTheme(fontFamily: 'UIQA'),
        home: Scaffold(
            body: MediaQuery(
                data: MediaQueryData(
                    size: Size(width, 1100),
                    textScaler: TextScaler.linear(scale)),
                child: SingleChildScrollView(
                    child: RepaintBoundary(
                        key: boundary,
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: YandexSettings(
                                controller: x.connection,
                                updates: x.updates))))))));
    await settle(tester);
  }

  Finder field(String id) => find.byKey(ValueKey('yandex-update-$id'));
  Future<void> export(
      WidgetTester tester, GlobalKey boundary, String name) async {
    final directory = Platform.environment['CMP_EXPORT_UI_QA'];
    if (directory == null) return;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.runAsync(() => tester.tap(finder));
    await tester.pump();
  }

  Future<void> chooseQuality(WidgetTester tester) async {
    await tap(
        tester,
        find.descendant(
            of: field('quality'),
            matching: find.byType(DropdownButton<YandexUpdateQuality>)));
    await tester.pumpAndSettle();
    await tester
        .runAsync(() => tester.tap(find.text('FLAC · без потерь').last));
    await until(
        tester,
        () =>
            x.updates.quality == YandexUpdateQuality.flac ||
            x.updates.failure != null);
    await settle(tester);
  }

  testWidgets(
      'update options are visible with an explicit folder and default three-track limit',
      (tester) async {
    await pump(tester);
    expect(field('folder'), findsOneWidget);
    expect(find.text('MP3 · до 320 кбит/с'), findsOneWidget);
    expect(find.text('3 трека'), findsOneWidget);
    expect(tester.widget<FilledButton>(field('start')).onPressed, isNotNull);
    expect(x.fakeRunner.calls, 0);
    expect(x.transport.requests, isEmpty);
  });
  testWidgets('empty folder label stays above its hint in the production theme',
      (tester) async {
    await tester.runAsync(() async {
      await x.updates.close();
      await x.f.repositories.settings.writeString(
          YandexLibraryUpdateController.optionsKey,
          '{"version":1,"folder":null,"quality":"mp3","limit":3}');
      x.updates = x.newController();
    });
    final boundary = GlobalKey();
    await pump(tester, boundary: boundary);
    await tester.ensureVisible(field('folder'));
    await tester.pumpAndSettle();
    final label = tester.getRect(find.text('Папка для загрузок'));
    final hint = tester.getRect(find.text('Выбрать'));
    expect(label.bottom, lessThanOrEqualTo(hint.top));
    final decoration = tester.widget<InputDecorator>(find.descendant(
        of: field('folder'), matching: find.byType(InputDecorator)));
    expect(decoration.decoration.floatingLabelBehavior,
        FloatingLabelBehavior.always);
    expect(tester.takeException(), isNull);
    await export(tester, boundary, 'empty-folder');
  });
  testWidgets('M4A selection survives recreation and reaches the runner',
      (tester) async {
    await pump(tester);
    await tap(
        tester,
        find.descendant(
            of: field('quality'),
            matching: find.byType(DropdownButton<YandexUpdateQuality>)));
    await tester.pumpAndSettle();
    await tester
        .runAsync(() => tester.tap(find.text('M4A · AAC до 256 кбит/с').last));
    await until(tester, () => x.updates.quality == YandexUpdateQuality.m4a);
    await settle(tester);
    await tester.runAsync(() async {
      await x.updates.close();
      x.updates = x.newController();
    });
    await pump(tester);
    expect(x.updates.quality, YandexUpdateQuality.m4a);
    await tap(tester, field('start'));
    await settle(tester);
    expect(x.fakeRunner.selection, YandexUpdateQuality.m4a.selection);
  });
  testWidgets(
      'quality and all-jobs selection persist through controller recreation',
      (tester) async {
    await pump(tester);
    await chooseQuality(tester);
    expect(x.updates.quality, YandexUpdateQuality.flac);
    await tap(
        tester,
        find.descendant(
            of: field('limit'), matching: find.byType(DropdownButton<int>)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Все задания').last));
    await until(tester, () => x.updates.limit == 100000);
    await settle(tester);
    expect(x.updates.limit, 100000);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await x.updates.close();
      x.updates = x.newController();
      await x.updates.initialize();
    });
    await pump(tester);
    expect(find.text('FLAC · без потерь'), findsOneWidget);
    expect(find.text('Все задания'), findsOneWidget);
  });
  testWidgets(
      'failed preference write keeps the displayed and effective quality consistent',
      (tester) async {
    await tester.runAsync(() => x.f.database.customStatement(
        "CREATE TRIGGER reject_update_options BEFORE INSERT ON app_settings BEGIN SELECT RAISE(ABORT, 'synthetic'); END"));
    await pump(tester);
    await chooseQuality(tester);
    expect(x.updates.quality, YandexUpdateQuality.mp3);
    expect(find.text('MP3 · до 320 кбит/с'), findsOneWidget);
    expect(find.text('FLAC · без потерь'), findsNothing);
    expect(field('error'), findsOneWidget);
  });
  testWidgets(
      'button refreshes selected sources, queues new identities and passes selected scope',
      (tester) async {
    await pump(tester);
    await tap(tester, field('start'));
    await settle(tester);
    expect(x.fakeRunner.calls, 1);
    expect(x.fakeRunner.limit, 3);
    expect(x.fakeRunner.folder, x.f.folderId);
    expect(x.updates.planned, 2);
    expect(field('message'), findsOneWidget);
    expect(field('cancel'), findsNothing);
  });
  testWidgets(
      'active update shows progress, disables options and can be cancelled',
      (tester) async {
    final entered = Completer<void>(), release = Completer<void>();
    x.fakeRunner.onRun = (control, progress) async {
      progress!(const YandexDownloadRunProgress(
          YandexDownloadRunStage.processing, 1, 0));
      entered.complete();
      control.addCancellationListener(release.complete);
      await release.future;
      return const YandexDownloadRunResult(
          YandexDownloadRunOutcome.cancelled, 1, 0);
    };
    await pump(tester);
    await tap(tester, field('start'));
    await until(tester, () => entered.isCompleted);
    await tester.pump();
    expect(field('cancel'), findsOneWidget);
    expect(tester.widget<FilledButton>(field('start')).onPressed, isNull);
    expect(
        tester
            .widget<DropdownButton<YandexUpdateQuality>>(find.descendant(
                of: field('quality'),
                matching: find.byType(DropdownButton<YandexUpdateQuality>)))
            .onChanged,
        isNull);
    expect(find.textContaining('Записываю теги и обложку'), findsOneWidget);
    await tap(tester, field('cancel'));
    await settle(tester);
    expect(find.textContaining('Обновление остановлено.'), findsOneWidget);
    expect(field('cancel'), findsNothing);
  });
  testWidgets('leaving settings preserves an accepted background update',
      (tester) async {
    final entered = Completer<void>(), release = Completer<void>();
    x.fakeRunner.onRun = (_, __) async {
      entered.complete();
      await release.future;
      return const YandexDownloadRunResult(
          YandexDownloadRunOutcome.limited, 3, 3);
    };
    await pump(tester);
    await tap(tester, field('start'));
    await until(tester, () => entered.isCompleted);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(x.updates.isBusy, isTrue);
    expect(x.fakeRunner.cancellations, 0);
    release.complete();
    await settle(tester);
    await pump(tester);
    expect(find.textContaining('Добавлено треков: 3.'), findsOneWidget);
  });
  testWidgets('explicit retry checkbox is passed to planning', (tester) async {
    await pump(tester);
    await tap(tester, field('retry'));
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(field('retry')).value, isTrue);
    await tap(tester, field('start'));
    await settle(tester);
    expect(x.fakeRunner.calls, 1);
    expect(x.plans.lastPlan!.retryTerminalJobs, isTrue);
  });
  testWidgets(
      'Android-compatible view keeps account controls and omits Windows download options',
      (tester) async {
    await tester.runAsync(() async {
      await x.close();
      x = await LibraryUpdateFixture.open(supported: false);
    });
    await pump(tester);
    expect(find.textContaining('Загрузка музыки пока доступна на Windows'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('yandex-check')), findsOneWidget);
    expect(field('start'), findsNothing);
    expect(field('folder'), findsNothing);
  });
  for (final (width, scale) in [(360.0, 1.0), (360.0, 2.0), (1200.0, 1.0)]) {
    testWidgets(
        'options layout at $width pixels and text scale $scale has no overflow',
        (tester) async {
      final boundary = GlobalKey();
      await pump(tester, width: width, scale: scale, boundary: boundary);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(field('start'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await export(tester, boundary, 'update-${width.toInt()}-$scale');
    });
  }
}
