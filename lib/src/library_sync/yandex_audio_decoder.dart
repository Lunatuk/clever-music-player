import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/stream/sic.dart';

import '../library/library_scan_control.dart';

/// Per-response transport key, kept in memory only. The decoded stream enters
/// the existing bounded raw reservation; no second file or whole-song buffer.
final class YandexAudioDecoder {
  YandexAudioDecoder(String transport, Object? key)
      : _key = _parse(transport, key);
  final Uint8List? _key;
  bool get isEncrypted => _key != null;

  static Uint8List? _parse(String transport, Object? key) {
    if (transport == 'raw' && (key == null || key == '')) return null;
    if (transport != 'encraw' ||
        key is! String ||
        !{32, 48, 64}.contains(key.length) ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(key)) {
      throw const FormatException('Invalid audio delivery parameters.');
    }
    return Uint8List.fromList([
      for (var i = 0; i < key.length; i += 2)
        int.parse(key.substring(i, i + 2), radix: 16)
    ]);
  }

  Stream<List<int>> decode(Stream<List<int>> input,
          {LibraryScanControl? control}) =>
      _key == null ? input : _decode(input, control);

  Stream<List<int>> _decode(
      Stream<List<int>> input, LibraryScanControl? control) async* {
    // SDK/YaDown AES-CTR: all-zero 16-byte IV, counter starts at zero.
    final cipher = SICStreamCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(_key!), Uint8List(16)));
    await for (final chunk in input) {
      for (var offset = 0; offset < chunk.length; offset += 16 * 1024) {
        control?.throwIfCancelled();
        final end = min(offset + 16 * 1024, chunk.length);
        final bytes = chunk is Uint8List
            ? Uint8List.sublistView(chunk, offset, end)
            : Uint8List.fromList(chunk.sublist(offset, end));
        final decoded = Uint8List(bytes.length);
        cipher.processBytes(bytes, 0, bytes.length, decoded, 0);
        yield decoded;
        // Bound CPU work even when a source provides a very large chunk.
        await Future<void>.delayed(Duration.zero);
      }
    }
    control?.throwIfCancelled();
  }

  @override
  String toString() => 'YandexAudioDecoder(<redacted>)';
}
