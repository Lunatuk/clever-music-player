import 'metadata_source.dart';
import 'audio_source_reference.dart';

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

  /// Construct a track from a validated typed address without changing storage.
  factory Track.fromSource({
    int? id,
    int? libraryFolderId,
    String? stableId,
    required AudioSourceReference source,
    String? contentHash,
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    String? artworkPath,
    String? artworkHash,
    String? artworkMimeType,
    String? customArtworkPath,
    String? customArtworkHash,
    String? customArtworkMimeType,
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
    bool isMissing = false,
    required DateTime addedAt,
    required DateTime updatedAt,
  }) =>
      Track(
        id: id,
        libraryFolderId: libraryFolderId,
        stableId: stableId,
        filePath: source.storageValue,
        contentHash: contentHash,
        title: title,
        artist: artist,
        album: album,
        albumArtist: albumArtist,
        genre: genre,
        artworkPath: artworkPath,
        artworkHash: artworkHash,
        artworkMimeType: artworkMimeType,
        customArtworkPath: customArtworkPath,
        customArtworkHash: customArtworkHash,
        customArtworkMimeType: customArtworkMimeType,
        codec: codec,
        duration: duration,
        trackNumber: trackNumber,
        discNumber: discNumber,
        year: year,
        metadataSource: metadataSource,
        metadataConfidence: metadataConfidence,
        fileSizeBytes: fileSizeBytes,
        modifiedAt: modifiedAt,
        lastSeenAt: lastSeenAt,
        isMissing: isMissing,
        addedAt: addedAt,
        updatedAt: updatedAt,
      );

  final int? id;
  final int? libraryFolderId;

  /// A non-unique metadata signature, separate from the persisted [id].
  final String? stableId;

  /// Legacy storage column: a local path or a content URI. Use [source] for IO.
  final String filePath;
  AudioSourceReference get source => AudioSourceReference.fromStorage(filePath);
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

    if (AudioSourceReference.isContentUriValue(filePath)) return 'Без названия';
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
    AudioSourceReference? source,
    Object? contentHash = _unset,
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
    if (source != null && filePath != null) {
      throw ArgumentError('Укажите один источник: source или filePath.');
    }
    return Track(
      id: id ?? this.id,
      libraryFolderId: libraryFolderId ?? this.libraryFolderId,
      stableId: stableId ?? this.stableId,
      filePath: source?.storageValue ?? filePath ?? this.filePath,
      contentHash: identical(contentHash, _unset)
          ? this.contentHash
          : contentHash as String?,
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
