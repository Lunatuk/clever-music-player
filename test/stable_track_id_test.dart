import 'package:clever_music_player/src/library/stable_track_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes stable id text parts', () {
    expect(normalizeStableIdPart('  The--Song!!  '), 'the song');
    expect(normalizeStableIdPart('LOCAL_TRACK 01'), 'local track 01');
    expect(normalizeStableIdPart(null), isEmpty);
  });

  test('stable id is deterministic across case and spacing differences', () {
    final first = generateStableTrackId(
      filePath: '/Music/A/The Song.mp3',
      title: 'The Song',
      artist: 'Local Artist',
      album: 'Local Album',
      fileSizeBytes: 1234,
      durationMs: 5000,
    );
    final second = generateStableTrackId(
      filePath: '/different/path.mp3',
      title: ' the--song ',
      artist: 'LOCAL   ARTIST',
      album: 'local_album',
      fileSizeBytes: 1234,
      durationMs: 5000,
    );

    expect(second, first);
  });

  test('stable id changes when identity metadata changes', () {
    final first = generateStableTrackId(
      filePath: '/Music/A/The Song.mp3',
      title: 'The Song',
      fileSizeBytes: 1234,
    );
    final second = generateStableTrackId(
      filePath: '/Music/A/The Song.mp3',
      title: 'The Song',
      fileSizeBytes: 5678,
    );

    expect(second, isNot(first));
  });

  test('stable id falls back to normalized file path without metadata', () {
    final first = generateStableTrackId(filePath: r'C:\Music\Song.mp3');
    final second = generateStableTrackId(filePath: 'c:/music/song.mp3');

    expect(second, first);
  });

  test('normalization preserves letters and digits from other writing systems',
      () {
    expect(
        normalizeStableIdPart('  Кино--Группа_крови!!  '), 'кино группа крови');
    expect(normalizeStableIdPart('東京 音楽 １２'), '東京 音楽 １２');
    expect(normalizeStableIdPart('العربية ١٢'), 'العربية ١٢');
    expect(normalizeStableIdPart('Cafe\u0301'), 'cafe\u0301');
    expect(normalizeStableIdPart('Кино\t  Группа\nкрови'), 'кино группа крови');
  });

  test('different Cyrillic titles do not have the same metadata signature', () {
    String signature(String title) => generateStableTrackId(
          filePath: '/music/song.mp3',
          title: title,
          artist: 'Кино',
          album: 'Группа крови',
          fileSizeBytes: 1234,
          durationMs: 5000,
        );

    expect(signature('Группа крови'), isNot(signature('Перемен')));
  });
}
