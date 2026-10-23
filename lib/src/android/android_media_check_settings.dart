import 'package:flutter/material.dart';

import 'android_media_check_controller.dart';
import 'android_media_licenses.dart';

final class AndroidMediaCheckSettings extends StatefulWidget {
  const AndroidMediaCheckSettings({super.key, required this.controller});
  final AndroidMediaCheckController controller;
  @override
  State<AndroidMediaCheckSettings> createState() =>
      _AndroidMediaCheckSettingsState();
}

final class _AndroidMediaCheckSettingsState
    extends State<AndroidMediaCheckSettings> {
  @override
  void dispose() {
    widget.controller.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Подготовка музыки',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                        'Проверка тегов, обложек и звука на коротких встроенных '
                        'примерах MP3, M4A и FLAC. Твоя музыка не изменяется, интернет не нужен.'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                        onPressed: widget.controller.busy
                            ? null
                            : widget.controller.check,
                        icon: const Icon(Icons.library_music_outlined),
                        label: const Text('Проверить теги и обложки')),
                    if (widget.controller.busy) ...[
                      const LinearProgressIndicator(),
                      TextButton(
                          onPressed: widget.controller.cancel,
                          child: const Text('Остановить проверку')),
                    ],
                    if (widget.controller.message != null) ...[
                      const SizedBox(height: 8),
                      Text(widget.controller.message!),
                    ],
                    TextButton(
                        onPressed: widget.controller.busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const AndroidMediaLicenses())),
                        child: const Text('FFmpeg · лицензия и исходники')),
                  ]))));
}
