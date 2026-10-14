import 'package:flutter/material.dart';

import '../player/playback_transitions.dart';

class PlaybackTransitionSettings extends StatefulWidget {
  const PlaybackTransitionSettings({super.key, required this.transitions});
  final PlaybackTransitions transitions;

  @override
  State<PlaybackTransitionSettings> createState() =>
      _PlaybackTransitionSettingsState();
}

class _PlaybackTransitionSettingsState
    extends State<PlaybackTransitionSettings> {
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.transitions.crossfadeDurationStream,
      initialData: widget.transitions.crossfadeDuration,
      builder: (context, snapshot) {
        final seconds = (snapshot.data ?? widget.transitions.crossfadeDuration)
                .inMilliseconds /
            1000;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Следующий трек подготавливается заранее.'),
            const SizedBox(height: 8),
            Text(seconds == 0
                ? 'Плавный переход выключен'
                : 'Плавный переход: ${seconds.toStringAsFixed(0)} с'),
            Slider(
              key: const ValueKey('crossfade-duration-slider'),
              value: seconds.clamp(0, 10),
              min: 0,
              max: 10,
              divisions: 10,
              label: seconds == 0 ? 'Выкл.' : '${seconds.toStringAsFixed(0)} с',
              onChanged: _saving
                  ? null
                  : (value) async {
                      setState(() {
                        _saving = true;
                        _error = null;
                      });
                      try {
                        await widget.transitions.setCrossfadeDuration(
                            Duration(seconds: value.round()));
                      } on Object {
                        if (mounted) {
                          setState(() => _error =
                              'Не удалось сохранить настройку перехода.');
                        }
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
            ),
            const Text('0 с — без наложения. Предзагрузка остаётся включённой. '
                'Плавный переход применяется при автоматической смене трека.'),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        );
      },
    );
  }
}
