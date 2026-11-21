import 'package:flutter/material.dart';

import '../../domain/models/track.dart';
import '../../domain/models/audio_source_reference.dart';
import '../../library/library_track_variants.dart';
import '../track_metadata_subtitle.dart';

final class TrackVariantsButton extends StatelessWidget {
  const TrackVariantsButton({
    super.key,
    required this.group,
    required this.onPressed,
  });

  final LibraryTrackVariants group;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Варианты трека (${group.tracks.length})',
        onPressed: onPressed,
        icon: const Icon(Icons.layers_outlined),
      );
}

enum _VariantAction { play, prefer, reset, forgetAudioMatch }

Future<void> showTrackVariantsDialog(
  BuildContext context, {
  required LibraryTrackVariants group,
  required LibraryVariantRepository repository,
  required Future<void> Function(Track) play,
}) async {
  final matches = switch (repository) {
    final AudioMatchRepository value => value,
    _ => null,
  };
  final result = await showDialog<(Track?, _VariantAction)>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(group.representative.displayTitle),
      content: SizedBox(
        width: 480,
        height: (group.tracks.length * 94.0)
            .clamp(0.0, MediaQuery.sizeOf(context).height * 0.46),
        child: ListView.builder(
          itemCount: group.tracks.length,
          itemBuilder: (context, index) {
            final track = group.tracks[index];
            final preferred =
                group.preferredId != null && group.preferredId == track.id;
            final current = track == group.representative;
            final file = _displayPath(track);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(track.displayTitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  [
                    buildTrackMetadataSubtitle(track),
                    if (file.isNotEmpty) file,
                    if (track.isMissing) 'Файл недоступен',
                    if (current && !preferred) 'Выбрано автоматически',
                  ].join('\n'),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: preferred
                        ? 'Предпочитаемая версия'
                        : 'Предпочитать этот файл',
                    onPressed: track.isMissing || track.id == null || preferred
                        ? null
                        : () => Navigator.pop(
                            context, (track, _VariantAction.prefer)),
                    icon: Icon(
                        preferred ? Icons.bookmark : Icons.bookmark_border),
                  ),
                  IconButton(
                    tooltip: 'Воспроизвести эту версию',
                    onPressed: track.isMissing
                        ? null
                        : () => Navigator.pop(
                            context, (track, _VariantAction.play)),
                    icon: const Icon(Icons.play_arrow_outlined),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        if (group.audioMatches.isNotEmpty && matches != null)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, (null, _VariantAction.forgetAudioMatch)),
            child: const Text('Убрать связь по звуку'),
          ),
        if (group.preferredId != null)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, (null, _VariantAction.reset)),
            child: const Text('Выбирать автоматически'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
  if (result == null || !context.mounted) return;
  try {
    final (track, action) = result;
    switch (action) {
      case _VariantAction.play:
        await play(track!);
      case _VariantAction.prefer:
        await repository.setPreferred(group.identity, track!.id!);
      case _VariantAction.reset:
        await repository.setPreferred(group.identity, null);
      case _VariantAction.forgetAudioMatch:
        await matches?.forgetAudioMatches(group.audioMatches);
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Не удалось применить выбор версии трека.')));
    }
  }
}

String _displayPath(Track track) {
  final uri = AudioSourceReference.isContentUriValue(track.filePath)
      ? Uri.tryParse(track.filePath)
      : null;
  final path = uri == null
      ? track.filePath
      : (uri.pathSegments.isEmpty ? '' : uri.pathSegments.last);
  final parts = path.split(RegExp(r'[/\\]'));
  return parts.skip(parts.length > 2 ? parts.length - 2 : 0).join('/');
}
