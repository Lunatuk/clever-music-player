import 'metadata_source.dart';

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
    this.artworkPath,
    this.artworkHash,
    this.artworkMimeType,
    this.customArtworkPath,
    this.customArtworkHash,
    this.customArtworkMimeType,
    this.codec,
    this.duration,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.metadataSource,
    this.metadataConfidence,
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
  final String? artworkPath;
  final String? artworkHash;
  final String? artworkMimeType;
  final String? customArtworkPath;
  final String? customArtworkHash;
  final String? customArtworkMimeType;
  final String? codec;
  final Duration? duration;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final MetadataSource? metadataSource;
  final double? metadataConfidence;
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

  bool get hasCustomArtwork {
    final path = customArtworkPath?.trim();
    return path != null && path.isNotEmpty;
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
    String? artworkPath,
    String? artworkHash,
    String? artworkMimeType,
    Object? customArtworkPath = _unset,
    Object? customArtworkHash = _unset,
    Object? customArtworkMimeType = _unset,
    String? codec,
    Duration? duration,
    int? trackNumber,
    int? discNumber,
    int? year,
    MetadataSource? metadataSource,
    double? metadataConfidence,
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
      artworkPath: artworkPath ?? this.artworkPath,
      artworkHash: artworkHash ?? this.artworkHash,
      artworkMimeType: artworkMimeType ?? this.artworkMimeType,
      customArtworkPath: identical(customArtworkPath, _unset)
          ? this.customArtworkPath
          : customArtworkPath as String?,
      customArtworkHash: identical(customArtworkHash, _unset)
          ? this.customArtworkHash
          : customArtworkHash as String?,
      customArtworkMimeType: identical(customArtworkMimeType, _unset)
          ? this.customArtworkMimeType
          : customArtworkMimeType as String?,
      codec: codec ?? this.codec,
      duration: duration ?? this.duration,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      metadataSource: metadataSource ?? this.metadataSource,
      metadataConfidence: metadataConfidence ?? this.metadataConfidence,
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
            other.artworkPath == artworkPath &&
            other.artworkHash == artworkHash &&
            other.artworkMimeType == artworkMimeType &&
            other.customArtworkPath == customArtworkPath &&
            other.customArtworkHash == customArtworkHash &&
            other.customArtworkMimeType == customArtworkMimeType &&
            other.codec == codec &&
            other.duration == duration &&
            other.trackNumber == trackNumber &&
            other.discNumber == discNumber &&
            other.year == year &&
            other.metadataSource == metadataSource &&
            other.metadataConfidence == metadataConfidence &&
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
      artworkPath,
      artworkHash,
      artworkMimeType,
      customArtworkPath,
      customArtworkHash,
      customArtworkMimeType,
      codec,
      duration,
      trackNumber,
      discNumber,
      year,
      metadataSource,
      metadataConfidence,
      fileSizeBytes,
      modifiedAt,
      lastSeenAt,
      isMissing,
      addedAt,
      updatedAt,
    ]);
  }
}

const Object _unset = Object();
