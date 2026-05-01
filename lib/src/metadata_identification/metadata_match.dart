import '../domain/models/models.dart';

final class MetadataMatch {
  const MetadataMatch({
    required this.confidence,
    required this.source,
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.year,
    this.externalIds,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final int? year;
  final double confidence;
  final MetadataSource source;
  final Map<String, String>? externalIds;
}
