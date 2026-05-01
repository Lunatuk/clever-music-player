import '../domain/models/models.dart';
import 'filename_metadata_parser.dart';

final class EmbeddedAudioMetadata {
  const EmbeddedAudioMetadata({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.duration,
    this.trackNumber,
    this.discNumber,
    this.year,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final Duration? duration;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
}

final class MergedMetadata {
  const MergedMetadata({
    required this.title,
    required this.source,
    required this.confidence,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.duration,
    this.trackNumber,
    this.discNumber,
    this.year,
  });

  final String title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final Duration? duration;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final MetadataSource source;
  final double confidence;
}

bool isUsefulTag(String? value) {
  final normalized = normalizeMetadataText(value);
  if (normalized == null) {
    return false;
  }

  final lower = normalized.toLowerCase();
  const placeholders = {
    '<unknown>',
    'unknown',
    'unknown artist',
    'unknown album',
    'untitled',
    'n/a',
    'na',
    'null',
  };
  if (placeholders.contains(lower)) {
    return false;
  }

  if (RegExp(r'^(?:track|audio|song)\s*\d*$', caseSensitive: false)
      .hasMatch(normalized)) {
    return false;
  }

  return true;
}

String? normalizeMetadataText(String? value) {
  if (value == null) {
    return null;
  }

  final normalized = value
      .replaceAll('\u0000', ' ')
      .replaceAll(_domainNoisePattern, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(_separatorEdgesPattern, '')
      .trim();
  return normalized.isEmpty ? null : normalized;
}

MergedMetadata mergeMetadata({
  required EmbeddedAudioMetadata? tagMetadata,
  required FilenameMetadataResult filenameMetadata,
  required FilenameMetadataResult fallbackMetadata,
}) {
  final tagTitle = _usefulNormalizedTag(tagMetadata?.title);
  final tagArtist = _usefulNormalizedTag(tagMetadata?.artist);
  final tagAlbum = _usefulNormalizedTag(tagMetadata?.album);
  final tagAlbumArtist = _usefulNormalizedTag(tagMetadata?.albumArtist);
  final tagGenre = _usefulNormalizedTag(tagMetadata?.genre);

  final filenameTitle = _usefulText(filenameMetadata.title);
  final filenameArtist = _usefulText(filenameMetadata.artist);
  final filenameAlbum = _usefulText(filenameMetadata.album);
  final fallbackTitle = _usefulText(fallbackMetadata.title) ?? 'Unknown Track';

  final title = tagTitle ?? filenameTitle ?? fallbackTitle;
  final artist = tagArtist ?? filenameArtist;
  final album = tagAlbum ?? filenameAlbum;

  final tagIdentityCount = [
    tagTitle,
    tagArtist,
    tagAlbum,
  ].whereType<String>().length;
  final source = _mergedSource(
    tagIdentityCount: tagIdentityCount,
    filenameMetadata: filenameMetadata,
  );
  final confidence = _mergedConfidence(
    source: source,
    hasTagTitle: tagTitle != null,
    hasTagArtist: tagArtist != null,
    filenameConfidence: filenameMetadata.confidence,
    fallbackConfidence: fallbackMetadata.confidence,
  );

  return MergedMetadata(
    title: title,
    artist: artist,
    album: album,
    albumArtist: tagAlbumArtist,
    genre: tagGenre,
    duration: tagMetadata?.duration,
    trackNumber: tagMetadata?.trackNumber,
    discNumber: tagMetadata?.discNumber,
    year: tagMetadata?.year,
    source: source,
    confidence: confidence,
  );
}

String? _usefulNormalizedTag(String? value) {
  return isUsefulTag(value) ? normalizeMetadataText(value) : null;
}

String? _usefulText(String? value) {
  return normalizeMetadataText(value);
}

MetadataSource _mergedSource({
  required int tagIdentityCount,
  required FilenameMetadataResult filenameMetadata,
}) {
  if (tagIdentityCount > 0) {
    return MetadataSource.embeddedTags;
  }

  if (filenameMetadata.source == MetadataSource.filename) {
    return MetadataSource.filename;
  }

  return MetadataSource.fallback;
}

double _mergedConfidence({
  required MetadataSource source,
  required bool hasTagTitle,
  required bool hasTagArtist,
  required double filenameConfidence,
  required double fallbackConfidence,
}) {
  final confidence = switch (source) {
    MetadataSource.embeddedTags => hasTagTitle && hasTagArtist
        ? 0.95
        : hasTagTitle
            ? 0.88
            : 0.82,
    MetadataSource.filename => filenameConfidence,
    MetadataSource.fallback => fallbackConfidence,
    MetadataSource.manual => 1.0,
    MetadataSource.acousticFingerprint => 0.9,
  };

  return confidence.clamp(0.0, 1.0).toDouble();
}

final _domainNoisePattern = RegExp(
  r'[\(\[\{]?\s*(?:https?://)?(?:www\.)?[a-z0-9][a-z0-9-]*'
  r'(?:\.[a-z0-9][a-z0-9-]*)+\S*?\s*[\)\]\}]?',
  caseSensitive: false,
);
final _separatorEdgesPattern = RegExp(
  '^[\\s._\\-${String.fromCharCode(0x2013)}'
  '${String.fromCharCode(0x2014)}]+|'
  '[\\s._\\-${String.fromCharCode(0x2013)}'
  '${String.fromCharCode(0x2014)}]+\$',
);
