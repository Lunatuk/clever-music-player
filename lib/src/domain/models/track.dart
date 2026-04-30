final class Track {
  const Track({
    this.id,
    this.libraryFolderId,
    required this.filePath,
    this.contentHash,
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.duration,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.fileSizeBytes,
    this.modifiedAt,
    required this.addedAt,
    required this.updatedAt,
  });

  final int? id;
  final int? libraryFolderId;
  final String filePath;
  final String? contentHash;
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final Duration? duration;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final int? fileSizeBytes;
  final DateTime? modifiedAt;
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
    String? filePath,
    String? contentHash,
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    Duration? duration,
    int? trackNumber,
    int? discNumber,
    int? year,
    int? fileSizeBytes,
    DateTime? modifiedAt,
    DateTime? addedAt,
    DateTime? updatedAt,
  }) {
    return Track(
      id: id ?? this.id,
      libraryFolderId: libraryFolderId ?? this.libraryFolderId,
      filePath: filePath ?? this.filePath,
      contentHash: contentHash ?? this.contentHash,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre ?? this.genre,
      duration: duration ?? this.duration,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      modifiedAt: modifiedAt ?? this.modifiedAt,
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
            other.filePath == filePath &&
            other.contentHash == contentHash &&
            other.title == title &&
            other.artist == artist &&
            other.album == album &&
            other.albumArtist == albumArtist &&
            other.genre == genre &&
            other.duration == duration &&
            other.trackNumber == trackNumber &&
            other.discNumber == discNumber &&
            other.year == year &&
            other.fileSizeBytes == fileSizeBytes &&
            other.modifiedAt == modifiedAt &&
            other.addedAt == addedAt &&
            other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      libraryFolderId,
      filePath,
      contentHash,
      title,
      artist,
      album,
      albumArtist,
      genre,
      duration,
      trackNumber,
      discNumber,
      year,
      fileSizeBytes,
      modifiedAt,
      addedAt,
      updatedAt,
    );
  }
}
