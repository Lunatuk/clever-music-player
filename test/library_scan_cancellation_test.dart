import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/file_content_hasher.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late AppDatabase database;
  late DriftRepositories repositories;
  late List<File> files;
  var scanTime = DateTime(2026);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cmp_scan_cancel_');
    database = AppDatabase(NativeDatabase.memory());
    repositories = DriftRepositories(database);
    files = [];
    scanTime = DateTime(2026);
    for (var i = 0; i < 3; i++) {
      final file = File(p.join(directory.path, '$i.wav'));
      await file.writeAsBytes([i, 2, 3]);
      files.add(file);
    }
  });
  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });
  LibraryScannerService scanner(
          {MetadataReaderService? reader,
          DirectoryEntityLister? lister,
          FileContentHasher? hasher}) =>
      LibraryScannerService(
        libraryRepository: repositories.libraryFolders,
        trackRepository: repositories.tracks,
        metadataReader: reader ?? const FallbackMetadataReaderService(),
        listEntities: lister ?? (_) => Stream.fromIterable(files),
        contentHasher: hasher ?? const Sha256FileContentHasher(),
        clock: () => scanTime,
      );

  test('pre-cancelled scan does not create a source or read files', () async {
    final control = LibraryScanControl()..cancel();
    final result = await scanner().scanFolder(directory.path, control: control);
    expect(result.wasCancelled, isTrue);
    expect(result.processedFiles, 0);
    expect(result.errors, isEmpty);
    expect(await repositories.libraryFolders.listFolders(), isEmpty);
  });

  test(
      'partial rescan preserves unseen records, hashes, feedback and scan timestamp',
      () async {
    await scanner().scanFolder(directory.path);
    final original = await repositories.tracks.listTracks();
    final firstId = original.first.id!;
    await repositories.trackUserState.upsertState(TrackUserState(
      trackId: firstId,
      playCount: 8,
      isFavorite: true,
      updatedAt: scanTime,
    ));
    final playlist = await repositories.playlists.createPlaylist('Keep');
    for (final track in original) {
      await repositories.playlists.addTrackToPlaylist(playlist, track.id!);
    }
    final source = (await repositories.libraryFolders.listFolders()).single;
    scanTime = DateTime(2026, 2);
    late LibraryScanControl control;
    control = LibraryScanControl(onProgress: (progress) {
      if (progress.processedFiles == 1) control.cancel();
    });
    final result = await scanner().scanFolder(directory.path, control: control);
    expect(result.wasCancelled, isTrue);
    expect(result.processedFiles, 1);
    expect(result.updatedTracks, 1);
    expect(result.missingTracks, 0);
    expect(result.errors, isEmpty);
    final after =
        await repositories.tracks.watchAllTracks(includeMissing: true).first;
    expect(after.map((track) => track.id), original.map((track) => track.id));
    expect(after.map((track) => track.contentHash),
        original.map((track) => track.contentHash));
    expect(after.every((track) => !track.isMissing), isTrue);
    expect(
        (await repositories.trackUserState.findByTrackId(firstId))!.playCount,
        8);
    expect(
        (await repositories.playlists.watchPlaylistTracks(playlist).first)
            .map((entry) => entry.trackId),
        original.map((track) => track.id));
    expect(
        (await repositories.libraryFolders.listFolders()).single.lastScannedAt,
        source.lastScannedAt);
    final retry = await scanner()
        .scanFolder(directory.path, control: LibraryScanControl());
    expect(retry.wasCancelled, isFalse);
    expect(retry.processedFiles, 3);
    expect(
        (await repositories.libraryFolders.listFolders()).single.lastScannedAt,
        scanTime);
  });

  test(
      'cancelled initial import retains completed files and resumes without duplicates',
      () async {
    late LibraryScanControl control;
    control = LibraryScanControl(onProgress: (progress) {
      if (progress.processedFiles == 1) control.cancel();
    });
    final result = await scanner().scanFolder(directory.path, control: control);
    expect(result.wasCancelled, isTrue);
    expect(result.addedTracks, 1);
    final original = (await repositories.tracks.listTracks()).single;
    expect(
        (await repositories.libraryFolders.listFolders()).single.lastScannedAt,
        isNull);
    final retry = await scanner()
        .scanFolder(directory.path, control: LibraryScanControl());
    expect(retry.addedTracks, 2);
    expect(retry.updatedTracks, 1);
    expect(await repositories.tracks.listTracks(), hasLength(3));
    expect((await repositories.tracks.findByPath(original.filePath))!.id,
        original.id);
  });

  test(
      'cancel while metadata is pending drains it without publishing partial file data',
      () async {
    await scanner().scanFolder(directory.path);
    final original = (await repositories.tracks.findByPath(files.first.path))!;
    await files.first.writeAsBytes([9, 8, 7, 6]);
    final reader = _GatedMetadataReader();
    final control = LibraryScanControl();
    var finished = false;
    final scanning = scanner(reader: reader)
        .scanFolder(directory.path, control: control)
        .then((result) {
      finished = true;
      return result;
    });
    await reader.entered.future;
    control.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    reader.release.complete();
    final result = await scanning;
    expect(result.wasCancelled, isTrue);
    expect(result.errors, isEmpty);
    expect(result.processedFiles, 0);
    expect(await repositories.tracks.findById(original.id!), original);
    expect(await repositories.tracks.listTracks(), hasLength(3));
  });

  test('cancelled hashing does not clear the last verified hash', () async {
    await scanner().scanFolder(directory.path);
    final original = (await repositories.tracks.findByPath(files.first.path))!;
    final control = LibraryScanControl();
    final result = await scanner(hasher: _CancellingHasher(control))
        .scanFolder(directory.path, control: control);
    expect(result.wasCancelled, isTrue);
    expect(result.errors, isEmpty);
    expect(result.processedFiles, 0);
    expect(await repositories.tracks.findById(original.id!), original);
  });

  test('cancel stops a directory stream that is waiting for its next event',
      () async {
    final stopped = Completer<void>();
    final entities =
        StreamController<FileSystemEntity>(onCancel: stopped.complete);
    addTearDown(entities.close);
    final control = LibraryScanControl();
    final entered = Completer<void>();
    final scanning = scanner(lister: (_) {
      entered.complete();
      return entities.stream;
    }).scanFolder(directory.path, control: control);
    await entered.future;
    await Future<void>.delayed(Duration.zero);
    control.cancel();
    final result = await scanning.timeout(const Duration(seconds: 5));
    await stopped.future;
    expect(result.wasCancelled, isTrue);
    expect(result.errors, isEmpty);
    expect(result.missingTracks, 0);
  });

  test('cancel closes a real directory listing and permits an immediate retry',
      () async {
    late LibraryScanControl control;
    control = LibraryScanControl(onProgress: (progress) {
      if (progress.processedFiles == 1) control.cancel();
    });
    final actual = scanner(
        lister: (folder) => folder.list(recursive: true, followLinks: false));
    final result = await actual.scanFolder(directory.path, control: control);
    expect(result.wasCancelled, isTrue);
    expect(result.addedTracks, 1);
    final retry =
        await actual.scanFolder(directory.path, control: LibraryScanControl());
    expect(retry.wasCancelled, isFalse);
    expect(await repositories.tracks.listTracks(), hasLength(3));
  });

  test('cancel at finalization prevents missing marks and timestamp updates',
      () async {
    await scanner().scanFolder(directory.path);
    final before =
        (await repositories.libraryFolders.listFolders()).single.lastScannedAt;
    scanTime = DateTime(2026, 3);
    late LibraryScanControl control;
    control = LibraryScanControl(onProgress: (progress) {
      if (progress.stage == LibraryScanStage.finishing) control.cancel();
    });
    final result =
        await scanner(lister: (_) => Stream.fromIterable(files.take(2)))
            .scanFolder(directory.path, control: control);
    expect(result.wasCancelled, isTrue);
    expect(result.processedFiles, 2);
    expect(result.missingTracks, 0);
    expect(await repositories.tracks.listTracks(), hasLength(3));
    expect(
        (await repositories.libraryFolders.listFolders()).single.lastScannedAt,
        before);
  });

  test('incomplete traversal never advances the complete-scan timestamp',
      () async {
    await scanner().scanFolder(directory.path);
    final before =
        (await repositories.libraryFolders.listFolders()).single.lastScannedAt;
    scanTime = DateTime(2026, 3);
    Stream<FileSystemEntity> partial(Directory _) async* {
      yield files.first;
      throw FileSystemException('Traversal failed');
    }

    final result = await scanner(lister: partial).scanFolder(directory.path);
    expect(result.errors, hasLength(1));
    expect(result.wasCancelled, isFalse);
    expect(result.missingTracks, 0);
    expect(
        (await repositories.libraryFolders.listFolders()).single.lastScannedAt,
        before);
  });

  test(
      'progress counts completed files and reports hashing bytes and processing phases',
      () async {
    final progress = <LibraryScanProgress>[];
    final result = await scanner().scanFolder(directory.path,
        control: LibraryScanControl(onProgress: progress.add));
    expect(result.processedFiles, 3);
    expect(progress.first.processedFiles, 0);
    expect(progress.last.processedFiles, 3);
    expect(progress.last.addedTracks, 3);
    expect(progress.map((item) => item.stage).toSet(),
        LibraryScanStage.values.toSet());
    final hash =
        progress.where((item) => item.stage == LibraryScanStage.hashing);
    expect(
        hash.any((item) => item.fileBytesRead == 3 && item.fileSizeBytes == 3),
        isTrue);
    expect(progress.every((item) => item.processedFiles <= 3), isTrue);
  });

  test(
      'controlled worker produces the same fingerprint and preserves IO errors',
      () async {
    const hasher = Sha256FileContentHasher();
    final actual = await hasher.hashFileWithControl(files.first,
        control: LibraryScanControl());
    expect(actual.storageKey, (await hasher.hashFile(files.first)).storageKey);
    await files.first.delete();
    await expectLater(
        hasher.hashFileWithControl(files.first, control: LibraryScanControl()),
        throwsA(isA<FileSystemException>()));
  });

  test(
      'controlled worker cancels during a real streamed file read and releases its file',
      () async {
    await files.first.writeAsBytes(Uint8List(8 * 1024 * 1024));
    const hasher = Sha256FileContentHasher();
    for (var attempt = 0; attempt < 3; attempt++) {
      final control = LibraryScanControl();
      var callbacks = 0;
      await expectLater(
          hasher.hashFileWithControl(files.first, control: control,
              onProgress: (_) {
            callbacks++;
            control.cancel();
          }),
          throwsA(isA<LibraryScanCancelled>()));
      expect(callbacks, 1);
    }
    await files.first.delete();
    expect(await files.first.exists(), isFalse);
  });
}

final class _GatedMetadataReader implements MetadataReaderService {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<AudioMetadata> read(File file) async {
    entered.complete();
    await release.future;
    return const FallbackMetadataReaderService().read(file);
  }
}

final class _CancellingHasher implements FileContentHasher {
  _CancellingHasher(this.control);
  final LibraryScanControl control;
  @override
  Future<FileContentFingerprint> hashFile(File file) async {
    control.cancel();
    throw const LibraryScanCancelled();
  }
}
