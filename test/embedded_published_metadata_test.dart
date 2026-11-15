import 'dart:io';

import 'package:clever_music_player/src/domain/models/metadata_source.dart';
import 'package:clever_music_player/src/library/metadata_enrichment.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late File file;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cmp_strict_tags_');
    file = await File(p.join(root.path, 'cmp-opaque - Resource.mp3'))
        .writeAsString('abc');
  });
  tearDown(() => root.delete(recursive: true));

  test(
      'published and scanned copies use the same parsing confidence regardless of richness',
      () async {
    for (final rich in [false, true]) {
      final tags = EmbeddedAudioMetadata(
          title: 'Andromeda',
          artist: 'LXST CXNTURY',
          album: rich ? 'Andromeda' : null,
          albumArtist: rich ? 'LXST CXNTURY' : null,
          year: rich ? 2019 : null,
          genre: rich ? 'Phonk' : null);
      final published =
          await EmbeddedAudioMetadataReaderService(reader: (_) async => tags)
              .read(file);
      final scanned = await AudioMetadataReaderService(
          embeddedMetadataReader: (_) async => tags).read(file);
      expect(published.metadataConfidence, 0.95);
      expect(published.metadataConfidence, scanned.metadataConfidence);
      expect(published.metadataSource, scanned.metadataSource);
      expect(published.album, scanned.album);
      expect(published.year, scanned.year);
    }
  });
  test(
      'reader uses embedded fields without inferring an artist from the opaque path',
      () async {
    final reader = EmbeddedAudioMetadataReaderService(
        reader: (_) async => const EmbeddedAudioMetadata(
            title: 'Track',
            albumArtist: 'Album artist',
            genre: 'Rock',
            trackNumber: 2));
    final result = await reader.read(file);
    expect(result.title, 'Track');
    expect(result.artist, isNull);
    expect(result.albumArtist, 'Album artist');
    expect(result.metadataSource, MetadataSource.embeddedTags);
    expect(result.fileSizeBytes, 3);
  });
  for (final title in [null, '', '   ']) {
    test('missing title ${title?.length} does not import an opaque filename',
        () async {
      final reader = EmbeddedAudioMetadataReaderService(
          reader: (_) async => EmbeddedAudioMetadata(title: title));
      await expectLater(reader.read(file), throwsFormatException);
    });
  }
  test(
      'tag decoding failure propagates instead of falling back to the filename',
      () async {
    final reader = EmbeddedAudioMetadataReaderService(
        reader: (_) async => throw const FormatException('synthetic'));
    await expectLater(reader.read(file), throwsFormatException);
  });
  test('no readable tags cannot produce apparently successful metadata',
      () async {
    final reader =
        EmbeddedAudioMetadataReaderService(reader: (_) async => null);
    await expectLater(reader.read(file), throwsFormatException);
  });
}
