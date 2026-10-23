import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../diagnostics/diagnostics_service.dart';

/// Export only by explicit user action. The system picker saves a copy; no
/// external messages or broad storage permission, and no private path in UI.
final class AndroidDiagnosticsSettings extends StatefulWidget {
  const AndroidDiagnosticsSettings(
      {super.key, required this.diagnostics, this.save});
  final DiagnosticsService diagnostics;
  final Future<String?> Function(String, Uint8List)? save;
  @override
  State<AndroidDiagnosticsSettings> createState() =>
      _AndroidDiagnosticsSettingsState();
}

final class _AndroidDiagnosticsSettingsState
    extends State<AndroidDiagnosticsSettings> {
  bool _busy = false;
  String? _message;
  Future<void> _export() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final report = await widget.diagnostics.exportReport();
      final bytes = await report.readAsBytes();
      if (!mounted) return;
      final name = p.basename(report.path);
      final saved = await (widget.save?.call(name, bytes) ??
          FilePicker.platform.saveFile(
              fileName: name,
              type: FileType.custom,
              allowedExtensions: const ['json'],
              bytes: bytes));
      if (mounted) {
        setState(() => _message = saved == null
            ? 'Сохранение отменено.'
            : 'Отчёт сохранён. Его можно прикрепить к сообщению.');
      }
    } on Object {
      if (mounted) {
        setState(() => _message =
            'Не удалось сохранить отчёт. Проверь свободное место и повтори действие.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Диагностика', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
                'Отчёт содержит события и технические коды без названий музыки, путей и токена. Сохрани его и отправь только по своему решению.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.save_alt),
                label: const Text('Сохранить диагностический отчёт')),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null) Text(_message!),
          ])));
}
