import 'dart:convert';
import 'dart:typed_data';

/// Container/tag fixture for parser tests; no encoded audio frames/playback.
Uint8List flacMetadataFixture({bool malformedPicture = false}) {
  Uint8List word(int value, {Endian endian = Endian.big}) =>
      (ByteData(4)..setUint32(0, value, endian)).buffer.asUint8List();
  Uint8List block(int type, List<int> payload, {bool last = false}) =>
      Uint8List.fromList([
        type | (last ? 128 : 0),
        payload.length >> 16 & 255,
        payload.length >> 8 & 255,
        payload.length & 255,
        ...payload
      ]);
  final streamInfo = ByteData(34)
    ..setUint16(0, 4096, Endian.big)
    ..setUint16(2, 4096, Endian.big)
    ..setUint64(10, (44100 << 44) | (15 << 36) | 88200, Endian.big);
  final comments = BytesBuilder()
    ..add(word(3, endian: Endian.little))
    ..add(utf8.encode('CMP'));
  final tags = [
    'TITLE=Песня 💿',
    'ARTIST=Исполнитель',
    'ALBUM=Fixture album',
    'GENRE=Rock',
    'DATE=2024',
    'TRACKNUMBER=3'
  ];
  comments.add(word(tags.length, endian: Endian.little));
  for (final tag in tags) {
    final bytes = utf8.encode(tag);
    comments
      ..add(word(bytes.length, endian: Endian.little))
      ..add(bytes);
  }
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=');
  final picture = malformedPicture
      ? [0, 0, 0]
      : [
          ...word(3),
          ...word(9),
          ...utf8.encode('image/png'),
          ...word(0),
          ...word(1),
          ...word(1),
          ...word(32),
          ...word(0),
          ...word(png.length),
          ...png,
        ];
  return Uint8List.fromList([
    ...ascii.encode('fLaC'),
    ...block(0, streamInfo.buffer.asUint8List()),
    ...block(4, comments.takeBytes()),
    ...block(6, picture, last: true),
  ]);
}
