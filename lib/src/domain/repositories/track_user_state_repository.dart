import '../models/track_user_state.dart';

abstract interface class TrackUserStateRepository {
  Future<void> upsertState(TrackUserState state);

  Future<TrackUserState?> findByTrackId(int trackId);

  Future<Map<int, TrackUserState>> findByTrackIds(Iterable<int> trackIds);

  Stream<TrackUserState?> watchTrackState(int trackId);

  Future<void> deleteState(int trackId);
}
