import 'library_repository.dart';
import 'playback_event_repository.dart';
import 'playlist_repository.dart';
import 'settings_repository.dart';
import 'track_repository.dart';
import 'track_user_state_repository.dart';

abstract interface class AppRepositories {
  LibraryRepository get libraryFolders;

  TrackRepository get tracks;

  PlaybackEventRepository get playbackEvents;

  PlaylistRepository get playlists;

  TrackUserStateRepository get trackUserState;

  SettingsRepository get settings;

  Future<void> resetLearningState();
}
