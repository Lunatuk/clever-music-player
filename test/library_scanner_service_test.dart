import 'dart:io';
import 'dart:typed_data';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/metadata_enrichment.dart';
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

  test('scanner saves embedded artwork and stores artwork fields', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_artwork_scan_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final file = File(p.join(tempDirectory.path, 'covered.mp3'));
    await file.writeAsBytes([1, 2, 3]);
    final artworkDirectory = Directory(p.join(tempDirectory.path, 'artwork'));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: _StaticArtworkMetadataReader(
        artwork: _pngArtwork([1, 2, 3, 4]),
      ),
      artworkCache: AppSupportArtworkCacheService(
        artworkDirectory: artworkDirectory,
      ),
    );

    final result = await scanner.scanFolder(tempDirectory.path);

    expect(result.errors, isEmpty);
    final track = (await repositories.tracks.listTracks(limit: 10)).single;
    expect(track.artworkPath, isNotNull);
    expect(track.artworkHash, hasLength(64));
    expect(track.artworkMimeType, 'image/png');
    expect(await File(track.artworkPath!).exists(), isTrue);
    expect(p.extension(track.artworkPath!), '.png');
  });

  test('duplicate embedded artwork bytes reuse the cached file', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_duplicate_artwork_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    await File(p.join(tempDirectory.path, 'first.mp3')).writeAsBytes([1]);
    await File(p.join(tempDirectory.path, 'second.mp3')).writeAsBytes([2]);
    final artworkDirectory = Directory(p.join(tempDirectory.path, 'artwork'));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: _StaticArtworkMetadataReader(
        artwork: _pngArtwork([9, 8, 7, 6]),
      ),
      artworkCache: AppSupportArtworkCacheService(
        artworkDirectory: artworkDirectory,
      ),
    );

    await scanner.scanFolder(tempDirectory.path);

    final tracks = await repositories.tracks.listTracks(limit: 10);
    expect(tracks, hasLength(2));
    expect(tracks.map((track) => track.artworkHash).toSet(), hasLength(1));
    expect(tracks.map((track) => track.artworkPath).toSet(), hasLength(1));
    expect(artworkDirectory.listSync().whereType<File>(), hasLength(1));
  });

  test('rescan preserves artwork when no embedded artwork is returned',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_preserve_artwork_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final file = File(p.join(tempDirectory.path, 'preserve.mp3'));
    await file.writeAsBytes([1, 2, 3]);
    final artworkDirectory = Directory(p.join(tempDirectory.path, 'artwork'));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final reader = _SequenceMetadataReader([
      _audioMetadata(
        file,
        title: 'Covered',
        metadataSource: MetadataSource.embeddedTags,
        metadataConfidence: 0.95,
        artwork: _pngArtwork([1, 1, 1, 1]),
      ),
      _audioMetadata(
        file,
        title: 'Rescanned',
        metadataSource: MetadataSource.fallback,
        metadataConfidence: 0.2,
      ),
    ]);
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: reader,
      artworkCache: AppSupportArtworkCacheService(
        artworkDirectory: artworkDirectory,
      ),
    );

    await scanner.scanFolder(tempDirectory.path);
    final firstTrack = (await repositories.tracks.listTracks(limit: 10)).single;

    await scanner.scanFolder(tempDirectory.path);

    final updatedTrack =
        (await repositories.tracks.listTracks(limit: 10)).single;
    expect(updatedTrack.title, 'Rescanned');
    expect(updatedTrack.artworkHash, firstTrack.artworkHash);
    expect(updatedTrack.artworkPath, firstTrack.artworkPath);
    expect(updatedTrack.artworkMimeType, 'image/png');
  });

  test('rescan updates artwork when embedded artwork changes', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_update_artwork_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final file = File(p.join(tempDirectory.path, 'update.mp3'));
    await file.writeAsBytes([1, 2, 3]);
    final artworkDirectory = Directory(p.join(tempDirectory.path, 'artwork'));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final reader = _SequenceMetadataReader([
      _audioMetadata(
        file,
        title: 'Covered',
        metadataSource: MetadataSource.embeddedTags,
        metadataConfidence: 0.95,
        artwork: _pngArtwork([1, 1, 1, 1]),
      ),
      _audioMetadata(
        file,
        title: 'Covered',
        metadataSource: MetadataSource.embeddedTags,
        metadataConfidence: 0.95,
        artwork: _pngArtwork([2, 2, 2, 2]),
      ),
    ]);
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: reader,
      artworkCache: AppSupportArtworkCacheService(
        artworkDirectory: artworkDirectory,
      ),
    );

    await scanner.scanFolder(tempDirectory.path);
    final firstTrack = (await repositories.tracks.listTracks(limit: 10)).single;

    await scanner.scanFolder(tempDirectory.path);

    final updatedTrack =
        (await repositories.tracks.listTracks(limit: 10)).single;
    expect(updatedTrack.artworkHash, isNot(firstTrack.artworkHash));
    expect(updatedTrack.artworkPath, isNot(firstTrack.artworkPath));
    expect(artworkDirectory.listSync().whereType<File>(), hasLength(2));
  });

  test('scanner continues when artwork storage fails', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_artwork_failure_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    await File(p.join(tempDirectory.path, 'covered.mp3')).writeAsBytes([1]);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: _StaticArtworkMetadataReader(
        artwork: _pngArtwork([4, 5, 6, 7]),
      ),
      artworkCache: const _FailingArtworkCacheService(),
    );

    final result = await scanner.scanFolder(tempDirectory.path);

    expect(result.addedTracks, 1);
    expect(result.errors, isEmpty);
    final track = (await repositories.tracks.listTracks(limit: 10)).single;
    expect(track.artworkPath, isNull);
    expect(track.artworkHash, isNull);
  });

  test('rescan preserves manual metadata and updates technical fields',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_manual_metadata_rescan_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final file = File(p.join(tempDirectory.path, 'manual.mp3'));
    await file.writeAsBytes([1, 2, 3]);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final initialModifiedAt = DateTime(2026);
    final rescannedModifiedAt = DateTime(2026, 2);
    final reader = _SequenceMetadataReader([
      _audioMetadata(
        file,
        title: 'Scanned Title',
        artist: 'Scanned Artist',
        album: 'Scanned Album',
        duration: const Duration(minutes: 1),
        fileSizeBytes: 3,
        modifiedAt: initialModifiedAt,
        metadataSource: MetadataSource.embeddedTags,
        metadataConfidence: 0.95,
      ),
      _audioMetadata(
        file,
        title: 'Auto Title',
        artist: 'Auto Artist',
        album: 'Auto Album',
        albumArtist: 'Auto Album Artist',
        genre: 'Auto Genre',
        duration: const Duration(minutes: 2),
        trackNumber: 9,
        discNumber: 3,
        year: 1999,
        codec: 'flac',
        fileSizeBytes: 99,
        modifiedAt: rescannedModifiedAt,
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
    await repositories.tracks.updateTrackMetadata(
      TrackMetadataUpdate(
        trackId: firstTrack.id!,
        title: 'Manual Title',
        artist: 'Manual Artist',
        album: 'Manual Album',
        albumArtist: 'Manual Album Artist',
        genre: 'Manual Genre',
        year: 2026,
        trackNumber: 7,
        discNumber: 2,
        updatedAt: DateTime(2026, 1, 2),
      ),
    );

    final result = await scanner.scanFolder(tempDirectory.path);

    expect(result.addedTracks, 0);
    expect(result.updatedTracks, 1);
    final updatedTrack =
        (await repositories.tracks.listTracks(limit: 10)).single;
    expect(updatedTrack.id, firstTrack.id);
    expect(updatedTrack.stableId, firstTrack.stableId);
    expect(updatedTrack.title, 'Manual Title');
    expect(updatedTrack.artist, 'Manual Artist');
    expect(updatedTrack.album, 'Manual Album');
    expect(updatedTrack.albumArtist, 'Manual Album Artist');
    expect(updatedTrack.genre, 'Manual Genre');
    expect(updatedTrack.year, 2026);
    expect(updatedTrack.trackNumber, 7);
    expect(updatedTrack.discNumber, 2);
    expect(updatedTrack.metadataSource, MetadataSource.manual);
    expect(updatedTrack.metadataConfidence, 1.0);
    expect(updatedTrack.fileSizeBytes, 99);
    expect(updatedTrack.modifiedAt, rescannedModifiedAt);
    expect(updatedTrack.duration, const Duration(minutes: 2));
    expect(updatedTrack.codec, 'flac');
    expect(updatedTrack.lastSeenAt, isNotNull);
    expect(updatedTrack.isMissing, isFalse);
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
  String? albumArtist,
  String? genre,
  Duration? duration,
  int? trackNumber,
  int? discNumber,
  int? year,
  String? codec,
  int? fileSizeBytes,
  DateTime? modifiedAt,
  EmbeddedArtwork? artwork,
}) {
  final stat = file.statSync();
  return AudioMetadata(
    filePath: p.normalize(file.absolute.path),
    fileSizeBytes: fileSizeBytes ?? stat.size,
    modifiedAt: modifiedAt ?? stat.modified,
    title: title,
    codec: codec ?? p.extension(file.path).replaceFirst('.', '').toLowerCase(),
    metadataSource: metadataSource,
    metadataConfidence: metadataConfidence,
    artist: artist,
    album: album,
    albumArtist: albumArtist,
    genre: genre,
    duration: duration,
    trackNumber: trackNumber,
    discNumber: discNumber,
    year: year,
    artwork: artwork,
  );
}

EmbeddedArtwork _pngArtwork(List<int> payload) {
  return EmbeddedArtwork(
    bytes: Uint8List.fromList([
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      ...payload,
    ]),
    mimeType: 'image/png',
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

final class _StaticArtworkMetadataReader implements MetadataReaderService {
  const _StaticArtworkMetadataReader({required this.artwork});

  final EmbeddedArtwork artwork;

  @override
  Future<AudioMetadata> read(File file) async {
    return _audioMetadata(
      file,
      title: p.basenameWithoutExtension(file.path),
      metadataSource: MetadataSource.embeddedTags,
      metadataConfidence: 0.95,
      artwork: artwork,
    );
  }
}

final class _FailingArtworkCacheService implements ArtworkCacheService {
  const _FailingArtworkCacheService();

  @override
  Future<CachedArtwork?> saveEmbeddedArtwork(EmbeddedArtwork? artwork) {
    throw StateError('artwork storage failed');
  }
}
