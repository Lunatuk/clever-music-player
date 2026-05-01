import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/filename_metadata_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = FilenameMetadataParser();

  test('parses artist dash title filenames', () {
    final result = parser.parse('BOOKER - Пора завязывать.mp3');

    expect(result.artist, 'BOOKER');
    expect(result.title, 'Пора завязывать');
    expect(result.source, MetadataSource.filename);
    expect(result.confidence, greaterThanOrEqualTo(0.6));
  });

  test('parses artist em dash title filenames', () {
    final result = parser.parse('Kendrick Lamar — Prayer instrumental.mp3');

    expect(result.artist, 'Kendrick Lamar');
    expect(result.title, 'Prayer instrumental');
    expect(result.source, MetadataSource.filename);
  });

  test('parses bracketed artist filenames', () {
    final result = parser.parse('[yayaheart] Мне 20 Hardstyle Remix.mp3');

    expect(result.artist, 'yayaheart');
    expect(result.title, 'Мне 20 Hardstyle Remix');
    expect(result.source, MetadataSource.filename);
  });

  test('does not invent artists for weak fallback filenames', () {
    final result = parser.parse('scars.mp3');

    expect(result.artist, isNull);
    expect(result.title, 'scars');
    expect(result.source, MetadataSource.fallback);
    expect(result.confidence, lessThanOrEqualTo(0.25));
  });

  test('keeps multi-underscore filenames as title guesses', () {
    final result = parser.parse(
      'SREZKA_Агата_Кристи_Как_На_Войне_SPEED_UP_REMIX.mp3',
    );

    expect(result.artist, isNull);
    expect(result.title, 'SREZKA Агата Кристи Как На Войне SPEED UP REMIX');
    expect(result.confidence, lessThan(0.5));
  });
}
