import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../diagnostics/diagnostics_service.dart';

class DiagnosticsSettings extends StatefulWidget {
  const DiagnosticsSettings({
    super.key,
    required this.diagnostics,
    required this.openDirectory,
  });

  final DiagnosticsService diagnostics;
  final Future<void> Function(Directory directory) openDirectory;

  @override
  State<DiagnosticsSettings> createState() => _DiagnosticsSettingsState();
}

class _DiagnosticsSettingsState extends State<DiagnosticsSettings> {
  bool _busy = false;
  File? _report;
  String? _error;

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Не удалось выполнить действие. Проверь доступ к папке '
              'диагностики и свободное место, затем повтори.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Локальный журнал помогает разобраться в ошибках. Отчёт содержит '
          'события и технические коды без путей к музыке, названий треков '
          'и текста исключений. Отправляй его только по своему решению.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        final report = await widget.diagnostics.exportReport();
                        if (mounted) setState(() => _report = report);
                      }),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Создать диагностический отчёт'),
            ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await widget.openDirectory(
                            await widget.diagnostics.directory());
                      }),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Открыть папку диагностики'),
            ),
            if (_report != null)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() => widget.openDirectory(_report!.parent)),
                icon: const Icon(Icons.folder_outlined),
                label: const Text('Открыть папку отчёта'),
              ),
            if (_busy)
              const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        if (_report != null) ...[
          const SizedBox(height: 12),
          SelectableText('Отчёт сохранён: ${p.basename(_report!.path)}'),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
