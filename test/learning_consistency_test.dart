import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase database;
  late DriftRepositories repositories;
  late int trackId;
  late Directory directory;
  late File databaseFile;
  final now = DateTime(2026, 10, 12, 20);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('clever_history_');
    databaseFile = File(p.join(directory.path, 'library.sqlite'));
    database = AppDatabase(NativeDatabase(databaseFile));
    repositories = DriftRepositories(database);
    trackId = await repositories.tracks.upsertTrack(
      Track(filePath: '/music/song.mp3', addedAt: now, updatedAt: now),
    );
  });
  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  PlaybackEvent event(PlaybackEventType type, {DateTime? at}) {
    return PlaybackEvent.recording(
      trackId: trackId,
      type: type,
      occurredAt: at ?? now,
      position: const Duration(seconds: 15),
      trackDuration: const Duration(minutes: 3),
      waveMode: WaveMode.balanced,
    );
  }

  test('concurrent history and feedback preserve all counts and preferences',
      () async {
    final older = now.subtract(const Duration(days: 1));
    await repositories.trackUserState.upsertState(TrackUserState(
      trackId: trackId,
      playCount: 7,
      completeCount: 4,
      skipCount: 3,
      rating: 5,
      userScoreBoost: 2.5,
      preferredWaveMode: WaveMode.balanced,
      updatedAt: older,
    ));
    await Future.wait([
      for (var i = 0; i < 20; i++) ...[
        repositories.playbackEvents
            .recordEvent(event(PlaybackEventType.started)),
        repositories.playbackEvents
            .recordEvent(event(PlaybackEventType.completed)),
        repositories.playbackEvents
            .recordEvent(event(PlaybackEventType.skipped)),
      ],
      repositories.trackUserState.toggleFeedback(
        trackId,
        TrackFeedback.like,
        updatedAt: now,
      ),
    ]);

    final state = (await repositories.trackUserState.findByTrackId(trackId))!;
    expect(state.playCount, 27);
    expect(state.completeCount, 24);
    expect(state.skipCount, 23);
    expect(state.isFavorite, isTrue);
    expect(state.isHidden, isFalse);
    expect(state.rating, isNull);
    expect(state.userScoreBoost, 2.5);
    expect(state.preferredWaveMode, WaveMode.balanced);
    expect(state.lastPlayedAt, now);
    expect(state.lastCompletedAt, now);
    expect(state.lastSkippedAt, now);
    expect(await repositories.playbackEvents.recentEvents(), hasLength(60));
  });

  for (final type in [
    PlaybackEventType.started,
    PlaybackEventType.completed,
    PlaybackEventType.skipped,
  ]) {
    test('concurrent retries count $type exactly once', () async {
      final pending = event(type);
      final ids = await Future.wait([
        for (var i = 0; i < 20; i++)
          repositories.playbackEvents.recordEvent(pending),
      ]);
      expect(ids.toSet(), hasLength(1));
      expect(await repositories.playbackEvents.recentEvents(), hasLength(1));
      final state = (await repositories.trackUserState.findByTrackId(trackId))!;
      expect(state.playCount, type == PlaybackEventType.started ? 1 : 0);
      expect(state.completeCount, type == PlaybackEventType.completed ? 1 : 0);
      expect(state.skipCount, type == PlaybackEventType.skipped ? 1 : 0);
    });
  }

  test('distinct events at the same time are both counted', () async {
    final first = event(PlaybackEventType.started);
    final second = event(PlaybackEventType.started);
    expect(first.operationId, isNot(second.operationId));
    await repositories.playbackEvents.recordEvent(first);
    await repositories.playbackEvents.recordEvent(second);
    expect(
        (await repositories.trackUserState.findByTrackId(trackId))?.playCount,
        2);
  });

  for (final hasState in [false, true]) {
    test('counter failure rolls back event and state (existing=$hasState)',
        () async {
      if (hasState) {
        await repositories.trackUserState.upsertState(TrackUserState(
          trackId: trackId,
          isFavorite: true,
          playCount: 7,
          updatedAt: now,
        ));
      }
      final before = await repositories.trackUserState.findByTrackId(trackId);
      final pending = event(PlaybackEventType.started);
      await database.customStatement(
        'CREATE TRIGGER fail_state BEFORE INSERT ON track_user_state '
        "BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END",
      );
      await expectLater(
          repositories.playbackEvents.recordEvent(pending), throwsException);
      expect(await repositories.playbackEvents.recentEvents(), isEmpty);
      expect(await repositories.trackUserState.findByTrackId(trackId), before);

      await database.customStatement('DROP TRIGGER fail_state');
      await repositories.playbackEvents.recordEvent(pending);
      await repositories.playbackEvents.recordEvent(pending);
      expect(
          (await repositories.trackUserState.findByTrackId(trackId))?.playCount,
          hasState ? 8 : 1);
      expect(await repositories.playbackEvents.recentEvents(), hasLength(1));
    });
  }

  test('event failure leaves preferences and counters unchanged', () async {
    await repositories.trackUserState.toggleFeedback(
      trackId,
      TrackFeedback.like,
      updatedAt: now,
    );
    final before = await repositories.trackUserState.findByTrackId(trackId);
    await database.customStatement(
      'CREATE TRIGGER fail_event BEFORE INSERT ON playback_events '
      "BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END",
    );
    await expectLater(
        repositories.playbackEvents
            .recordEvent(event(PlaybackEventType.started)),
        throwsException);
    expect(await repositories.trackUserState.findByTrackId(trackId), before);
    expect(await repositories.playbackEvents.recentEvents(), isEmpty);
  });

  test('a delayed event cannot move timestamps backwards or remove a dislike',
      () async {
    await repositories.trackUserState.toggleFeedback(
      trackId,
      TrackFeedback.dislike,
      updatedAt: now.add(const Duration(hours: 1)),
    );
    for (final type in [
      PlaybackEventType.started,
      PlaybackEventType.completed,
      PlaybackEventType.skipped,
    ]) {
      await repositories.playbackEvents.recordEvent(event(type));
      await repositories.playbackEvents.recordEvent(
        event(type, at: now.subtract(const Duration(days: 2))),
      );
    }
    final state = (await repositories.trackUserState.findByTrackId(trackId))!;
    expect(state.lastPlayedAt, now);
    expect(state.lastCompletedAt, now);
    expect(state.lastSkippedAt, now);
    expect(state.updatedAt, now.add(const Duration(hours: 1)));
    expect(state.isHidden, isTrue);
    expect(state.isFavorite, isFalse);
    expect([state.playCount, state.completeCount, state.skipCount], [2, 2, 2]);
  });

  test('uncounted events and imported history do not change counters',
      () async {
    final pending = event(PlaybackEventType.paused);
    await repositories.playbackEvents.recordEvent(pending);
    await repositories.playbackEvents.recordEvent(pending);
    await repositories.playbackEvents.addEvent(PlaybackEvent(
      trackId: trackId,
      type: PlaybackEventType.started,
      occurredAt: now,
    ));
    expect(await repositories.trackUserState.findByTrackId(trackId), isNull);
    expect(await repositories.playbackEvents.recentEvents(), hasLength(2));
  });

  test('different payload cannot reuse a recorded operation ID', () async {
    final pending = event(PlaybackEventType.started);
    await repositories.playbackEvents.recordEvent(pending);
    await expectLater(
      repositories.playbackEvents.recordEvent(PlaybackEvent(
        operationId: pending.operationId,
        trackId: trackId,
        type: PlaybackEventType.skipped,
        occurredAt: now,
      )),
      throwsStateError,
    );
    final state = (await repositories.trackUserState.findByTrackId(trackId))!;
    expect(state.playCount, 1);
    expect(state.skipCount, 0);
    expect(await repositories.playbackEvents.recentEvents(), hasLength(1));
  });

  test('recording without an operation ID fails before writing', () async {
    expect(
      () => repositories.playbackEvents.recordEvent(PlaybackEvent(
        trackId: trackId,
        type: PlaybackEventType.started,
        occurredAt: now,
      )),
      throwsArgumentError,
    );
    expect(await repositories.playbackEvents.recentEvents(), isEmpty);
    expect(await repositories.trackUserState.findByTrackId(trackId), isNull);
  });

  test('recorded operation is deduplicated after closing and reopening',
      () async {
    final pending = event(PlaybackEventType.started,
        at: now.add(const Duration(microseconds: 123456)));
    final savedId = await repositories.playbackEvents.recordEvent(pending);
    await database.close();
    database = AppDatabase(NativeDatabase(databaseFile));
    repositories = DriftRepositories(database);
    expect(await repositories.playbackEvents.recordEvent(pending), savedId);
    expect(await repositories.playbackEvents.recentEvents(), hasLength(1));
    expect(
        (await repositories.trackUserState.findByTrackId(trackId))?.playCount,
        1);
  });
}
