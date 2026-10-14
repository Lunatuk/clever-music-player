import '../domain/models/metadata_source.dart';
import '../library/filename_metadata_parser.dart';
import '../library/metadata_enrichment.dart';
import 'audio_documents.dart';

/// Apply the desktop metadata rules to SAF's display name, never to an opaque
/// document URI. Useful embedded fields take priority; guesses fill gaps only.
MergedMetadata mergeAudioDocumentMetadata(AudioDocumentMetadata document) {
  const parser = FilenameMetadataParser();
  final name = document.name?.trim();
  final hasName = name != null && name.isNotEmpty;
  // With no display name there is no better replacement for a generic title
  // such as "Track". Keep it as a low-confidence label, not an inferred identity.
  final fallback = hasName
      ? parser.fallback(name)
      : FilenameMetadataResult(
          title: normalizeMetadataText(document.title) ?? 'Без названия',
          confidence: 0.2,
          source: MetadataSource.fallback,
          patternMatched: 'unnamedDocument');
  return mergeMetadata(
      tagMetadata: EmbeddedAudioMetadata(
          title: document.title,
          artist: document.artist,
          album: document.album,
          albumArtist: document.albumArtist,
          genre: document.genre,
          duration: document.duration),
      filenameMetadata: hasName ? parser.parse(name) : fallback,
      fallbackMetadata: fallback);
}
