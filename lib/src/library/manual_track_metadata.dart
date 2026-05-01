import '../domain/models/models.dart';

TrackMetadataUpdate buildManualTrackMetadataUpdate({
  required int trackId,
  required DateTime updatedAt,
  required String title,
  required String artist,
  required String album,
  required String albumArtist,
  required String genre,
  required String year,
  required String trackNumber,
  required String discNumber,
}) {
  final titleError = validateManualMetadataTitle(title);
  if (titleError != null) {
    throw FormatException(titleError);
  }

  final yearError = validateOptionalMetadataYear(year);
  if (yearError != null) {
    throw FormatException(yearError);
  }

  final trackNumberError = validateOptionalPositiveMetadataInteger(
    trackNumber,
    'Track number',
  );
  if (trackNumberError != null) {
    throw FormatException(trackNumberError);
  }

  final discNumberError = validateOptionalPositiveMetadataInteger(
    discNumber,
    'Disc number',
  );
  if (discNumberError != null) {
    throw FormatException(discNumberError);
  }

  return TrackMetadataUpdate(
    trackId: trackId,
    title: title.trim(),
    artist: normalizeOptionalManualMetadataText(artist),
    album: normalizeOptionalManualMetadataText(album),
    albumArtist: normalizeOptionalManualMetadataText(albumArtist),
    genre: normalizeOptionalManualMetadataText(genre),
    year: parseOptionalMetadataInteger(year),
    trackNumber: parseOptionalMetadataInteger(trackNumber),
    discNumber: parseOptionalMetadataInteger(discNumber),
    updatedAt: updatedAt,
  );
}

String? validateManualMetadataTitle(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return 'Title is required.';
  }
  return null;
}

String? validateOptionalMetadataYear(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return int.tryParse(trimmed) == null ? 'Enter a valid year.' : null;
}

String? validateOptionalPositiveMetadataInteger(
  String? value,
  String fieldLabel,
) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final parsed = int.tryParse(trimmed);
  if (parsed == null || parsed <= 0) {
    return '$fieldLabel must be a positive integer.';
  }
  return null;
}

String? normalizeOptionalManualMetadataText(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

int? parseOptionalMetadataInteger(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return int.parse(trimmed);
}
