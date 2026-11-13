import 'dart:io';

import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final helper = Platform.environment['CMP_TEST_MEDIA_HELPER'];
  final skip = !Platform.isWindows || helper == null
      ? 'Requires the qualified Windows media helper.'
      : false;
  for (final format in ['mp3', 'm4a', 'flac']) {
    test('real $format comment reaches full and artwork-free metadata readers',
        () async {
      final directory = await Directory.systemTemp.createTemp('cmp_source_id_');
      try {
        final file = File(p.join(directory.path, 'Музыка с тегами.$format'));
        final process = await Process.run(p.join(helper!, 'ffmpeg.exe'), [
          '-nostdin',
          '-v',
          'error',
          '-i',
          p.absolute('test/fixtures/media_helper/tone.$format'),
          '-map',
          '0:a:0',
          '-c:a',
          'copy',
          '-metadata',
          'comment=https://music.yandex.ru/album/12/track/34',
          file.path,
        ]);
        expect(process.exitCode, 0, reason: '${process.stderr}');
        const reader = AudioMetadataReaderService();
        final metadata = await reader.read(file);
        expect(metadata.yandexIdentityRead, isTrue);
        expect(metadata.yandexIdentity?.externalId, '34');
        expect(metadata.yandexIdentity?.variantKey, '12');
        expect(await reader.readYandexIdentity(file), metadata.yandexIdentity);
      } finally {
        await directory.delete(recursive: true);
      }
    }, skip: skip);
  }
}
