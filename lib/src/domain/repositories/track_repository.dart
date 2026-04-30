import '../models/track.dart';

abstract interface class TrackRepository {
  Future<int> upsertTrack(Track track);

  Future<Track?> findById(int id);

  Future<Track?> findByPath(String filePath);

  Future<List<Track>> listTracks({int limit = 100, int offset = 0});

  Stream<List<Track>> watchTracks({int limit = 100});

  Future<void> deleteTrack(int id);
}
