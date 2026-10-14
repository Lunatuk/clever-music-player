import 'dart:async';

import 'package:clever_music_player/src/app/dependency_scope.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/library_folder.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/custom_artwork_service.dart';
import 'package:clever_music_player/src/library/directory_picker_service.dart';
import 'package:clever_music_player/src/library/library_controller.dart';
import 'package:clever_music_player/src/library/library_management_service.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:clever_music_player/src/queue/playback_queue_service.dart';
import 'package:clever_music_player/src/recommendation/recommendation_service.dart';
import 'package:clever_music_player/src/smtc/smtc_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_audio_engine.dart';

void main() {
  test('app disposal closes admission before draining work and closing SQLite',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    final repositories = DriftRepositories(database);
    final now = DateTime(2026);
    await repositories.libraryFolders.upsertFolder(
        LibraryFolder(path: '/music', createdAt: now, updatedAt: now));
    final folder = (await repositories.libraryFolders.listFolders()).single;
    final entered = Completer<void>();
    final finish = Completer<void>();
    Future<LibraryScanResult> scan(String path) async {
      entered.complete();
      await finish.future;
      // This late database operation must finish before database.close().
      await repositories.libraryFolders
          .setFolderEnabled(folder.id!, isEnabled: false, updatedAt: now);
      return LibraryScanResult(
          folderPath: path,
          scannedFiles: 0,
          addedTracks: 0,
          updatedTracks: 0,
          missingTracks: 0,
          errors: const []);
    }

    final library = LibraryController(
        directoryPicker: const _Picker(),
        scanFolder: scan,
        management: LibraryManagementService(
            libraryRepository: repositories.libraryFolders, scanFolder: scan));
    final player = JustAudioPlayerService(
        playbackEvents: repositories.playbackEvents,
        audioEngine: TestAudioEngine(),
        isWindows: false);
    final recommendations = RecommendationService(
        tracks: repositories.tracks,
        trackUserState: repositories.trackUserState,
        playbackEvents: repositories.playbackEvents);
    final queue = PlaybackQueueService(
        playerService: player,
        tracks: repositories.tracks,
        trackUserState: repositories.trackUserState,
        playbackEvents: repositories.playbackEvents,
        recommendationService: recommendations);
    final dependencies = AppDependencies(
        database: database,
        repositories: repositories,
        recommendationService: recommendations,
        libraryScanner: LibraryScannerService(
            libraryRepository: repositories.libraryFolders,
            trackRepository: repositories.tracks,
            metadataReader: const FallbackMetadataReaderService()),
        directoryPicker: const _Picker(),
        customArtwork: const FilePickerCustomArtworkService(
            artworkCache: NoopArtworkCacheService()),
        playerService: player,
        playbackQueue: queue,
        smtcService: const NoopSmtcService(),
        libraryController: library);
    final scanning = library.rescanFolder(folder);
    await entered.future;
    var disposed = false;
    final disposing = dependencies.dispose().then((_) => disposed = true);
    expect(await library.addFolder(), LibraryOperationOutcome.closed);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, false);
    expect(await repositories.libraryFolders.listFolders(), hasLength(1));
    finish.complete();
    expect(await scanning, LibraryOperationOutcome.closed);
    await disposing;
    expect(disposed, true);
    await expectLater(
        database.customSelect('SELECT 1').get(), throwsA(anything));
  });
}

class _Picker implements DirectoryPickerService {
  const _Picker();
  @override
  Future<String?> pickMusicFolder() async => null;
}
