import 'dart:io';
import 'dart:typed_data';

import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/binary_http_download_transport.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:clever_music_player/src/library_sync/downloaded_cover_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const decoder = DownloadedCoverDecoder();
  Future<Uint8List> fixture(String extension) =>
      File('test/fixtures/media_helper/cover.$extension').readAsBytes();
  Matcher invalid() => throwsA(isA<AudioValidationException>().having(
      (e) => e.outcome, 'outcome', AudioValidationOutcome.invalidCover));
  for (final (extension, format) in [
    ('png', EmbeddedCoverFormat.png),
    ('jpg', EmbeddedCoverFormat.jpeg)
  ]) {
    test('decode actual $extension, keep an immutable exact byte snapshot',
        () async {
      final input = await fixture(extension);
      final original = input.toList();
      final operation = decoder.decode(input);
      input.fillRange(0, input.length, 0);
      final cover = await operation;
      expect(cover.format, format);
      expect(cover.bytes, original);
      expect(() => cover.bytes[0] = 0, throwsUnsupportedError);
    });
    test('reject truncated $extension', () async {
      final input = await fixture(extension);
      await expectLater(
          decoder.decode(Uint8List.sublistView(input, 0, input.length - 8)),
          invalid());
    });
  }
  for (final bytes in <List<int>>[
    [], [255, 216, 255, 217], [137, 80, 78, 71, 13, 10, 26, 10],
    '<html>SECRET_RESPONSE</html>'.codeUnits,
    [71, 73, 70, 56, 57, 97, 1, 0, 1, 0], // GIF is deliberately unsupported.
    List.filled(maximumDownloadedCoverBytes + 1, 0),
  ].indexed) {
    test('reject unsupported/invalid bounded image ${bytes.$1}', () async {
      await expectLater(
          decoder.decode(Uint8List.fromList(bytes.$2)), invalid());
    });
  }
  test('reject PNG damaged payload CRC', () async {
    final bytes = await fixture('png');
    bytes[bytes.length - 16] ^= 1;
    await expectLater(decoder.decode(bytes), invalid());
  });
  test('reject PNG trailing data', () async {
    await expectLater(
        decoder.decode(Uint8List.fromList([...await fixture('png'), 0])),
        invalid());
  });
  test('reject oversized image dimensions before full frame allocation',
      () async {
    final bytes = await fixture('png');
    ByteData.sublistView(bytes).setUint32(16, 1025);
    _crc(bytes, 12, 29);
    await expectLater(decoder.decode(bytes), invalid());
  });
  test('reject APNG even if the first frame is valid', () async {
    final bytes = await fixture('png');
    final chunk = Uint8List(20);
    final data = ByteData.sublistView(chunk)
      ..setUint32(0, 8)
      ..setUint32(4, 0x6163544c)
      ..setUint32(8, 2);
    expect(data.lengthInBytes, 20);
    _crc(chunk, 4, 16);
    await expectLater(
        decoder.decode(Uint8List.fromList(
            [...bytes.take(33), ...chunk, ...bytes.skip(33)])),
        invalid());
  });
  test('pre-cancelled decode does no work and preserves cancellation type',
      () async {
    final control = LibraryScanControl()..cancel();
    await expectLater(decoder.decode(await fixture('png'), control: control),
        throwsA(isA<LibraryScanCancelled>()));
  });
  test('cancellation while native descriptor work is pending is drained',
      () async {
    final control = LibraryScanControl();
    final operation = decoder.decode(await fixture('png'), control: control);
    control.cancel();
    await expectLater(operation, throwsA(isA<LibraryScanCancelled>()));
    expect((await decoder.decode(await fixture('png'))).format,
        EmbeddedCoverFormat.png);
  });
}

void _crc(Uint8List bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var i = start; i < end; i++) {
    crc ^= bytes[i];
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
    }
  }
  ByteData.sublistView(bytes).setUint32(end, crc ^ 0xffffffff);
}
