import '../domain/models/models.dart';

String buildTrackMetadataSubtitle(Track track) {
  final artist = _nonEmpty(track.artist);
  final album = _nonEmpty(track.album);
  final codec = _nonEmpty(track.codec)?.toUpperCase();
  final metadataSource = track.metadataSource;
  final metadataLabel = metadataSource == null
      ? null
      : [
          metadataSource.displayLabel,
          if (track.metadataConfidence != null)
            track.metadataConfidence!.toStringAsFixed(2),
        ].join(' ');

  return [
    artist ?? 'Неизвестный исполнитель',
    album,
    codec,
    metadataLabel,
  ].whereType<String>().join(' · ');
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
