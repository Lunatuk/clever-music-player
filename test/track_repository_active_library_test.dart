import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/library_management_service.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/library_track_list.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('disabling a folder hides its tracks from active track queries',
      () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);

    await fixture.disableFolder(fixture.downloadsFolderId);

    final tracks = await fixture.repositories.tracks.listTracks(limit: 10);

    expect(tracks.map((track) => track.title), ['Library Track']);
  });

  test('disabling a folder excludes its tracks from search results', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);

    await fixture.disableFolder(fixture.downloadsFolderId);

    final activeTracks = await fixture.repositories.tracks
        .watchAllTracks(includeMissing: true)
        .first;
    final visible = buildVisibleLibraryTracks(
      tracks: activeTracks,
      searchQuery: 'download',
      showMissingTracks: false,
      sortOption: LibraryTrackSortOption.title,
    );

    expect(visible, isEmpty);
  });

  test('reenabling a folder restores its tracks without rescanning', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);

    await fixture.repositories.trackUserState.upsertState(
      TrackUserState(
        trackId: fixture.downloadTrackId,
        isFavorite: true,
        playCount: 3,
        updatedAt: fixture.now,
      ),
    );
    await fixture.disableFolder(fixture.downloadsFolderId);
    expect(await fixture.activeTrackTitles(), ['Library Track']);

    await fixture.enableFolder(fixture.downloadsFolderId);

    expect(
      await fixture.activeTrackTitles(),
      ['Download Clip', 'Library Track'],
    );
    final state = await fixture.repositories.trackUserState.findByTrackId(
      fixture.downloadTrackId,
    );
    expect(state?.isFavorite, isTrue);
    expect(state?.playCount, 3);
  });

  test('disabling a folder does not delete track user state or history',
      () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);

    await fixture.repositories.trackUserState.upsertState(
      TrackUserState(
        trackId: fixture.downloadTrackId,
        isFavorite: true,
        updatedAt: fixture.now,
      ),
    );
    await fixture.repositories.playbackEvents.addEvent(
      PlaybackEvent(
        trackId: fixture.downloadTrackId,
        type: PlaybackEventType.started,
        occurredAt: fixture.now,
      ),
    );

    await fixture.disableFolder(fixture.downloadsFolderId);

    final state = await fixture.repositories.trackUserState.findByTrackId(
      fixture.downloadTrackId,
    );
    final track = await fixture.repositories.tracks.findById(
      fixture.downloadTrackId,
    );
    final events = await fixture.repositories.playbackEvents.recentForTrack(
      fixture.downloadTrackId,
    );

    expect(state?.isFavorite, isTrue);
    expect(track, isNotNull);
    expect(events, hasLength(1));
  });

  test('folder watches still include disabled folders', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);

    await fixture.disableFolder(fixture.downloadsFolderId);

    final folders =
        await fixture.repositories.libraryFolders.watchFolders().first;

    expect(folders, hasLength(2));
    expect(
      folders
          .singleWhere((folder) => folder.id == fixture.downloadsFolderId)
          .isEnabled,
      isFalse,
    );
  });

  test('show missing tracks does not reveal disabled-folder tracks', () async {
    final fixture = await _createFixture(includeMissingTracks: true);
    addTearDown(fixture.close);

    await fixture.disableFolder(fixture.downloadsFolderId);

    final activeTracks = await fixture.repositories.tracks
        .watchAllTracks(includeMissing: true)
        .first;
    final visible = buildVisibleLibraryTracks(
      tracks: activeTracks,
      searchQuery: '',
      showMissingTracks: true,
      sortOption: LibraryTrackSortOption.title,
    );

    expect(visible.map((track) => track.title), [
      'Library Missing',
      'Library Track',
    ]);
  });

  test('indexed track reads can include disabled folders for stats', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);

    await fixture.disableFolder(fixture.downloadsFolderId);

    final indexedTracks = await fixture.repositories.tracks
        .watchAllTracks(
          includeMissing: true,
          includeDisabledFolders: true,
        )
        .first;

    expect(indexedTracks.map((track) => track.title), [
      'Download Clip',
      'Library Track',
    ]);
  });

  test('remove folder deletes folder row and only its app database tracks',
      () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);

    await fixture.disableFolder(fixture.downloadsFolderId);
    await fixture.removeDownloadsFromLibrary();

    final folders = await fixture.repositories.libraryFolders.listFolders();
    final allTracks = await fixture.repositories.tracks
        .watchAllTracks(
          includeMissing: true,
          includeDisabledFolders: true,
        )
        .first;

    expect(folders.map((folder) => folder.path), ['/music/library']);
    expect(allTracks.map((track) => track.title), ['Library Track']);
    expect(
      await fixture.repositories.tracks.findById(fixture.downloadTrackId),
      isNull,
    );
    expect(
      await fixture.repositories.tracks.findById(fixture.libraryTrackId),
      isNotNull,
    );
  });

  test('remove folder cleans app-only state and history for removed tracks',
      () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);

    await fixture.repositories.trackUserState.upsertState(
      TrackUserState(
        trackId: fixture.downloadTrackId,
        isFavorite: true,
        updatedAt: fixture.now,
      ),
    );
    await fixture.repositories.playbackEvents.addEvent(
      PlaybackEvent(
        trackId: fixture.downloadTrackId,
        type: PlaybackEventType.started,
        occurredAt: fixture.now,
      ),
    );
    await fixture.disableFolder(fixture.downloadsFolderId);

    await fixture.removeDownloadsFromLibrary();

    expect(
      await fixture.repositories.trackUserState.findByTrackId(
        fixture.downloadTrackId,
      ),
      isNull,
    );
    expect(
      await fixture.repositories.playbackEvents.recentForTrack(
        fixture.downloadTrackId,
      ),
      isEmpty,
    );
  });

  test('removed folder tracks do not appear in active track streams', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.close);

    await fixture.disableFolder(fixture.downloadsFolderId);
    await fixture.removeDownloadsFromLibrary();

    final activeTracks = await fixture.repositories.tracks
        .watchAllTracks(includeMissing: true)
        .first;

    expect(activeTracks.map((track) => track.title), ['Library Track']);
  });

  test('remove folder does not delete physical files from disk', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_remove_folder_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final audioFile = File(p.join(tempDirectory.path, 'keep.mp3'));
    await audioFile.writeAsBytes([1, 2, 3]);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final now = DateTime(2026);
    final folderId = await repositories.libraryFolders.upsertFolder(
      LibraryFolder(
        path: tempDirectory.path,
        displayName: 'Temp',
        isEnabled: false,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repositories.tracks.upsertTrack(
      _track(
        folderId: folderId,
        title: 'Keep',
        filePath: audioFile.path,
        now: now,
      ),
    );
    final service = LibraryManagementService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      scanFolder: (path) async => LibraryScanResult(
        folderPath: path,
        scannedFiles: 0,
        addedTracks: 0,
        updatedTracks: 0,
        missingTracks: 0,
        errors: const [],
      ),
    );

    await service.removeFolderFromLibrary(
      (await repositories.libraryFolders.findFolderByPath(tempDirectory.path))!,
    );

    expect(await audioFile.exists(), isTrue);
    expect(await tempDirectory.exists(), isTrue);
    expect(await repositories.tracks.findByPath(audioFile.path), isNull);
  });
}

