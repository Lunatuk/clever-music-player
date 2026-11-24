import '../domain/models/audio_document_identity.dart';
import '../domain/models/track.dart';
import 'exact_track_copies.dart';

const recordingCandidateLimit = 8;
const _durationTolerance = Duration(seconds: 2);
final _separators = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);

String _normalize(String? text) =>
    text?.toLowerCase().replaceAll(_separators, ' ').trim() ?? '';

/// Metadata only narrows the queue. It cannot confirm an audio match.
List<Track> selectRecordingCandidates(Track reference, Iterable<Track> tracks,
    {bool Function(Track)? alreadyKnown}) {
  final title = _normalize(reference.title);
  if (title.isEmpty || reference.isMissing) return const [];
  final artist = _normalize(reference.artist);
  final album = _normalize(reference.album);
  final document = audioDocumentIdentity(reference.filePath);
  final candidates =
      <({Track track, bool sameArtist, bool sameAlbum, Duration? gap})>[];
  for (final track in tracks) {
    if (track.isMissing ||
        track.filePath == reference.filePath ||
        _normalize(track.title) != title ||
        (document != null &&
            document == audioDocumentIdentity(track.filePath)) ||
        (alreadyKnown?.call(track) ?? false)) {
      continue;
    }
    final otherArtist = _normalize(track.artist);
    final sameArtist = artist.isNotEmpty && artist == otherArtist;
    if (artist.isNotEmpty && otherArtist.isNotEmpty && !sameArtist) continue;
    final left = reference.duration;
    final right = track.duration;
    final gap = left != null &&
            right != null &&
            left > Duration.zero &&
            right > Duration.zero
        ? (left - right).abs()
        : null;
    if (gap == null ? !sameArtist : gap > _durationTolerance) continue;
    candidates.add((
      track: track,
      sameArtist: sameArtist,
      sameAlbum: album.isNotEmpty && album == _normalize(track.album),
      gap: gap,
    ));
  }
  candidates.sort((left, right) {
    final artistOrder = (right.sameArtist ? 1 : 0) - (left.sameArtist ? 1 : 0);
    if (artistOrder != 0) return artistOrder;
    final gapOrder = (left.gap ?? _durationTolerance * 2)
        .compareTo(right.gap ?? _durationTolerance * 2);
    if (gapOrder != 0) return gapOrder;
    final albumOrder = (right.sameAlbum ? 1 : 0) - (left.sameAlbum ? 1 : 0);
    if (albumOrder != 0) return albumOrder;
    return left.track.filePath.compareTo(right.track.filePath);
  });
  final selected = withoutExactTrackCopies(
    [reference, for (final entry in candidates) entry.track],
    preferEquivalent: (track) => identical(track, reference),
  );
  return selected.where((track) => !identical(track, reference)).toList();
}
