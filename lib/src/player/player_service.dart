import '../domain/models/track.dart';
import 'player_state.dart';

abstract interface class PlayerService {
  PlayerState get state;

  Track? get currentTrack;

  bool get isPlaying;

  Duration get position;

  Duration? get duration;

  double get volume;

  Stream<PlayerState> get stateStream;

  Future<void> playTrack(Track track);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seek(Duration position);

  Future<void> setVolume(double volume);

  Future<void> increaseVolume();

  Future<void> decreaseVolume();

  Future<void> toggleMute();

  Future<void> dispose();
}
