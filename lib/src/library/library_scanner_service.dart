import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';
import 'artwork_cache_service.dart';
import 'metadata_enrichment.dart';
import 'metadata_reader_service.dart';
import 'stable_track_id.dart';

const supportedAudioExtensions = {
  '.mp3',
  '.flac',
  '.m4a',
  '.aac',
  '.ogg',
  '.wav',
};

bool isSupportedAudioFilePath(String filePath) {
  return supportedAudioExtensions.contains(p.extension(filePath).toLowerCase());
}

typedef DirectoryEntityLister = Stream<FileSystemEntity> Function(
  Directory directory,
);

Stream<FileSystemEntity> _defaultDirectoryEntityLister(Directory directory) {
  return directory.list(
    recursive: true,
    followLinks: false,
  );
}

final class LibraryScanError {
  const LibraryScanError({
    required this.path,
    required this.message,
  });

  final String path;
  final String message;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LibraryScanError &&
            other.path == path &&
            other.message == message;
  }

  @override
  int get hashCode => Object.hash(path, message);
}

final class LibraryScanResult {
  const LibraryScanResult({
    required this.folderPath,
    required this.scannedFiles,
    required this.addedTracks,
    required this.updatedTracks,
    required this.missingTracks,
    required this.errors,
  });

  final String folderPath;
  final int scannedFiles;
  final int addedTracks;
  final int updatedTracks;
  final int missingTracks;
  final List<LibraryScanError> errors;

  bool get hasErrors => errors.isNotEmpty;

  String get summary {
    return 'Scanned $scannedFiles files, added $addedTracks, '
        'updated $updatedTracks, missing $missingTracks.';
  }

  static LibraryScanResult combine(Iterable<LibraryScanResult> results) {
    final items = results.toList(growable: false);
    return LibraryScanResult(
      folderPath: items.map((result) => result.folderPath).join(', '),
      scannedFiles: items.fold(0, (sum, result) => sum + result.scannedFiles),
      addedTracks: items.fold(0, (sum, result) => sum + result.addedTracks),
      updatedTracks: items.fold(0, (sum, result) => sum + result.updatedTracks),
      missingTracks: items.fold(0, (sum, result) => sum + result.missingTracks),
      errors: [
        for (final result in items) ...result.errors,
      ],
    );
  }
}

