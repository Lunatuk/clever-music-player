import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/library/file_content_hasher.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late AppDatabase database;
  late DriftRepositories repositories;
  late List<File> files;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cmp_import_batches_');
    database = AppDatabase(NativeDatabase.memory());
    repositories = DriftRepositories(database);
    files = [];
  });
  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });
  Future<void> createFiles(int count) async {
    for (var i = 0; i < count; i++) {
      files
          .add(await File(p.join(root.path, '$i.wav')).writeAsBytes([i, 2, 3]));
    }
  }

  LibraryScannerService scanner({
    int batchSize = 64,
    Duration flushInterval = const Duration(days: 1),
    MetadataReaderService? reader,
    DirectoryEntityLister? lister,
    TrackRepository? tracks,
  }) =>
      LibraryScannerService(
          libraryRepository: repositories.libraryFolders,
          trackRepository: tracks ?? repositories.tracks,
          metadataReader: reader ?? const FallbackMetadataReaderService(),
          contentHasher: const _FixtureHasher(),
          importBatchSize: batchSize,
          importFlushInterval: flushInterval,
          listEntities: lister ?? (_) => Stream.fromIterable(files));

  test('bounded batches and a final remainder preserve all files', () async {
    await createFiles(129);
    final result = await scanner().scanFolder(root.path);
    expect(result.errors, isEmpty);
    expect(result.processedFiles, 129);
    expect(result.addedTracks, 129);
    expect(result.metrics.importRows, 129);
    expect(result.metrics.importBatches, 3);
    expect(result.metrics.fileSystemUs, greaterThan(0));
    expect(await repositories.tracks.listTracks(limit: 1000), hasLength(129));
    final retry = await scanner().scanFolder(root.path);
    expect(retry.addedTracks, 0);
    expect(retry.updatedTracks, 129);
    expect(retry.metrics.importBatches, 0);
    expect(retry.metrics.metadataReads, 0);
  });

  test('elapsed flush boundary works before reaching the size limit', () async {
    await createFiles(3);
    final result =
        await scanner(flushInterval: Duration.zero).scanFolder(root.path);
    expect(result.errors, isEmpty);
    expect(result.metrics.importBatches, 3);
    expect(result.metrics.importRows, 3);
  });

  test('cancelling a partial buffer saves only fully prepared files', () async {
    await createFiles(5);
    late LibraryScanControl control;
    control = LibraryScanControl(onProgress: (progress) {
      if (progress.processedFiles == 2) control.cancel();
    });
    final result = await scanner().scanFolder(root.path, control: control);
    expect(result.wasCancelled, isTrue);
    expect(result.errors, isEmpty);
    expect(result.processedFiles, 2);
    expect(result.addedTracks, 2);
    expect(result.metrics.importBatches, 1);
    expect(result.metrics.importRows, 2);
    expect(await repositories.tracks.listTracks(), hasLength(2));
    expect(
        (await repositories.libraryFolders.listFolders()).single.lastScannedAt,
        isNull);
    final retry = await scanner().scanFolder(root.path);
    expect(retry.addedTracks, 3);
    expect(retry.updatedTracks, 2);
    expect(await repositories.tracks.listTracks(), hasLength(5));
  });

  test(
      'pending tags drain on cancellation while earlier buffered files survive',
      () async {
    await createFiles(4);
    final reader = _GatedReader(files.last.path);
    final control = LibraryScanControl();
    final scanning =
        scanner(reader: reader).scanFolder(root.path, control: control);
    await reader.entered.future;
    control.cancel();
    reader.release.complete();
    final result = await scanning;
    expect(result.wasCancelled, isTrue);
    expect(result.processedFiles, 3);
    expect(result.addedTracks, 3);
    expect(result.metrics.importRows, 3);
    expect(result.errors, isEmpty);
    expect(await repositories.tracks.findByPath(files.last.path), isNull);
  });

  test('a bad DB row rolls back its batch, then good rows save individually',
      () async {
    await createFiles(3);
    await repositories.tracks.listTracks();
    await database.customStatement(
        'CREATE TRIGGER reject_bad BEFORE INSERT ON tracks '
        "WHEN NEW.title = '1' BEGIN SELECT RAISE(ABORT, 'injected failure'); END;");
    final result = await scanner().scanFolder(root.path);
    expect(result.processedFiles, 3);
    expect(result.errors, hasLength(1));
    expect(result.errors.single.path, files[1].path);
    expect(result.addedTracks, 2);
    expect(result.metrics.importRows, 2);
    expect(result.metrics.importBatches, 2);
    expect(await repositories.tracks.findByPath(files[1].path), isNull);
    expect(await repositories.tracks.listTracks(), hasLength(2));
    await database.customStatement('DROP TRIGGER reject_bad');
    final retry = await scanner().scanFolder(root.path);
    expect(retry.errors, isEmpty);
    expect(retry.addedTracks, 1);
    expect(retry.updatedTracks, 2);
  });

  test(
      'partial traversal commits prepared files and preserves the scan timestamp',
      () async {
    await createFiles(3);
    Stream<FileSystemEntity> broken(Directory _) async* {
      yield files.first;
      throw const FileSystemException('injected traversal failure');
    }

    final result = await scanner(lister: broken).scanFolder(root.path);
    expect(result.errors, hasLength(1));
    expect(result.addedTracks, 1);
    expect(result.missingTracks, 0);
    expect(
        (await repositories.libraryFolders.listFolders()).single.lastScannedAt,
        isNull);
    expect(await repositories.tracks.listTracks(), hasLength(1));
  });

  test(
      'file changed in the buffer is rejected before its identity is published',
      () async {
    await createFiles(2);
    final reader = _GatedReader(files.last.path);
    final scanning = scanner(reader: reader).scanFolder(root.path);
    await reader.entered.future;
    await files.first.writeAsBytes([9, 8, 7, 6]);
    reader.release.complete();
    final result = await scanning;
    expect(result.errors, hasLength(1));
    expect(result.errors.single.path, files.first.path);
    expect(result.addedTracks, 1);
    expect(await repositories.tracks.findByPath(files.first.path), isNull);
    final retry = await scanner().scanFolder(root.path);
    expect(retry.errors, isEmpty);
    expect(retry.addedTracks, 1);
    expect(retry.updatedTracks, 1);
  });

  test(
      'deleted buffered file does not prevent other prepared files from saving',
      () async {
    await createFiles(2);
    final reader = _GatedReader(files.last.path);
    final scanning = scanner(reader: reader).scanFolder(root.path);
    await reader.entered.future;
    await files.first.delete();
    reader.release.complete();
    final result = await scanning;
    expect(result.errors, hasLength(1));
    expect(result.addedTracks, 1);
    expect(await repositories.tracks.findByPath(files.first.path), isNull);
  });

  test(
      'changed buffered existing file keeps its ID and invalidates stale identity',
      () async {
    await createFiles(2);
    await scanner().scanFolder(root.path);
    final original = (await repositories.tracks.findByPath(files.first.path))!;
    await files.first.writeAsBytes([9, 8, 7, 6]);
    await files.last.writeAsBytes([9, 8, 7, 6]);
    final reader = _GatedReader(files.last.path);
    final scanning = scanner(reader: reader).scanFolder(root.path);
    await reader.entered.future;
    await files.first.writeAsBytes([1, 2, 3, 4, 5]);
    reader.release.complete();
    final result = await scanning;
    expect(result.errors, hasLength(1));
    expect(result.updatedTracks, 1);
    expect(result.missingTracks, 0);
    final saved = (await repositories.tracks.findById(original.id!))!;
    expect(saved.id, original.id);
    expect(saved.filePath, original.filePath);
    expect(saved.isMissing, isFalse);
    expect(saved.contentHash, isNull);
    final retry = await scanner().scanFolder(root.path);
    expect(retry.errors, isEmpty);
    expect(retry.addedTracks, 0);
    expect(retry.updatedTracks, 2);
    expect((await repositories.tracks.findById(original.id!))!.contentHash,
        isNotNull);
  });

  test(
      'manual editing while a rescan buffer waits preserves latest user fields',
      () async {
    await createFiles(2);
    await scanner().scanFolder(root.path);
    final original = (await repositories.tracks.findByPath(files.first.path))!;
    await repositories.tracks.updateCustomArtwork(
        trackId: original.id!,
        path: '/old.jpg',
        hash: 'old',
        mimeType: 'image/jpeg',
        updatedAt: DateTime(2026));
    for (final file in files) {
      await file.writeAsBytes([9, 8, 7, 6]);
    }
    final reader = _GatedReader(files.last.path);
    final scanning = scanner(reader: reader).scanFolder(root.path);
    await reader.entered.future;
    await repositories.tracks.updateTrackMetadata(TrackMetadataUpdate(
        trackId: original.id!,
        title: 'Edited during scan',
        updatedAt: DateTime(2027)));
    await repositories.tracks
        .clearCustomArtwork(trackId: original.id!, updatedAt: DateTime(2027));
    reader.release.complete();
    final result = await scanning;
    expect(result.errors, isEmpty);
    final saved = (await repositories.tracks.findById(original.id!))!;
    expect(saved.title, 'Edited during scan');
    expect(saved.artist, isNull);
    expect(saved.customArtworkPath, isNull);
    expect(saved.metadataSource, MetadataSource.manual);
    expect(saved.fileSizeBytes, 4);
    expect(saved.updatedAt, DateTime(2027));
  });

  test('cancellation waits for the in-flight transaction and retains its batch',
      () async {
    await createFiles(3);
    final entered = Completer<void>();
    final release = Completer<void>();
    final adapter = _ImportAdapter(repositories.tracks, (prepared) async {
      entered.complete();
      await release.future;
      return (repositories.tracks as TrackImportRepository)
          .upsertScannedTracks(prepared);
    });
    final control = LibraryScanControl();
    var finished = false;
    final scanning = scanner(batchSize: 2, tracks: adapter)
        .scanFolder(root.path, control: control)
        .then((result) {
      finished = true;
      return result;
    });
    await entered.future;
    control.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    release.complete();
    final result = await scanning;
    expect(result.wasCancelled, isTrue);
    expect(result.errors, isEmpty);
    expect(result.addedTracks, 2);
    expect(result.processedFiles, 2);
    expect(await repositories.tracks.listTracks(), hasLength(2));
  });

  test('repeated path in a directory adapter never becomes two new records',
      () async {
    await createFiles(1);
    final result = await scanner(
            lister: (_) => Stream.fromIterable([files.first, files.first]))
        .scanFolder(root.path);
    expect(result.errors, isEmpty);
    expect(result.addedTracks, 1);
    expect(result.updatedTracks, 1);
    expect(await repositories.tracks.listTracks(), hasLength(1));
  });
}

