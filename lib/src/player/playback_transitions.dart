import '../domain/models/track.dart';

/// Optional capability: basic PlayerService implementations need only one deck.
abstract interface class PlaybackTransitions {
  Duration get crossfadeDuration;
  Stream<Duration> get crossfadeDurationStream;
  Stream<Track> get automaticTransitionStream;

  Future<void> setCrossfadeDuration(Duration duration);
  Future<void> prepareNextTrack(Track? track);
  Future<void> playAutomatically(Track track);
}
