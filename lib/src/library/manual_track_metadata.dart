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
    'Номер трека',
  );
  if (trackNumberError != null) {
    throw FormatException(trackNumberError);
  }

  final discNumberError = validateOptionalPositiveMetadataInteger(
    discNumber,
    'Номер диска',
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
    return 'Название обязательно.';
  }
  return null;
}

String? validateOptionalMetadataYear(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return int.tryParse(trimmed) == null ? 'Введите корректный год.' : null;
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
    return '$fieldLabel должен быть положительным целым числом.';
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
