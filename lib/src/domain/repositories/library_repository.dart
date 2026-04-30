import '../models/library_folder.dart';

abstract interface class LibraryRepository {
  Future<int> upsertFolder(LibraryFolder folder);

  Future<List<LibraryFolder>> listFolders({bool includeDisabled = true});

  Stream<List<LibraryFolder>> watchFolders({bool includeDisabled = true});

  Future<void> deleteFolder(int id);
}
