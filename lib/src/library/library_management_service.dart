import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';
import 'library_scanner_service.dart';
import 'library_scan_control.dart';
import 'library_scan_metrics.dart';

typedef LibraryFolderScanner = Future<LibraryScanResult> Function(
  String folderPath,
);

typedef ControlledLibraryFolderScanner = Future<LibraryScanResult>
    Function(String folderPath, {required LibraryScanControl control});

final class NoEnabledLibraryFoldersException implements Exception {
  const NoEnabledLibraryFoldersException();

  @override
  String toString() {
    return 'Нет включённых папок с музыкой. Включите папку или добавьте новую '
        'перед пересканированием.';
  }
}

final class LibraryManagementService {
  LibraryManagementService({
    required LibraryRepository libraryRepository,
    required LibraryFolderScanner scanFolder,
    ControlledLibraryFolderScanner? controlledScanFolder,
    DateTime Function()? clock,
  })  : _libraryRepository = libraryRepository,
        _scanFolder = scanFolder,
        _controlledScanFolder = controlledScanFolder,
        _clock = clock ?? DateTime.now;

  final LibraryRepository _libraryRepository;
  final LibraryFolderScanner _scanFolder;
  final ControlledLibraryFolderScanner? _controlledScanFolder;
  final DateTime Function() _clock;

  Future<LibraryScanResult> rescanEnabledFolders(
      {LibraryScanControl? control}) async {
    if (control?.isCancellationRequested ?? false) {
      return LibraryScanResult.cancelled('');
    }
    final folders = await _libraryRepository.listFolders(
      includeDisabled: false,
    );
    if (control?.isCancellationRequested ?? false) {
      return LibraryScanResult.cancelled('');
    }
    if (folders.isEmpty) {
      throw const NoEnabledLibraryFoldersException();
    }

    return _scanFolders(folders, control: control);
  }

  Future<LibraryScanResult> rescanFolder(
    LibraryFolder folder, {
    LibraryScanControl? control,
  }) {
    return _scan(folder.path, control);
  }

  Future<LibraryScanResult> _scan(String path, LibraryScanControl? control) {
    if (control?.isCancellationRequested ?? false) {
      return Future.value(LibraryScanResult.cancelled(path));
    }
    final controlled = _controlledScanFolder;
    return control != null && controlled != null
        ? controlled(path, control: control)
        : _scanFolder(path);
  }

  Future<void> setFolderEnabled(
    LibraryFolder folder, {
    required bool isEnabled,
  }) async {
    final id = folder.id;
    if (id == null) {
      throw StateError(
        'Папка библиотеки должна быть сохранена перед обновлением.',
      );
    }

    // Folder enabled state excludes tracks from active-library queries without
    // deleting their rows, user state, or playback history.
    await _libraryRepository.setFolderEnabled(
      id,
      isEnabled: isEnabled,
      updatedAt: _clock(),
    );
  }

  Future<void> removeFolderFromLibrary(LibraryFolder folder) async {
    final id = folder.id;
    if (id == null) {
      throw StateError(
        'Папка библиотеки должна быть сохранена перед удалением.',
      );
    }
    if (folder.isEnabled) {
      throw StateError('Отключите папку перед удалением из библиотеки.');
    }

    // This removes only app database rows. It must never delete audio files or
    // directories from disk.
    final repository = _libraryRepository;
    if (repository is! LibraryFolderRemovalRepository) {
      throw UnsupportedError(
          'Хранилище не поддерживает безопасное удаление папки.');
    }
    await (repository as LibraryFolderRemovalRepository)
        .removeDisabledFolder(id);
  }

  Future<LibraryScanResult> _scanFolders(Iterable<LibraryFolder> folders,
      {LibraryScanControl? control}) async {
    final results = <LibraryScanResult>[];
    final items = folders.toList(growable: false);
    var processed = 0;
    var added = 0;
    var updated = 0;
    var errors = 0;
    var metrics = const LibraryScanMetrics();
    for (var index = 0; index < items.length; index++) {
      if (control?.isCancellationRequested ?? false) break;
      final folder = items[index];
      final number = index + 1;
      var folderActive = true;
      final folderControl = control == null
          ? null
          : LibraryScanControl(
              onProgress: (progress) {
                if (!folderActive) return;
                control.report(progress.withBatch(
                    number: number,
                    count: items.length,
                    processedBefore: processed,
                    addedBefore: added,
                    updatedBefore: updated,
                    errorsBefore: errors,
                    metricsBefore: metrics));
              },
            );
      void cancelFolder() => folderControl?.cancel();
      control?.addCancellationListener(cancelFolder);
      try {
        final result = await _scan(folder.path, folderControl);
        results.add(result);
        processed += result.processedFiles;
        added += result.addedTracks;
        updated += result.updatedTracks;
        errors += result.errors.length;
        metrics = LibraryScanMetrics.combine([metrics, result.metrics]);
        if (result.wasCancelled) break;
      } finally {
        folderActive = false;
        control?.removeCancellationListener(cancelFolder);
      }
    }
    final combined = LibraryScanResult.combine(results);
    if (!(control?.isCancellationRequested ?? false) || combined.wasCancelled) {
      return combined;
    }
    return LibraryScanResult(
        folderPath: combined.folderPath,
        scannedFiles: combined.scannedFiles,
        addedTracks: combined.addedTracks,
        updatedTracks: combined.updatedTracks,
        missingTracks: combined.missingTracks,
        errors: combined.errors,
        processedFiles: combined.processedFiles,
        metrics: combined.metrics,
        wasCancelled: true);
  }
}
