import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/library/library_track_list.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Explicit benchmark, outside the regression suite. Uses only own temporary
/// file-backed databases and already prepared synthetic metadata. Not a release
/// GUI or full import benchmark: no hashing, tags, covers, audio or frame render.
void main() {
  test('compare database import with live library consumers', () async {
    final results = <Map<String, Object>>[];
    for (final batchSize in [1, 16, 64]) {
      results.add(await _measure(batchSize));
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(results));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<Map<String, Object>> _measure(int batchSize) async {
  const seedCount = 1000, importCount = 1000;
  final root = await Directory.systemTemp.createTemp('cmp_db_benchmark_');
  final database = AppDatabase(NativeDatabase.createInBackground(
      File(p.join(root.path, 'library.sqlite'))));
  final repositories = DriftRepositories(database);
  final importer = repositories.tracks as TrackImportRepository;
  final subscriptions = <StreamSubscription<Object?>>[];
  final feedbackReads = <Future<void>>[];
  final now = DateTime(2026);
  Track track(int i) => Track(
      filePath: '/synthetic/$i.mp3',
      title: 'Track ${i.toString().padLeft(5, '0')}',
      artist: 'Artist ${i % 20}',
      album: 'Album ${i % 100}',
      genre: 'Test',
      stableId: 'signature-$i',
      contentHash: 'file-sha256-v1:3:${i.toRadixString(16).padLeft(64, '0')}',
      duration: const Duration(minutes: 3),
      fileSizeBytes: 5000000,
      metadataSource: MetadataSource.embeddedTags,
      addedAt: now,
      updatedAt: now);
  try {
    for (var start = 0; start < seedCount; start += 64) {
      final end = (start + 64).clamp(0, seedCount);
      await importer
          .upsertScannedTracks([for (var i = start; i < end; i++) track(i)]);
    }
    final activeReady = Completer<void>(), countReady = Completer<void>();
    final activeDone = Completer<void>(), countDone = Completer<void>();
    Completer<void>? visibleCommit, indexedCommit;
    var targetCount = seedCount;
    var libraryNotifications = 0, indexedNotifications = 0;
    subscriptions.add(
        repositories.tracks.watchAllTracks(includeMissing: true).listen((rows) {
      libraryNotifications++;
      final visible = buildVisibleLibraryTracks(
          tracks: rows,
          searchQuery: '',
          showMissingTracks: false,
          sortOption: LibraryTrackSortOption.title);
      expect(visible, hasLength(rows.length));
      // Mimics the feedback query recreated when the visible ID set grows.
      feedbackReads.add(repositories.trackUserState
          .findByTrackIds(rows.map((track) => track.id!))
          .then((_) {}));
      if (!activeReady.isCompleted) activeReady.complete();
      if (rows.length == targetCount && visibleCommit?.isCompleted == false) {
        visibleCommit!.complete();
      }
      if (rows.length == seedCount + importCount && !activeDone.isCompleted) {
        activeDone.complete();
      }
    }));
    final countStream = batchSize == 1
        ? repositories.tracks
            .watchAllTracks(includeMissing: true, includeDisabledFolders: true)
            .map((rows) => rows.length)
        : (repositories.tracks as TrackLibraryCountRepository)
            .watchIndexedTrackCount();
    subscriptions.add(countStream.listen((count) {
      indexedNotifications++;
      if (!countReady.isCompleted) countReady.complete();
      if (count == targetCount && indexedCommit?.isCompleted == false) {
        indexedCommit!.complete();
      }
      if (count == seedCount + importCount && !countDone.isCompleted) {
        countDone.complete();
      }
    }));
    await Future.wait([activeReady.future, countReady.future]);
    await Future.wait(feedbackReads);
    libraryNotifications = indexedNotifications = 0;
    final timer = Stopwatch()..start();
    for (var start = seedCount;
        start < seedCount + importCount;
        start += batchSize) {
      final end = (start + batchSize).clamp(0, seedCount + importCount);
      final prepared = <Track>[];
      for (var i = start; i < end; i++) {
        prepared.add(track(i));
        // A real scanner awaits file IO between prepared tracks. Let Drift's
        // invalidation timers and consumers run at the same boundary here.
        await Future<void>.delayed(Duration.zero);
      }
      targetCount = end;
      visibleCommit = Completer<void>();
      indexedCommit = Completer<void>();
      if (batchSize == 1) {
        await repositories.tracks.upsertTrack(prepared.single);
      } else {
        await importer.upsertScannedTracks(prepared);
      }
      // Observe each visible commit explicitly. A dense write loop otherwise
      // lets Drift coalesce almost all stream events, unlike an interactive
      // import that repeatedly returns to the UI while reading real files.
      await Future.wait([visibleCommit.future, indexedCommit.future]);
      await Future.wait(feedbackReads);
    }
    await Future.wait([activeDone.future, countDone.future]);
    await Future.wait(feedbackReads);
    timer.stop();
    expect(
        await (repositories.tracks as TrackLibraryCountRepository)
            .watchIndexedTrackCount()
            .first,
        seedCount + importCount);
    return {
      'mode': batchSize == 1
          ? 'legacy-single-plus-full-indexed-list'
          : 'batch-plus-count',
      'batchSize': batchSize,
      'eventLoopYieldBetweenTracks': true,
      'awaitConsumersAfterCommit': true,
      'seedCount': seedCount,
      'importCount': importCount,
      'elapsedMs': timer.elapsedMicroseconds / 1000,
      'libraryNotifications': libraryNotifications,
      'indexedNotifications': indexedNotifications,
    };
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await database.close();
    await root.delete(recursive: true);
  }
}
