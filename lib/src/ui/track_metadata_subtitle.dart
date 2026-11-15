import '../domain/models/models.dart';
import '../library/metadata_completeness.dart';

String buildTrackMetadataSubtitle(Track track) {
  final artist = _nonEmpty(track.artist);
  final album = _nonEmpty(track.album);
  final codec = _nonEmpty(track.codec)?.toUpperCase();

  return [
    artist ?? 'Неизвестный исполнитель',
    album,
    codec,
    track.metadataSource?.displayLabel,
    'сведения: ${buildMetadataCompletenessLabel(track)}',
  ].whereType<String>().join(' · ');
}

String buildMetadataCompletenessLabel(Track track) {
  final coverage = MetadataCompleteness.forTrack(track);
  return '${coverage.count}/${coverage.total}';
}

String buildMetadataCompletenessTooltip(Track track) {
  final coverage = MetadataCompleteness.forTrack(track);
  final missing = coverage.missing.map((field) => field.label).join(', ');
  return 'Сведения в карточке: ${coverage.count}/${coverage.total}. '
      'Источник: ${track.metadataSource?.displayLabel ?? 'не указан'}. '
      '${missing.isEmpty ? 'Все основные поля заполнены.' : 'Не заполнены: $missing.'}\n'
      'Учитываются сведения из тегов, имени файла и ручных правок. '
      'Заполненность не подтверждает правильность данных или наличие тегов в файле. '
      'Номера трека и диска необязательны.';
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
