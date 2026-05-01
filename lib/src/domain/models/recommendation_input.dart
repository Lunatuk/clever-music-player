import 'playback_event.dart';
import 'track.dart';
import 'track_user_state.dart';
import 'wave_mode.dart';

final class RecommendationInput {
  RecommendationInput({
    required Iterable<Track> tracks,
    required Map<int, TrackUserState> userStates,
    required Iterable<PlaybackEvent> recentEvents,
    required this.waveMode,
    required this.limit,
    required this.generatedAt,
  })  : tracks = List.unmodifiable(tracks),
        userStates = Map.unmodifiable(userStates),
        recentEvents = List.unmodifiable(recentEvents);

  final List<Track> tracks;
  final Map<int, TrackUserState> userStates;
  final List<PlaybackEvent> recentEvents;
  final WaveMode waveMode;
  final int limit;
  final DateTime generatedAt;
}
