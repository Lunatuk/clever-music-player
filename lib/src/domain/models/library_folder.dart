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

  LibraryFolder copyWith({
    int? id,
    String? path,
    String? displayName,
    bool? isEnabled,
    bool? isRecursive,
    DateTime? lastScannedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LibraryFolder(
      id: id ?? this.id,
      path: path ?? this.path,
      displayName: displayName ?? this.displayName,
      isEnabled: isEnabled ?? this.isEnabled,
      isRecursive: isRecursive ?? this.isRecursive,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

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
