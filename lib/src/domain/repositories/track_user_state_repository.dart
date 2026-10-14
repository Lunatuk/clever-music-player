import '../models/track_user_state.dart';

abstract interface class TrackUserStateRepository {
  /// Replace a complete snapshot (imports/restore only). Interactive changes
  /// must use the atomic operations below to avoid overwriting newer data.
  Future<void> upsertState(TrackUserState state);

  /// Toggle using the latest stored feedback, preserving all listening data.
  Future<TrackUserState> toggleFeedback(
    int trackId,
    TrackFeedback feedback, {
    required DateTime updatedAt,
  });

  Future<TrackUserState?> findByTrackId(int trackId);

  Future<Map<int, TrackUserState>> findByTrackIds(Iterable<int> trackIds);

  Stream<TrackUserState?> watchTrackState(int trackId);

  Stream<Map<int, TrackUserState>> watchTrackStatesByTrackIds(
    Iterable<int> trackIds,
  );

  Future<void> deleteState(int trackId);
}
