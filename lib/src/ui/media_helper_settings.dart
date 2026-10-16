import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../library/library_scan_control.dart';
import '../library_sync/bundled_media_helper.dart';

typedef MediaHelperCheck = Future<String> Function(LibraryScanControl control);

class MediaHelperSettings extends StatefulWidget {
  const MediaHelperSettings(
      {super.key, required this.openDirectory, this.check});
  final Future<void> Function(Directory directory) openDirectory;
  final MediaHelperCheck? check;

  @override
  State<MediaHelperSettings> createState() => _MediaHelperSettingsState();
}

class _MediaHelperSettingsState extends State<MediaHelperSettings> {
  LibraryScanControl? _control;
  String? _message;
  bool _error = false;
  bool _opening = false;

  Future<String> _checkBundle(LibraryScanControl control) async {
    final helper = BundledMediaHelper.forCurrentProcess();
    try {
      return (await helper.qualify(control: control)).version;
    } finally {
      await helper.close();
    }
  }

  Future<void> _check() async {
    if (_control != null) return;
    final control = LibraryScanControl();
    setState(() {
      _control = control;
      _message = null;
      _error = false;
    });
    var error = false;
    String message;
    try {
      final version = await (widget.check ?? _checkBundle)(control);
      control.throwIfCancelled();
      message = 'Медиапомощник готов: FFmpeg $version. '
          'MP3, M4A, FLAC, теги и обложки поддерживаются.';
    } on LibraryScanCancelled {
      message = 'Проверка отменена.';
    } on MediaHelperException catch (failure) {
      error = true;
      message = switch (failure.failure) {
        MediaHelperFailure.missing =>
          'Медиапомощник отсутствует. Распакуй полный архив новой версии плеера.',
        MediaHelperFailure.invalidBundle =>
          'Комплект медиапомощника повреждён или неполон. '
              'Распакуй полный архив новой версии плеера в отдельную папку.',
        MediaHelperFailure.unsupportedPlatform =>
          'Медиапомощник пока доступен для Windows x64.',
        MediaHelperFailure.incompatible =>
          'Медиапомощник несовместим с этой версией плеера.',
        MediaHelperFailure.unavailable =>
          'Не удалось запустить медиапомощник. Проверь доступ к папке плеера.',
        MediaHelperFailure.timedOut =>
          'Медиапомощник не ответил вовремя. Можно повторить проверку.',
      };
    } on Object {
      error = true;
      message = 'Не удалось проверить медиапомощник. Можно повторить проверку.';
    }
    if (mounted) {
      setState(() {
        _control = null;
        _message = message;
        _error = error;
      });
    }
  }

  Future<void> _openLicenses() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.openDirectory(Directory(p.join(
          p.dirname(Platform.resolvedExecutable), 'tools', 'media-helper')));
    } on Object {
      if (mounted) {
        setState(() {
          _message = 'Не удалось открыть папку лицензий и исходников.';
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _control?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Медиапомощник подготавливает теги и обложки для будущей '
              'загрузки музыки. Проверка работает локально и не обращается '
              'к фонотеке или аккаунту.'),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: _control == null ? _check : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Проверить медиапомощник')),
            if (_control != null)
              TextButton(
                  onPressed: _control!.isCancellationRequested
                      ? null
                      : () => setState(() => _control!.cancel()),
                  child: const Text('Отменить проверку')),
            TextButton(
                onPressed: _opening ? null : _openLicenses,
                child: const Text('FFmpeg · LGPL 2.1+ · лицензия и исходники')),
          ]),
          if (_control != null) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!,
                style: _error
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null),
          ],
        ],
      );
}
