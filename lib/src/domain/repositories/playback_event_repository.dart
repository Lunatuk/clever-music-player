import '../models/playback_event.dart';

abstract interface class PlaybackEventRepository {
  Future<int> addEvent(PlaybackEvent event);

  Future<List<PlaybackEvent>> recentEvents({int limit = 100});

  Future<List<PlaybackEvent>> recentForTrack(int trackId, {int limit = 50});
}
