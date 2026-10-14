import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/library_track_list.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/flac_metadata_fixture.dart';

void main() {
  late Directory root;
  late Directory music;
  late Directory artwork;
  late AppDatabase database;
  late DriftRepositories repositories;
  late LibraryScannerService scanner;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cmp_import_pipeline_');
    music = await Directory(p.join(root.path, 'music')).create();
    artwork = Directory(p.join(root.path, 'artwork'));
    for (final name in ['original.flac', 'копия 💿.flac']) {
      await File(p.join(music.path, name)).writeAsBytes(flacMetadataFixture());
    }
    database = AppDatabase(NativeDatabase.memory());
    repositories = DriftRepositories(database);
    scanner = LibraryScannerService(
        libraryRepository: repositories.libraryFolders,
        trackRepository: repositories.tracks,
        metadataReader: const AudioMetadataReaderService(),
        artworkCache: AppSupportArtworkCacheService(artworkDirectory: artwork));
  });
  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  test(
      'real optimized import preserves tags, shared cover, copies, feedback and playlists',
      () async {
    final first =
        await scanner.scanFolder(music.path, control: LibraryScanControl());
    expect(first.errors, isEmpty);
    expect(first.addedTracks, 2);
    expect(first.metrics.hashedFiles, 2);
    expect(first.metrics.metadataReads, 2);
    expect(first.metrics.nativeHashFiles, Platform.isWindows ? 2 : 0);
    final tracks = await repositories.tracks.listTracks();
    expect(tracks.map((track) => track.title).toSet(), {'Песня 💿'});
    expect(tracks.map((track) => track.contentHash).toSet(), hasLength(1));
    expect(tracks.map((track) => track.artworkPath).toSet(), hasLength(1));
    expect(await artwork.list().length, 1);
    expect(
        buildVisibleLibraryTracks(
            tracks: tracks,
            searchQuery: '',
            showMissingTracks: false,
            sortOption: LibraryTrackSortOption.title),
        hasLength(1));
    await repositories.trackUserState.upsertState(TrackUserState(
        trackId: tracks.first.id!,
        isFavorite: true,
        playCount: 8,
        updatedAt: DateTime(2026)));
    final playlist = await repositories.playlists.createPlaylist('Keep');
    for (final track in tracks) {
      await repositories.playlists.addTrackToPlaylist(playlist, track.id!);
    }
    final second =
        await scanner.scanFolder(music.path, control: LibraryScanControl());
    expect(second.addedTracks, 0);
    expect(second.updatedTracks, 2);
    expect(second.metrics.metadataReads, 0);
    expect((await repositories.tracks.listTracks()).map((track) => track.id),
        tracks.map((track) => track.id));
    expect(
        (await repositories.trackUserState.findByTrackId(tracks.first.id!))!
            .playCount,
        8);
    expect(
        (await repositories.playlists.watchPlaylistTracks(playlist).first)
            .map((entry) => entry.trackId),
        tracks.map((track) => track.id));
  });

  test(
      'cancel after real tags/cover completes stops before publishing a partial track',
      () async {
    late LibraryScanControl control;
    control = LibraryScanControl(onProgress: (progress) {
      if (progress.stage == LibraryScanStage.saving) control.cancel();
    });
    final result = await scanner.scanFolder(music.path, control: control);
    expect(result.wasCancelled, isTrue);
    expect(result.errors, isEmpty);
    expect(result.addedTracks, 0);
    expect(result.processedFiles, 0);
    expect(result.metrics.hashedFiles, 1);
    expect(result.metrics.metadataReads, 1);
    expect(await repositories.tracks.listTracks(), isEmpty);
    final sources =
        await music.list().where((entity) => entity is File).toList();
    for (final source in sources) {
      await source.delete();
    }
  });
}