final class LibraryScannerService {
  const LibraryScannerService({
    required this.libraryRepository,
    required this.trackRepository,
    required this.metadataReader,
    this.artworkCache = const NoopArtworkCacheService(),
    this.listEntities = _defaultDirectoryEntityLister,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LibraryRepository libraryRepository;
  final TrackRepository trackRepository;
  final MetadataReaderService metadataReader;
  final ArtworkCacheService artworkCache;
  final DirectoryEntityLister listEntities;
  final DateTime Function() _clock;

  Future<LibraryScanResult> scanFolder(String folderPath) async {
    final normalizedRootPath = p.normalize(Directory(folderPath).absolute.path);
    final rootDirectory = Directory(normalizedRootPath);
    final errors = <LibraryScanError>[];

    if (!await rootDirectory.exists()) {
      return LibraryScanResult(
        folderPath: normalizedRootPath,
        scannedFiles: 0,
        addedTracks: 0,
        updatedTracks: 0,
        missingTracks: 0,
        errors: [
          LibraryScanError(
            path: normalizedRootPath,
            message: 'Folder does not exist.',
          ),
        ],
      );
    }

    final now = _clock();
    final folder = await _ensureFolder(normalizedRootPath, now);
    final folderId = folder.id!;
    final knownTracks = await trackRepository.listTracksByLibraryFolder(
      folderId,
      includeMissing: true,
    );
    final knownByStableId = {
      for (final track in knownTracks)
        if (track.stableId != null) track.stableId!: track,
    };
    final knownByFilePath = {
      for (final track in knownTracks) p.normalize(track.filePath): track,
    };
    final knownById = {
      for (final track in knownTracks)
        if (track.id != null) track.id!: track,
    };
    final seenKnownTrackIds = <int>{};
    final unchangedTrackIds = <int>[];

    var scannedFiles = 0;
    var addedTracks = 0;
    var updatedTracks = 0;
    var completedDirectoryTraversal = false;

    try {
      await for (final entity in listEntities(rootDirectory)) {
        if (_shouldIgnoreEntity(entity, rootPath: normalizedRootPath)) {
          continue;
        }
        if (entity is! File || !isSupportedAudioFilePath(entity.path)) {
          continue;
        }

        scannedFiles++;

        try {
          final fileStat = await entity.stat();
          final normalizedFilePath = p.normalize(entity.absolute.path);
          final existingByPath = knownByFilePath[normalizedFilePath];
          final existingId = existingByPath?.id;
          if (existingId != null &&
              _isUnchangedFile(existingByPath!, fileStat)) {
            updatedTracks++;
            seenKnownTrackIds.add(existingId);
            unchangedTrackIds.add(existingId);
            continue;
          }

          final metadata = await metadataReader.read(entity);
          final artwork = await _cacheArtwork(metadata.artwork);
          final track = _trackFromMetadata(
            metadata: metadata,
            artwork: artwork,
            folderId: folderId,
            knownByStableId: knownByStableId,
            knownByFilePath: knownByFilePath,
            now: now,
          );
          final wasKnown = track.id != null;
          final savedId = await trackRepository.upsertTrack(track);

          if (wasKnown) {
            updatedTracks++;
            seenKnownTrackIds.add(savedId);
          } else {
            addedTracks++;
          }
        } on Object catch (error) {
          errors.add(
            LibraryScanError(
              path: entity.path,
              message: error.toString(),
            ),
          );
        }
      }
      completedDirectoryTraversal = true;
    } on Object catch (error) {
      errors.add(
        LibraryScanError(
          path: normalizedRootPath,
          message: error.toString(),
        ),
      );
    }

    var missingTracks = 0;
    await _markTracksSeen(unchangedTrackIds, knownById, now);

    if (completedDirectoryTraversal) {
      final missingTrackIds = <int>[];
      for (final track in knownTracks) {
        final id = track.id;
        if (id == null || seenKnownTrackIds.contains(id) || track.isMissing) {
          continue;
        }

        missingTrackIds.add(id);
        missingTracks++;
      }
      await _markTracksMissing(missingTrackIds, knownById, now);
    }

    await libraryRepository.upsertFolder(
      folder.copyWith(
        lastScannedAt: now,
        updatedAt: now,
      ),
    );

    return LibraryScanResult(
      folderPath: normalizedRootPath,
      scannedFiles: scannedFiles,
      addedTracks: addedTracks,
      updatedTracks: updatedTracks,
      missingTracks: missingTracks,
      errors: errors,
    );
  }

  bool _isUnchangedFile(Track track, FileStat stat) {
    final fileSizeBytes = track.fileSizeBytes;
    final modifiedAt = track.modifiedAt;
    return fileSizeBytes != null &&
        modifiedAt != null &&
        fileSizeBytes == stat.size &&
        _sameUtcMillisecond(modifiedAt, stat.modified);
  }

  Future<void> _markTracksSeen(
    List<int> trackIds,
    Map<int, Track> knownById,
    DateTime seenAt,
  ) async {
    if (trackIds.isEmpty) {
      return;
    }

    final scanRepository = trackRepository is TrackScanRepository
        ? trackRepository as TrackScanRepository
        : null;
    if (scanRepository != null) {
      await scanRepository.markTracksSeen(trackIds: trackIds, seenAt: seenAt);
      return;
    }

    for (final trackId in trackIds) {
      final track = knownById[trackId];
      if (track == null) {
        continue;
      }
      await trackRepository.upsertTrack(
        track.copyWith(
          lastSeenAt: seenAt,
          isMissing: false,
          updatedAt: seenAt,
        ),
      );
    }
  }

  Future<void> _markTracksMissing(
    List<int> trackIds,
    Map<int, Track> knownById,
    DateTime updatedAt,
  ) async {
    if (trackIds.isEmpty) {
      return;
    }

    final scanRepository = trackRepository is TrackScanRepository
        ? trackRepository as TrackScanRepository
        : null;
    if (scanRepository != null) {
      await scanRepository.markTracksMissing(
        trackIds: trackIds,
        updatedAt: updatedAt,
      );
      return;
    }

    for (final trackId in trackIds) {
      final track = knownById[trackId];
      if (track == null) {
        continue;
      }
      await trackRepository.upsertTrack(
        track.copyWith(
          isMissing: true,
          updatedAt: updatedAt,
        ),
      );
    }
  }

  Future<LibraryFolder> _ensureFolder(String folderPath, DateTime now) async {
    final existing = await libraryRepository.findFolderByPath(folderPath);
    if (existing != null) {
      return existing;
    }

    final folder = LibraryFolder(
      path: folderPath,
      displayName: p.basename(folderPath),
      createdAt: now,
      updatedAt: now,
    );
    final id = await libraryRepository.upsertFolder(folder);
    return folder.copyWith(id: id);
  }

  Track _trackFromMetadata({
    required AudioMetadata metadata,
    required CachedArtwork? artwork,
    required int folderId,
    required Map<String, Track> knownByStableId,
    required Map<String, Track> knownByFilePath,
    required DateTime now,
  }) {
    final durationMs = metadata.duration?.inMilliseconds;
    final stableId = generateStableTrackId(
      filePath: metadata.filePath,
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album,
      fileSizeBytes: metadata.fileSizeBytes,
      durationMs: durationMs,
    );
    final existing = knownByFilePath[p.normalize(metadata.filePath)] ??
        knownByStableId[stableId];
    final preserveManualMetadata =
        existing?.metadataSource == MetadataSource.manual;

    return Track(
      id: existing?.id,
      libraryFolderId: folderId,
      stableId:
          preserveManualMetadata ? existing?.stableId ?? stableId : stableId,
      filePath: metadata.filePath,
      contentHash: existing?.contentHash,
      title: preserveManualMetadata ? existing?.title : metadata.title,
      artist: preserveManualMetadata ? existing?.artist : metadata.artist,
      album: preserveManualMetadata ? existing?.album : metadata.album,
      albumArtist:
          preserveManualMetadata ? existing?.albumArtist : metadata.albumArtist,
      genre: preserveManualMetadata ? existing?.genre : metadata.genre,
      artworkPath: artwork?.path ?? existing?.artworkPath,
      artworkHash: artwork?.hash ?? existing?.artworkHash,
      artworkMimeType: artwork?.mimeType ?? existing?.artworkMimeType,
      customArtworkPath: existing?.customArtworkPath,
      customArtworkHash: existing?.customArtworkHash,
      customArtworkMimeType: existing?.customArtworkMimeType,
      codec: metadata.codec,
      duration: metadata.duration,
      trackNumber:
          preserveManualMetadata ? existing?.trackNumber : metadata.trackNumber,
      discNumber:
          preserveManualMetadata ? existing?.discNumber : metadata.discNumber,
      year: preserveManualMetadata ? existing?.year : metadata.year,
      metadataSource: preserveManualMetadata
          ? MetadataSource.manual
          : metadata.metadataSource,
      metadataConfidence:
          preserveManualMetadata ? 1.0 : metadata.metadataConfidence,
      fileSizeBytes: metadata.fileSizeBytes,
      modifiedAt: metadata.modifiedAt,
      lastSeenAt: now,
      isMissing: false,
      addedAt: existing?.addedAt ?? now,
      updatedAt: now,
    );
  }

  Future<CachedArtwork?> _cacheArtwork(EmbeddedArtwork? artwork) async {
    if (artwork == null) {
      return null;
    }

    try {
      return await artworkCache.saveEmbeddedArtwork(artwork);
    } on Object {
      return null;
    }
  }

  bool _shouldIgnoreEntity(FileSystemEntity entity,
      {required String rootPath}) {
    final relativePath = p.relative(entity.path, from: rootPath);
    if (relativePath == '.') {
      return false;
    }

    final segments = p.split(relativePath);
    return segments.any(_isHiddenOrSystemSegment);
  }

  bool _isHiddenOrSystemSegment(String segment) {
    final lower = segment.toLowerCase();
    return segment.startsWith('.') ||
        lower == r'$recycle.bin' ||
        lower == 'system volume information' ||
        lower == '__macosx' ||
        lower == 'thumbs.db' ||
        lower == 'desktop.ini';
  }
}

bool _sameUtcMillisecond(DateTime left, DateTime right) {
  return left.toUtc().millisecondsSinceEpoch ==
      right.toUtc().millisecondsSinceEpoch;
}
