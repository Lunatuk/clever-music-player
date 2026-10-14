import '../models/library_folder.dart';

abstract interface class LibraryRepository {
  Future<int> upsertFolder(LibraryFolder folder);

  Future<LibraryFolder?> findFolderByPath(String path);

  Future<List<LibraryFolder>> listFolders({bool includeDisabled = true});

  Stream<List<LibraryFolder>> watchFolders({bool includeDisabled = true});

  Future<void> setFolderEnabled(
    int id, {
    required bool isEnabled,
    required DateTime updatedAt,
  });

  Future<void> deleteFolder(int id);
}

/// Removes the folder and its owned track/user/playlist rows atomically.
/// Must check the current enabled flag inside the same transaction. A folder
/// already removed is a successful no-op. Never changes audio files on disk.
abstract interface class LibraryFolderRemovalRepository {
  Future<void> removeDisabledFolder(int id);
}