final class _FixtureHasher implements FileContentHasher {
  const _FixtureHasher();
  @override
  Future<FileContentFingerprint> hashFile(File file) async {
    final stat = await file.stat();
    final digest = sha256.convert(await file.readAsBytes()).toString();
    return FileContentFingerprint(
        digest: digest,
        sizeBytes: stat.size,
        modifiedAt: stat.modified,
        changedAt: stat.changed);
  }
}

final class _GatedReader implements MetadataReaderService {
  _GatedReader(this.path);
  final String path;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<AudioMetadata> read(File file) async {
    if (file.path == path) {
      entered.complete();
      await release.future;
    }
    return const FallbackMetadataReaderService().read(file);
  }
}

final class _ImportAdapter implements TrackRepository, TrackImportRepository {
  const _ImportAdapter(this.inner, this.save);
  final TrackRepository inner;
  final Future<List<int>> Function(List<Track>) save;
  @override
  Future<List<int>> upsertScannedTracks(List<Track> tracks) => save(tracks);
  @override
  Future<Track?> findByPath(String filePath) => inner.findByPath(filePath);
  @override
  Future<Track?> findById(int id) => inner.findById(id);
  @override
  Future<int> upsertTrack(Track track) => inner.upsertTrack(track);
  @override
  Future<List<Track>> listTracksByLibraryFolder(int libraryFolderId,
          {bool includeMissing = true}) =>
      inner.listTracksByLibraryFolder(libraryFolderId,
          includeMissing: includeMissing);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'Unexpected repository call: ${invocation.memberName}');
}
