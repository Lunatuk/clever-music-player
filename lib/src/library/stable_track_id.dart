import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../domain/models/audio_source_reference.dart';

/// A metadata signature for comparison, not a unique track identity.
///
/// Different files (including copies) may share this value. Persisted track IDs
/// and explicit file locations must be used when updating a library record.
String generateStableTrackId({
  required String filePath,
  String? title,
  String? artist,
  String? album,
  int? fileSizeBytes,
  int? durationMs,
}) {
  final titlePart = normalizeStableIdPart(title);
  final artistPart = normalizeStableIdPart(artist);
  final albumPart = normalizeStableIdPart(album);
  final sizePart = fileSizeBytes == null ? '' : fileSizeBytes.toString();
  final durationPart = durationMs == null ? '' : durationMs.toString();

  final hasMetadata = [
    titlePart,
    artistPart,
    albumPart,
    sizePart,
    durationPart,
  ].any((part) => part.isNotEmpty);

  final source = hasMetadata
      ? [
          'title:$titlePart',
          'artist:$artistPart',
          'album:$albumPart',
          'size:$sizePart',
          'duration:$durationPart',
        ].join('|')
      : AudioSourceReference.isContentUriValue(filePath)
          ? 'uri:$filePath'
          : 'path:${normalizeStableFilePath(filePath)}';

  return sha256.convert(utf8.encode(source)).toString();
}

String normalizeStableIdPart(String? value) {
  if (value == null) {
    return '';
  }

  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N} ]+', unicode: true), '')
      .trim();
}

String normalizeStableFilePath(String filePath) {
  return p.normalize(filePath).replaceAll('\\', '/').toLowerCase();
}
