import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/filename_metadata_parser.dart';
import 'package:clever_music_player/src/library/metadata_enrichment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = FilenameMetadataParser();

  test('embedded tags win over filename parser', () {
    final merged = mergeMetadata(
      tagMetadata: const EmbeddedAudioMetadata(
        title: 'Tagged Title',
        artist: 'Tagged Artist',
        album: 'Tagged Album',
      ),
      filenameMetadata: parser.parse('Filename Artist - Filename Title.mp3'),
      fallbackMetadata: parser.fallback('Filename Artist - Filename Title.mp3'),
    );

    expect(merged.title, 'Tagged Title');
    expect(merged.artist, 'Tagged Artist');
    expect(merged.album, 'Tagged Album');
    expect(merged.source, MetadataSource.embeddedTags);
    expect(merged.confidence, greaterThanOrEqualTo(0.85));
  });

  test('filename parser fills missing artist when embedded title exists', () {
    final merged = mergeMetadata(
      tagMetadata: const EmbeddedAudioMetadata(title: 'Prayer instrumental'),
      filenameMetadata:
          parser.parse('Kendrick Lamar - Prayer instrumental.mp3'),
      fallbackMetadata: parser.fallback(
        'Kendrick Lamar - Prayer instrumental.mp3',
      ),
    );

    expect(merged.title, 'Prayer instrumental');
    expect(merged.artist, 'Kendrick Lamar');
    expect(merged.source, MetadataSource.embeddedTags);
  });

  test('duration is preserved from tags when visible metadata uses filename',
      () {
    final merged = mergeMetadata(
      tagMetadata: const EmbeddedAudioMetadata(
        duration: Duration(minutes: 2),
      ),
      filenameMetadata: parser.parse('Artist - Title.mp3'),
      fallbackMetadata: parser.fallback('Artist - Title.mp3'),
    );

    expect(merged.title, 'Title');
    expect(merged.artist, 'Artist');
    expect(merged.duration, const Duration(minutes: 2));
  });

  test('fallback works when tags and parser fail', () {
    final merged = mergeMetadata(
      tagMetadata: null,
      filenameMetadata: parser.parse('scars.mp3'),
      fallbackMetadata: parser.fallback('scars.mp3'),
    );

    expect(merged.title, 'scars');
    expect(merged.artist, isNull);
    expect(merged.source, MetadataSource.fallback);
    expect(merged.confidence, 0.2);
  });

  test('garbage and empty tags are ignored', () {
    final merged = mergeMetadata(
      tagMetadata: const EmbeddedAudioMetadata(
        title: '   ',
        artist: '<unknown>',
        album: '(www.lightaudio.ru)',
      ),
      filenameMetadata: parser.parse('BOOKER - Пора завязывать.mp3'),
      fallbackMetadata: parser.fallback('BOOKER - Пора завязывать.mp3'),
    );

    expect(merged.title, 'Пора завязывать');
    expect(merged.artist, 'BOOKER');
    expect(merged.album, isNull);
    expect(merged.source, MetadataSource.filename);
  });
}
