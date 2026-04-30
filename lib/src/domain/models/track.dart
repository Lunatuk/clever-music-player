final class Track {
  const Track({
    this.id,
    this.libraryFolderId,
    this.stableId,
    required this.filePath,
    this.contentHash,
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.codec,
    this.duration,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.fileSizeBytes,
    this.modifiedAt,
    this.lastSeenAt,
    this.isMissing = false,
    required this.addedAt,
    required this.updatedAt,
  });

  final int? id;
  final int? libraryFolderId;
  final String? stableId;
  final String filePath;
  final String? contentHash;
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final String? codec;
  final Duration? duration;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final int? fileSizeBytes;
  final DateTime? modifiedAt;
  final DateTime? lastSeenAt;
  final bool isMissing;
  final DateTime addedAt;
  final DateTime updatedAt;

  String get displayTitle {
    final trimmedTitle = title?.trim();
    if (trimmedTitle != null && trimmedTitle.isNotEmpty) {
      return trimmedTitle;
    }

    return filePath.split(RegExp(r'[/\\]')).last;
  }

  Track copyWith({
    int? id,
    int? libraryFolderId,
    String? stableId,
    String? filePath,
    String? contentHash,
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    String? codec,
    Duration? duration,
    int? trackNumber,
    int? discNumber,
    int? year,
    int? fileSizeBytes,
    DateTime? modifiedAt,
    DateTime? lastSeenAt,
    bool? isMissing,
    DateTime? addedAt,
    DateTime? updatedAt,
  }) {
    return Track(
      id: id ?? this.id,
      libraryFolderId: libraryFolderId ?? this.libraryFolderId,
      stableId: stableId ?? this.stableId,
      filePath: filePath ?? this.filePath,
      contentHash: contentHash ?? this.contentHash,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre ?? this.genre,
      codec: codec ?? this.codec,
      duration: duration ?? this.duration,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isMissing: isMissing ?? this.isMissing,
      addedAt: addedAt ?? this.addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Track &&
            other.id == id &&
            other.libraryFolderId == libraryFolderId &&
            other.stableId == stableId &&
            other.filePath == filePath &&
            other.contentHash == contentHash &&
            other.title == title &&
            other.artist == artist &&
            other.album == album &&
            other.albumArtist == albumArtist &&
            other.genre == genre &&
            other.codec == codec &&
            other.duration == duration &&
            other.trackNumber == trackNumber &&
            other.discNumber == discNumber &&
            other.year == year &&
            other.fileSizeBytes == fileSizeBytes &&
            other.modifiedAt == modifiedAt &&
            other.lastSeenAt == lastSeenAt &&
            other.isMissing == isMissing &&
            other.addedAt == addedAt &&
            other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      id,
      libraryFolderId,
      stableId,
      filePath,
      contentHash,
      title,
      artist,
      album,
      albumArtist,
      genre,
      codec,
      duration,
      trackNumber,
      discNumber,
      year,
      fileSizeBytes,
      modifiedAt,
      lastSeenAt,
      isMissing,
      addedAt,
      updatedAt,
    ]);
  }
}
