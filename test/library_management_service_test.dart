import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/library/library_management_service.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disabled folders are excluded from bulk rescan', () async {
    final repository = _FakeLibraryRepository([
      _folder(id: 1, path: '/music/enabled-a'),
      _folder(id: 2, path: '/music/disabled', isEnabled: false),
      _folder(id: 3, path: '/music/enabled-b'),
    ]);
    final tracks = _FakeTrackRepository();
    final scannedPaths = <String>[];
    final service = LibraryManagementService(
      libraryRepository: repository,
      trackRepository: tracks,
      scanFolder: (path) async {
        scannedPaths.add(path);
        return _scanResult(path);
      },
    );

    final result = await service.rescanEnabledFolders();

    expect(scannedPaths, ['/music/enabled-a', '/music/enabled-b']);
    expect(result.scannedFiles, 2);
  });

  test('rescan folder scans only the selected folder', () async {
    final repository = _FakeLibraryRepository([
      _folder(id: 1, path: '/music/a'),
      _folder(id: 2, path: '/music/b', isEnabled: false),
    ]);
    final tracks = _FakeTrackRepository();
    final scannedPaths = <String>[];
    final service = LibraryManagementService(
      libraryRepository: repository,
      trackRepository: tracks,
      scanFolder: (path) async {
        scannedPaths.add(path);
        return _scanResult(path);
      },
    );

    await service.rescanFolder(_folder(id: 2, path: '/music/b'));

    expect(scannedPaths, ['/music/b']);
  });

  test('repository persists folder enabled state updates', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final now = DateTime(2026);
    final id = await repositories.libraryFolders.upsertFolder(
      LibraryFolder(
        path: '/music',
        displayName: 'Music',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await repositories.libraryFolders.setFolderEnabled(
      id,
      isEnabled: false,
      updatedAt: now.add(const Duration(minutes: 1)),
    );
    var folders = await repositories.libraryFolders.listFolders();
    expect(folders.single.isEnabled, isFalse);

    await repositories.libraryFolders.setFolderEnabled(
      id,
      isEnabled: true,
      updatedAt: now.add(const Duration(minutes: 2)),
    );
    folders = await repositories.libraryFolders.listFolders();
    expect(folders.single.isEnabled, isTrue);
  });

  test('service enabling and disabling folder updates repository state',
      () async {
    final repository = _FakeLibraryRepository([
      _folder(id: 1, path: '/music'),
    ]);
    final tracks = _FakeTrackRepository();
    final service = LibraryManagementService(
      libraryRepository: repository,
      trackRepository: tracks,
      scanFolder: (path) async => _scanResult(path),
      clock: () => DateTime(2026, 5, 1),
    );

    await service.setFolderEnabled(
      repository.folders.single,
      isEnabled: false,
    );
    expect(repository.folders.single.isEnabled, isFalse);

    await service.setFolderEnabled(
      repository.folders.single,
      isEnabled: true,
    );
    expect(repository.folders.single.isEnabled, isTrue);
  });

  test('service removes disabled folder from database repositories', () async {
    final repository = _FakeLibraryRepository([
      _folder(id: 1, path: '/music/disabled', isEnabled: false),
    ]);
    final tracks = _FakeTrackRepository();
    final service = LibraryManagementService(
      libraryRepository: repository,
      trackRepository: tracks,
      scanFolder: (path) async => _scanResult(path),
    );

    await service.removeFolderFromLibrary(repository.folders.single);

    expect(tracks.deletedFolderIds, [1]);
    expect(repository.folders, isEmpty);
  });

  test('service requires disabling a folder before removal', () async {
    final repository = _FakeLibraryRepository([
      _folder(id: 1, path: '/music/enabled'),
    ]);
    final tracks = _FakeTrackRepository();
    final service = LibraryManagementService(
      libraryRepository: repository,
      trackRepository: tracks,
      scanFolder: (path) async => _scanResult(path),
    );

    await expectLater(
      service.removeFolderFromLibrary(repository.folders.single),
      throwsStateError,
    );
    expect(tracks.deletedFolderIds, isEmpty);
    expect(repository.folders, hasLength(1));
  });
}

