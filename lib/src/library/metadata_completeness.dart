import '../domain/models/track.dart';
import 'metadata_enrichment.dart';

enum MetadataDetail {
  title('название'),
  artist('исполнитель'),
  album('альбом'),
  albumArtist('исполнитель альбома'),
  genre('жанр'),
  year('год'),
  artwork('обложка');

  const MetadataDetail(this.label);
  final String label;
}

/// Coverage of the current library card, including manual/inferred fields.
/// Neither a correctness score nor proof of embedded tags/file availability.
/// Reading this model never opens an audio file or checks artwork on disk.
final class MetadataCompleteness {
  MetadataCompleteness._(Set<MetadataDetail> present)
      : present = Set.unmodifiable(present);

  factory MetadataCompleteness.forTrack(Track track) => MetadataCompleteness._({
        if (_useful(track.title)) MetadataDetail.title,
        if (_useful(track.artist)) MetadataDetail.artist,
        if (_useful(track.album)) MetadataDetail.album,
        if (_useful(track.albumArtist)) MetadataDetail.albumArtist,
        if (_useful(track.genre)) MetadataDetail.genre,
        if (track.year != null && track.year! > 0 && track.year! <= 9999)
          MetadataDetail.year,
        if (_hasPath(track.customArtworkPath) || _hasPath(track.artworkPath))
          MetadataDetail.artwork,
      });

  final Set<MetadataDetail> present;
  int get count => present.length;
  int get total => MetadataDetail.values.length;
  Iterable<MetadataDetail> get missing =>
      MetadataDetail.values.where((field) => !present.contains(field));

  // Track/disc numbers depend on release context and are not mandatory fields.
  static bool _hasPath(String? value) => value?.trim().isNotEmpty ?? false;
  static bool _useful(String? value) =>
      isUsefulTag(value) &&
      !const {
        'без названия',
        'неизвестный трек',
        'неизвестный исполнитель',
        'неизвестный альбом',
      }.contains(normalizeMetadataText(value)?.toLowerCase());
}
