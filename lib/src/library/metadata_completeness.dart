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

  factory MetadataCompleteness.forTrack(Track track) =>
      MetadataCompleteness._fields(
          title: track.title,
          artist: track.artist,
          album: track.album,
          albumArtist: track.albumArtist,
          genre: track.genre,
          year: track.year,
          hasArtwork:
              _hasPath(track.customArtworkPath) || _hasPath(track.artworkPath));

  factory MetadataCompleteness.forEmbeddedTags(Map<String, String> tags,
          {required bool hasArtwork}) =>
      MetadataCompleteness._fields(
          title: tags['title'],
          artist: tags['artist'],
          album: tags['album'],
          albumArtist: tags['album_artist'],
          genre: tags['genre'],
          year: int.tryParse(RegExp(r'^([0-9]{4})(?:$|[-/])')
                  .firstMatch(tags['date'] ?? '')
                  ?.group(1) ??
              ''),
          hasArtwork: hasArtwork);

  factory MetadataCompleteness._fields(
          {String? title,
          String? artist,
          String? album,
          String? albumArtist,
          String? genre,
          int? year,
          required bool hasArtwork}) =>
      MetadataCompleteness._({
        if (_useful(title)) MetadataDetail.title,
        if (_useful(artist)) MetadataDetail.artist,
        if (_useful(album)) MetadataDetail.album,
        if (_useful(albumArtist)) MetadataDetail.albumArtist,
        if (_useful(genre)) MetadataDetail.genre,
        if (year != null && year > 0 && year <= 9999) MetadataDetail.year,
        if (hasArtwork) MetadataDetail.artwork,
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
