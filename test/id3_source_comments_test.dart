import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:clever_music_player/src/library/embedded_yandex_identity.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _syncSafe(int size) => [
      (size >> 21) & 127,
      (size >> 14) & 127,
      (size >> 7) & 127,
      size & 127,
    ];

List<int> _encoded(String text, int encoding, bool little) {
  if (encoding == 0) return latin1.encode(text);
  if (encoding == 3) return utf8.encode(text);
  final bytes = ByteData(text.length * 2);
  for (var index = 0; index < text.length; index++) {
    bytes.setUint16(
        index * 2, text.codeUnitAt(index), little ? Endian.little : Endian.big);
  }
  return [
    if (encoding == 1) ...little ? [255, 254] : [254, 255],
    ...bytes.buffer.asUint8List(),
  ];
}

void main() {
  const url = 'https://music.yandex.ru/album/12/track/34';
  for (final (version, encoding, little) in [
    (3, 0, false),
    (3, 1, true),
    (3, 1, false),
    (4, 2, false),
    (4, 3, false),
  ]) {
    test('reads ID3v2.$version COMM encoding=$encoding little=$little',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('cmp_id3_source_');
      try {
        final payload = [
          encoding,
          ...ascii.encode('eng'),
          ..._encoded(encoding == 0 ? 'Source' : 'Источник', encoding, little),
          0,
          if (encoding == 1 || encoding == 2) 0,
          ..._encoded(url, encoding, little),
        ];
        final size = payload.length;
        final frames = [
          ...ascii.encode('COMM'),
          ...version == 4
              ? _syncSafe(size)
              : [
                  (size >> 24) & 255,
                  (size >> 16) & 255,
                  (size >> 8) & 255,
                  size & 255
                ],
          0,
          0,
          ...payload,
        ];
        final file = await File('${directory.path}/comment.mp3').writeAsBytes([
          ...ascii.encode('ID3'),
          version,
          0,
          0,
          ..._syncSafe(frames.length),
          ...frames,
        ]);
        final input = file.openSync();
        try {
          final metadata = ID3v2Parser(fetchImage: false).parse(input);
          expect(metadata.comments, hasLength(1));
          expect(metadata.comments.single.text, url);
          expect(
              embeddedYandexIdentity(metadata.comments.map((c) => c.text))
                  ?.externalId,
              '34');
        } finally {
          input.closeSync();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    });
  }
}
