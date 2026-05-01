import '../models/track.dart';

abstract interface class TrackRepository {
  Future<int> upsertTrack(Track track);

  Future<Track?> findById(int id);

  Future<Track?> findByStableId(String stableId);

  Future<Track?> findByPath(String filePath);

  Future<List<Track>> listTracks({
    int limit = 100,
    int offset = 0,
    bool includeDisabledFolders = false,
  });

  Future<List<Track>> listTracksByLibraryFolder(
    int libraryFolderId, {
    bool includeMissing = true,
  });

  Stream<List<Track>> watchAllTracks({
    bool includeMissing = false,
    bool includeDisabledFolders = false,
  });

  Stream<List<Track>> watchTracks({
    int limit = 100,
    bool includeDisabledFolders = false,
  });

  Future<void> deleteTracksByLibraryFolder(int libraryFolderId);

  Future<void> deleteTrack(int id);
}
