import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/library_repository.dart';
import 'package:clever_music_player/src/library/library_management_service.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase database;
  late DriftRepositories repositories;
  late LibraryManagementService management;
  late Directory temporary;
  late File source;
  late LibraryFolder folder;
  late int trackId;
  late int playlistId;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cmp-folder-removal-');
    source = await File(p.join(temporary.path, 'source.mp3'))
        .writeAsBytes([1, 2, 3, 4]);
    database = AppDatabase(NativeDatabase.memory());
    repositories = DriftRepositories(database);
    final now = DateTime(2026);
    final id = await repositories.libraryFolders.upsertFolder(LibraryFolder(
        path: temporary.path,
        isEnabled: false,
        createdAt: now,
        updatedAt: now));
    folder =
        (await repositories.libraryFolders.findFolderByPath(temporary.path))!;
    trackId = await repositories.tracks.upsertTrack(Track(
        filePath: source.path,
        libraryFolderId: id,
        addedAt: now,
        updatedAt: now));
    await repositories.trackUserState.upsertState(TrackUserState(
        trackId: trackId, isFavorite: true, playCount: 7, updatedAt: now));
    await repositories.playbackEvents.addEvent(PlaybackEvent(
        trackId: trackId, type: PlaybackEventType.started, occurredAt: now));
    playlistId = await repositories.playlists.createPlaylist('Keep playlist');
    await repositories.playlists.addTrackToPlaylist(playlistId, trackId);
    management = LibraryManagementService(
        libraryRepository: repositories.libraryFolders,
        scanFolder: (_) async => const LibraryScanResult(
            folderPath: '',
            scannedFiles: 0,
            addedTracks: 0,
            updatedTracks: 0,
            missingTracks: 0,
            errors: []));
  });
  tearDown(() async {
    await database.close();
    await temporary.delete(recursive: true);
  });

  Future<void> expectLibraryPreserved() async {
    expect(await repositories.libraryFolders.findFolderByPath(folder.path),
        isNotNull);
    expect(await repositories.tracks.findById(trackId), isNotNull);
    final state = await repositories.trackUserState.findByTrackId(trackId);
    expect(state?.isFavorite, true);
    expect(state?.playCount, 7);
    expect(await repositories.playbackEvents.recentForTrack(trackId),
        hasLength(1));
    expect(await repositories.playlists.watchPlaylistTracks(playlistId).first,
        hasLength(1));
    expect(await source.readAsBytes(), [1, 2, 3, 4]);
  }

  test(
      'folder deletion failure rolls back tracks, feedback, history and playlist membership',
      () async {
    await database.customStatement('''CREATE TRIGGER reject_folder_removal
      BEFORE DELETE ON library_folders BEGIN
      SELECT RAISE(ABORT, 'injected deletion failure'); END;''');
    await expectLater(
        management.removeFolderFromLibrary(folder), throwsA(anything));
    await expectLibraryPreserved();
  });

  test('a stale disabled snapshot cannot delete a currently enabled folder',
      () async {
    await repositories.libraryFolders.setFolderEnabled(folder.id!,
        isEnabled: true, updatedAt: DateTime(2026, 2));
    await expectLater(
        management.removeFolderFromLibrary(folder), throwsStateError);
    await expectLibraryPreserved();
  });

  test('an ignored folder delete also rolls back its associated rows',
      () async {
    await database.customStatement('''CREATE TRIGGER ignore_folder_removal
      BEFORE DELETE ON library_folders BEGIN SELECT RAISE(IGNORE); END;''');
    await expectLater(
        management.removeFolderFromLibrary(folder), throwsStateError);
    await expectLibraryPreserved();
  });

  test('an adapter without atomic removal fails before changing any rows',
      () async {
    final legacy = LibraryManagementService(
        libraryRepository: _LegacyLibrary(repositories.libraryFolders),
        scanFolder: (_) async => throw UnimplementedError());
    await expectLater(
        legacy.removeFolderFromLibrary(folder), throwsUnsupportedError);
    await expectLibraryPreserved();
  });

  test(
      'removal changes only database rows and preserves files and unrelated records',
      () async {
    final before = sha256.convert(await source.readAsBytes());
    final otherId = await repositories.tracks.upsertTrack(Track(
        filePath: p.join(temporary.path, 'other.mp3'),
        addedAt: DateTime(2026),
        updatedAt: DateTime(2026)));
    await repositories.playlists.addTrackToPlaylist(playlistId, otherId);
    await management.removeFolderFromLibrary(folder);
    expect(await repositories.libraryFolders.findFolderByPath(folder.path),
        isNull);
    expect(await repositories.tracks.findById(trackId), isNull);
    expect(await repositories.trackUserState.findByTrackId(trackId), isNull);
    expect(await repositories.playbackEvents.recentForTrack(trackId), isEmpty);
    final entries =
        await repositories.playlists.watchPlaylistTracks(playlistId).first;
    expect(entries.map((entry) => entry.track.id), [otherId]);
    expect(await repositories.tracks.findById(otherId), isNotNull);
    expect(sha256.convert(await source.readAsBytes()), before);
    expect(await temporary.exists(), true);
    await management.removeFolderFromLibrary(folder); // Idempotent retry.
    expect(await repositories.tracks.findById(otherId), isNotNull);
  });
}

class _LegacyLibrary implements LibraryRepository {
  _LegacyLibrary(this.delegate);
  final LibraryRepository delegate;
  @override
  Future<int> upsertFolder(LibraryFolder folder) =>
      delegate.upsertFolder(folder);
  @override
  Future<LibraryFolder?> findFolderByPath(String path) =>
      delegate.findFolderByPath(path);
  @override
  Future<List<LibraryFolder>> listFolders({bool includeDisabled = true}) =>
      delegate.listFolders(includeDisabled: includeDisabled);
  @override
  Stream<List<LibraryFolder>> watchFolders({bool includeDisabled = true}) =>
      delegate.watchFolders(includeDisabled: includeDisabled);
  @override
  Future<void> setFolderEnabled(int id,
          {required bool isEnabled, required DateTime updatedAt}) =>
      delegate.setFolderEnabled(id, isEnabled: isEnabled, updatedAt: updatedAt);
  @override
  Future<void> deleteFolder(int id) => delegate.deleteFolder(id);
}
