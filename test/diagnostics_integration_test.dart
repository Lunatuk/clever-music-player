import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/player/windows_playback_cache.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:path/path.dart' as p;

import 'support/test_audio_engine.dart';

void main() {
  late Directory temporary;
  late LocalDiagnosticsService diagnostics;
  late AppDatabase database;
  late DriftRepositories repositories;
  setUp(() async {
    temporary =
        await Directory.systemTemp.createTemp('cmp-diagnostics-integration-');
    diagnostics = LocalDiagnosticsService(
        directoryProvider: () async =>
            Directory(p.join(temporary.path, 'diagnostics')));
    database = AppDatabase(NativeDatabase.memory(), diagnostics: diagnostics);
    repositories = DriftRepositories(database);
  });
  tearDown(() async {
    await database.close();
    await diagnostics.flush();
    await temporary.delete(recursive: true);
  });

  Future<List<dynamic>> events() async {
    final file = await diagnostics.exportReport();
    final contents = await file.readAsString();
    expect(contents, isNot(contains(temporary.path)));
    expect(contents, isNot(contains('PRIVATE')));
    return (jsonDecode(contents) as Map)['events'] as List;
  }

  test('new database emits successful migration and open after transaction',
      () async {
    await repositories.tracks.listTracks();
    final entries = await events();
    expect(entries.map((e) => e['event']),
        ['migrationStarted', 'migrationCompleted', 'databaseOpened']);
    expect(entries[0]['schemaFrom'], 0);
    expect(entries[1]['schemaTo'], 13);
    expect(
        await database
            .customSelect('PRAGMA user_version')
            .getSingle()
            .then((r) => r.data.values.single),
        13);
  });

  test('failed migration is reported without a false success or raw SQL',
      () async {
    await database.close();
    database = AppDatabase(NativeDatabase.memory(setup: (db) {
      db.execute('PRAGMA user_version=8;');
    }), diagnostics: diagnostics);
    await expectLater(
        database.customSelect('SELECT 1').get(), throwsA(anything));
    final entries = await events();
    expect(entries.map((e) => e['event']),
        ['migrationStarted', 'migrationFailed']);
    expect(entries.last['schemaFrom'], 8);
    expect(entries.last['schemaTo'], 13);
  });

  test('scanner and cache report outcomes while preserving source bytes',
      () async {
    final music =
        await Directory(p.join(temporary.path, 'PRIVATE music')).create();
    final source = await File(p.join(music.path, 'PRIVATE song.mp3'))
        .writeAsBytes([1, 2, 3]);
    final before = sha256.convert(await source.readAsBytes());
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: const FallbackMetadataReaderService(),
      diagnostics: diagnostics,
    );
    final scan = await scanner.scanFolder(music.path);
    final track = (await repositories.tracks.listTracks()).single;
    final cache = WindowsPlaybackCache(
      appSupportDirectoryProvider: () async =>
          Directory(p.join(temporary.path, 'cache')),
      diagnostics: diagnostics,
    );
    await cache.resolve(track, source.path);
    await cache.resolve(track, source.path);
    final entries = await events();
    final complete = entries.singleWhere((e) => e['event'] == 'scanCompleted');
    expect(complete['addedTracks'], scan.addedTracks);
    expect(complete['scannedFiles'], 1);
    expect(complete['hashedBytes'], 3);
    expect(complete['hashedFiles'], 1);
    expect(complete['nativeHashFiles'], Platform.isWindows ? 1 : 0);
    expect(complete['metadataReads'], 1);
    expect(complete['hashUs'], scan.metrics.hashUs);
    expect(complete['metadataUs'], scan.metrics.metadataUs);
    expect(complete['artworkUs'], scan.metrics.artworkUs);
    expect(complete['databaseUs'], scan.metrics.databaseUs);
    expect(complete['fileSystemUs'], scan.metrics.fileSystemUs);
    expect(complete['importBatches'], 1);
    expect(complete['importRows'], 1);
    expect(complete['hashReadUs'], scan.metrics.hashReadUs);
    expect(complete['hashComputeUs'], scan.metrics.hashComputeUs);
    expect(complete['hashWorkerUs'], scan.metrics.hashWorkerUs);
    expect(complete['hashOverheadUs'], scan.metrics.hashOverheadUs);
    expect(complete['hashStartupUs'], scan.metrics.hashStartupUs);
    expect(complete['hashWorkerStarts'], 1);
    expect(complete['databaseLookupUs'], scan.metrics.databaseLookupUs);
    expect(complete['databaseImportUs'], scan.metrics.databaseImportUs);
    expect(
        complete['databaseMaintenanceUs'], scan.metrics.databaseMaintenanceUs);
    final cached = entries.where((e) => e['event'] == 'cacheResolved').toList();
    expect(cached.map((e) => e['reused']), [false, true]);
    expect(cached.first['sourceBytes'], 3);
    expect(sha256.convert(await source.readAsBytes()), before);
  });

  test('cancelled scan has its own diagnostic event without paths or failures',
      () async {
    final music =
        await Directory(p.join(temporary.path, 'PRIVATE cancelled')).create();
    await File(p.join(music.path, 'PRIVATE song.mp3')).writeAsBytes([1]);
    late LibraryScanControl control;
    control = LibraryScanControl(onProgress: (_) => control.cancel());
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: const FallbackMetadataReaderService(),
      diagnostics: diagnostics,
    );
    final result = await scanner.scanFolder(music.path, control: control);
    expect(result.wasCancelled, isTrue);
    final entries = await events();
    final cancelled =
        entries.singleWhere((entry) => entry['event'] == 'scanCancelled');
    expect(cancelled['scannedFiles'], 0);
    expect(cancelled['errorCount'], 0);
    expect(entries.any((entry) => entry['event'] == 'scanFileFailed'), isFalse);
    expect(entries.toString(), isNot(contains('PRIVATE')));
  });

  test('scanner reports individual metadata failures without file names',
      () async {
    final music = await Directory(p.join(temporary.path, 'music')).create();
    await File(p.join(music.path, 'PRIVATE broken.mp3')).writeAsBytes([1]);
    final scanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: _BrokenReader(),
      diagnostics: diagnostics,
    );
    final scan = await scanner.scanFolder(music.path);
    expect(scan.errors, hasLength(1));
    final entries = await events();
    expect(
        entries.singleWhere((e) => e['event'] == 'scanFileFailed')['errorKind'],
        'format');
    expect(
        entries.singleWhere((e) => e['event'] == 'scanCompleted')['errorCount'],
        1);
  });

  test('source error and decoder code appear without tags or exception message',
      () async {
    final engine = TestAudioEngine();
    final track = Track(
        filePath: p.join(temporary.path, 'PRIVATE song.mp3'),
        title: 'PRIVATE title',
        artist: 'PRIVATE artist',
        addedAt: DateTime(2026),
        updatedAt: DateTime(2026));
    final player = JustAudioPlayerService(
        playbackEvents: repositories.playbackEvents,
        audioEngine: engine,
        isWindows: false,
        fileExists: (_) => false,
        diagnostics: diagnostics);
    await player.playTrack(track);
    expect(player.state.status, PlayerPlaybackStatus.error);
    await player.dispose();
    final entries = await events();
    expect(entries.map((e) => e['event']),
        containsAll(['audioLoadStarted', 'sourceMissing', 'audioLoadFailed']));

    final failedEngine = TestAudioEngine()
      ..setFilePathError =
          just_audio.PlayerException(17, 'PRIVATE token', null);
    final failedPlayer = JustAudioPlayerService(
        playbackEvents: repositories.playbackEvents,
        audioEngine: failedEngine,
        isWindows: false,
        fileExists: (_) => true,
        diagnostics: diagnostics);
    await failedPlayer.playTrack(track);
    await failedPlayer.dispose();
    final failed =
        (await events()).where((e) => e['event'] == 'audioLoadFailed').last;
    expect(failed['nativeCode'], 17);
  });

  test('preparation is distinguished and journal failure does not stop audio',
      () async {
    final failing = LocalDiagnosticsService(
        directoryProvider: () async =>
            throw const FileSystemException('PRIVATE disk error'));
    final track = Track(
        filePath: p.join(temporary.path, 'PRIVATE song.mp3'),
        addedAt: DateTime(2026),
        updatedAt: DateTime(2026));
    final engine = TestAudioEngine();
    final player = JustAudioPlayerService(
        playbackEvents: repositories.playbackEvents,
        audioEngine: engine,
        isWindows: false,
        fileExists: (_) => true,
        diagnostics: failing);
    await player.playTrack(track);
    await failing.flush();
    expect(engine.playCalls, 1);
    expect(player.state.status, PlayerPlaybackStatus.playing);
    await player.dispose();

    final prepared = JustAudioPlayerService(
        playbackEvents: repositories.playbackEvents,
        audioEngine: TestAudioEngine(),
        isWindows: false,
        fileExists: (_) => true,
        diagnostics: diagnostics);
    await prepared.prepareTrack(track);
    final entries = await events();
    expect(
        entries.singleWhere(
            (e) => e['event'] == 'audioLoadCompleted')['preparing'],
        true);
    expect(prepared.isPlaying, false);
    await prepared.dispose();
  });

  for (final timeout in [false, true]) {
    test(
        'Windows cache failure retains ${timeout ? 'timeout' : 'HRESULT'} and permits retry',
        () async {
      final source = await File(p.join(temporary.path, 'PRIVATE source.mp3'))
          .writeAsBytes([1, 2, 3]);
      final track = Track(
          filePath: source.path,
          addedAt: DateTime(2026),
          updatedAt: DateTime(2026));
      final engine = TestAudioEngine()
        ..setFilePathError = timeout
            ? TimeoutException('PRIVATE decoder timeout')
            : just_audio.PlayerException(
                -1072875836, 'PRIVATE native path', null);
      final player = JustAudioPlayerService(
          playbackEvents: repositories.playbackEvents,
          diagnostics: diagnostics,
          audioEngine: engine,
          isWindows: true,
          fileExists: (_) => true,
          playbackCache: WindowsPlaybackCache(
              appSupportDirectoryProvider: () async => temporary));
      try {
        await player.playTrack(track);
        expect(player.state.status, PlayerPlaybackStatus.error);
        expect(engine.playCalls, 0);
        final recorded = await events();
        final attempts = recorded
            .where((e) => e['event'] == 'audioLoadAttemptFailed')
            .toList();
        expect(attempts.map((e) => e['cached']), [false, true]);
        final failed =
            recorded.lastWhere((e) => e['event'] == 'audioLoadFailed');
        if (timeout) {
          expect(failed['errorKind'], 'timeout');
          expect(attempts.every((e) => e['errorKind'] == 'timeout'), isTrue);
        } else {
          expect(failed['nativeCode'], -1072875836);
          expect(attempts.every((e) => e['nativeCode'] == -1072875836), isTrue);
        }
        engine.setFilePathError = null;
        await player.playTrack(track);
        expect(engine.playCalls, 1);
        expect(await source.readAsBytes(), [1, 2, 3]);
      } finally {
        await player.dispose();
      }
    });
  }

  test('play and pause requests are distinguishable from successful loading',
      () async {
    final track = Track(
        filePath: p.join(temporary.path, 'PRIVATE song.mp3'),
        addedAt: DateTime(2026),
        updatedAt: DateTime(2026));
    final player = JustAudioPlayerService(
        playbackEvents: repositories.playbackEvents,
        audioEngine: TestAudioEngine(),
        isWindows: false,
        fileExists: (_) => true,
        diagnostics: diagnostics);
    try {
      await player.playTrack(track);
      await Future<void>.delayed(Duration.zero);
      await player.pause();
      await Future<void>.delayed(Duration.zero);
      final entries = await events();
      final names = entries.map((e) => e['event']).toList();
      expect(
          names,
          containsAllInOrder([
            'audioLoadStarted',
            'audioLoadCompleted',
            'audioPlayRequested',
            'audioPauseRequested',
          ]));
      final observed =
          entries.where((e) => e['event'] == 'audioStateChanged').toList();
      expect(observed, isNotEmpty);
      expect(observed.last['playing'], false);
    } finally {
      await player.dispose();
    }
  });
}

class _BrokenReader implements MetadataReaderService {
  @override
  Future<AudioMetadata> read(File file) async =>
      throw const FormatException('PRIVATE tags');
}
