import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../diagnostics/diagnostics_service.dart';
import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';
import 'artwork_cache_service.dart';
import 'file_content_hasher.dart';
import 'library_scan_control.dart';
import 'library_scan_metrics.dart';
import 'sha256_digest.dart';
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
    this.wasCancelled = false,
    int? processedFiles,
    this.metrics = const LibraryScanMetrics(),
  }) : _processedFiles = processedFiles;

  factory LibraryScanResult.cancelled(String folderPath) => LibraryScanResult(
      folderPath: folderPath,
      scannedFiles: 0,
      addedTracks: 0,
      updatedTracks: 0,
      missingTracks: 0,
      errors: const [],
      wasCancelled: true);

  final String folderPath;
  final int scannedFiles;
  final int addedTracks;
  final int updatedTracks;
  final int missingTracks;
  final List<LibraryScanError> errors;
  final bool wasCancelled;
  final LibraryScanMetrics metrics;
  final int? _processedFiles;
  int get processedFiles => _processedFiles ?? scannedFiles;

  bool get hasErrors => errors.isNotEmpty;

  String get summary {
    final text =
        'Просканировано файлов: $processedFiles, добавлено: $addedTracks, '
        'обновлено: $updatedTracks, отсутствует: $missingTracks.';
    return wasCancelled ? 'Сканирование остановлено. $text' : text;
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
      wasCancelled: items.any((result) => result.wasCancelled),
      processedFiles:
          items.fold<int>(0, (sum, result) => sum + result.processedFiles),
      metrics:
          LibraryScanMetrics.combine(items.map((result) => result.metrics)),
    );
  }
}

final class LibraryScannerService {
  const LibraryScannerService({
    required this.libraryRepository,
    required this.trackRepository,
    required this.metadataReader,
    this.artworkCache = const NoopArtworkCacheService(),
    this.contentHasher = const Sha256FileContentHasher(),
    this.reuseHashWorker = true,
    this.listEntities = _defaultDirectoryEntityLister,
    this.diagnostics = const NoopDiagnosticsService(),
    this.importBatchSize = TrackImportRepository.maxBatchSize,
    this.importFlushInterval = const Duration(milliseconds: 750),
    DateTime Function()? clock,
  })  : assert(importBatchSize > 0 &&
            importBatchSize <= TrackImportRepository.maxBatchSize),
        _clock = clock ?? DateTime.now;

  final DiagnosticsService diagnostics;
  final LibraryRepository libraryRepository;
  final TrackRepository trackRepository;
  final MetadataReaderService metadataReader;
  final ArtworkCacheService artworkCache;
  final FileContentHasher contentHasher;
  final bool reuseHashWorker;
  final DirectoryEntityLister listEntities;
  final int importBatchSize;
  final Duration importFlushInterval;
  final DateTime Function() _clock;

  Future<LibraryScanResult> scanFolder(
    String folderPath, {
    LibraryScanControl? control,
  }) async {
    if (importBatchSize <= 0 ||
        importBatchSize > TrackImportRepository.maxBatchSize ||
        importFlushInterval.isNegative) {
      throw ArgumentError('Invalid import batch configuration.');
    }
    final timer = Stopwatch()..start();
    final metrics = ScanMetricsRecorder();
    final configuredHasher = contentHasher;
    final session =
        reuseHashWorker && configuredHasher is SessionFileContentHasher
            ? (configuredHasher as SessionFileContentHasher).openSession()
            : null;
    diagnostics.record(DiagnosticEvent.scanStarted);
    try {
      late LibraryScanResult scanned;
      try {
        scanned = await _scanFolder(folderPath,
            control: control,
            metrics: metrics,
            hasher: session ?? configuredHasher);
      } finally {
        await session?.close();
      }
      final result = LibraryScanResult(
          folderPath: scanned.folderPath,
          scannedFiles: scanned.scannedFiles,
          addedTracks: scanned.addedTracks,
          updatedTracks: scanned.updatedTracks,
          missingTracks: scanned.missingTracks,
          errors: scanned.errors,
          wasCancelled: scanned.wasCancelled,
          processedFiles: scanned.processedFiles,
          metrics: metrics.snapshot());
      diagnostics.record(
          result.wasCancelled
              ? DiagnosticEvent.scanCancelled
              : DiagnosticEvent.scanCompleted,
          fields: {
            DiagnosticField.elapsedMs: timer.elapsedMilliseconds,
            DiagnosticField.scannedFiles: result.processedFiles,
            DiagnosticField.addedTracks: result.addedTracks,
            DiagnosticField.updatedTracks: result.updatedTracks,
            DiagnosticField.missingTracks: result.missingTracks,
            DiagnosticField.errorCount: result.errors.length,
            ..._metricFields(result.metrics),
          });
      return result;
    } on Object catch (error) {
      diagnostics.record(DiagnosticEvent.scanFailed, error: error, fields: {
        DiagnosticField.elapsedMs: timer.elapsedMilliseconds,
        ..._metricFields(metrics.snapshot())
      });
      rethrow;
    }
  }

