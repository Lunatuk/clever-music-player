import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' as tags;
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/flac_metadata_fixture.dart';

void main() {
  late Directory root;
  setUp(() async =>
      root = await Directory.systemTemp.createTemp('cmp_background_tags_'));
  tearDown(() => root.delete(recursive: true));

  test(
      'real background parser transfers Unicode tags, duration and artwork unchanged',
      () async {
    final bytes = flacMetadataFixture();
    final file =
        await File(p.join(root.path, 'путь 💿.flac')).writeAsBytes(bytes);
    final direct = tags.readMetadata(file, getImage: true);
    final actual = await const AudioMetadataReaderService().read(file);
    expect(actual.title, 'Песня 💿');
    expect(actual.artist, 'Исполнитель');
    expect(actual.album, direct.album);
    expect(actual.genre, direct.genres.first);
    expect(actual.trackNumber, 3);
    expect(actual.year, 2024);
    expect(actual.duration, const Duration(seconds: 2));
    expect(actual.artwork!.bytes, direct.pictures.first.bytes);
    expect(actual.artwork!.mimeType, 'image/png');
    expect(actual.metadataSource, MetadataSource.embeddedTags);
    expect(await file.readAsBytes(), bytes);
    await file.delete();
  });

  test('broken picture keeps readable tags through the no-image fallback',
      () async {
    final file = await File(p.join(root.path, 'broken-picture.flac'))
        .writeAsBytes(flacMetadataFixture(malformedPicture: true));
    final actual = await const AudioMetadataReaderService().read(file);
    expect(actual.title, 'Песня 💿');
    expect(actual.artwork, isNull);
    expect(actual.metadataSource, MetadataSource.embeddedTags);
    await file.delete();
  });

  test(
      'failed real background parsing keeps filename fallback and releases file',
      () async {
    final file = await File(p.join(root.path, 'Artist - Title.mp3'))
        .writeAsBytes([1, 2, 3]);
    final actual = await const AudioMetadataReaderService().read(file);
    expect(actual.title, 'Title');
    expect(actual.artist, 'Artist');
    expect(actual.metadataSource, MetadataSource.filename);
    await file.delete();
  });
  test('low-level metadata entry point releases unsupported files too',
      () async {
    final file = await File(p.join(root.path, 'unsupported.mp3'))
        .writeAsBytes([1, 2, 3]);
    expect(() => tags.readAllMetadata(file), throwsA(anything));
    await file.delete();
  });
}
