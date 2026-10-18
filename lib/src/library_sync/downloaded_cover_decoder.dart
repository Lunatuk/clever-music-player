import 'dart:typed_data';
import 'dart:ui' as ui;

import '../library/library_scan_control.dart';
import 'binary_http_download_transport.dart';
import 'downloaded_audio_metadata.dart';
import 'downloaded_audio_validation.dart';

/// Small immutable JPEG/PNG only. Header dimensions are checked before pixel
/// allocation; the engine must then decode a single frame at its native size.
/// This is not publication evidence: the prepared audio still needs the normal
/// helper decode, embedded-cover digest and unchanged-audio validation.
final class DownloadedCoverDecoder {
  const DownloadedCoverDecoder();
  static const maximumDimension = 1024;
  static const maximumPixels = 1024 * 1024;

  Future<EmbeddedCover> decode(Uint8List bytes,
      {LibraryScanControl? control}) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      control?.throwIfCancelled();
      if (bytes.isEmpty || bytes.length > maximumDownloadedCoverBytes) {
        _invalid();
      }
      // EmbeddedCover takes a private immutable snapshot before asynchronous IO.
      final EmbeddedCover cover;
      if (bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80) {
        cover = EmbeddedCover(bytes, EmbeddedCoverFormat.png);
        _pngEnvelope(cover.bytes);
      } else {
        cover = EmbeddedCover(bytes, EmbeddedCoverFormat.jpeg);
        if (bytes.length < 4 ||
            bytes[bytes.length - 2] != 255 ||
            bytes.last != 217) {
          _invalid();
        }
      }
      buffer = await ui.ImmutableBuffer.fromUint8List(cover.bytes);
      control?.throwIfCancelled();
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      control?.throwIfCancelled();
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width > maximumDimension ||
          descriptor.height > maximumDimension ||
          descriptor.width * descriptor.height > maximumPixels) {
        _invalid();
      }
      codec = await descriptor.instantiateCodec();
      control?.throwIfCancelled();
      if (codec.frameCount != 1) _invalid();
      image = (await codec.getNextFrame()).image;
      control?.throwIfCancelled();
      return cover;
    } on LibraryScanCancelled {
      rethrow;
    } on Object {
      // Engine/format exceptions can contain data; never expose their text.
      throw const AudioValidationException(AudioValidationOutcome.invalidCover);
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static Never _invalid() =>
      throw const AudioValidationException(AudioValidationOutcome.invalidCover);

  static void _pngEnvelope(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var offset = 8, chunks = 0, pixels = false;
    while (offset + 12 <= bytes.length) {
      if (++chunks > 4096) _invalid();
      final length = data.getUint32(offset);
      final type = data.getUint32(offset + 4);
      final end = offset + 12 + length;
      if (end > bytes.length ||
          (chunks == 1 && (type != 0x49484452 || length != 13))) {
        _invalid();
      }
      // Validate every chunk's CRC, including skipped ancillary metadata.
      var crc = 0xffffffff;
      for (var i = offset + 4; i < end - 4; i++) {
        crc = _crcTable[(crc ^ bytes[i]) & 255] ^ (crc >>> 8);
      }
      if ((crc ^ 0xffffffff) != data.getUint32(end - 4)) _invalid();
      if (type == 0x6163544c) _invalid(); // APNG animation is not album art.
      if (type == 0x49444154) pixels = true;
      if (type == 0x49454e44) {
        if (length != 0 || !pixels || end != bytes.length) _invalid();
        return;
      }
      offset = end;
    }
    _invalid();
  }

  static final List<int> _crcTable = List.generate(256, (value) {
    var crc = value;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
    return crc;
  }, growable: false);
}
