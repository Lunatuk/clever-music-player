import '../models/playback_event.dart';

abstract interface class PlaybackEventRepository {
  /// Insert imported history without changing counters. Do not use for playback.
  Future<int> addEvent(PlaybackEvent event);

  /// Atomically save a new event and its derived counters. Retrying the same
  /// operationId returns the existing event ID without counting it again.
  Future<int> recordEvent(PlaybackEvent event);

  Future<List<PlaybackEvent>> recentEvents({int limit = 100});

  Future<List<PlaybackEvent>> recentForTrack(int trackId, {int limit = 50});
}
