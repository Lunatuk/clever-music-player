import 'package:flutter/material.dart';

import '../../domain/models/track.dart';
import '../../queue/queue_state.dart';
import '../track_display_helpers.dart';

final class QueuePanel extends StatelessWidget {
  const QueuePanel({
    super.key,
    required this.queueState,
    required this.onRemoveQueuedTrack,
    required this.onClearQueue,
    required this.onPlayQueuedTrackNow,
  });

  final QueueState queueState;
  final ValueChanged<int> onRemoveQueuedTrack;
  final VoidCallback onClearQueue;
  final ValueChanged<int> onPlayQueuedTrackNow;

  @override
  Widget build(BuildContext context) {
    final hasManualQueue = queueState.manualQueue.isNotEmpty;
    if (!hasManualQueue) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Очередь', style: textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: onClearQueue,
                  icon: const Icon(Icons.clear_all_outlined),
                  label: const Text('Очистить очередь'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var index = 0;
                index < queueState.manualQueue.length;
                index++) ...[
              _QueueTrackRow(
                track: queueState.manualQueue[index],
                leading: '${index + 1}',
                onPlayNow: () => onPlayQueuedTrackNow(index),
                onRemove: () => onRemoveQueuedTrack(index),
              ),
              if (index < queueState.manualQueue.length - 1)
                const Divider(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

final class _QueueTrackRow extends StatelessWidget {
  const _QueueTrackRow({
    required this.track,
    required this.leading,
    this.onPlayNow,
    this.onRemove,
  });

  final Track track;
  final String leading;
  final VoidCallback? onPlayNow;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            leading,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium,
              ),
              Text(
                artistLabel(track),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (onPlayNow != null) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Воспроизвести сейчас',
            onPressed: onPlayNow,
            icon: const Icon(Icons.play_arrow_outlined),
          ),
        ],
        if (onRemove != null) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Удалить из очереди',
            onPressed: onRemove,
            icon: const Icon(Icons.close_outlined),
          ),
        ],
      ],
    );
  }
}
