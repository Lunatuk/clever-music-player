enum ScanTimingPhase { hashing, metadata, artwork, database, fileSystem }

enum ScanDatabaseOperation { lookup, import, maintenance }

final class LibraryScanMetrics {
  const LibraryScanMetrics({
    this.elapsedUs = 0,
    this.hashUs = 0,
    this.metadataUs = 0,
    this.artworkUs = 0,
    this.databaseUs = 0,
    this.hashedBytes = 0,
    this.hashedFiles = 0,
    this.nativeHashFiles = 0,
    this.metadataReads = 0,
    this.fileSystemUs = 0,
    this.importBatches = 0,
    this.importRows = 0,
    this.hashReadUs = 0,
    this.hashComputeUs = 0,
    this.hashWorkerUs = 0,
    this.hashOverheadUs = 0,
    this.hashStartupUs = 0,
    this.hashWorkerStarts = 0,
    this.databaseLookupUs = 0,
    this.databaseImportUs = 0,
    this.databaseMaintenanceUs = 0,
  });
  final int elapsedUs;
  final int hashUs;
  final int metadataUs;
  final int artworkUs;
  final int databaseUs;
  final int hashedBytes;
  final int hashedFiles;
  final int nativeHashFiles;
  final int metadataReads;
  final int fileSystemUs;
  final int importBatches;
  final int importRows;
  final int hashReadUs,
      hashComputeUs,
      hashWorkerUs,
      hashOverheadUs,
      hashStartupUs,
      hashWorkerStarts;
  final int databaseLookupUs, databaseImportUs, databaseMaintenanceUs;

  static LibraryScanMetrics combine(Iterable<LibraryScanMetrics> metrics) {
    var elapsed = 0, hash = 0, metadata = 0, artwork = 0, database = 0;
    var bytes = 0, files = 0, native = 0, reads = 0;
    var fileSystem = 0, batches = 0, rows = 0;
    var hashRead = 0,
        hashCompute = 0,
        worker = 0,
        overhead = 0,
        startup = 0,
        starts = 0;
    var lookup = 0, imports = 0, maintenance = 0;
    for (final item in metrics) {
      elapsed += item.elapsedUs;
      hash += item.hashUs;
      metadata += item.metadataUs;
      artwork += item.artworkUs;
      database += item.databaseUs;
      bytes += item.hashedBytes;
      files += item.hashedFiles;
      native += item.nativeHashFiles;
      reads += item.metadataReads;
      fileSystem += item.fileSystemUs;
      batches += item.importBatches;
      rows += item.importRows;
      hashRead += item.hashReadUs;
      hashCompute += item.hashComputeUs;
      worker += item.hashWorkerUs;
      overhead += item.hashOverheadUs;
      startup += item.hashStartupUs;
      starts += item.hashWorkerStarts;
      lookup += item.databaseLookupUs;
      imports += item.databaseImportUs;
      maintenance += item.databaseMaintenanceUs;
    }
    return LibraryScanMetrics(
        elapsedUs: elapsed,
        hashUs: hash,
        metadataUs: metadata,
        artworkUs: artwork,
        databaseUs: database,
        hashedBytes: bytes,
        hashedFiles: files,
        nativeHashFiles: native,
        metadataReads: reads,
        fileSystemUs: fileSystem,
        importBatches: batches,
        importRows: rows,
        hashReadUs: hashRead,
        hashComputeUs: hashCompute,
        hashWorkerUs: worker,
        hashOverheadUs: overhead,
        hashStartupUs: startup,
        hashWorkerStarts: starts,
        databaseLookupUs: lookup,
        databaseImportUs: imports,
        databaseMaintenanceUs: maintenance);
  }
}

/// Sequential phase timings include awaits/worker startup and failed attempts.
/// No filenames, paths, metadata or artwork bytes are retained here.
final class ScanMetricsRecorder {
  final _total = Stopwatch()..start();
  final _timings = <ScanTimingPhase, int>{};
  final _databaseTimings = <ScanDatabaseOperation, int>{};
  var _bytes = 0, _files = 0, _native = 0, _reads = 0;
  var _batches = 0, _rows = 0;
  var _hashRead = 0,
      _hashCompute = 0,
      _worker = 0,
      _overhead = 0,
      _startup = 0,
      _starts = 0;

  Future<T> measure<T>(ScanTimingPhase phase, Future<T> Function() work) async {
    final timer = Stopwatch()..start();
    if (phase == ScanTimingPhase.metadata) _reads++;
    try {
      return await work();
    } finally {
      _timings.update(phase, (value) => value + timer.elapsedMicroseconds,
          ifAbsent: () => timer.elapsedMicroseconds);
    }
  }

  Future<T> measureDatabase<T>(
          ScanDatabaseOperation operation, Future<T> Function() work) =>
      measure(ScanTimingPhase.database, () async {
        final timer = Stopwatch()..start();
        try {
          return await work();
        } finally {
          _databaseTimings.update(
              operation, (value) => value + timer.elapsedMicroseconds,
              ifAbsent: () => timer.elapsedMicroseconds);
        }
      });

  void verifiedHash(
      {required int bytes,
      required bool native,
      int readUs = 0,
      int computeUs = 0,
      int workerUs = 0,
      int overheadUs = 0,
      int startupUs = 0,
      int workerStarts = 0}) {
    _bytes += bytes;
    _files++;
    if (native) _native++;
    _hashRead += readUs;
    _hashCompute += computeUs;
    _worker += workerUs;
    _overhead += overheadUs;
    _startup += startupUs;
    _starts += workerStarts;
  }

  void committedImport({required int rows}) {
    _batches++;
    _rows += rows;
  }

  LibraryScanMetrics snapshot() => LibraryScanMetrics(
        elapsedUs: _total.elapsedMicroseconds,
        hashUs: _timings[ScanTimingPhase.hashing] ?? 0,
        metadataUs: _timings[ScanTimingPhase.metadata] ?? 0,
        artworkUs: _timings[ScanTimingPhase.artwork] ?? 0,
        databaseUs: _timings[ScanTimingPhase.database] ?? 0,
        hashedBytes: _bytes,
        hashedFiles: _files,
        nativeHashFiles: _native,
        metadataReads: _reads,
        fileSystemUs: _timings[ScanTimingPhase.fileSystem] ?? 0,
        importBatches: _batches,
        importRows: _rows,
        hashReadUs: _hashRead,
        hashComputeUs: _hashCompute,
        hashWorkerUs: _worker,
        hashOverheadUs: _overhead,
        hashStartupUs: _startup,
        hashWorkerStarts: _starts,
        databaseLookupUs: _databaseTimings[ScanDatabaseOperation.lookup] ?? 0,
        databaseImportUs: _databaseTimings[ScanDatabaseOperation.import] ?? 0,
        databaseMaintenanceUs:
            _databaseTimings[ScanDatabaseOperation.maintenance] ?? 0,
      );
}
