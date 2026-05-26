import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';
import 'library_scanner_service.dart';

typedef LibraryFolderScanner = Future<LibraryScanResult> Function(
  String folderPath,
);

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
    required TrackRepository trackRepository,
    required LibraryFolderScanner scanFolder,
    DateTime Function()? clock,
  })  : _libraryRepository = libraryRepository,
        _trackRepository = trackRepository,
        _scanFolder = scanFolder,
        _clock = clock ?? DateTime.now;

  final LibraryRepository _libraryRepository;
  final TrackRepository _trackRepository;
  final LibraryFolderScanner _scanFolder;
  final DateTime Function() _clock;

  Future<LibraryScanResult> rescanEnabledFolders() async {
    final folders = await _libraryRepository.listFolders(
      includeDisabled: false,
    );
    if (folders.isEmpty) {
      throw const NoEnabledLibraryFoldersException();
    }

    return _scanFolders(folders);
  }

  Future<LibraryScanResult> rescanFolder(LibraryFolder folder) {
    return _scanFolder(folder.path);
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
    await _trackRepository.deleteTracksByLibraryFolder(id);
    await _libraryRepository.deleteFolder(id);
  }

  Future<LibraryScanResult> _scanFolders(
      Iterable<LibraryFolder> folders) async {
    final results = <LibraryScanResult>[];
    for (final folder in folders) {
      results.add(await _scanFolder(folder.path));
    }
    return LibraryScanResult.combine(results);
  }
}
