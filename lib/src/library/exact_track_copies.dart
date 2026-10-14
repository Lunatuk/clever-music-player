import '../domain/models/track.dart';
import 'file_content_hasher.dart';

/// A non-destructive view. Callers must first filter disabled folders/search.
/// Unknown hashes never authorize hiding a track. File records remain intact.
List<Track> withoutExactTrackCopies(Iterable<Track> tracks) {
  final result = <Track>[];
  final indexesByContent = <String, int>{};
  for (final track in tracks) {
    final key = verifiedFileContentKey(track.contentHash);
    if (key == null) {
      result.add(track);
      continue;
    }
    final index = indexesByContent[key];
    if (index == null) {
      indexesByContent[key] = result.length;
      result.add(track);
    } else if (_preferCopy(track, result[index])) {
      result[index] = track;
    }
  }
  return result;
}

bool _preferCopy(Track candidate, Track current) {
  if (candidate.isMissing != current.isMissing) return !candidate.isMissing;
  // Keep the original imported ID independent of sorting/stream order.
  final candidateId = candidate.id;
  final currentId = current.id;
  if (candidateId != currentId) {
    if (candidateId == null) return false;
    if (currentId == null) return true;
    return candidateId < currentId;
  }
  return candidate.filePath.compareTo(current.filePath) < 0;
}
