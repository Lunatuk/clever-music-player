import '../domain/models/track.dart';
import '../domain/models/audio_document_identity.dart';
import 'file_content_hasher.dart';

/// A non-destructive view. Callers must first filter disabled folders/search.
/// Unknown hashes never authorize hiding distinct documents. Different grants
/// to the very same provider/document are one source even without a hash.
/// File records, grants, user state and download receipts remain intact.
List<Track> withoutExactTrackCopies(Iterable<Track> tracks) {
  final result = <Track>[];
  final indexesByContent = <String, int>{};
  for (final track in withoutRepeatedAudioSources(tracks)) {
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

/// Collapse exact DocumentsContract aliases only, after visibility filtering.
/// Do not invent identities for arbitrary content providers or local files.
List<Track> withoutRepeatedAudioSources(Iterable<Track> tracks) {
  final result = <Track>[];
  final indexes = <AudioDocumentIdentity, int>{};
  for (final track in tracks) {
    final key = audioDocumentIdentity(track.filePath);
    if (key == null) {
      result.add(track);
      continue;
    }
    final index = indexes[key];
    if (index == null) {
      indexes[key] = result.length;
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