  Future<LibraryScanResult> _scanFolder(
    String folderPath, {
    LibraryScanControl? control,
    required ScanMetricsRecorder metrics,
    required FileContentHasher hasher,
  }) async {
    final activeControl = control ?? LibraryScanControl();
    final normalizedRootPath = p.normalize(Directory(folderPath).absolute.path);
    final rootDirectory = Directory(normalizedRootPath);
    final errors = <LibraryScanError>[];

    if (activeControl.isCancellationRequested) {
      return LibraryScanResult.cancelled(normalizedRootPath);
    }

    final rootExists =
        await metrics.measure(ScanTimingPhase.fileSystem, rootDirectory.exists);
    if (activeControl.isCancellationRequested) {
      return LibraryScanResult.cancelled(normalizedRootPath);
    }
    if (!rootExists) {
      return LibraryScanResult(
        folderPath: normalizedRootPath,
        scannedFiles: 0,
        addedTracks: 0,
        updatedTracks: 0,
        missingTracks: 0,
        errors: [
          LibraryScanError(
            path: normalizedRootPath,
            message: 'Папка не существует.',
          ),
        ],
      );
    }

    final now = _clock();
    final folder = await metrics.measureDatabase(
        ScanDatabaseOperation.maintenance,
        () => _ensureFolder(normalizedRootPath, now));
    final folderId = folder.id!;
    final knownTracks = await metrics.measureDatabase(
        ScanDatabaseOperation.lookup,
        () => trackRepository.listTracksByLibraryFolder(
              folderId,
              includeMissing: true,
            ));
    final knownByFilePath = {
      for (final track in knownTracks) p.normalize(track.filePath): track,
    };
    final knownById = {
      for (final track in knownTracks)
        if (track.id != null) track.id!: track,
    };
    final seenKnownTrackIds = <int>{};
    final scanStateOnlyTrackIds = <int>[];
    final contentHashes = <int, String?>{};
    final pendingTracks = <_PreparedScanTrack>[];
    final flushTimer = Stopwatch()..start();
    final importer = trackRepository is TrackImportRepository
        ? trackRepository as TrackImportRepository
        : null;

    var scannedFiles = 0;
    var addedTracks = 0;
    var updatedTracks = 0;
    var completedDirectoryTraversal = false;
    var processedFiles = 0;
    String? currentFileName;
    void report(LibraryScanStage stage, {int bytesRead = 0, int? sizeBytes}) {
      activeControl.report(LibraryScanProgress(
        folderPath: normalizedRootPath,
        stage: stage,
        processedFiles: processedFiles,
        addedTracks: addedTracks,
        updatedTracks: updatedTracks,
        errorCount: errors.length,
        fileName: currentFileName,
        fileBytesRead: bytesRead,
        fileSizeBytes: sizeBytes,
        metrics: metrics.snapshot(),
      ));
    }

    Future<void> flushPendingTracks() async {
      if (pendingTracks.isEmpty) return;
      final preparedFiles = List<_PreparedScanTrack>.of(pendingTracks);
      pendingTracks.clear();
      Future<void> save(List<Track> prepared) async {
        final ids = await metrics.measureDatabase(ScanDatabaseOperation.import,
            () async {
          if (importer != null) return importer.upsertScannedTracks(prepared);
          return [await trackRepository.upsertTrack(prepared.single)];
        });
        metrics.committedImport(rows: prepared.length);
        for (var index = 0; index < prepared.length; index++) {
          final track = prepared[index];
          final id = ids[index];
          if (track.id != null) {
            updatedTracks++;
            seenKnownTrackIds.add(id);
          } else {
            addedTracks++;
          }
          knownByFilePath[track.filePath] = track.copyWith(id: id);
          knownById[id] = track.copyWith(id: id);
          // This identity was already saved with the track, in one commit.
          contentHashes.remove(id);
        }
      }

      void failed(Track track, Object error) {
        diagnostics.record(DiagnosticEvent.scanFileFailed,
            error: error, fields: {DiagnosticField.trackId: track.id});
        final id = track.id;
        if (id != null) {
          scanStateOnlyTrackIds.add(id);
          contentHashes[id] = null;
        }
        errors.add(
            LibraryScanError(path: track.filePath, message: error.toString()));
      }

      final batch = <Track>[];
      for (final prepared in preparedFiles) {
        try {
          final fingerprint = prepared.fingerprint;
          if (fingerprint != null &&
              !await metrics.measure(
                  ScanTimingPhase.fileSystem,
                  () =>
                      fingerprint.matchesFile(File(prepared.track.filePath)))) {
            throw FileSystemException(
                'Файл изменился до сохранения. Повторите сканирование.',
                prepared.track.filePath);
          }
          batch.add(prepared.track);
        } on Object catch (error) {
          failed(prepared.track, error);
        }
      }
      try {
        if (batch.isNotEmpty) await save(batch);
      } on Object catch (error) {
        // Atomic rollback allows isolating a bad row without losing good files.
        if (batch.length == 1) {
          failed(batch.single, error);
        } else {
          for (final track in batch) {
            try {
              await save([track]);
            } on Object catch (error) {
              failed(track, error);
            }
          }
        }
      }
      flushTimer.reset();
    }

    report(LibraryScanStage.discovering);

    try {
      await for (final entity in _cancellableEntities(
          listEntities(rootDirectory), activeControl, metrics)) {
        activeControl.throwIfCancelled();
        if (_shouldIgnoreEntity(entity, rootPath: normalizedRootPath)) {
          continue;
        }
        if (entity is! File || !isSupportedAudioFilePath(entity.path)) {
          continue;
        }

        scannedFiles++;
        currentFileName = p.basename(entity.path);
        var fileWasCancelled = false;

        Track? existingByPath;
        void discardPartialFile() {
          fileWasCancelled = true;
          final id = existingByPath?.id;
          if (id != null) {
            contentHashes.remove(id);
            knownById[id] = existingByPath!;
          }
        }

        try {
          final normalizedFilePath = p.normalize(entity.absolute.path);
          existingByPath = knownByFilePath[normalizedFilePath] ??
              await metrics.measureDatabase(ScanDatabaseOperation.lookup,
                  () => trackRepository.findByPath(normalizedFilePath));
          activeControl.throwIfCancelled();
          final existingId = existingByPath?.id;
          if (existingId != null) {
            // Seeing a file and successfully reading its tags are separate
            // facts. A read error must not make an observed track disappear.
            seenKnownTrackIds.add(existingId);
            knownById[existingId] = existingByPath!;
            // A failed check must invalidate a previous duplicate decision.
            contentHashes[existingId] = null;
          }
          final fileStat =
              await metrics.measure(ScanTimingPhase.fileSystem, entity.stat);
          activeControl.throwIfCancelled();
          FileContentFingerprint? fingerprint;
          try {
            // Explicit scans re-read bytes even if size/mtime were preserved.
            report(LibraryScanStage.hashing, sizeBytes: fileStat.size);
            activeControl.throwIfCancelled();
            final verified = await metrics.measure(
                ScanTimingPhase.hashing,
                () => control != null && hasher is ControlledFileContentHasher
                    ? hasher.hashFileWithControl(
                        entity,
                        control: activeControl,
                        onProgress: (progress) => report(
                            LibraryScanStage.hashing,
                            bytesRead: progress.bytesRead,
                            sizeBytes: progress.totalBytes),
                      )
                    : hasher.hashFile(entity));
            fingerprint = verified;
            metrics.verifiedHash(
                bytes: verified.sizeBytes,
                native: verified.backend == Sha256Backend.windowsCng,
                readUs: verified.timings.ioUs,
                computeUs: verified.timings.digestUs,
                workerUs: verified.timings.workerUs,
                overheadUs: verified.timings.roundTripUs,
                startupUs: verified.timings.startupUs,
                workerStarts: verified.timings.workerStarts);
          } on LibraryScanCancelled {
            rethrow;
          } on Object catch (error) {
            activeControl.throwIfCancelled();
            diagnostics.record(DiagnosticEvent.scanFileFailed,
                error: error, fields: {DiagnosticField.trackId: existingId});
            errors.add(LibraryScanError(
              path: entity.path,
              message: 'Не удалось проверить точные копии: $error',
            ));
          }
          activeControl.throwIfCancelled();
          final contentHash = fingerprint?.storageKey;
          if (existingId != null) {
            contentHashes[existingId] = contentHash;
            knownById[existingId] =
                existingByPath!.copyWith(contentHash: contentHash);
          }
          final previousHash =
              verifiedFileContentKey(existingByPath?.contentHash);
          final contentChanged = previousHash != null &&
              contentHash != null &&
              previousHash != contentHash;
          if (existingId != null &&
              !contentChanged &&
              _isUnchangedFile(existingByPath!, fileStat)) {
            updatedTracks++;
            scanStateOnlyTrackIds.add(existingId);
            continue;
          }

          report(LibraryScanStage.readingMetadata);
          activeControl.throwIfCancelled();
          final metadata = await metrics.measure(
              ScanTimingPhase.metadata, () => metadataReader.read(entity));
          activeControl.throwIfCancelled();
          final artwork = await metrics.measure(
              ScanTimingPhase.artwork, () => _cacheArtwork(metadata.artwork));
          activeControl.throwIfCancelled();
          if (fingerprint != null &&
              !await metrics.measure(ScanTimingPhase.fileSystem,
                  () => fingerprint!.matchesFile(entity))) {
            throw FileSystemException(
              'Файл изменился во время сканирования. Повторите сканирование.',
              entity.path,
            );
          }
          activeControl.throwIfCancelled();
          final track = _trackFromMetadata(
            metadata: metadata,
            artwork: artwork,
            folderId: folderId,
            filePath: normalizedFilePath,
            existing: existingByPath,
            contentHash: contentHash,
            now: now,
          );
          report(LibraryScanStage.saving);
          activeControl.throwIfCancelled();
          if (pendingTracks
              .any((item) => item.track.filePath == track.filePath)) {
            await flushPendingTracks();
            activeControl.throwIfCancelled();
            pendingTracks.add(_PreparedScanTrack(
                track.copyWith(id: knownByFilePath[track.filePath]?.id),
                fingerprint));
          } else {
            pendingTracks.add(_PreparedScanTrack(track, fingerprint));
          }
        } on LibraryScanCancelled {
          discardPartialFile();
          rethrow;
        } on Object catch (error) {
          if (activeControl.isCancellationRequested) {
            discardPartialFile();
            throw const LibraryScanCancelled();
          }
          diagnostics.record(DiagnosticEvent.scanFileFailed,
              error: error,
              fields: {DiagnosticField.trackId: existingByPath?.id});
          final existingId = existingByPath?.id;
          if (existingId != null) {
            scanStateOnlyTrackIds.add(existingId);
            contentHashes[existingId] = null;
            knownById[existingId] = existingByPath!.copyWith(contentHash: null);
          }
          errors.add(
            LibraryScanError(
              path: entity.path,
              message: error.toString(),
            ),
          );
        } finally {
          if (!fileWasCancelled) {
            processedFiles++;
            currentFileName = null;
            report(LibraryScanStage.discovering);
            if (!activeControl.isCancellationRequested &&
                (importer == null ||
                    pendingTracks.length >= importBatchSize ||
                    flushTimer.elapsed >= importFlushInterval)) {
              await flushPendingTracks();
              report(LibraryScanStage.discovering);
            }
          }
        }
      }
      completedDirectoryTraversal = true;
    } on LibraryScanCancelled {
      // Completed files are committed below; unseen files keep their state.
    } on Object catch (error) {
      diagnostics.record(DiagnosticEvent.scanTraversalFailed, error: error);
      errors.add(
        LibraryScanError(
          path: normalizedRootPath,
          message: error.toString(),
        ),
      );
    }

    var missingTracks = 0;
    currentFileName = null;
    report(LibraryScanStage.finishing);
    // Even on cancellation, already prepared files survive. No partial file
    // enters this buffer, and no transaction stays open while reading audio.
    await flushPendingTracks();
    await metrics.measureDatabase(ScanDatabaseOperation.maintenance,
        () => _markTracksSeen(scanStateOnlyTrackIds, knownById, now));

    final completed =
        completedDirectoryTraversal && !activeControl.isCancellationRequested;
    if (completed) {
      final missingTrackIds = <int>[];
      for (final track in knownTracks) {
        final id = track.id;
        if (id == null || seenKnownTrackIds.contains(id) || track.isMissing) {
          continue;
        }

        missingTrackIds.add(id);
        missingTracks++;
      }
      await metrics.measureDatabase(ScanDatabaseOperation.maintenance,
          () => _markTracksMissing(missingTrackIds, knownById, now));
    }

    await metrics.measureDatabase(ScanDatabaseOperation.maintenance,
        () => _saveContentHashes(contentHashes));

    if (completed) {
      await metrics.measureDatabase(
          ScanDatabaseOperation.maintenance,
          () => libraryRepository.upsertFolder(
                folder.copyWith(
                  lastScannedAt: now,
                  updatedAt: now,
                ),
              ));
    }

    report(LibraryScanStage.finishing);
    return LibraryScanResult(
      folderPath: normalizedRootPath,
      scannedFiles: scannedFiles,
      addedTracks: addedTracks,
      updatedTracks: updatedTracks,
      missingTracks: missingTracks,
      errors: errors,
      wasCancelled: activeControl.isCancellationRequested,
      processedFiles: processedFiles,
      metrics: metrics.snapshot(),
    );
  }

