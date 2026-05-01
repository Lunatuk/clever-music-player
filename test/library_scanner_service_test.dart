import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
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
    expect(
        tracks.map((track) => track.title), containsAll(['first', 'second']));
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

  test('scanner does not mark tracks missing when traversal fails', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_traversal_error_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final folder = await _seedKnownFolder(
      repositories,
      tempDirectory.path,
    );
    await _seedKnownTrack(
      repositories,
      folderId: folder.id!,
      filePath: p.join(tempDirectory.path, 'known.mp3'),
    );
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: const FallbackMetadataReaderService(),
      listEntities: (directory) {
        return Stream.error(
          FileSystemException('Permission denied', directory.path),
        );
      },
    );

    final result = await scanner.scanFolder(tempDirectory.path);

    expect(result.errors, hasLength(1));
    expect(result.missingTracks, 0);

    final tracks = await repositories.tracks.listTracksByLibraryFolder(
      folder.id!,
      includeMissing: true,
    );
    expect(tracks.single.isMissing, isFalse);
  });

  test('scanner does not mark tracks missing when folder does not exist',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_missing_folder_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final missingFolderPath = p.join(tempDirectory.path, 'missing');

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final folder = await _seedKnownFolder(
      repositories,
      missingFolderPath,
    );
    await _seedKnownTrack(
      repositories,
      folderId: folder.id!,
      filePath: p.join(missingFolderPath, 'known.mp3'),
    );
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: const FallbackMetadataReaderService(),
    );

    final result = await scanner.scanFolder(missingFolderPath);

    expect(result.errors, hasLength(1));
    expect(result.errors.single.message, 'Folder does not exist.');
    expect(result.missingTracks, 0);

    final tracks = await repositories.tracks.listTracksByLibraryFolder(
      folder.id!,
      includeMissing: true,
    );
    expect(tracks.single.isMissing, isFalse);
  });

  test('rescan with improved metadata updates existing track by file path',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_improved_metadata_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final file = File(p.join(tempDirectory.path, 'scars.mp3'));
    await file.writeAsBytes([1, 2, 3]);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final reader = _SequenceMetadataReader([
      _audioMetadata(
        file,
        title: 'scars',
        metadataSource: MetadataSource.fallback,
        metadataConfidence: 0.2,
      ),
      _audioMetadata(
        file,
        title: 'Scars',
        artist: 'Known Artist',
        album: 'Known Album',
        metadataSource: MetadataSource.embeddedTags,
        metadataConfidence: 0.95,
      ),
    ]);
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: reader,
    );

    await scanner.scanFolder(tempDirectory.path);
    final firstTrack = (await repositories.tracks.listTracks(limit: 10)).single;
    await repositories.trackUserState.upsertState(
      TrackUserState(
        trackId: firstTrack.id!,
        isFavorite: true,
        rating: 1,
        updatedAt: DateTime(2026),
      ),
    );
    await repositories.playbackEvents.addEvent(
      PlaybackEvent(
        trackId: firstTrack.id!,
        type: PlaybackEventType.started,
        occurredAt: DateTime(2026),
      ),
    );

    final result = await scanner.scanFolder(tempDirectory.path);

    expect(result.addedTracks, 0);
    expect(result.updatedTracks, 1);

    final tracks = await repositories.tracks.listTracks(limit: 10);
    expect(tracks, hasLength(1));
    final updatedTrack = tracks.single;
    expect(updatedTrack.id, firstTrack.id);
    expect(updatedTrack.title, 'Scars');
    expect(updatedTrack.artist, 'Known Artist');
    expect(updatedTrack.album, 'Known Album');
    expect(updatedTrack.metadataSource, MetadataSource.embeddedTags);

    final state = await repositories.trackUserState.findByTrackId(
      firstTrack.id!,
    );
    expect(state?.isFavorite, isTrue);
    expect(state?.rating, 1);

    final events = await repositories.playbackEvents.recentForTrack(
      firstTrack.id!,
    );
    expect(events, hasLength(1));
  });

  test('metadata reader failure records an error and continues scanning',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_reader_failure_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final badFile = File(p.join(tempDirectory.path, 'bad.mp3'));
    final goodFile = File(p.join(tempDirectory.path, 'Artist - Good.mp3'));
    await badFile.writeAsBytes([1]);
    await goodFile.writeAsBytes([2]);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader:
          _SelectiveFailingMetadataReader(failingPath: badFile.path),
    );

    final result = await scanner.scanFolder(tempDirectory.path);

    expect(result.scannedFiles, 2);
    expect(result.addedTracks, 1);
    expect(result.errors, hasLength(1));

    final tracks = await repositories.tracks.listTracks(limit: 10);
    expect(tracks.single.title, 'Good');
    expect(tracks.single.artist, 'Artist');
  });
}

Future<LibraryFolder> _seedKnownFolder(
  DriftRepositories repositories,
  String folderPath,
) async {
  final now = DateTime(2026);
  final normalizedPath = p.normalize(Directory(folderPath).absolute.path);
  final folder = LibraryFolder(
    path: normalizedPath,
    displayName: p.basename(normalizedPath),
    createdAt: now,
    updatedAt: now,
  );
  final id = await repositories.libraryFolders.upsertFolder(folder);
  return folder.copyWith(id: id);
}

Future<void> _seedKnownTrack(
  DriftRepositories repositories, {
  required int folderId,
  required String filePath,
}) async {
  final now = DateTime(2026);
  await repositories.tracks.upsertTrack(
    Track(
      libraryFolderId: folderId,
      stableId: 'known-${p.basename(filePath)}',
      filePath: p.normalize(filePath),
      title: 'Known',
      addedAt: now,
      updatedAt: now,
    ),
  );
}

AudioMetadata _audioMetadata(
  File file, {
  required String title,
  required MetadataSource metadataSource,
  required double metadataConfidence,
  String? artist,
  String? album,
}) {
  final stat = file.statSync();
  return AudioMetadata(
    filePath: p.normalize(file.absolute.path),
    fileSizeBytes: stat.size,
    modifiedAt: stat.modified,
    title: title,
    codec: p.extension(file.path).replaceFirst('.', '').toLowerCase(),
    metadataSource: metadataSource,
    metadataConfidence: metadataConfidence,
    artist: artist,
    album: album,
  );
}

final class _SequenceMetadataReader implements MetadataReaderService {
  _SequenceMetadataReader(this._metadata);

  final List<AudioMetadata> _metadata;
  var _index = 0;

  @override
  Future<AudioMetadata> read(File file) async {
    final metadata = _metadata[_index];
    _index = (_index + 1).clamp(0, _metadata.length - 1).toInt();
    return metadata;
  }
}

final class _SelectiveFailingMetadataReader implements MetadataReaderService {
  const _SelectiveFailingMetadataReader({required this.failingPath});

  final String failingPath;

  @override
  Future<AudioMetadata> read(File file) async {
    if (p.equals(file.path, failingPath)) {
      throw StateError('metadata failure');
    }

    return const FallbackMetadataReaderService().read(file);
  }
}
