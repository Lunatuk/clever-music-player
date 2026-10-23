import 'package:flutter/material.dart';

import 'design_preview_canvas.dart';
import 'design_preview_model.dart';

final class DesignPreviewScreen extends StatefulWidget {
  const DesignPreviewScreen({super.key});
  @override
  State<DesignPreviewScreen> createState() => _DesignPreviewScreenState();
}

final class _DesignPreviewScreenState extends State<DesignPreviewScreen> {
  PreviewDirection _direction = PreviewDirection.graphite;
  PreviewPage _page = PreviewPage.library;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Варианты дизайна')),
      body: SafeArea(
          top: false,
          child: LayoutBuilder(builder: (context, box) {
            final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
            final minimumHeight =
                box.maxHeight < 550 || largeText ? 1000.0 : box.maxHeight;
            final content = Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          for (final direction in PreviewDirection.values)
                            ChoiceChip(
                                label: Text(
                                    '${direction.code} · ${direction.label}'),
                                selected: direction == _direction,
                                onSelected: (_) =>
                                    setState(() => _direction = direction))
                        ]),
                        const SizedBox(height: 8),
                        Text(_direction.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall),
                        DropdownButton<PreviewPage>(
                            isExpanded: true,
                            value: _page,
                            onChanged: (v) {
                              if (v != null) setState(() => _page = v);
                            },
                            items: const [
                              DropdownMenuItem(
                                  value: PreviewPage.library,
                                  child: Text('Медиатека')),
                              DropdownMenuItem(
                                  value: PreviewPage.player,
                                  child: Text('Плеер')),
                              DropdownMenuItem(
                                  value: PreviewPage.queue,
                                  child: Text('Очередь')),
                            ]),
                        const Text(
                            'Демо-коллекция. Кнопки меняют макет; музыка не запускается.',
                            style: TextStyle(fontSize: 11)),
                      ])),
              Expanded(
                  child: ClipRect(
                      child: DesignPreviewCanvas(
                          direction: _direction,
                          initialPage: _page,
                          onPageChanged: (v) => setState(() => _page = v)))),
            ]);
            if (minimumHeight <= box.maxHeight) return content;
            return SingleChildScrollView(
                child: SizedBox(height: minimumHeight, child: content));
          })));
}
