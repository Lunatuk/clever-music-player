final class TrackMetadataUpdate {
  const TrackMetadataUpdate({
    required this.trackId,
    required this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    required this.updatedAt,
  });

  final int trackId;
  final String title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final DateTime updatedAt;
}
