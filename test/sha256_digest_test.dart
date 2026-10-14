import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clever_music_player/src/library/file_content_hasher.dart';
import 'package:clever_music_player/src/library/sha256_digest.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  for (final native in [false, true]) {
    test('SHA-256 backend $native matches vectors and block boundaries', () {
      for (final length in [
        0,
        1,
        55,
        56,
        63,
        64,
        65,
        65535,
        65536,
        65537,
        1024 * 1024 + 7
      ]) {
        final bytes = Uint8List.fromList(
            List.generate(length, (i) => (i * 13 + 7) % 256));
        final digest = createSha256Digest(preferNative: native);
        try {
          expect(
              digest.backend,
              native && Platform.isWindows
                  ? Sha256Backend.windowsCng
                  : Sha256Backend.dart);
          for (var offset = 0; offset < bytes.length; offset += 7901) {
            digest.add(Uint8List.sublistView(
                bytes, offset, (offset + 7901).clamp(0, bytes.length)));
          }
          expect(digest.finish(), sha256.convert(bytes).toString(),
              reason: 'length $length');
          expect(() => digest.add([1]), throwsStateError);
          expect(digest.finish, throwsStateError);
        } finally {
          digest.dispose();
          digest.dispose();
        }
      }
      expect(sha256Hex(utf8.encode('abc'), preferNative: native),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('SHA-256 backend $native accepts a whole large byte buffer', () {
      final bytes =
          Uint8List.fromList(List.generate(512 * 1024 + 3, (i) => i % 251));
      expect(sha256Hex(bytes, preferNative: native),
          sha256.convert(bytes).toString());
      final digest = createSha256Digest(preferNative: native);
      digest.add([1, 2, 3]);
      digest.dispose();
      expect(digest.finish, throwsStateError);
    });
  }

  test('native and portable file workers keep identical stored identities',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('cmp_sha_backends_');
    try {
      final file = File(p.join(directory.path, 'песня 💿.flac'));
      await file.writeAsBytes(Uint8List(2 * 1024 * 1024 + 17));
      final native = await const Sha256FileContentHasher().hashFile(file);
      final portable = await const Sha256FileContentHasher(preferNative: false)
          .hashFile(file);
      expect(native.storageKey, portable.storageKey);
      expect(native.backend,
          Platform.isWindows ? Sha256Backend.windowsCng : Sha256Backend.dart);
      expect(portable.backend, Sha256Backend.dart);
      await file.delete();
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