LibraryScanResult _scanResult(String path) {
  return LibraryScanResult(
    folderPath: path,
    scannedFiles: 1,
    addedTracks: 0,
    updatedTracks: 1,
    missingTracks: 0,
    errors: const [],
  );
}

LibraryFolder _folder({
  required int id,
  required String path,
  bool isEnabled = true,
}) {
  final now = DateTime(2026);
  return LibraryFolder(
    id: id,
    path: path,
    displayName: path.split('/').last,
    isEnabled: isEnabled,
    createdAt: now,
    updatedAt: now,
  );
}

final class _FakeLibraryRepository implements LibraryRepository {
  _FakeLibraryRepository(List<LibraryFolder> folders)
      : folders = List.of(folders);

  final List<LibraryFolder> folders;

  @override
  Future<int> upsertFolder(LibraryFolder folder) async {
    final existingIndex = folders.indexWhere((item) => item.id == folder.id);
    if (existingIndex >= 0) {
      folders[existingIndex] = folder;
      return folder.id!;
    }

    final id = folder.id ?? folders.length + 1;
    folders.add(folder.copyWith(id: id));
    return id;
  }

  @override
  Future<LibraryFolder?> findFolderByPath(String path) async {
    for (final folder in folders) {
      if (folder.path == path) {
        return folder;
      }
    }
    return null;
  }

  @override
  Future<List<LibraryFolder>> listFolders({
    bool includeDisabled = true,
  }) async {
    return folders
        .where((folder) => includeDisabled || folder.isEnabled)
        .toList(growable: false);
  }

  @override
  Stream<List<LibraryFolder>> watchFolders({
    bool includeDisabled = true,
  }) {
    return Stream.value(
      folders
          .where((folder) => includeDisabled || folder.isEnabled)
          .toList(growable: false),
    );
  }

  @override
  Future<void> setFolderEnabled(
    int id, {
    required bool isEnabled,
    required DateTime updatedAt,
  }) async {
    final index = folders.indexWhere((folder) => folder.id == id);
    if (index < 0) {
      return;
    }
    folders[index] = folders[index].copyWith(
      isEnabled: isEnabled,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> deleteFolder(int id) async {
    folders.removeWhere((folder) => folder.id == id);
  }
}

final class _FakeTrackRepository implements TrackRepository {
  final deletedFolderIds = <int>[];

  @override
  Future<void> deleteTracksByLibraryFolder(int libraryFolderId) async {
    deletedFolderIds.add(libraryFolderId);
  }

  @override
  Future<void> deleteTrack(int id) async {}

  @override
  Future<Track?> findById(int id) async => null;

  @override
  Future<Track?> findByPath(String filePath) async => null;

  @override
  Future<Track?> findByStableId(String stableId) async => null;

  @override
  Future<List<Track>> listTracks({
    int limit = 100,
    int offset = 0,
    bool includeDisabledFolders = false,
  }) async {
    return const [];
  }

  @override
  Future<List<Track>> listTracksByLibraryFolder(
    int libraryFolderId, {
    bool includeMissing = true,
  }) async {
    return const [];
  }

  @override
  Future<int> upsertTrack(Track track) async => track.id ?? 0;

  @override
  Future<void> updateTrackMetadata(TrackMetadataUpdate metadata) async {}

  @override
  Stream<List<Track>> watchAllTracks({
    bool includeMissing = false,
    bool includeDisabledFolders = false,
  }) {
    return Stream.value(const []);
  }

  @override
  Stream<List<Track>> watchTracks({
    int limit = 100,
    bool includeDisabledFolders = false,
  }) {
    return Stream.value(const []);
  }
}
