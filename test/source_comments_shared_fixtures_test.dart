import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:clever_music_player/src/library/embedded_yandex_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final extension in ['mp3', 'm4a', 'flac']) {
    test('shared encoded $extension fixture retains the same desktop source ID',
        () {
      final metadata =
          readMetadata(File('test/fixtures/source_comments/linked.$extension'));
      expect(metadata.comments, hasLength(1));
      final identity = embeddedYandexIdentity(metadata.comments);
      expect(identity?.externalId, '34');
      expect(identity?.variantKey, '12');
      expect(metadata.title, 'Source fixture');
    });
  }
}
