import 'dart:io';
import 'dart:ui' as ui;
import 'package:clever_music_player/src/appearance/appearance_settings.dart';
import 'package:clever_music_player/src/appearance/appearance_controller.dart';

import 'package:clever_music_player/src/ui/design_preview/design_preview_canvas.dart';
import 'package:clever_music_player/src/ui/design_preview/design_preview_model.dart';
import 'package:clever_music_player/src/ui/design_preview/design_preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final exportDirectory = Platform.environment['CMP_EXPORT_DESIGN_PREVIEW'];
  setUpAll(() async {
    if (exportDirectory == null || !Platform.isWindows) return;
    final font = FontLoader('PreviewQA');
    for (final file in ['segoeui.ttf', 'segoeuib.ttf']) {
      font.addFont(File('C:/Windows/Fonts/$file')
          .readAsBytes()
          .then((b) => ByteData.sublistView(b)));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then((b) => ByteData.sublistView(b)));
    await icons.load();
  });
  Future<void> export(WidgetTester tester, GlobalKey key, String name,
      {double ratio = 1.5}) async {
    if (exportDirectory == null) return;
    await tester.runAsync(() async {
      final render =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: ratio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await Directory(exportDirectory).create(recursive: true);
      await File('$exportDirectory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> pump(WidgetTester tester, Widget child,
      {double width = 390,
      double height = 844,
      double scale = 1,
      GlobalKey? key}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'PreviewQA'),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(body: RepaintBoundary(key: key, child: child))));
    await tester.pumpAndSettle();
  }

  for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
    for (final page in PreviewPage.values) {
      for (final desktop in [false, true]) {
        testWidgets(
            '${mode.name}/${page.name}/${desktop ? 'desktop' : 'phone'} render',
            (tester) async {
          final key = GlobalKey();
          await pump(
              tester,
              DesignPreviewCanvas(
                  appearance: AppearanceSettings(mode: mode),
                  initialPage: page,
                  fontFamily: 'PreviewQA'),
              width: desktop ? 1280 : 390,
              height: desktop ? 800 : 844,
              key: key);
          expect(tester.takeException(), isNull);
          await export(tester, key,
              '${mode.name}-${desktop ? 'desktop' : 'phone'}-${page.name}');
        });
      }
      testWidgets('${mode.name}/${page.name} 320px large text', (tester) async {
        await pump(
            tester,
            DesignPreviewCanvas(
                appearance: AppearanceSettings(mode: mode), initialPage: page),
            width: 320,
            height: 720,
            scale: 2);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'reference navigation, search, queue and local player remain isolated',
      (tester) async {
    await pump(tester, const DesignPreviewCanvas());
    await tester.tap(find.text('Коллекция').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('preview-search')), 'не найдено');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
    await tester.tap(find.byTooltip('Очистить поиск'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Очередь').last);
    await tester.pumpAndSettle();
    expect(find.text('Далее · 6'), findsOneWidget);
    await tester.tap(find.byTooltip('Убрать из очереди').first);
    await tester.pumpAndSettle();
    expect(find.text('Далее · 5'), findsOneWidget);
    await tester.tap(find.text('Очистить'));
    await tester.pumpAndSettle();
    expect(find.text('Очередь пуста'), findsOneWidget);
  });
  testWidgets('local seek, favorite, pause and return work', (tester) async {
    await pump(
        tester, const DesignPreviewCanvas(initialPage: PreviewPage.player));
    await tester.tap(find.byTooltip('Пауза'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Воспроизвести'), findsOneWidget);
    await tester.tap(find.byTooltip('Убрать из избранного'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('В избранное'), findsOneWidget);
    await tester.tap(find.byType(Slider));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('В медиатеку'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-search')), findsOneWidget);
  });
  testWidgets('same song twice has independent queue identities',
      (tester) async {
    await pump(
        tester, const DesignPreviewCanvas(initialPage: PreviewPage.library));
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Действия с треком').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Слушать следующим'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Очередь').last);
    await tester.pumpAndSettle();
    expect(find.text('Далее · 8'), findsOneWidget);
    await tester.tap(find.byTooltip('Убрать из очереди').first);
    await tester.pumpAndSettle();
    expect(find.text('Далее · 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('gallery page and appearance controls use shared controller',
      (tester) async {
    final controller = AppearanceController();
    await controller.initialize();
    addTearDown(controller.dispose);
    await pump(tester, DesignPreviewScreen(appearance: controller));
    await tester.tap(find.byType(DropdownButton<PreviewPage>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Очередь').last);
    await tester.pumpAndSettle();
    expect(find.text('Далее · 6'), findsOneWidget);
    await controller.update(controller.value.copyWith(
        mode: AppearanceMode.light, accentRgb: 0x70d9b4, compact: true));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DesignPreviewCanvas>(find.byType(DesignPreviewCanvas))
            .appearance,
        controller.value);
    expect(find.text('Далее · 6'), findsOneWidget);
  });
  for (final size in [const Size(320, 720), const Size(844, 390)]) {
    testWidgets('gallery at $size with 200% text', (tester) async {
      await pump(tester, const DesignPreviewScreen(),
          width: size.width, height: size.height, scale: 2);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('reference comparison sheet renders phone and desktop',
      (tester) async {
    final key = GlobalKey();
    await pump(
        tester,
        ColoredBox(
            color: const Color(0xffeaeaea),
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Clever Music Player · новая компоновка',
                          style: TextStyle(
                              fontSize: 28,
                              color: Colors.black,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const Text(
                          'По референсам пользователя · телефон и компьютер · вымышленные данные',
                          style: TextStyle(
                              fontSize: 14, color: Color(0xff505050))),
                      const SizedBox(height: 24),
                      Expanded(
                          child: Row(children: [
                        const SizedBox(
                            width: 390,
                            child:
                                DesignPreviewCanvas(fontFamily: 'PreviewQA')),
                        const SizedBox(width: 24),
                        Expanded(
                            child: FittedBox(
                                fit: BoxFit.contain,
                                child: const SizedBox(
                                    width: 1280,
                                    height: 800,
                                    child: DesignPreviewCanvas(
                                        fontFamily: 'PreviewQA')))),
                      ])),
                    ]))),
        width: 1500,
        height: 1000,
        key: key);
    expect(tester.takeException(), isNull);
    await export(tester, key, 'reference-layouts', ratio: 1);
  });
}
