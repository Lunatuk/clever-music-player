import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/library_scan_metrics.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late AppDatabase database;
  late DriftRepositories repositories;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cmp_scan_metrics_');
    database = AppDatabase(NativeDatabase.memory());
    repositories = DriftRepositories(database);
    await File(p.join(root.path, 'track.wav')).writeAsBytes([1, 2, 3]);
  });
  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });
  LibraryScannerService scanner(
          {MetadataReaderService reader =
              const FallbackMetadataReaderService()}) =>
      LibraryScannerService(
          libraryRepository: repositories.libraryFolders,
          trackRepository: repositories.tracks,
          metadataReader: reader);

  test(
      'new versus unchanged scan separates tag reads and keeps all-byte verification',
      () async {
    final first =
        await scanner().scanFolder(root.path, control: LibraryScanControl());
    final second =
        await scanner().scanFolder(root.path, control: LibraryScanControl());
    for (final metrics in [first.metrics, second.metrics]) {
      expect(metrics.hashedBytes, 3);
      expect(metrics.hashedFiles, 1);
      expect(metrics.nativeHashFiles, Platform.isWindows ? 1 : 0);
      expect(metrics.hashUs, greaterThan(0));
      expect(metrics.databaseUs, greaterThan(0));
      expect(metrics.fileSystemUs, greaterThan(0));
      expect(
          metrics.elapsedUs,
          greaterThanOrEqualTo(metrics.hashUs +
              metrics.metadataUs +
              metrics.artworkUs +
              metrics.databaseUs +
              metrics.fileSystemUs));
    }
    expect(first.metrics.metadataReads, 1);
    expect(first.metrics.importBatches, 1);
    expect(first.metrics.importRows, 1);
    expect(first.metrics.metadataUs, greaterThan(0));
    expect(second.metrics.metadataReads, 0);
    expect(second.metrics.metadataUs, 0);
    expect(second.metrics.artworkUs, 0);
    expect(second.metrics.importBatches, 0);
    expect(second.metrics.importRows, 0);
  });

  test(
      'failed metadata attempt is timed without counting it as an imported file',
      () async {
    final result = await scanner(reader: _BrokenReader()).scanFolder(root.path);
    expect(result.errors, hasLength(1));
    expect(result.addedTracks, 0);
    expect(result.metrics.metadataReads, 1);
    expect(result.metrics.metadataUs, greaterThan(0));
    expect(result.metrics.hashedBytes, 3);
  });

  test('combined and batch progress metrics sum numeric values', () {
    const one = LibraryScanMetrics(
        elapsedUs: 100,
        hashUs: 40,
        metadataUs: 20,
        artworkUs: 10,
        databaseUs: 20,
        hashedBytes: 3,
        hashedFiles: 1,
        nativeHashFiles: 1,
        metadataReads: 1,
        fileSystemUs: 5,
        importBatches: 1,
        importRows: 4,
        hashReadUs: 8,
        hashComputeUs: 9,
        hashWorkerUs: 18,
        hashOverheadUs: 3,
        hashStartupUs: 2,
        hashWorkerStarts: 1,
        databaseLookupUs: 5,
        databaseImportUs: 8,
        databaseMaintenanceUs: 6);
    const two = LibraryScanMetrics(
        elapsedUs: 300,
        hashUs: 100,
        metadataUs: 50,
        artworkUs: 20,
        databaseUs: 80,
        hashedBytes: 9,
        hashedFiles: 2,
        nativeHashFiles: 2,
        metadataReads: 2,
        fileSystemUs: 10,
        importBatches: 2,
        importRows: 8,
        hashReadUs: 16,
        hashComputeUs: 18,
        hashWorkerUs: 36,
        hashOverheadUs: 6,
        hashStartupUs: 4,
        hashWorkerStarts: 2,
        databaseLookupUs: 10,
        databaseImportUs: 16,
        databaseMaintenanceUs: 12);
    final progress = const LibraryScanProgress(
            folderPath: '/b', stage: LibraryScanStage.hashing, metrics: two)
        .withBatch(
            number: 2,
            count: 2,
            processedBefore: 1,
            addedBefore: 1,
            updatedBefore: 0,
            errorsBefore: 0,
            metricsBefore: one);
    expect(progress.metrics.elapsedUs, 400);
    expect(progress.metrics.hashUs, 140);
    expect(progress.metrics.hashedBytes, 12);
    expect(progress.metrics.metadataReads, 3);
    expect(progress.metrics.fileSystemUs, 15);
    expect(progress.metrics.importBatches, 3);
    expect(progress.metrics.importRows, 12);
    expect(progress.metrics.hashReadUs, 24);
    expect(progress.metrics.hashComputeUs, 27);
    expect(progress.metrics.hashWorkerUs, 54);
    expect(progress.metrics.hashOverheadUs, 9);
    expect(progress.metrics.hashStartupUs, 6);
    expect(progress.metrics.hashWorkerStarts, 3);
    expect(progress.metrics.databaseLookupUs, 15);
    expect(progress.metrics.databaseImportUs, 24);
    expect(progress.metrics.databaseMaintenanceUs, 18);
    final result = LibraryScanResult.combine([
      LibraryScanResult(
          folderPath: '/a',
          scannedFiles: 1,
          addedTracks: 1,
          updatedTracks: 0,
          missingTracks: 0,
          errors: const [],
          metrics: one),
      LibraryScanResult(
          folderPath: '/b',
          scannedFiles: 2,
          addedTracks: 2,
          updatedTracks: 0,
          missingTracks: 0,
          errors: const [],
          metrics: two),
    ]);
    expect(result.metrics.nativeHashFiles, 3);
    expect(result.metrics.artworkUs, 30);
    expect(result.metrics.databaseUs, 100);
    expect(result.metrics.fileSystemUs, 15);
    expect(result.metrics.importBatches, 3);
    expect(result.metrics.importRows, 12);
    expect(result.metrics.hashWorkerStarts, 3);
    expect(result.metrics.hashReadUs, 24);
    expect(result.metrics.databaseImportUs, 24);
  });

  test('recorder measures failed work as well as successful work', () async {
    final recorder = ScanMetricsRecorder();
    await expectLater(
        recorder.measure(ScanTimingPhase.metadata, () async {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          throw StateError('bad metadata');
        }),
        throwsStateError);
    recorder.verifiedHash(bytes: 128, native: true);
    final metrics = recorder.snapshot();
    expect(metrics.metadataUs, greaterThan(0));
    expect(metrics.metadataReads, 1);
    expect(metrics.hashedBytes, 128);
    expect(metrics.nativeHashFiles, 1);
  });

  test(
      'database details include failed attempts without double counting phases',
      () async {
    final recorder = ScanMetricsRecorder();
    expect(
        await recorder.measureDatabase(
            ScanDatabaseOperation.lookup, () async => 42),
        42);
    await expectLater(
        recorder.measureDatabase(ScanDatabaseOperation.import, () async {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          throw StateError('injected transaction failure');
        }),
        throwsStateError);
    await recorder.measureDatabase(
        ScanDatabaseOperation.maintenance, () async {});
    final metrics = recorder.snapshot();
    expect(metrics.databaseImportUs, greaterThan(0));
    expect(
        metrics.databaseUs,
        greaterThanOrEqualTo(metrics.databaseLookupUs +
            metrics.databaseImportUs +
            metrics.databaseMaintenanceUs));
    expect(metrics.elapsedUs, greaterThanOrEqualTo(metrics.databaseUs));
  });
}

final class _BrokenReader implements MetadataReaderService {
  @override
  Future<AudioMetadata> read(File file) => Future.error(StateError('bad tags'));
}
