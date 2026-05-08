import '../models/track.dart';
import '../models/track_metadata_update.dart';

abstract interface class TrackRepository {
  Future<int> upsertTrack(Track track);

  Future<void> updateTrackMetadata(TrackMetadataUpdate metadata);

  Future<void> updateCustomArtwork({
    required int trackId,
    required String path,
    required String hash,
    required String? mimeType,
    required DateTime updatedAt,
  });

  Future<void> clearCustomArtwork({
    required int trackId,
    required DateTime updatedAt,
  });

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
