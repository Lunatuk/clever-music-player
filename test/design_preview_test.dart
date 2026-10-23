import 'dart:io';
import 'dart:ui' as ui;

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

  for (final direction in PreviewDirection.values) {
    for (final page in PreviewPage.values) {
      for (final desktop in [false, true]) {
        testWidgets(
            '${direction.name}/${page.name}/${desktop ? 'desktop' : 'phone'} layout and visual export',
            (tester) async {
          final key = GlobalKey();
          await pump(
              tester,
              DesignPreviewCanvas(
                  direction: direction,
                  initialPage: page,
                  fontFamily: 'PreviewQA'),
              width: desktop ? 1280 : 390,
              height: desktop ? 800 : 844,
              key: key);
          expect(tester.takeException(), isNull);
          await export(tester, key,
              '${direction.code.toLowerCase()}-${desktop ? 'desktop' : 'phone'}-${page.name}');
        });
      }
      testWidgets(
          '${direction.name}/${page.name} 320px and large text remain usable',
          (tester) async {
        await pump(tester,
            DesignPreviewCanvas(direction: direction, initialPage: page),
            width: 320, height: 720, scale: 2);
        expect(tester.takeException(), isNull);
      });
    }
  }
  test('preview text and accent colors have readable contrast on both surfaces',
      () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
    }

    for (final d in PreviewDirection.values) {
      final c = d.colors;
      expect(contrast(c.text, c.background), greaterThanOrEqualTo(4.5));
      expect(contrast(c.muted, c.background), greaterThanOrEqualTo(4.5));
      expect(contrast(c.muted, c.panel), greaterThanOrEqualTo(4.5));
      expect(contrast(c.accent, c.background), greaterThanOrEqualTo(4.5));
    }
  });
  testWidgets(
      'demo search, play/pause, queue removal and empty state work without runtime dependencies',
      (tester) async {
    await pump(tester,
        const DesignPreviewCanvas(direction: PreviewDirection.graphite));
    await tester.enterText(
        find.byKey(const ValueKey('preview-search')), 'несуществующий запрос');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('preview-search')), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Пауза'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Воспроизвести'), findsOneWidget);
    await tester.tap(find.byTooltip('Открыть очередь'));
    await tester.pumpAndSettle();
    expect(find.text('Далее · 6'), findsOneWidget);
    await tester.tap(find.byTooltip('Убрать из очереди').first);
    await tester.pumpAndSettle();
    expect(find.text('Далее · 5'), findsOneWidget);
    await tester.tap(find.text('Очистить'));
    await tester.pumpAndSettle();
    expect(find.text('Очередь пуста'), findsOneWidget);
  });
  testWidgets(
      'full demo player supports local seek, favorite and returning to library',
      (tester) async {
    await pump(
        tester,
        const DesignPreviewCanvas(
            direction: PreviewDirection.paper,
            initialPage: PreviewPage.player));
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
    expect(find.text('Моя музыка'), findsOneWidget);
  });
  testWidgets(
      'gallery switches three directions and pages on a phone without resetting real app state',
      (tester) async {
    await pump(tester, const DesignPreviewScreen(), width: 390, height: 844);
    expect(find.textContaining('Демо-коллекция'), findsOneWidget);
    await tester.tap(find.text('B · Бумага'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DesignPreviewCanvas>(find.byType(DesignPreviewCanvas))
            .direction,
        PreviewDirection.paper);
    await tester.tap(find.byType(DropdownButton<PreviewPage>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Очередь').last);
    await tester.pumpAndSettle();
    expect(find.text('Далее · 6'), findsOneWidget);
    await tester.tap(find.text('C · Полночь'));
    await tester.pumpAndSettle();
    expect(find.text('Далее · 6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(320, 720), const Size(844, 390)]) {
    testWidgets('gallery controls remain usable with large text at $size',
        (tester) async {
      await pump(tester, const DesignPreviewScreen(),
          width: size.width, height: size.height, scale: 2);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('contact sheet renders all three complete phone layouts',
      (tester) async {
    final key = GlobalKey();
    await pump(
        tester,
        Theme(
            data: ThemeData(fontFamily: 'PreviewQA'),
            child: ColoredBox(
                color: const Color(0xffe9e6de),
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Clever Music Player · три направления',
                              style: TextStyle(
                                  fontSize: 29,
                                  color: Color(0xff282e29),
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          const Text(
                              'Одна коллекция · медиатека на телефоне · иллюстративные обложки',
                              style: TextStyle(
                                  fontSize: 14, color: Color(0xff60665f))),
                          const SizedBox(height: 20),
                          Expanded(
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                for (final d in PreviewDirection.values) ...[
                                  if (d.index != 0) const SizedBox(width: 18),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text('${d.code} · ${d.label}',
                                            style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xff282e29))),
                                        const SizedBox(height: 12),
                                        Expanded(
                                            child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                                child: DesignPreviewCanvas(
                                                    direction: d,
                                                    fontFamily: 'PreviewQA'))),
                                      ])),
                                ]
                              ])),
                        ])))),
        width: 1280,
        height: 1040,
        key: key);
    expect(tester.takeException(), isNull);
    await export(tester, key, 'three-directions', ratio: 1);
  });
}