  Stream<FileSystemEntity> _cancellableEntities(
    Stream<FileSystemEntity> entities,
    LibraryScanControl control,
    ScanMetricsRecorder metrics,
  ) async* {
    final iterator = StreamIterator(entities);
    Future<void>? stopping;
    void stopListing() {
      stopping ??= iterator.cancel().catchError((Object _) {
        // A close error during requested cancellation is not a file read error.
      });
    }

    control.addCancellationListener(stopListing);
    try {
      while (await metrics.measure(
          ScanTimingPhase.fileSystem, iterator.moveNext)) {
        control.throwIfCancelled();
        yield iterator.current;
      }
      control.throwIfCancelled();
    } finally {
      control.removeCancellationListener(stopListing);
      await (stopping ?? iterator.cancel());
    }
  }

  bool _isUnchangedFile(Track track, FileStat stat) {
    final fileSizeBytes = track.fileSizeBytes;
    final modifiedAt = track.modifiedAt;
    return fileSizeBytes != null &&
        modifiedAt != null &&
        fileSizeBytes == stat.size &&
        _sameUtcMillisecond(modifiedAt, stat.modified);
  }

  Future<void> _saveContentHashes(
    Map<int, String?> hashes,
  ) async {
    if (hashes.isEmpty) return;
    final repository = trackRepository;
    if (repository is TrackContentHashRepository) {
      await (repository as TrackContentHashRepository)
          .updateContentHashes(hashes);
    } else {
      for (final entry in hashes.entries) {
        final track = await repository.findById(entry.key);
        if (track != null) {
          await repository
              .upsertTrack(track.copyWith(contentHash: entry.value));
        }
      }
    }
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
    required String filePath,
    required Track? existing,
    required String? contentHash,
    required DateTime now,
  }) {
    final durationMs = metadata.duration?.inMilliseconds;
    final stableId = generateStableTrackId(
      filePath: filePath,
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album,
      fileSizeBytes: metadata.fileSizeBytes,
      durationMs: durationMs,
    );
    final preserveManualMetadata =
        existing?.metadataSource == MetadataSource.manual;

    return Track(
      id: existing?.id,
      libraryFolderId: existing?.libraryFolderId ?? folderId,
      stableId:
          preserveManualMetadata ? existing?.stableId ?? stableId : stableId,
      filePath: filePath,
      contentHash: contentHash,
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

final class _PreparedScanTrack {
  const _PreparedScanTrack(this.track, this.fingerprint);
  final Track track;
  final FileContentFingerprint? fingerprint;
}

bool _sameUtcMillisecond(DateTime left, DateTime right) {
  return left.toUtc().millisecondsSinceEpoch ==
      right.toUtc().millisecondsSinceEpoch;
}

Map<DiagnosticField, Object?> _metricFields(LibraryScanMetrics metrics) => {
      DiagnosticField.hashUs: metrics.hashUs,
      DiagnosticField.metadataUs: metrics.metadataUs,
      DiagnosticField.artworkUs: metrics.artworkUs,
      DiagnosticField.databaseUs: metrics.databaseUs,
      DiagnosticField.hashedBytes: metrics.hashedBytes,
      DiagnosticField.hashedFiles: metrics.hashedFiles,
      DiagnosticField.nativeHashFiles: metrics.nativeHashFiles,
      DiagnosticField.metadataReads: metrics.metadataReads,
      DiagnosticField.fileSystemUs: metrics.fileSystemUs,
      DiagnosticField.importBatches: metrics.importBatches,
      DiagnosticField.importRows: metrics.importRows,
      DiagnosticField.hashReadUs: metrics.hashReadUs,
      DiagnosticField.hashComputeUs: metrics.hashComputeUs,
      DiagnosticField.hashWorkerUs: metrics.hashWorkerUs,
      DiagnosticField.hashOverheadUs: metrics.hashOverheadUs,
      DiagnosticField.hashStartupUs: metrics.hashStartupUs,
      DiagnosticField.hashWorkerStarts: metrics.hashWorkerStarts,
      DiagnosticField.databaseLookupUs: metrics.databaseLookupUs,
      DiagnosticField.databaseImportUs: metrics.databaseImportUs,
      DiagnosticField.databaseMaintenanceUs: metrics.databaseMaintenanceUs,
    };
