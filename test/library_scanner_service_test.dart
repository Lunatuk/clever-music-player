import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('supported audio extension detection is case insensitive', () {
    expect(isSupportedAudioFilePath('/music/song.MP3'), isTrue);
    expect(isSupportedAudioFilePath('/music/song.flac'), isTrue);
    expect(isSupportedAudioFilePath('/music/song.txt'), isFalse);
    expect(isSupportedAudioFilePath('/music/song'), isFalse);
  });

  test('scanner finds supported files and ignores unsupported files', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_scanner_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    await File(p.join(tempDirectory.path, 'first.mp3')).writeAsBytes([1, 2, 3]);
    await File(p.join(tempDirectory.path, 'notes.txt')).writeAsString('notes');

    final subDirectory = Directory(p.join(tempDirectory.path, 'sub'));
    await subDirectory.create();
    await File(p.join(subDirectory.path, 'second.flac')).writeAsBytes([4, 5]);

    final hiddenDirectory = Directory(p.join(tempDirectory.path, '.hidden'));
    await hiddenDirectory.create();
    await File(p.join(hiddenDirectory.path, 'secret.mp3')).writeAsBytes([6]);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: const FallbackMetadataReaderService(),
    );

    final result = await scanner.scanFolder(tempDirectory.path);

    expect(result.scannedFiles, 2);
    expect(result.addedTracks, 2);
    expect(result.updatedTracks, 0);
    expect(result.missingTracks, 0);
    expect(result.errors, isEmpty);

    final tracks = await repositories.tracks.listTracks(limit: 10);
    expect(tracks.map((track) => track.title), containsAll(['first', 'second']));
    expect(tracks.every((track) => track.stableId != null), isTrue);
    expect(tracks.every((track) => track.lastSeenAt != null), isTrue);
    expect(tracks.every((track) => !track.isMissing), isTrue);
  });

  test('scanner marks previously seen files as missing', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_missing_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final firstFile = File(p.join(tempDirectory.path, 'first.mp3'));
    await firstFile.writeAsBytes([1, 2, 3]);
    await File(p.join(tempDirectory.path, 'second.flac')).writeAsBytes([4, 5]);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: const FallbackMetadataReaderService(),
    );

    await scanner.scanFolder(tempDirectory.path);
    await firstFile.delete();

    final result = await scanner.scanFolder(tempDirectory.path);

    expect(result.scannedFiles, 1);
    expect(result.addedTracks, 0);
    expect(result.updatedTracks, 1);
    expect(result.missingTracks, 1);

    final folder = await repositories.libraryFolders.findFolderByPath(
      p.normalize(tempDirectory.absolute.path),
    );
    final tracks = await repositories.tracks.listTracksByLibraryFolder(
      folder!.id!,
      includeMissing: true,
    );

    expect(tracks.where((track) => track.isMissing), hasLength(1));
    expect(tracks.where((track) => !track.isMissing), hasLength(1));
  });
}
