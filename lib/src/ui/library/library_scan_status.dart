import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../library/library_controller.dart';
import '../../library/library_scan_control.dart';
import '../../library/library_scan_metrics.dart';

/// Command state and file progress subscribe independently of the music list.
final class LibraryScanStatus extends StatelessWidget {
  const LibraryScanStatus({required this.controller, this.error, super.key});
  final LibraryController controller;
  final Object? error;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _buildStatus(context),
      );

  Widget _buildStatus(BuildContext context) {
    final state = controller.state;
    final scheme = Theme.of(context).colorScheme;
    final subtle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        );
    if (state.isScanning) {
      return ValueListenableBuilder<LibraryScanProgress?>(
        valueListenable: controller.scanProgress,
        builder: (context, progress, _) {
          final size = progress?.fileSizeBytes;
          final fraction = !state.isCancelling &&
                  progress?.stage == LibraryScanStage.hashing &&
                  size != null &&
                  size > 0
              ? (progress!.fileBytesRead / size).clamp(0.0, 1.0)
              : null;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                          state.isCancelling
                              ? 'Останавливаем сканирование…'
                              : 'Сканируются локальные папки…',
                          style: subtle),
                      TextButton.icon(
                        onPressed: state.canCancelScan
                            ? () {
                                controller.cancelScan();
                              }
                            : null,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: Text(state.isCancelling
                            ? 'Остановка…'
                            : 'Остановить сканирование'),
                      ),
                    ]),
                if (progress != null) ...[
                  Text(
                      'Папка ${progress.folderNumber} из ${progress.folderCount}: '
                      '${p.basename(progress.folderPath)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtle),
                  Text(
                      'Обработано файлов: ${progress.processedFiles} · '
                      'Добавлено: ${progress.addedTracks} · Обновлено: ${progress.updatedTracks} · '
                      'Ошибок: ${progress.errorCount}',
                      style: subtle),
                  if (progress.metrics.elapsedUs > 0)
                    Text(_speedLabel(progress.processedFiles, progress.metrics),
                        style: subtle),
                  if (!state.isCancelling)
                    Text(
                      '${_stageLabel(progress.stage)}'
                      '${progress.fileName == null ? '' : ': ${progress.fileName}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtle,
                    ),
                ],
                if (state.isCancelling)
                  Text(
                      'Завершаем текущую операцию и сохраняем обработанные результаты.',
                      style: subtle),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: fraction),
              ]);
        },
      );
    }
    final failure = state.error ?? error;
    if (failure != null) {
      return Text('$failure', style: TextStyle(color: scheme.error));
    }
    final result = state.lastScanResult;
    if (result == null) {
      return Text('Сканирование ещё не запускалось.', style: subtle);
    }
    final visibleErrors = result.errors.take(3).toList(growable: false);
    final remaining = result.errors.length - visibleErrors.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(result.summary, style: subtle),
      if (result.metrics.elapsedUs > 0)
        Text(_speedLabel(result.processedFiles, result.metrics), style: subtle),
      const SizedBox(height: 4),
      for (final item in visibleErrors)
        Text('${item.path}: ${item.message}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.error)),
      if (remaining > 0)
        Text('Ещё ошибок сканирования: $remaining.',
            style: TextStyle(color: scheme.error)),
    ]);
  }
}

String _speedLabel(int files, LibraryScanMetrics metrics) {
  final seconds = metrics.elapsedUs / 1000000;
  final mib = metrics.hashedBytes / (1024 * 1024);
  return 'Время: ${seconds.toStringAsFixed(1)} с · '
      '${(files / seconds).toStringAsFixed(1)} файлов/с · '
      'Проверено: ${mib.toStringAsFixed(1)} МиБ '
      '(${(mib / seconds).toStringAsFixed(1)} МиБ/с)';
}

String _stageLabel(LibraryScanStage stage) => switch (stage) {
      LibraryScanStage.discovering => 'Обход папки',
      LibraryScanStage.hashing => 'Проверка содержимого файла',
      LibraryScanStage.readingMetadata => 'Чтение метаданных',
      LibraryScanStage.saving => 'Сохранение трека',
      LibraryScanStage.finishing => 'Сохранение результатов обхода',
    };
