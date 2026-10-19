import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/domain/models/track.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:clever_music_player/src/player/windows_playback_snapshot.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_diagnostics.dart';
import 'support/test_audio_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.ryanheise.just_audio.methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('actual C++ snapshot payload reaches the typed parser', () async {
    final payload = jsonDecode(
        await File('test/fixtures/windows_native_playback_snapshot.json')
            .readAsString());
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getPlaybackDiagnostics');
      expect(call.arguments, <String, Object?>{});
      return [payload];
    });
    final snapshot = (await readWindowsPlaybackSnapshots()).single;
    expect(snapshot.state, 3);
    expect(snapshot.positionMs, 2500);
    expect(snapshot.durationMs, 60000);
    expect(snapshot.sourcePresent, isTrue);
  });
  test('no native players is a valid observation', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => []);
    expect(await readWindowsPlaybackSnapshots(), isEmpty);
  });
  test('malformed and oversized native data is rejected', () async {
    for (final value in [
      null,
      [42],
      [{}],
      [
        {
          'playbackState': 5,
          'positionMs': 0,
          'durationMs': 0,
          'sourcePresent': true
        }
      ],
      [
        {
          'playbackState': 3,
          'positionMs': -1,
          'durationMs': 0,
          'sourcePresent': true
        }
      ],
      [
        {
          'playbackState': 3,
          'positionMs': 0,
          'durationMs': -1,
          'sourcePresent': true
        }
      ],
      [
        {
          'playbackState': 3,
          'positionMs': 0,
          'durationMs': 0,
          'sourcePresent': 1
        }
      ],
      List.filled(9, {
        'playbackState': 3,
        'positionMs': 0,
        'durationMs': 0,
        'sourcePresent': true
      })
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      await expectLater(readWindowsPlaybackSnapshots(), throwsFormatException);
    }
  });

  late AppDatabase db;
  late RecordingDiagnostics diagnostics;
  late TestAudioEngine engine;
  late JustAudioPlayerService player;
  final track = Track(
      id: 42,
      filePath: 'C:/music/song.mp3',
      duration: const Duration(minutes: 2),
      addedAt: DateTime(2026),
      updatedAt: DateTime(2026));
  Future<void> open(WindowsPlaybackProbe probe) async {
    db = AppDatabase(NativeDatabase.memory());
    diagnostics = RecordingDiagnostics();
    engine = TestAudioEngine();
    player = JustAudioPlayerService(
        playbackEvents: DriftRepositories(db).playbackEvents,
        diagnostics: diagnostics,
        audioEngine: engine,
        isWindows: true,
        fileExists: (_) => true,
        windowsDiagnosticsDelay: const Duration(milliseconds: 20),
        windowsPlaybackProbe: probe,
        windowsProgressRecoveryInterval: const Duration(milliseconds: 5),
        windowsSyntheticProgressGrace: Duration.zero);
    addTearDown(() async {
      await player.dispose();
      await db.close();
    });
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 100; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('Observation did not arrive');
  }

  test(
      'report separates UI progress from actual native positions and both decks',
      () async {
    await open(() async => const [
          WindowsPlaybackSnapshot(4, 0, 120000, true),
          WindowsPlaybackSnapshot(3, 2500, 120000, true)
        ]);
    await player.playTrack(track);
    await until(() =>
        diagnostics.entries
            .where((e) => e.event == DiagnosticEvent.windowsPlaybackObserved)
            .length ==
        2);
    final observed = diagnostics.entries
        .where((e) => e.event == DiagnosticEvent.windowsPlaybackObserved)
        .toList();
    expect(observed.map((e) => e.fields[DiagnosticField.nativePositionMs]),
        [0, 2500]);
    expect(observed.map((e) => e.fields[DiagnosticField.nativePlayerSlot]),
        [0, 1]);
    expect(observed.first.fields[DiagnosticField.opening], false);
    expect(observed.first.fields[DiagnosticField.playerPositionMs],
        greaterThanOrEqualTo(0));
  });
  test('stalled opening is observed before load finishes', () async {
    final finish = Completer<Duration?>();
    await open(() async => const [WindowsPlaybackSnapshot(1, 0, 0, true)]);
    engine.setFilePathHandler = (_, __) => finish.future;
    final loading = player.playTrack(track);
    await until(() => diagnostics.entries
        .any((e) => e.event == DiagnosticEvent.windowsPlaybackObserved));
    final observation = diagnostics.entries
        .lastWhere((e) => e.event == DiagnosticEvent.windowsPlaybackObserved);
    expect(observation.fields[DiagnosticField.opening], true);
    expect(observation.fields[DiagnosticField.nativePlaybackState], 1);
    finish.complete(const Duration(minutes: 2));
    await loading;
  });
  test('empty native list is explicitly recorded', () async {
    await open(() async => []);
    await player.playTrack(track);
    await until(() => diagnostics.entries
        .any((e) => e.event == DiagnosticEvent.windowsPlaybackObserved));
    expect(
        diagnostics.entries.last.fields[DiagnosticField.nativePlayerCount], 0);
  });
  test('closing drains an accepted probe and suppresses late reporting',
      () async {
    final entered = Completer<void>(),
        done = Completer<List<WindowsPlaybackSnapshot>>();
    await open(() {
      entered.complete();
      return done.future;
    });
    await player.playTrack(track);
    await entered.future;
    var closed = false;
    final closing = player.dispose().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    done.complete(const [WindowsPlaybackSnapshot(3, 9999, 120000, true)]);
    await closing;
    expect(
        diagnostics.entries
            .where((e) => e.event == DiagnosticEvent.windowsPlaybackObserved),
        isEmpty);
  });
  test('probe failure is recorded and does not stop playback', () async {
    await open(() async =>
        throw PlatformException(code: '-2147467259', message: 'PRIVATE path'));
    await player.playTrack(track);
    await until(() => diagnostics.entries.any(
        (e) => e.event == DiagnosticEvent.windowsPlaybackObservationFailed));
    expect(diagnostics.entries.last.fields[DiagnosticField.nativeCode],
        -2147467259);
    expect(player.isPlaying, isTrue);
  });
}
