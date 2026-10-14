import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';

// Lightweight state for service/widget tests. Transaction, concurrency, retry
// and rollback guarantees are tested against SQLite, not against these fakes.
Future<TrackUserState> toggleTestFeedback(
  TrackUserStateRepository repository,
  int trackId,
  TrackFeedback feedback,
  DateTime updatedAt,
) async {
  final existing = await repository.findByTrackId(trackId);
  final state = _state(
    existing,
    trackId,
    updatedAt,
    isFavorite: feedback == TrackFeedback.like &&
        !(existing?.isFavorite == true && existing?.isHidden != true),
    isHidden: feedback == TrackFeedback.dislike &&
        !(existing?.isHidden == true && existing?.isFavorite != true),
    clearRating: true,
  );
  await repository.upsertState(state);
  return state;
}

Future<int> recordTestEvent(
  PlaybackEventRepository events,
  TrackUserStateRepository? states,
  PlaybackEvent event,
) async {
  final previous = await events.recentEvents(limit: 10000);
  final duplicate = previous.where(
    (saved) => saved.operationId == event.operationId,
  );
  if (duplicate.isNotEmpty) return duplicate.first.id ?? 0;
  final id = await events.addEvent(event);
  if (states != null &&
      const {
        PlaybackEventType.started,
        PlaybackEventType.completed,
        PlaybackEventType.skipped,
      }.contains(event.type)) {
    final existing = await states.findByTrackId(event.trackId);
    await states.upsertState(
      _state(existing, event.trackId, event.occurredAt, event: event),
    );
  }
  return id;
}

TrackUserState _state(
  TrackUserState? old,
  int id,
  DateTime now, {
  bool? isFavorite,
  bool? isHidden,
  bool clearRating = false,
  PlaybackEvent? event,
}) {
  return TrackUserState(
    trackId: id,
    isFavorite: isFavorite ?? old?.isFavorite ?? false,
    isHidden: isHidden ?? old?.isHidden ?? false,
    rating: clearRating ? null : old?.rating,
    playCount: (old?.playCount ?? 0) +
        (event?.type == PlaybackEventType.started ? 1 : 0),
    completeCount: (old?.completeCount ?? 0) +
        (event?.type == PlaybackEventType.completed ? 1 : 0),
    skipCount: (old?.skipCount ?? 0) +
        (event?.type == PlaybackEventType.skipped ? 1 : 0),
    lastPlayedAt:
        event?.type == PlaybackEventType.started ? now : old?.lastPlayedAt,
    lastCompletedAt:
        event?.type == PlaybackEventType.completed ? now : old?.lastCompletedAt,
    lastSkippedAt:
        event?.type == PlaybackEventType.skipped ? now : old?.lastSkippedAt,
    userScoreBoost: old?.userScoreBoost ?? 0,
    preferredWaveMode: old?.preferredWaveMode,
    updatedAt: now,
  );
}
