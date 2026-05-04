import '../models/playlist.dart';

abstract interface class PlaylistRepository {
  Stream<List<PlaylistWithCount>> watchPlaylists();

  Future<int> createPlaylist(String name, {String? description});

  Future<void> renamePlaylist(int id, String name);

  Future<void> deletePlaylist(int id);

  Stream<List<PlaylistEntry>> watchPlaylistTracks(int playlistId);

  Future<void> addTrackToPlaylist(int playlistId, int trackId);

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId);
}
