import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/file_content_hasher.dart';
import 'package:clever_music_player/src/library/exact_track_copies.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final digest = 'a' * 64;
  for (final size in [0, 3, 12345678901, 9223372036854775807]) {
    test('canonical file identity roundtrips size $size', () {
      final identity = FileContentIdentity(sizeBytes: size, sha256: digest);
      expect(identity.storageKey, 'file-sha256-v1:$size:$digest');
      expect(FileContentIdentity.tryParse(identity.storageKey), identity);
      expect(FileContentIdentity.tryParse(identity.storageKey)?.hashCode,
          identity.hashCode);
    });
  }
  for (final value in <String?>[
    null,
    '',
    digest,
    'file-sha256-v2:3:$digest',
    'file-sha256-v1:-1:$digest',
    'file-sha256-v1:03:$digest',
    'file-sha256-v1:3:${'A' * 64}',
    'file-sha256-v1:3:$digest\n',
    'file-sha256-v1:3:$digest\u0000',
    'file-sha256-v1:9223372036854775808:$digest',
    'file-sha256-v1:${'1' * 100}:$digest',
    'file-sha256-v1:3:abc',
    ' file-sha256-v1:3:$digest',
  ]) {
    test('ambiguous or malformed storage identity is rejected: $value', () {
      expect(FileContentIdentity.tryParse(value), isNull);
      expect(verifiedFileContentKey(value), isNull);
    });
  }
  test('invalid evidence cannot construct a canonical identity', () {
    expect(() => FileContentIdentity(sizeBytes: -1, sha256: digest),
        throwsArgumentError);
    expect(() => FileContentIdentity(sizeBytes: 3, sha256: 'old-signature'),
        throwsFormatException);
  });
  test('file size mismatch never hides a second file', () {
    final key = 'file-sha256-v1:3:$digest';
    expect(verifiedFileContentKey(key, expectedSizeBytes: 4), isNull);
    expect(verifiedFileContentKey(key, expectedSizeBytes: 3), key);
    Track track(int id, int size, String hash) => Track(
        id: id,
        filePath: '/$id.mp3',
        title: 'Same title',
        artist: 'Same artist',
        fileSizeBytes: size,
        contentHash: hash,
        addedAt: DateTime(2026),
        updatedAt: DateTime(2026));
    expect(withoutExactTrackCopies([track(1, 3, key), track(2, 4, key)]),
        hasLength(2));
    expect(withoutExactTrackCopies([track(1, 3, digest), track(2, 3, key)]),
        hasLength(2));
    expect(withoutExactTrackCopies([track(1, 3, key), track(2, 3, key)]),
        hasLength(1));
  });
  test('verification keeps its protocol digest separate from the Track key',
      () {
    final proof = DownloadedAssetVerification(
        actualQuality: 'high',
        container: 'mp3',
        codec: 'mp3',
        fileSizeBytes: 3,
        duration: const Duration(seconds: 3),
        contentHash: digest,
        checkedAt: DateTime.utc(2026));
    expect(proof.contentHash, digest);
    expect(proof.fileContentKey, 'file-sha256-v1:3:$digest');
    expect(proof.matchesContentHash(digest), isTrue);
    expect(proof.matchesContentHash(proof.fileContentKey), isTrue);
    expect(proof.matchesContentHash('file-sha256-v1:4:$digest'), isFalse);
    expect(proof.matchesContentHash('b' * 64), isFalse);
    expect(proof.matchesContentHash(null), isFalse);
    expect(verifiedFileContentKey(digest), isNull);
  });
}
