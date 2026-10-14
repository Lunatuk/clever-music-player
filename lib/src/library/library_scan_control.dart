import 'library_scan_metrics.dart';

enum LibraryScanStage {
  discovering,
  hashing,
  readingMetadata,
  saving,
  finishing
}

final class LibraryScanProgress {
  const LibraryScanProgress({
    required this.folderPath,
    required this.stage,
    this.folderNumber = 1,
    this.folderCount = 1,
    this.processedFiles = 0,
    this.addedTracks = 0,
    this.updatedTracks = 0,
    this.errorCount = 0,
    this.fileName,
    this.fileBytesRead = 0,
    this.fileSizeBytes,
    this.metrics = const LibraryScanMetrics(),
  });

  final String folderPath;
  final LibraryScanStage stage;
  final int folderNumber;
  final int folderCount;
  final int processedFiles;
  final int addedTracks;
  final int updatedTracks;
  final int errorCount;
  final String? fileName;
  final int fileBytesRead;
  final int? fileSizeBytes;
  final LibraryScanMetrics metrics;

  LibraryScanProgress withBatch({
    required int number,
    required int count,
    required int processedBefore,
    required int addedBefore,
    required int updatedBefore,
    required int errorsBefore,
    LibraryScanMetrics metricsBefore = const LibraryScanMetrics(),
  }) =>
      LibraryScanProgress(
        folderPath: folderPath,
        stage: stage,
        folderNumber: number,
        folderCount: count,
        processedFiles: processedBefore + processedFiles,
        addedTracks: addedBefore + addedTracks,
        updatedTracks: updatedBefore + updatedTracks,
        errorCount: errorsBefore + errorCount,
        fileName: fileName,
        fileBytesRead: fileBytesRead,
        fileSizeBytes: fileSizeBytes,
        metrics: LibraryScanMetrics.combine([metricsBefore, metrics]),
      );
}

final class LibraryScanCancelled implements Exception {
  const LibraryScanCancelled();
}

/// Cooperative cancellation. Never abandons an in-flight database operation.
final class LibraryScanControl {
  LibraryScanControl({this.onProgress});

  final void Function(LibraryScanProgress)? onProgress;
  final _listeners = <void Function()>{};
  bool _cancelled = false;
  bool get isCancellationRequested => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList(growable: false)) {
      listener();
    }
    _listeners.clear();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const LibraryScanCancelled();
  }

  void addCancellationListener(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeCancellationListener(void Function() listener) =>
      _listeners.remove(listener);

  void report(LibraryScanProgress progress) {
    if (!_cancelled) onProgress?.call(progress);
  }
}
