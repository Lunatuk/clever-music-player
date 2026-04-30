import 'dart:io';

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
    expect(metadata.artist, isNull);
    expect(metadata.album, isNull);
    expect(metadata.duration, isNull);
  });
}
