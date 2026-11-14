/// Identity of every byte of a file, including tags and artwork. This is
/// independent of catalogue IDs, metadata signatures and audio fingerprints.
final class FileContentIdentity {
  factory FileContentIdentity(
      {required int sizeBytes, required String sha256}) {
    if (sizeBytes < 0) throw ArgumentError.value(sizeBytes, 'sizeBytes');
    if (_digest.stringMatch(sha256) != sha256) {
      throw const FormatException('Требуется полный SHA-256 файла.');
    }
    return FileContentIdentity._(sizeBytes, sha256);
  }
  const FileContentIdentity._(this.sizeBytes, this.sha256);
  final int sizeBytes;
  final String sha256;
  static const keyPrefix = 'file-sha256-v1:';
  String get storageKey => '$keyPrefix$sizeBytes:$sha256';

  /// Bare legacy digests have no declared provenance and are not evidence.
  static FileContentIdentity? tryParse(String? value) {
    if (value == null) return null;
    final match = _key.firstMatch(value);
    if (match == null || match[0] != value) return null;
    final size = int.tryParse(match[1]!);
    return size == null ? null : FileContentIdentity._(size, match[2]!);
  }

  @override
  bool operator ==(Object other) =>
      other is FileContentIdentity &&
      sizeBytes == other.sizeBytes &&
      sha256 == other.sha256;
  @override
  int get hashCode => Object.hash(sizeBytes, sha256);
}

final _digest = RegExp(r'^[0-9a-f]{64}$');
final _key = RegExp(r'^file-sha256-v1:(0|[1-9][0-9]{0,18}):([0-9a-f]{64})$');
