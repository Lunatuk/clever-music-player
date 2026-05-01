import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/metadata_enrichment.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('fallback metadata reader derives metadata from file', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_metadata_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final file = File(p.join(tempDirectory.path, 'Local Track.M4A'));
    await file.writeAsBytes([1, 2, 3, 4]);

    final metadata = await const FallbackMetadataReaderService().read(file);

    expect(metadata.filePath, p.normalize(file.absolute.path));
    expect(metadata.fileSizeBytes, 4);
    expect(metadata.title, 'Local Track');
    expect(metadata.codec, 'm4a');
    expect(metadata.metadataSource, MetadataSource.fallback);
    expect(metadata.metadataConfidence, 0.2);
    expect(metadata.artist, isNull);
    expect(metadata.album, isNull);
    expect(metadata.duration, isNull);
  });

  test('embedded metadata reader falls back when tag reading fails', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_metadata_tag_failure_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final file = File(p.join(tempDirectory.path, 'Artist - Title.mp3'));
    await file.writeAsBytes([1, 2, 3, 4]);
    final reader = AudioMetadataReaderService(
      embeddedMetadataReader: (_) => throw StateError('bad tags'),
    );

    final metadata = await reader.read(file);

    expect(metadata.title, 'Title');
    expect(metadata.artist, 'Artist');
    expect(metadata.metadataSource, MetadataSource.filename);
    expect(metadata.metadataConfidence, greaterThan(0.4));
  });

  test('embedded metadata reader uses embedded metadata when available',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_metadata_tags_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final file = File(p.join(tempDirectory.path, 'Artist - Title.mp3'));
    await file.writeAsBytes([1, 2, 3, 4]);
    final reader = AudioMetadataReaderService(
      embeddedMetadataReader: (_) async {
        return const EmbeddedAudioMetadata(
          title: 'Tagged Title',
          artist: 'Tagged Artist',
          album: 'Tagged Album',
          duration: Duration(seconds: 90),
          trackNumber: 3,
          discNumber: 1,
          year: 2024,
        );
      },
    );

    final metadata = await reader.read(file);

    expect(metadata.title, 'Tagged Title');
    expect(metadata.artist, 'Tagged Artist');
    expect(metadata.album, 'Tagged Album');
    expect(metadata.duration, const Duration(seconds: 90));
    expect(metadata.trackNumber, 3);
    expect(metadata.discNumber, 1);
    expect(metadata.year, 2024);
    expect(metadata.metadataSource, MetadataSource.embeddedTags);
  });
}
