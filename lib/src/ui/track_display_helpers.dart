import '../domain/models/track.dart';

String trackCountLabel(int count) {
  return '$count ${_ruPlural(count, one: 'трек', few: 'трека', many: 'треков')}';
}

String artistLabel(Track? track) {
  final artist = track?.artist?.trim();
  if (artist != null && artist.isNotEmpty) {
    return artist;
  }
  return track == null
      ? 'Выберите локальный трек для воспроизведения'
      : 'Неизвестный исполнитель';
}

bool isSameTrack(Track track, Track? other) {
  if (other == null) {
    return false;
  }
  if (track.id != null && other.id != null) {
    return track.id == other.id;
  }
  return track.filePath == other.filePath;
}

String _ruPlural(
  int count, {
  required String one,
  required String few,
  required String many,
}) {
  final mod100 = count.abs() % 100;
  if (mod100 >= 11 && mod100 <= 14) {
    return many;
  }
  return switch (count.abs() % 10) {
    1 => one,
    >= 2 && <= 4 => few,
    _ => many,
  };
}
