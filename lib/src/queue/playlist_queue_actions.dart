import '../domain/models/models.dart';

Future<int> addPlaylistEntriesToQueue({
  required Iterable<PlaylistEntry> entries,
  required Future<void> Function(Track track) addToQueue,
}) async {
  var queuedCount = 0;
  for (final entry in entries) {
    if (!entry.isPlayable) {
      continue;
    }
    await addToQueue(entry.track);
    queuedCount++;
  }
  return queuedCount;
}