Future<_RepositoryFixture> _createFixture({
  bool includeMissingTracks = false,
}) async {
  final database = AppDatabase(NativeDatabase.memory());
  final repositories = DriftRepositories(database);
  final now = DateTime(2026);
  final libraryFolderId = await repositories.libraryFolders.upsertFolder(
    LibraryFolder(
      path: '/music/library',
      displayName: 'Library',
      createdAt: now,
      updatedAt: now,
    ),
  );
  final downloadsFolderId = await repositories.libraryFolders.upsertFolder(
    LibraryFolder(
      path: '/downloads',
      displayName: 'Downloads',
      createdAt: now,
      updatedAt: now,
    ),
  );
  final libraryTrackId = await repositories.tracks.upsertTrack(
    _track(
      folderId: libraryFolderId,
      title: 'Library Track',
      filePath: '/music/library/library-track.mp3',
      now: now,
    ),
  );
  final downloadTrackId = await repositories.tracks.upsertTrack(
    _track(
      folderId: downloadsFolderId,
      title: 'Download Clip',
      filePath: '/downloads/download-clip.mp3',
      now: now,
    ),
  );

  if (includeMissingTracks) {
    await repositories.tracks.upsertTrack(
      _track(
        folderId: libraryFolderId,
        title: 'Library Missing',
        filePath: '/music/library/library-missing.mp3',
        isMissing: true,
        now: now,
      ),
    );
    await repositories.tracks.upsertTrack(
      _track(
        folderId: downloadsFolderId,
        title: 'Download Missing',
        filePath: '/downloads/download-missing.mp3',
        isMissing: true,
        now: now,
      ),
    );
  }

  return _RepositoryFixture(
    database: database,
    repositories: repositories,
    now: now,
    downloadsFolderId: downloadsFolderId,
    libraryTrackId: libraryTrackId,
    downloadTrackId: downloadTrackId,
  );
}

Track _track({
  required int folderId,
  required String title,
  required String filePath,
  required DateTime now,
  bool isMissing = false,
}) {
  return Track(
    libraryFolderId: folderId,
    filePath: filePath,
    title: title,
    artist: 'Artist',
    album: 'Album',
    isMissing: isMissing,
    addedAt: now,
    updatedAt: now,
  );
}

final class _RepositoryFixture {
  const _RepositoryFixture({
    required this.database,
    required this.repositories,
    required this.now,
    required this.downloadsFolderId,
    required this.libraryTrackId,
    required this.downloadTrackId,
  });

  final AppDatabase database;
  final DriftRepositories repositories;
  final DateTime now;
  final int downloadsFolderId;
  final int libraryTrackId;
  final int downloadTrackId;

  Future<List<String?>> activeTrackTitles() async {
    final tracks = await repositories.tracks.listTracks(limit: 10);
    return tracks.map((track) => track.title).toList(growable: false);
  }

  Future<void> disableFolder(int id) {
    return repositories.libraryFolders.setFolderEnabled(
      id,
      isEnabled: false,
      updatedAt: now.add(const Duration(minutes: 1)),
    );
  }

  Future<void> enableFolder(int id) {
    return repositories.libraryFolders.setFolderEnabled(
      id,
      isEnabled: true,
      updatedAt: now.add(const Duration(minutes: 2)),
    );
  }

  Future<void> removeDownloadsFromLibrary() async {
    final folder = await repositories.libraryFolders.findFolderByPath(
      '/downloads',
    );
    final service = LibraryManagementService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      scanFolder: (path) async => LibraryScanResult(
        folderPath: path,
        scannedFiles: 0,
        addedTracks: 0,
        updatedTracks: 0,
        missingTracks: 0,
        errors: const [],
      ),
    );
    await service.removeFolderFromLibrary(folder!);
  }

  Future<void> close() => database.close();
}
