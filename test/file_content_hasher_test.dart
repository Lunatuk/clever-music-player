import 'dart:io';
import 'dart:typed_data';

import 'package:clever_music_player/src/library/file_content_hasher.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  const hasher = Sha256FileContentHasher();
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cmp_content_hash_');
  });
  tearDown(() => directory.delete(recursive: true));

  test('full SHA-256 is independent of name and path including Unicode',
      () async {
    final first = File(p.join(directory.path, 'песня 💿.mp3'));
    final copy = File(p.join(directory.path, 'renamed.flac'));
    await first.writeAsString('abc');
    await first.copy(copy.path);
    final fingerprint = await hasher.hashFile(first);
    expect(fingerprint.storageKey,
        'file-sha256-v1:3:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect((await hasher.hashFile(copy)).storageKey, fingerprint.storageKey);
    expect(await fingerprint.matchesFile(first), isTrue);
  });

  test('same length and modification time do not imply the same content',
      () async {
    final file = File(p.join(directory.path, 'same.mp3'));
    await file.writeAsString('abc');
    final original = await hasher.hashFile(file);
    await file.writeAsString('abd');
    await file.setLastModified(original.modifiedAt);
    final changed = await hasher.hashFile(file);
    expect(changed.sizeBytes, original.sizeBytes);
    expect(changed.modifiedAt, original.modifiedAt);
    expect(changed.storageKey, isNot(original.storageKey));
  });

  test('streamed hash covers all chunks including the last byte', () async {
    final bytes = Uint8List(4 * 1024 * 1024 + 7);
    bytes[bytes.length - 1] = 127;
    final file = File(p.join(directory.path, 'long.wav'));
    await file.writeAsBytes(bytes);
    final fingerprint = await hasher.hashFile(file);
    expect(fingerprint.sizeBytes, bytes.length);
    expect(fingerprint.digest, sha256.convert(bytes).toString());
  });

  test('missing files and directories cannot produce identities', () async {
    await expectLater(hasher.hashFile(File(p.join(directory.path, 'gone.mp3'))),
        throwsA(isA<FileSystemException>()));
    await expectLater(hasher.hashFile(File(directory.path)),
        throwsA(isA<FileSystemException>()));
  });

  test('file stat check rejects changes or disappearance after hashing',
      () async {
    final file = File(p.join(directory.path, 'song.mp3'));
    await file.writeAsString('abc');
    final fingerprint = await hasher.hashFile(file);
    await file.writeAsString('changed');
    expect(await fingerprint.matchesFile(file), isFalse);
    await file.delete();
    expect(await fingerprint.matchesFile(file), isFalse);
  });

  test('legacy and malformed hash values are never duplicate evidence', () {
    for (final value in <String?>[
      null,
      '',
      'metadata-signature',
      'a' * 64,
      'file-sha256-v1:3:abc',
      'file-sha256-v1:-1:${'a' * 64}',
      'file-sha256-v1:03:${'a' * 64}',
      'file-sha256-v2:3:${'a' * 64}',
      'file-sha256-v1:3:${'A' * 64}',
      'file-sha256-v1:3:${'a' * 64}\n',
    ]) {
      expect(verifiedFileContentKey(value), isNull, reason: '$value');
    }
    final valid = 'file-sha256-v1:3:${'a' * 64}';
    expect(verifiedFileContentKey(valid), valid);
  });
}
