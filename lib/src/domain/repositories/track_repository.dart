import '../models/track.dart';

abstract interface class TrackRepository {
  Future<int> upsertTrack(Track track);

  Future<Track?> findById(int id);

  Future<Track?> findByStableId(String stableId);

  Future<Track?> findByPath(String filePath);

  Future<List<Track>> listTracks({int limit = 100, int offset = 0});

  Future<List<Track>> listTracksByLibraryFolder(
    int libraryFolderId, {
    bool includeMissing = true,
  });

  Stream<List<Track>> watchAllTracks({bool includeMissing = false});

  Stream<List<Track>> watchTracks({int limit = 100});

  Future<void> deleteTrack(int id);
}
