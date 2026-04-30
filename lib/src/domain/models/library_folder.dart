final class LibraryFolder {
  const LibraryFolder({
    this.id,
    required this.path,
    this.displayName,
    this.isEnabled = true,
    this.isRecursive = true,
    this.lastScannedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String path;
  final String? displayName;
  final bool isEnabled;
  final bool isRecursive;
  final DateTime? lastScannedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LibraryFolder &&
            other.id == id &&
            other.path == path &&
            other.displayName == displayName &&
            other.isEnabled == isEnabled &&
            other.isRecursive == isRecursive &&
            other.lastScannedAt == lastScannedAt &&
            other.createdAt == createdAt &&
            other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      path,
      displayName,
      isEnabled,
      isRecursive,
      lastScannedAt,
      createdAt,
      updatedAt,
    );
  }
}
