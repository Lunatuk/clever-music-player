import 'dart:async';
import 'package:flutter/material.dart';
import '../../appearance/appearance_controller.dart';
import '../../appearance/appearance_settings.dart';
import '../../appearance/appearance_settings_screen.dart';
import '../../appearance/appearance_theme.dart';
import 'design_preview_canvas.dart';
import 'design_preview_model.dart';

final class DesignPreviewScreen extends StatefulWidget {
  const DesignPreviewScreen({super.key, this.appearance});
  final AppearanceController? appearance;
  @override
  State<DesignPreviewScreen> createState() => _DesignPreviewScreenState();
}

final class _DesignPreviewScreenState extends State<DesignPreviewScreen> {
  late final _appearance = widget.appearance ?? AppearanceController();
  PreviewPage _page = PreviewPage.home;
  @override
  void initState() {
    super.initState();
    unawaited(_appearance.initialize());
  }

  @override
  void dispose() {
    if (widget.appearance == null) _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _appearance,
      builder: (context, _) {
        final value = _appearance.value;
        final brightness = value.mode == AppearanceMode.system
            ? MediaQuery.platformBrightnessOf(context)
            : value.mode == AppearanceMode.light
                ? Brightness.light
                : Brightness.dark;
        return Theme(
            data: createAppearanceTheme(value, brightness),
            child: Builder(
                builder: (context) => Scaffold(
                      appBar: AppBar(
                          title: const Text('Макет интерфейса'),
                          actions: [
                            IconButton(
                                tooltip: 'Настроить оформление',
                                icon: const Icon(Icons.palette_outlined),
                                onPressed: () => Navigator.of(context).push(
                                    appearanceRoute(
                                        context,
                                        (_) => AppearanceSettingsScreen(
                                            controller: _appearance))))
                          ]),
                      body: SafeArea(
                          top: false,
                          child: LayoutBuilder(builder: (context, box) {
                            final height = box.maxHeight < 550 ||
                                    MediaQuery.textScalerOf(context).scale(14) >
                                        21
                                ? 1000.0
                                : box.maxHeight;
                            final content = Column(children: [
                              Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Column(children: [
                                    DropdownButton<PreviewPage>(
                                        value: _page,
                                        isExpanded: true,
                                        items: [
                                          for (final e in const {
                                            PreviewPage.home: 'Главная',
                                            PreviewPage.library: 'Коллекция',
                                            PreviewPage.player: 'Плеер',
                                            PreviewPage.queue: 'Очередь'
                                          }.entries)
                                            DropdownMenuItem(
                                                value: e.key,
                                                child: Text(e.value))
                                        ],
                                        onChanged: (v) {
                                          if (v != null) {
                                            setState(() => _page = v);
                                          }
                                        }),
                                    const Padding(
                                        padding: EdgeInsets.only(bottom: 8),
                                        child: Text(
                                            'Демо-коллекция. Кнопки макета не управляют настоящей музыкой.',
                                            style: TextStyle(fontSize: 11))),
                                  ])),
                              Expanded(
                                  child: ClipRect(
                                      child: DesignPreviewCanvas(
                                          appearance: value,
                                          initialPage: _page,
                                          onPageChanged: (v) =>
                                              setState(() => _page = v)))),
                            ]);
                            return height <= box.maxHeight
                                ? content
                                : SingleChildScrollView(
                                    child: SizedBox(
                                        height: height, child: content));
                          })),
                    )));
      });
}
