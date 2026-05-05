import 'dart:async';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/player/player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/queue/playback_queue_service.dart';
import 'package:clever_music_player/src/queue/queue_state.dart';
import 'package:clever_music_player/src/recommendation/recommendation_service.dart';
import 'package:clever_music_player/src/library/library_management_service.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selection weights favor negative scores closer to zero', () {
    final now = DateTime(2026);
    final weights = selectionWeightsForRecommendations([
      _recommendationResult(id: 1, title: 'Minus One', score: -1, now: now),
      _recommendationResult(id: 2, title: 'Minus Seven', score: -7, now: now),
      _recommendationResult(
        id: 3,
        title: 'Minus Thirty Five',
        score: -35,
        now: now,
      ),
    ]);

    expect(weights[0], greaterThan(weights[1]));
    expect(weights[1], greaterThan(weights[2]));
  });

  test('selection weights preserve ordering for nearby negative scores', () {
    final now = DateTime(2026);
    final weights = selectionWeightsForRecommendations([
      _recommendationResult(id: 1, title: 'Minus Seven', score: -7, now: now),
      _recommendationResult(id: 2, title: 'Minus Eight', score: -8, now: now),
      _recommendationResult(
        id: 3,
        title: 'Minus Thirty Five',
        score: -35,
        now: now,
      ),
    ]);

    expect(weights[0], greaterThanOrEqualTo(weights[1]));
    expect(weights[1], greaterThan(weights[2]));
  });

  test('weighted selection pool excludes negative scores when positives exist',
      () {
    final now = DateTime(2026);
    final pool = buildWeightedSelectionPool([
      _recommendationResult(id: 1, title: 'Positive', score: 9, now: now),
      _recommendationResult(id: 2, title: 'Below One', score: 0.5, now: now),
      _recommendationResult(id: 3, title: 'Negative', score: -7, now: now),
      _recommendationResult(id: 4, title: 'One', score: 1, now: now),
    ]);

    expect(pool.map((result) => result.track.id), [1, 4]);
  });

  test('weighted selection pool uses negative cutoff when no positives exist',
      () {
    final now = DateTime(2026);
    final pool = buildWeightedSelectionPool([
      _recommendationResult(id: 1, title: 'Minus Five', score: -5, now: now),
      _recommendationResult(
        id: 2,
        title: 'Minus Thirteen',
        score: -13,
        now: now,
      ),
      _recommendationResult(
        id: 3,
        title: 'Minus Fifteen',
        score: -15,
        now: now,
      ),
      _recommendationResult(
        id: 4,
        title: 'Minus Twenty Three',
        score: -23,
        now: now,
      ),
    ]);

    expect(pool.map((result) => result.track.id), [1, 2, 3]);
  });

  test('negative cutoff excludes distant scores', () {
    final now = DateTime(2026);
    final pool = buildWeightedSelectionPool([
      _recommendationResult(id: 1, title: 'Minus Seven', score: -7, now: now),
      _recommendationResult(id: 2, title: 'Minus Eight', score: -8, now: now),
      _recommendationResult(
        id: 3,
        title: 'Minus Thirty Five',
        score: -35,
        now: now,
      ),
    ]);

    expect(pool.map((result) => result.track.id), [1, 2]);
  });

  test('negative cutoff keeps all scores within tolerance', () {
    final now = DateTime(2026);
    final pool = buildWeightedSelectionPool([
      _recommendationResult(id: 1, title: 'Minus Twenty', score: -20, now: now),
      _recommendationResult(
        id: 2,
        title: 'Minus Twenty Five',
        score: -25,
        now: now,
      ),
      _recommendationResult(
        id: 3,
        title: 'Minus Twenty Eight',
        score: -28,
        now: now,
      ),
    ]);

    expect(pool.map((result) => result.track.id), [1, 2, 3]);
  });

  test('negative cutoff result reports when cutoff is active', () {
    final now = DateTime(2026);
    final result = buildWeightedSelectionPoolResult([
      _recommendationResult(id: 1, title: 'Minus Seven', score: -7, now: now),
      _recommendationResult(id: 2, title: 'Minus Eight', score: -8, now: now),
      _recommendationResult(
        id: 3,
        title: 'Minus Thirty Five',
        score: -35,
        now: now,
      ),
    ]);

    expect(result.candidates.map((item) => item.track.id), [1, 2]);
    expect(
      result.message,
      'Negative score cutoff active: showing candidates within 10.0 points '
      'of best available score.',
    );
  });

  test('selection weights prefer higher scores within effective pool', () {
    final now = DateTime(2026);
    final pool = buildWeightedSelectionPool([
      _recommendationResult(id: 1, title: 'Minus Five', score: -5, now: now),
      _recommendationResult(
        id: 2,
        title: 'Minus Thirteen',
        score: -13,
        now: now,
      ),
      _recommendationResult(
        id: 3,
        title: 'Minus Fifteen',
        score: -15,
        now: now,
      ),
      _recommendationResult(
        id: 4,
        title: 'Minus Twenty Three',
        score: -23,
        now: now,
      ),
    ]);
    final weights = selectionWeightsForRecommendations(pool);

    expect(pool.map((result) => result.track.id), [1, 2, 3]);
    expect(weights[0], greaterThan(weights[1]));
    expect(weights[1], greaterThanOrEqualTo(weights[2]));
  });

  test('playSmartNext selects and plays a recommended track', () async {
    final now = DateTime(2026);
    final recent = _track(id: 1, title: 'Recent', artist: 'A', now: now);
    final fresh = _track(id: 2, title: 'Fresh', artist: 'B', now: now);
    final tracks = _FakeTrackRepository([recent, fresh]);
    final events = _FakePlaybackEventRepository([
      PlaybackEvent(
        trackId: 1,
        type: PlaybackEventType.started,
        occurredAt: now,
      ),
    ]);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      events: events,
      now: now,
    );

    await queue.playSmartNext();

    expect(queue.state.isWaveEnabled, isTrue);
    expect(queue.state.isWaveCurrentSource, isTrue);
    expect(queue.state.lastRecommendationResult?.track.id, 2);
    expect(player.playedTracks.single.id, 2);

    await queue.dispose();
    await player.dispose();
  });

  test('isWaveCurrentSource is true only for Smart Wave playback', () async {
    final now = DateTime(2026);
    final single = _track(id: 1, title: 'Single', now: now);
    final playlistTrack = _track(id: 2, title: 'Playlist', now: now);
    final queued = _track(id: 3, title: 'Queued', now: now);
    final smart = _track(id: 4, title: 'Smart', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([single, playlistTrack, queued, smart]),
      now: now,
    );

    await queue.playTrackManually(single);

    expect(queue.state.activeSource, PlaybackSource.singleTrack);
    expect(queue.state.isWaveCurrentSource, isFalse);

    await _startPlaylist(
      queue,
      [playlistTrack],
      startTrackId: playlistTrack.id!,
      now: now,
    );

    expect(queue.state.activeSource, PlaybackSource.playlist);
    expect(queue.state.isWaveCurrentSource, isFalse);

    await queue.addToQueue(queued);
    await queue.next();

    expect(queue.state.activeSource, PlaybackSource.manualQueue);
    expect(queue.state.isWaveCurrentSource, isFalse);

    await queue.playSmartNext();

    expect(queue.state.activeSource, PlaybackSource.wave);
    expect(queue.state.isWaveCurrentSource, isTrue);

    await queue.dispose();
    await player.dispose();
  });

  test('addToQueue adds a track without starting playback', () async {
    final now = DateTime(2026);
    final track = _track(id: 1, title: 'Queued', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([track]),
      now: now,
    );

    await queue.addToQueue(track);

    expect(queue.state.manualQueue.map((track) => track.id), [1]);
    expect(player.playedTracks, isEmpty);

    await queue.dispose();
    await player.dispose();
  });

  test('missing track cannot be queued', () async {
    final now = DateTime(2026);
    final missing = _track(id: 1, title: 'Missing', now: now, isMissing: true);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([missing]),
      now: now,
    );

    await queue.addToQueue(missing);

    expect(queue.state.manualQueue, isEmpty);
    expect(queue.state.lastError, contains('Missing tracks'));
    expect(player.playedTracks, isEmpty);

    await queue.dispose();
    await player.dispose();
  });

  test('manual queue preserves order', () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final third = _track(id: 3, title: 'Third', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second, third]),
      now: now,
    );

    await queue.addToQueue(first);
    await queue.addToQueue(second);
    await queue.addToQueue(third);

    expect(queue.state.manualQueue.map((track) => track.id), [1, 2, 3]);

    await queue.dispose();
    await player.dispose();
  });

  test('next plays first manual queued track before Smart Wave', () async {
    final now = DateTime(2026);
    final current = _track(id: 1, title: 'Current', artist: 'A', now: now);
    final queued = _track(id: 2, title: 'Queued', artist: 'B', now: now);
    final smart = _track(id: 3, title: 'Smart', artist: 'C', now: now);
    final events = _FakePlaybackEventRepository();
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([current, queued, smart]),
      events: events,
      now: now,
    );

    queue.enableWave();
    await queue.addToQueue(queued);
    player.emit(
      PlayerState(
        currentTrack: current,
        isPlaying: true,
        position: const Duration(seconds: 12),
        duration: current.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.next();

    expect(player.playedTracks.single.id, 2);
    expect(queue.state.manualQueue, isEmpty);
    expect(queue.state.lastRecommendationResult, isNull);
    expect(events.events.single.type, PlaybackEventType.skipped);

    await queue.dispose();
    await player.dispose();
  });

  test('next plays manualQueue.first and removes exactly one item', () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second]),
      now: now,
    );

    await queue.addToQueue(first);
    await queue.addToQueue(second);
    await queue.next();

    expect(player.playedTracks.map((track) => track.id), [1]);
    expect(queue.state.manualQueue.map((track) => track.id), [2]);

    await queue.dispose();
    await player.dispose();
  });

  test('completion plays first manual queued track before Smart Wave',
      () async {
    final now = DateTime(2026);
    final completed = _track(id: 1, title: 'Completed', artist: 'A', now: now);
    final queued = _track(id: 2, title: 'Queued', artist: 'B', now: now);
    final smart = _track(id: 3, title: 'Smart', artist: 'C', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([completed, queued, smart]),
      now: now,
    );

    queue.enableWave();
    await queue.addToQueue(queued);
    player.emit(
      PlayerState(
        currentTrack: completed,
        isPlaying: false,
        position: completed.duration!,
        duration: completed.duration,
        status: PlayerPlaybackStatus.completed,
      ),
    );

    await _waitUntil(() => player.playedTracks.isNotEmpty);

    expect(player.playedTracks.single.id, 2);
    expect(queue.state.manualQueue, isEmpty);
    expect(queue.state.lastRecommendationResult, isNull);

    await queue.dispose();
    await player.dispose();
  });

  test('completion plays manualQueue.first and removes exactly one item',
      () async {
    final now = DateTime(2026);
    final completed = _track(id: 1, title: 'Completed', now: now);
    final first = _track(id: 2, title: 'First', now: now);
    final second = _track(id: 3, title: 'Second', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([completed, first, second]),
      now: now,
    );

    await queue.addToQueue(first);
    await queue.addToQueue(second);
    player.emit(
      PlayerState(
        currentTrack: completed,
        isPlaying: false,
        position: completed.duration!,
        duration: completed.duration,
        status: PlayerPlaybackStatus.completed,
      ),
    );

    await _waitUntil(() => player.playedTracks.isNotEmpty);

    expect(player.playedTracks.map((track) => track.id), [2]);
    expect(queue.state.manualQueue.map((track) => track.id), [3]);

    await queue.dispose();
    await player.dispose();
  });

  test('playing playlist track sets playlist context at selected index',
      () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final missing = _track(id: 2, title: 'Missing', isMissing: true, now: now);
    final second = _track(id: 3, title: 'Second', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, missing, second]),
      now: now,
    );

    await queue.playPlaylist(
      playlistId: 42,
      playlistName: 'Road Mix',
      entries: [
        _playlistEntry(first, playlistId: 42, position: 0, now: now),
        _playlistEntry(
          missing,
          playlistId: 42,
          position: 1,
          now: now,
          unavailableReason: 'Missing',
        ),
        _playlistEntry(second, playlistId: 42, position: 2, now: now),
      ],
      startTrackId: 3,
    );

    expect(player.playedTracks.single.id, 3);
    expect(queue.state.activeSource, PlaybackSource.playlist);
    expect(queue.state.repeatMode, PlaybackRepeatMode.none);
    expect(queue.state.playbackContext.source, PlaybackSource.playlist);
    expect(queue.state.playbackContext.playlistId, 42);
    expect(queue.state.playbackContext.playlistName, 'Road Mix');
    expect(queue.state.playbackContext.currentIndex, 1);
    expect(queue.state.playbackContext.tracks.map((track) => track.id), [
      1,
      3,
    ]);

    await queue.dispose();
    await player.dispose();
  });

  test('next from playlist plays next playlist track', () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second]),
      now: now,
    );

    await _startPlaylist(queue, [first, second], startTrackId: 1, now: now);
    player.playedTracks.clear();

    await queue.next();

    expect(player.playedTracks.single.id, 2);
    expect(queue.state.playbackContext.currentIndex, 1);

    await queue.dispose();
    await player.dispose();
  });

  test('playlist playback follows reordered entry positions', () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final third = _track(id: 3, title: 'Third', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second, third]),
      now: now,
    );

    await queue.playPlaylist(
      playlistId: 42,
      playlistName: 'Road Mix',
      entries: [
        _playlistEntry(first, playlistId: 42, position: 1, now: now),
        _playlistEntry(second, playlistId: 42, position: 0, now: now),
        _playlistEntry(third, playlistId: 42, position: 2, now: now),
      ],
      startTrackId: 2,
    );
    player.playedTracks.clear();

    await queue.next();

    expect(queue.state.playbackContext.tracks.map((track) => track.id), [
      2,
      1,
      3,
    ]);
    expect(player.playedTracks.single.id, 1);
    expect(queue.state.playbackContext.currentIndex, 1);

    await queue.dispose();
    await player.dispose();
  });

  test('refreshing active playlist order keeps current track and updates index',
      () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final third = _track(id: 3, title: 'Third', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second, third]),
      now: now,
    );

    await _startPlaylist(
      queue,
      [first, second, third],
      startTrackId: 2,
      now: now,
    );
    player.playedTracks.clear();

    await queue.refreshPlaylistContextOrder(
      playlistId: 42,
      entries: [
        _playlistEntry(second, playlistId: 42, position: 0, now: now),
        _playlistEntry(third, playlistId: 42, position: 1, now: now),
        _playlistEntry(first, playlistId: 42, position: 2, now: now),
      ],
    );

    expect(player.playedTracks, isEmpty);
    expect(queue.state.currentTrack?.id, 2);
    expect(queue.state.playbackContext.currentIndex, 0);
    expect(queue.state.playbackContext.tracks.map((track) => track.id), [
      2,
      3,
      1,
    ]);

    await queue.next();

    expect(player.playedTracks.single.id, 3);

    await queue.dispose();
    await player.dispose();
  });

  test('natural completion from playlist plays next playlist track', () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second]),
      now: now,
    );

    await _startPlaylist(queue, [first, second], startTrackId: 1, now: now);
    player.playedTracks.clear();
    player.emit(_completedState(first));
    await _waitUntil(() => player.playedTracks.isNotEmpty);

    expect(player.playedTracks.single.id, 2);
    expect(queue.state.playbackContext.currentIndex, 1);

    await queue.dispose();
    await player.dispose();
  });

  test('manual queue has priority and playlist continues after it is consumed',
      () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final queued = _track(id: 3, title: 'Queued', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second, queued]),
      now: now,
    );

    await _startPlaylist(queue, [first, second], startTrackId: 1, now: now);
    await queue.addToQueue(queued);
    player.playedTracks.clear();

    player.emit(_completedState(first));
    await _waitUntil(() => player.playedTracks.length == 1);
    player.emit(_completedState(queued));
    await _waitUntil(() => player.playedTracks.length == 2);

    expect(player.playedTracks.map((track) => track.id), [3, 2]);
    expect(queue.state.manualQueue, isEmpty);
    expect(queue.state.playbackContext.currentIndex, 1);

    await queue.dispose();
    await player.dispose();
  });

  test('natural completion at playlist end falls back to Wave when disabled',
      () async {
    final now = DateTime(2026);
    final playlistTrack =
        _track(id: 1, title: 'Playlist', artist: 'A', now: now);
    final smart = _track(id: 2, title: 'Smart', artist: 'B', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([playlistTrack, smart]),
      now: now,
    );

    await _startPlaylist(
      queue,
      [playlistTrack],
      startTrackId: 1,
      now: now,
    );
    player.playedTracks.clear();
    player.emit(_completedState(playlistTrack));
    await _waitUntil(() => player.playedTracks.isNotEmpty);

    expect(player.playedTracks.single.id, 2);
    expect(queue.state.playbackContext.source, PlaybackSource.none);
    expect(queue.state.lastRecommendationResult?.track.id, 2);
    expect(queue.state.isWaveEnabled, isTrue);

    await queue.dispose();
    await player.dispose();
  });

  test('manual next at playlist end falls back to Wave when disabled',
      () async {
    final now = DateTime(2026);
    final playlistTrack =
        _track(id: 1, title: 'Playlist', artist: 'A', now: now);
    final smart = _track(id: 2, title: 'Smart', artist: 'B', now: now);
    final events = _FakePlaybackEventRepository();
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([playlistTrack, smart]),
      events: events,
      now: now,
    );

    await _startPlaylist(
      queue,
      [playlistTrack],
      startTrackId: 1,
      now: now,
    );
    player.emit(
      _playingState(
        playlistTrack,
        position: const Duration(seconds: 42),
      ),
    );
    player.playedTracks.clear();

    await queue.next();

    expect(player.playedTracks.single.id, 2);
    expect(queue.state.playbackContext.source, PlaybackSource.none);
    expect(queue.state.lastRecommendationResult?.track.id, 2);
    expect(queue.state.isWaveEnabled, isTrue);
    expect(events.events.single.type, PlaybackEventType.skipped);

    await queue.dispose();
    await player.dispose();
  });

  test('manual queue still has priority over playlist end fallback', () async {
    final now = DateTime(2026);
    final playlistTrack =
        _track(id: 1, title: 'Playlist', artist: 'A', now: now);
    final queued = _track(id: 2, title: 'Queued', artist: 'B', now: now);
    final smart = _track(id: 3, title: 'Smart', artist: 'C', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([playlistTrack, queued, smart]),
      now: now,
    );

    await _startPlaylist(
      queue,
      [playlistTrack],
      startTrackId: 1,
      now: now,
    );
    await queue.addToQueue(queued);
    player.playedTracks.clear();

    player.emit(_completedState(playlistTrack));
    await _waitUntil(() => player.playedTracks.length == 1);
    player.emit(_completedState(queued));
    await _waitUntil(() => player.playedTracks.length == 2);

    expect(player.playedTracks.first.id, 2);
    expect(player.playedTracks, hasLength(2));
    expect(queue.state.manualQueue, isEmpty);
    expect(queue.state.playbackContext.source, PlaybackSource.none);
    expect(queue.state.lastRecommendationResult?.track.id,
        player.playedTracks.last.id);
    expect(queue.state.isWaveEnabled, isTrue);

    await queue.dispose();
    await player.dispose();
  });

  test('repeat playlist loops from last to first', () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second]),
      now: now,
    );

    await _startPlaylist(queue, [first, second], startTrackId: 2, now: now);
    queue.setRepeatMode(PlaybackRepeatMode.playlist);
    player.playedTracks.clear();
    player.emit(_completedState(second));
    await _waitUntil(() => player.playedTracks.isNotEmpty);

    expect(player.playedTracks.single.id, 1);
    expect(queue.state.playbackContext.currentIndex, 0);
    expect(queue.state.lastRecommendationResult, isNull);
    expect(queue.state.isWaveEnabled, isFalse);

    await queue.dispose();
    await player.dispose();
  });

  test('repeat track repeats last playlist track without Wave fallback',
      () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second]),
      now: now,
    );

    await _startPlaylist(queue, [first, second], startTrackId: 2, now: now);
    queue.setRepeatMode(PlaybackRepeatMode.track);
    player.playedTracks.clear();
    player.emit(_completedState(second));
    await _waitUntil(() => player.playedTracks.isNotEmpty);

    expect(player.playedTracks.single.id, 2);
    expect(queue.state.playbackContext.currentIndex, 1);
    expect(queue.state.lastRecommendationResult, isNull);
    expect(queue.state.isWaveEnabled, isFalse);

    await queue.dispose();
    await player.dispose();
  });

  test('repeat track plus manual next advances to next playlist track',
      () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second]),
      now: now,
    );

    await _startPlaylist(queue, [first, second], startTrackId: 1, now: now);
    queue.setRepeatMode(PlaybackRepeatMode.track);
    player.playedTracks.clear();

    await queue.next();

    expect(player.playedTracks.single.id, 2);
    expect(queue.state.playbackContext.currentIndex, 1);

    await queue.dispose();
    await player.dispose();
  });

  test('previous in playlist after threshold seeks to start', () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second]),
      now: now,
    );

    await _startPlaylist(queue, [first, second], startTrackId: 2, now: now);
    player.emit(
      _playingState(second, position: const Duration(seconds: 6)),
    );
    player.playedTracks.clear();

    await queue.previous();

    expect(player.playedTracks, isEmpty);
    expect(player.seekCalls, [Duration.zero]);
    expect(player.state.position, Duration.zero);
    expect(queue.state.playbackContext.currentIndex, 1);

    await queue.dispose();
    await player.dispose();
  });

  test('previous in playlist before threshold plays previous track', () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second]),
      now: now,
    );

    await _startPlaylist(queue, [first, second], startTrackId: 2, now: now);
    player.emit(
      _playingState(second, position: const Duration(seconds: 5)),
    );
    player.playedTracks.clear();

    await queue.previous();

    expect(player.playedTracks.single.id, 1);
    expect(player.seekCalls, isEmpty);
    expect(queue.state.playbackContext.currentIndex, 0);

    await queue.dispose();
    await player.dispose();
  });

  test(
      'previous at first track with repeat playlist before threshold plays last',
      () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second]),
      now: now,
    );

    await _startPlaylist(queue, [first, second], startTrackId: 1, now: now);
    queue.setRepeatMode(PlaybackRepeatMode.playlist);
    player.emit(
      _playingState(first, position: const Duration(seconds: 5)),
    );
    player.playedTracks.clear();

    await queue.previous();

    expect(player.playedTracks.single.id, 2);
    expect(player.seekCalls, isEmpty);
    expect(queue.state.playbackContext.currentIndex, 1);

    await queue.dispose();
    await player.dispose();
  });

  test('previous outside playlist after threshold seeks to start', () async {
    final now = DateTime(2026);
    final current = _track(id: 1, title: 'Current', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([current]),
      now: now,
    );
    await queue.playTrackManually(current);
    player.emit(
      _playingState(current, position: const Duration(seconds: 6)),
    );
    player.playedTracks.clear();

    await queue.previous();

    expect(player.playedTracks, isEmpty);
    expect(player.seekCalls, [Duration.zero]);
    expect(player.state.position, Duration.zero);
    expect(queue.state.playbackContext.source, PlaybackSource.none);

    await queue.dispose();
    await player.dispose();
  });

  test('previous outside playlist before threshold is no-op', () async {
    final now = DateTime(2026);
    final current = _track(id: 1, title: 'Current', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([current]),
      now: now,
    );
    await queue.playTrackManually(current);
    player.emit(
      _playingState(current, position: const Duration(seconds: 5)),
    );
    player.playedTracks.clear();

    await queue.previous();

    expect(player.playedTracks, isEmpty);
    expect(player.seekCalls, isEmpty);
    expect(queue.state.playbackContext.source, PlaybackSource.none);

    await queue.dispose();
    await player.dispose();
  });

  test('previous with no current track is no-op', () async {
    final now = DateTime(2026);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: const _FakeTrackRepository([]),
      now: now,
    );

    await queue.previous();

    expect(player.playedTracks, isEmpty);
    expect(player.seekCalls, isEmpty);
    expect(queue.state.currentTrack, isNull);

    await queue.dispose();
    await player.dispose();
  });

  test('missing playlist track cannot start playlist playback', () async {
    final now = DateTime(2026);
    final missing = _track(id: 1, title: 'Missing', isMissing: true, now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([missing]),
      now: now,
    );

    await queue.playPlaylist(
      playlistId: 42,
      playlistName: 'Broken',
      entries: [
        _playlistEntry(
          missing,
          playlistId: 42,
          position: 0,
          now: now,
          unavailableReason: 'Missing',
        ),
      ],
      startTrackId: 1,
    );

    expect(player.playedTracks, isEmpty);
    expect(queue.state.playbackContext.source, PlaybackSource.none);
    expect(queue.state.lastError, contains('No playable tracks'));

    await queue.dispose();
    await player.dispose();
  });

  test('duplicate completed events do not consume two queued items', () async {
    final now = DateTime(2026);
    final completed = _track(id: 1, title: 'Completed', now: now);
    final first = _track(id: 2, title: 'First', now: now);
    final second = _track(id: 3, title: 'Second', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([completed, first, second]),
      now: now,
    );

    await queue.addToQueue(first);
    await queue.addToQueue(second);
    final completedState = PlayerState(
      currentTrack: completed,
      isPlaying: false,
      position: completed.duration!,
      duration: completed.duration,
      status: PlayerPlaybackStatus.completed,
    );

    player.emit(completedState);
    await _waitUntil(() => player.playedTracks.length == 1);
    player.emit(completedState);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(player.playedTracks.map((track) => track.id), [2]);
    expect(queue.state.manualQueue.map((track) => track.id), [3]);

    await queue.dispose();
    await player.dispose();
  });

  test('duplicate completed events during transition do not double play',
      () async {
    final now = DateTime(2026);
    final completed = _track(id: 1, title: 'Completed', now: now);
    final first = _track(id: 2, title: 'First', now: now);
    final second = _track(id: 3, title: 'Second', now: now);
    final playStarted = Completer<void>();
    final player = _FakePlayerService()..playTrackBlocker = playStarted;
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([completed, first, second]),
      now: now,
    );

    await queue.addToQueue(first);
    await queue.addToQueue(second);
    final completedState = PlayerState(
      currentTrack: completed,
      isPlaying: false,
      position: completed.duration!,
      duration: completed.duration,
      status: PlayerPlaybackStatus.completed,
    );

    player.emit(completedState);
    await _waitUntil(() => player.playTrackCalls.length == 1);
    player.emit(completedState);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(player.playTrackCalls.map((track) => track.id), [2]);
    expect(queue.state.manualQueue.map((track) => track.id), [3]);

    playStarted.complete();
    await _waitUntil(() => player.playedTracks.length == 1);

    expect(player.playedTracks.map((track) => track.id), [2]);
    expect(queue.state.isChoosingNext, isFalse);

    await queue.dispose();
    await player.dispose();
  });

  test('completion guard resets after the same track starts again', () async {
    final now = DateTime(2026);
    final repeated = _track(id: 1, title: 'Repeated', now: now);
    final firstQueued = _track(id: 2, title: 'First queued', now: now);
    final secondQueued = _track(id: 3, title: 'Second queued', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([repeated, firstQueued, secondQueued]),
      now: now,
    );

    await queue.addToQueue(firstQueued);
    player.emit(_completedState(repeated));
    await _waitUntil(() => player.playedTracks.length == 1);

    await queue.addToQueue(secondQueued);
    player.emit(
      PlayerState(
        currentTrack: repeated,
        isPlaying: true,
        position: const Duration(seconds: 1),
        duration: repeated.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );
    player.emit(_completedState(repeated));
    await _waitUntil(() => player.playedTracks.length == 2);

    expect(player.playedTracks.map((track) => track.id), [2, 3]);
    expect(queue.state.manualQueue, isEmpty);

    await queue.dispose();
    await player.dispose();
  });

  test('manual queue order is preserved over multiple completions', () async {
    final now = DateTime(2026);
    final initial = _track(id: 1, title: 'Initial', now: now);
    final first = _track(id: 2, title: 'First', now: now);
    final second = _track(id: 3, title: 'Second', now: now);
    final third = _track(id: 4, title: 'Third', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([initial, first, second, third]),
      now: now,
    );

    await queue.addToQueue(first);
    await queue.addToQueue(second);
    await queue.addToQueue(third);

    player.emit(_completedState(initial));
    await _waitUntil(() => player.playedTracks.length == 1);
    player.emit(_completedState(first));
    await _waitUntil(() => player.playedTracks.length == 2);
    player.emit(_completedState(second));
    await _waitUntil(() => player.playedTracks.length == 3);

    expect(player.playedTracks.map((track) => track.id), [2, 3, 4]);
    expect(queue.state.manualQueue, isEmpty);

    await queue.dispose();
    await player.dispose();
  });

  test('clearQueue empties manual queue', () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second]),
      now: now,
    );

    await queue.addToQueue(first);
    await queue.addToQueue(second);
    queue.clearQueue();

    expect(queue.state.manualQueue, isEmpty);

    await queue.dispose();
    await player.dispose();
  });

  test('removeQueuedTrack removes only that item', () async {
    final now = DateTime(2026);
    final first = _track(id: 1, title: 'First', now: now);
    final second = _track(id: 2, title: 'Second', now: now);
    final third = _track(id: 3, title: 'Third', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([first, second, third]),
      now: now,
    );

    await queue.addToQueue(first);
    await queue.addToQueue(second);
    await queue.addToQueue(third);
    queue.removeQueuedTrack(1);

    expect(queue.state.manualQueue.map((track) => track.id), [1, 3]);

    await queue.dispose();
    await player.dispose();
  });

  test('weighted selection can choose a non-top candidate', () async {
    final now = DateTime(2026);
    final top = _track(id: 1, title: 'Top', artist: 'A', now: now);
    final second = _track(id: 2, title: 'Second', artist: 'B', now: now);
    final tracks = _FakeTrackRepository([top, second]);
    final userState = _FakeTrackUserStateRepository({
      1: TrackUserState(
        trackId: 1,
        isFavorite: true,
        updatedAt: now,
      ),
    });
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      userState: userState,
      now: now,
      randomDouble: () => 0.99,
    );

    await queue.playSmartNext();

    expect(queue.state.recommendationCandidates.first.track.id, 1);
    expect(queue.state.lastRecommendationResult?.track.id, 2);
    expect(player.playedTracks.single.id, 2);

    await queue.dispose();
    await player.dispose();
  });

  test('weighted selection ignores negative scores when positives exist',
      () async {
    final now = DateTime(2026);
    final positiveOne =
        _track(id: 1, title: 'Positive One', artist: 'A', now: now);
    final positiveTwo =
        _track(id: 2, title: 'Positive Two', artist: 'B', now: now);
    final negative = _track(id: 3, title: 'Negative', artist: 'C', now: now);
    final tracks = _FakeTrackRepository([positiveOne, positiveTwo, negative]);
    final userState = _FakeTrackUserStateRepository({
      3: TrackUserState(
        trackId: 3,
        playCount: 5,
        userScoreBoost: -30,
        updatedAt: now,
      ),
    });
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      userState: userState,
      now: now,
      randomDouble: () => 0.99,
    );

    await queue.playSmartNext();

    expect(queue.state.lastRecommendationResult?.track.id, isNot(3));
    expect(
      queue.state.recommendationCandidates.map((result) => result.track.id),
      isNot(contains(3)),
    );
    expect(
      queue.state.recommendationCandidates.every(
        (result) => result.score >= 1,
      ),
      isTrue,
    );

    await queue.dispose();
    await player.dispose();
  });

  test('negative cutoff updates debug candidate pool', () async {
    final now = DateTime(2026);
    final minusFive = _track(id: 1, title: 'Minus Five', now: now);
    final minusThirteen = _track(id: 2, title: 'Minus Thirteen', now: now);
    final minusFifteen = _track(id: 3, title: 'Minus Fifteen', now: now);
    final minusTwentyThree =
        _track(id: 4, title: 'Minus Twenty Three', now: now);
    final tracks = _FakeTrackRepository([
      minusFive,
      minusThirteen,
      minusFifteen,
      minusTwentyThree,
    ]);
    final userState = _FakeTrackUserStateRepository({
      1: TrackUserState(
        trackId: 1,
        playCount: 1,
        userScoreBoost: -8,
        updatedAt: now,
      ),
      2: TrackUserState(
        trackId: 2,
        playCount: 1,
        userScoreBoost: -16,
        updatedAt: now,
      ),
      3: TrackUserState(
        trackId: 3,
        playCount: 1,
        userScoreBoost: -18,
        updatedAt: now,
      ),
      4: TrackUserState(
        trackId: 4,
        playCount: 1,
        userScoreBoost: -26,
        updatedAt: now,
      ),
    });
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      userState: userState,
      now: now,
      randomDouble: () => 0.99,
    );

    await queue.playSmartNext();

    expect(
      queue.state.recommendationCandidates.map((result) => result.track.id),
      [1, 2, 3],
    );
    expect(queue.state.lastRecommendationResult?.track.id, isNot(4));
    expect(
      queue.state.selectionPoolMessage,
      'Negative score cutoff active: showing candidates within 10.0 points '
      'of best available score.',
    );

    await queue.dispose();
    await player.dispose();
  });

  test('current track is not selected again when alternatives exist', () async {
    final now = DateTime(2026);
    final current = _track(id: 1, title: 'Current', artist: 'A', now: now);
    final alternative =
        _track(id: 2, title: 'Alternative', artist: 'B', now: now);
    final tracks = _FakeTrackRepository([current, alternative]);
    final userState = _FakeTrackUserStateRepository({
      1: TrackUserState(
        trackId: 1,
        isFavorite: true,
        updatedAt: now,
      ),
    });
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      userState: userState,
      now: now,
    );

    player.emit(
      PlayerState(
        currentTrack: current,
        isPlaying: true,
        duration: current.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.playSmartNext();

    expect(queue.state.lastRecommendationResult?.track.id, 2);
    expect(player.playedTracks.single.id, 2);

    await queue.dispose();
    await player.dispose();
  });

  test('last 3 played tracks are avoided when alternatives exist', () async {
    final now = DateTime(2026);
    final tracks = _FakeTrackRepository([
      _track(id: 1, title: 'Recent One', artist: 'A', now: now),
      _track(id: 2, title: 'Recent Two', artist: 'B', now: now),
      _track(id: 3, title: 'Recent Three', artist: 'C', now: now),
      _track(id: 4, title: 'Fresh Four', artist: 'D', now: now),
      _track(id: 5, title: 'Fresh Five', artist: 'E', now: now),
    ]);
    final userState = _FakeTrackUserStateRepository({
      1: TrackUserState(
        trackId: 1,
        isFavorite: true,
        updatedAt: now,
      ),
      2: TrackUserState(
        trackId: 2,
        isFavorite: true,
        updatedAt: now,
      ),
      3: TrackUserState(
        trackId: 3,
        isFavorite: true,
        updatedAt: now,
      ),
    });
    final events = _FakePlaybackEventRepository([
      _started(trackId: 1, now: now),
      _started(trackId: 2, now: now),
      _started(trackId: 3, now: now),
    ]);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      events: events,
      userState: userState,
      now: now,
      randomDouble: () => 0,
    );

    await queue.playSmartNext();

    expect(queue.state.lastRecommendationResult?.track.id, 4);
    expect(
      queue.state.recommendationCandidates.map((result) => result.track.id),
      isNot(contains(anyOf(1, 2, 3))),
    );
    expect(queue.state.repeatGuardMessage, contains('Recent repeat guard'));

    await queue.dispose();
    await player.dispose();
  });

  test('favorite boost does not overpower recent hard guard', () async {
    final now = DateTime(2026);
    final current = _track(id: 1, title: 'Current', artist: 'A', now: now);
    final favorite = _track(id: 2, title: 'Favorite', artist: 'B', now: now);
    final fresh = _track(id: 3, title: 'Fresh', artist: 'C', now: now);
    final tracks = _FakeTrackRepository([current, favorite, fresh]);
    final userState = _FakeTrackUserStateRepository({
      2: TrackUserState(
        trackId: 2,
        isFavorite: true,
        updatedAt: now,
      ),
    });
    final events = _FakePlaybackEventRepository([
      _started(trackId: 2, now: now),
      _started(trackId: 1, now: now),
    ]);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      events: events,
      userState: userState,
      now: now,
      randomDouble: () => 0,
    );

    player.emit(
      PlayerState(
        currentTrack: current,
        isPlaying: true,
        duration: current.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.playSmartNext();

    expect(queue.state.lastRecommendationResult?.track.id, 3);
    expect(player.playedTracks.single.id, 3);

    await queue.dispose();
    await player.dispose();
  });

  test('same recent artist and album are avoided when alternatives exist',
      () async {
    final now = DateTime(2026);
    final current = _track(
      id: 1,
      title: 'Current',
      artist: 'Shared Artist',
      album: 'Shared Album',
      now: now,
    );
    final sameArtist = _track(
      id: 2,
      title: 'Same Artist',
      artist: 'Shared Artist',
      album: 'Other Album',
      now: now,
    );
    final sameAlbum = _track(
      id: 3,
      title: 'Same Album',
      artist: 'Other Artist',
      album: 'Shared Album',
      now: now,
    );
    final fresh = _track(
      id: 4,
      title: 'Fresh',
      artist: 'Fresh Artist',
      album: 'Fresh Album',
      now: now,
    );
    final tracks =
        _FakeTrackRepository([current, sameArtist, sameAlbum, fresh]);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      now: now,
      randomDouble: () => 0,
    );

    player.emit(
      PlayerState(
        currentTrack: current,
        isPlaying: true,
        duration: current.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.playSmartNext();

    expect(queue.state.lastRecommendationResult?.track.id, 4);
    expect(
      queue.state.recommendationCandidates.map((result) => result.track.id),
      isNot(contains(anyOf(1, 2, 3))),
    );

    await queue.dispose();
    await player.dispose();
  });

  test('disliked and missing tracks are not selected', () async {
    final now = DateTime(2026);
    final hidden = _track(id: 1, title: 'Hidden', now: now);
    final disliked = _track(id: 2, title: 'Low Rating', now: now);
    final missing = _track(id: 3, title: 'Missing', now: now, isMissing: true);
    final visible = _track(id: 4, title: 'Visible', now: now);
    final tracks = _FakeTrackRepository([hidden, disliked, missing, visible]);
    final userState = _FakeTrackUserStateRepository({
      1: TrackUserState(trackId: 1, isHidden: true, updatedAt: now),
      2: TrackUserState(trackId: 2, rating: 1, updatedAt: now),
    });
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      userState: userState,
      now: now,
    );

    await queue.playSmartNext();

    expect(queue.state.lastRecommendationResult?.track.id, 4);
    expect(player.playedTracks.single.id, 4);

    await queue.dispose();
    await player.dispose();
  });

  test('smart next excludes tracks from disabled folders', () async {
    final now = DateTime(2026);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final enabledFolderId = await repositories.libraryFolders.upsertFolder(
      LibraryFolder(
        path: '/music/enabled',
        displayName: 'Enabled',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final disabledFolderId = await repositories.libraryFolders.upsertFolder(
      LibraryFolder(
        path: '/music/disabled',
        displayName: 'Disabled',
        isEnabled: false,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repositories.tracks.upsertTrack(
      _track(id: 1, title: 'Disabled Track', now: now).copyWith(
        libraryFolderId: disabledFolderId,
        filePath: '/music/disabled/disabled-track.flac',
      ),
    );
    await repositories.tracks.upsertTrack(
      _track(id: 2, title: 'Enabled Track', now: now).copyWith(
        libraryFolderId: enabledFolderId,
        filePath: '/music/enabled/enabled-track.flac',
      ),
    );
    final player = _FakePlayerService();
    final recommendation = RecommendationService(
      tracks: repositories.tracks,
      trackUserState: repositories.trackUserState,
      playbackEvents: repositories.playbackEvents,
    );
    final queue = PlaybackQueueService(
      playerService: player,
      tracks: repositories.tracks,
      trackUserState: repositories.trackUserState,
      playbackEvents: repositories.playbackEvents,
      recommendationService: recommendation,
      clock: () => now,
      randomDouble: () => 0,
    );

    await queue.playSmartNext();

    expect(player.playedTracks.single.title, 'Enabled Track');
    expect(
      queue.state.recommendationCandidates.map(
        (result) => result.track.title,
      ),
      isNot(contains('Disabled Track')),
    );

    await queue.dispose();
    await player.dispose();
  });

  test('smart next excludes tracks from removed folders', () async {
    final now = DateTime(2026);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final enabledFolderId = await repositories.libraryFolders.upsertFolder(
      LibraryFolder(
        path: '/music/enabled',
        displayName: 'Enabled',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final removedFolder = LibraryFolder(
      path: '/music/removed',
      displayName: 'Removed',
      isEnabled: false,
      createdAt: now,
      updatedAt: now,
    );
    final removedFolderId = await repositories.libraryFolders.upsertFolder(
      removedFolder,
    );
    final persistedRemovedFolder = removedFolder.copyWith(id: removedFolderId);
    await repositories.tracks.upsertTrack(
      _track(id: 1, title: 'Removed Track', now: now).copyWith(
        libraryFolderId: removedFolderId,
        filePath: '/music/removed/removed-track.flac',
      ),
    );
    await repositories.tracks.upsertTrack(
      _track(id: 2, title: 'Enabled Track', now: now).copyWith(
        libraryFolderId: enabledFolderId,
        filePath: '/music/enabled/enabled-track.flac',
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
    await service.removeFolderFromLibrary(persistedRemovedFolder);
    final player = _FakePlayerService();
    final recommendation = RecommendationService(
      tracks: repositories.tracks,
      trackUserState: repositories.trackUserState,
      playbackEvents: repositories.playbackEvents,
    );
    final queue = PlaybackQueueService(
      playerService: player,
      tracks: repositories.tracks,
      trackUserState: repositories.trackUserState,
      playbackEvents: repositories.playbackEvents,
      recommendationService: recommendation,
      clock: () => now,
      randomDouble: () => 0,
    );

    await queue.playSmartNext();

    expect(player.playedTracks.single.title, 'Enabled Track');
    expect(
      queue.state.recommendationCandidates.map(
        (result) => result.track.title,
      ),
      isNot(contains('Removed Track')),
    );

    await queue.dispose();
    await player.dispose();
  });

  test('next records skipped event when current track is interrupted',
      () async {
    final now = DateTime(2026);
    final current = _track(id: 1, title: 'Current', now: now);
    final next = _track(id: 2, title: 'Next', now: now);
    final tracks = _FakeTrackRepository([current, next]);
    final events = _FakePlaybackEventRepository();
    final userState = _FakeTrackUserStateRepository();
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      events: events,
      userState: userState,
      now: now,
    );

    queue.enableWave();
    player.emit(
      PlayerState(
        currentTrack: current,
        isPlaying: true,
        position: const Duration(seconds: 42),
        duration: current.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.next();

    expect(events.events.first.type, PlaybackEventType.skipped);
    expect(events.events.first.trackId, 1);
    expect(events.events.first.position, const Duration(seconds: 42));
    expect(userState.states[1]?.skipCount, 1);
    expect(userState.states[1]?.lastSkippedAt, now);
    expect(player.playedTracks.single.id, 2);

    await queue.dispose();
    await player.dispose();
  });

  test('next does nothing when queue is empty and wave is disabled', () async {
    final now = DateTime(2026);
    final current = _track(id: 1, title: 'Current', now: now);
    final next = _track(id: 2, title: 'Next', now: now);
    final events = _FakePlaybackEventRepository();
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([current, next]),
      events: events,
      now: now,
    );

    player.emit(
      PlayerState(
        currentTrack: current,
        isPlaying: true,
        position: const Duration(seconds: 42),
        duration: current.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.next();

    expect(player.playedTracks, isEmpty);
    expect(events.events, isEmpty);
    expect(queue.state.lastRecommendationResult, isNull);

    await queue.dispose();
    await player.dispose();
  });

  test('next plays queued item when wave is disabled', () async {
    final now = DateTime(2026);
    final queued = _track(id: 1, title: 'Queued', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([queued]),
      now: now,
    );

    await queue.addToQueue(queued);
    await queue.next();

    expect(player.playedTracks.single.id, 1);
    expect(queue.state.manualQueue, isEmpty);
    expect(queue.state.isWaveEnabled, isFalse);

    await queue.dispose();
    await player.dispose();
  });

  test('next uses Smart Wave when queue is empty and wave is enabled',
      () async {
    final now = DateTime(2026);
    final current = _track(id: 1, title: 'Current', artist: 'A', now: now);
    final smart = _track(id: 2, title: 'Smart', artist: 'B', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([current, smart]),
      now: now,
    );

    queue.enableWave();
    player.emit(
      PlayerState(
        currentTrack: current,
        isPlaying: true,
        position: const Duration(seconds: 42),
        duration: current.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.next();

    expect(player.playedTracks.single.id, 2);
    expect(queue.state.lastRecommendationResult?.track.id, 2);

    await queue.dispose();
    await player.dispose();
  });

  test('smart next does not record a skip for the current track', () async {
    final now = DateTime(2026);
    final current = _track(id: 1, title: 'Current', artist: 'A', now: now);
    final recommended =
        _track(id: 2, title: 'Recommended', artist: 'B', now: now);
    final tracks = _FakeTrackRepository([current, recommended]);
    final events = _FakePlaybackEventRepository([
      PlaybackEvent(
        trackId: 1,
        type: PlaybackEventType.started,
        occurredAt: now,
      ),
    ]);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      events: events,
      now: now,
    );

    player.emit(
      PlayerState(
        currentTrack: current,
        isPlaying: true,
        position: const Duration(seconds: 42),
        duration: current.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.playSmartNext();

    expect(
      events.events.map((event) => event.type),
      isNot(contains(PlaybackEventType.skipped)),
    );
    expect(player.playedTracks.single.id, 2);

    await queue.dispose();
    await player.dispose();
  });

  test('like updates user state and improves recommendation score', () async {
    final now = DateTime(2026);
    final liked = _track(id: 1, title: 'Liked', artist: 'A', now: now);
    final other = _track(id: 2, title: 'Other', artist: 'B', now: now);
    final tracks = _FakeTrackRepository([liked, other]);
    final userState = _FakeTrackUserStateRepository({
      1: TrackUserState(
        trackId: 1,
        isHidden: true,
        rating: 1,
        updatedAt: now,
      ),
    });
    final events = _FakePlaybackEventRepository();
    final player = _FakePlayerService();
    final recommendation = RecommendationService(
      tracks: tracks,
      trackUserState: userState,
      playbackEvents: events,
    );
    final queue = PlaybackQueueService(
      playerService: player,
      tracks: tracks,
      trackUserState: userState,
      playbackEvents: events,
      recommendationService: recommendation,
      clock: () => now,
      randomDouble: () => 0,
    );

    player.emit(
      PlayerState(
        currentTrack: liked,
        isPlaying: true,
        duration: liked.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.likeCurrentTrack();
    final balancedResults = await recommendation.recommend(now: now);
    final results = await recommendation.recommend(
      waveMode: WaveMode.favorites,
      now: now,
    );

    expect(userState.states[1]?.isFavorite, isTrue);
    expect(userState.states[1]?.isHidden, isFalse);
    expect(userState.states[1]?.rating, isNull);
    expect(queue.state.isCurrentTrackLiked, isTrue);
    expect(queue.state.isCurrentTrackDisliked, isFalse);
    expect(results.first.track.id, 1);
    expect(
      results.first.reasons.map((reason) => reason.code),
      contains('favorite'),
    );
    expect(
      balancedResults
          .firstWhere((result) => result.track.id == 1)
          .reasons
          .map((reason) => reason.code),
      isNot(contains('rating')),
    );
    expect(
      balancedResults
          .firstWhere((result) => result.track.id == 1)
          .reasons
          .firstWhere((reason) => reason.code == 'favorite')
          .weight,
      2,
    );

    await queue.dispose();
    await player.dispose();
  });

  test('dislike excludes track from future recommendations', () async {
    final now = DateTime(2026);
    final disliked = _track(id: 1, title: 'Disliked', artist: 'A', now: now);
    final other = _track(id: 2, title: 'Other', artist: 'B', now: now);
    final tracks = _FakeTrackRepository([disliked, other]);
    final userState = _FakeTrackUserStateRepository();
    final events = _FakePlaybackEventRepository();
    final player = _FakePlayerService();
    final recommendation = RecommendationService(
      tracks: tracks,
      trackUserState: userState,
      playbackEvents: events,
    );
    final queue = PlaybackQueueService(
      playerService: player,
      tracks: tracks,
      trackUserState: userState,
      playbackEvents: events,
      recommendationService: recommendation,
      clock: () => now,
      randomDouble: () => 0,
    );

    player.emit(
      PlayerState(
        currentTrack: disliked,
        isPlaying: true,
        duration: disliked.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.dislikeCurrentTrack();
    expect(userState.states[1]?.isFavorite, isFalse);
    expect(userState.states[1]?.isHidden, isTrue);
    expect(userState.states[1]?.rating, isNull);
    expect(queue.state.isCurrentTrackLiked, isFalse);
    expect(queue.state.isCurrentTrackDisliked, isTrue);

    final results = await recommendation.recommend(now: now);
    await queue.playSmartNext();
    final visibleTracks = await tracks.watchAllTracks().first;

    expect(results.map((result) => result.track.id), isNot(contains(1)));
    expect(player.playedTracks.single.id, 2);
    expect(visibleTracks.map((track) => track.id), contains(1));

    player.playedTracks.clear();
    await queue.playTrackManually(disliked);
    expect(player.playedTracks.single.id, 1);

    await queue.dispose();
    await player.dispose();
  });

  test('like clears dislike and dislike clears like', () async {
    final now = DateTime(2026);
    final track = _track(id: 1, title: 'Feedback', now: now);
    final tracks = _FakeTrackRepository([track]);
    final userState = _FakeTrackUserStateRepository({
      1: TrackUserState(
        trackId: 1,
        isFavorite: true,
        rating: 5,
        updatedAt: now,
      ),
    });
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      userState: userState,
      now: now,
    );

    player.emit(
      PlayerState(
        currentTrack: track,
        isPlaying: true,
        duration: track.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.dislikeCurrentTrack();

    expect(userState.states[1]?.isFavorite, isFalse);
    expect(userState.states[1]?.isHidden, isTrue);
    expect(userState.states[1]?.rating, isNull);
    expect(queue.state.isCurrentTrackLiked, isFalse);
    expect(queue.state.isCurrentTrackDisliked, isTrue);

    await queue.likeCurrentTrack();

    expect(userState.states[1]?.isFavorite, isTrue);
    expect(userState.states[1]?.isHidden, isFalse);
    expect(userState.states[1]?.rating, isNull);
    expect(queue.state.isCurrentTrackLiked, isTrue);
    expect(queue.state.isCurrentTrackDisliked, isFalse);

    await queue.dispose();
    await player.dispose();
  });

  test('like toggles neutral to liked and liked back to neutral', () async {
    final now = DateTime(2026);
    final track = _track(id: 1, title: 'Toggle Like', now: now);
    final userState = _FakeTrackUserStateRepository();
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([track]),
      userState: userState,
      now: now,
    );

    player.emit(
      PlayerState(
        currentTrack: track,
        isPlaying: true,
        duration: track.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.likeCurrentTrack();

    expect(userState.states[1]?.isFavorite, isTrue);
    expect(userState.states[1]?.isHidden, isFalse);
    expect(userState.states[1]?.rating, isNull);
    expect(queue.state.isCurrentTrackLiked, isTrue);

    await queue.likeCurrentTrack();

    expect(userState.states[1]?.isFavorite, isFalse);
    expect(userState.states[1]?.isHidden, isFalse);
    expect(userState.states[1]?.rating, isNull);
    expect(queue.state.isCurrentTrackLiked, isFalse);
    expect(queue.state.isCurrentTrackDisliked, isFalse);

    await queue.dispose();
    await player.dispose();
  });

  test('dislike toggles neutral to disliked and disliked back to neutral',
      () async {
    final now = DateTime(2026);
    final track = _track(id: 1, title: 'Toggle Dislike', now: now);
    final userState = _FakeTrackUserStateRepository();
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([track]),
      userState: userState,
      now: now,
    );

    player.emit(
      PlayerState(
        currentTrack: track,
        isPlaying: true,
        duration: track.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.dislikeCurrentTrack();

    expect(userState.states[1]?.isFavorite, isFalse);
    expect(userState.states[1]?.isHidden, isTrue);
    expect(userState.states[1]?.rating, isNull);
    expect(queue.state.isCurrentTrackDisliked, isTrue);

    await queue.dislikeCurrentTrack();

    expect(userState.states[1]?.isFavorite, isFalse);
    expect(userState.states[1]?.isHidden, isFalse);
    expect(userState.states[1]?.rating, isNull);
    expect(queue.state.isCurrentTrackLiked, isFalse);
    expect(queue.state.isCurrentTrackDisliked, isFalse);

    await queue.dispose();
    await player.dispose();
  });

  test('track list feedback methods can toggle a non-current track', () async {
    final now = DateTime(2026);
    final current = _track(id: 1, title: 'Current', now: now);
    final rowTrack = _track(id: 2, title: 'Row Track', now: now);
    final userState = _FakeTrackUserStateRepository();
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([current, rowTrack]),
      userState: userState,
      now: now,
    );

    player.emit(
      PlayerState(
        currentTrack: current,
        isPlaying: true,
        duration: current.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );

    await queue.toggleLike(rowTrack);

    expect(userState.states[2]?.isFavorite, isTrue);
    expect(userState.states[2]?.isHidden, isFalse);
    expect(userState.states[2]?.rating, isNull);
    expect(queue.state.currentTrackUserState, isNull);

    await queue.toggleDislike(rowTrack);

    expect(userState.states[2]?.isFavorite, isFalse);
    expect(userState.states[2]?.isHidden, isTrue);
    expect(userState.states[2]?.rating, isNull);

    await queue.dispose();
    await player.dispose();
  });

  test('completion with wave enabled triggers smart next', () async {
    final now = DateTime(2026);
    final completed = _track(id: 1, title: 'Done', artist: 'A', now: now);
    final next = _track(id: 2, title: 'Next', artist: 'B', now: now);
    final tracks = _FakeTrackRepository([completed, next]);
    final events = _FakePlaybackEventRepository([
      PlaybackEvent(
        trackId: 1,
        type: PlaybackEventType.started,
        occurredAt: now,
      ),
    ]);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      events: events,
      now: now,
    );

    queue.enableWave();
    player.emit(
      PlayerState(
        currentTrack: completed,
        isPlaying: false,
        position: completed.duration!,
        duration: completed.duration,
        status: PlayerPlaybackStatus.completed,
      ),
    );

    await _waitUntil(() => player.playedTracks.isNotEmpty);

    expect(player.playedTracks.single.id, 2);
    expect(queue.state.lastRecommendationResult?.track.id, 2);

    await queue.dispose();
    await player.dispose();
  });

  test('completion does not auto-next when queue is empty and wave is disabled',
      () async {
    final now = DateTime(2026);
    final completed = _track(id: 1, title: 'Done', artist: 'A', now: now);
    final next = _track(id: 2, title: 'Next', artist: 'B', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([completed, next]),
      now: now,
    );

    player.emit(
      PlayerState(
        currentTrack: completed,
        isPlaying: false,
        position: completed.duration!,
        duration: completed.duration,
        status: PlayerPlaybackStatus.completed,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(player.playedTracks, isEmpty);
    expect(queue.state.lastRecommendationResult, isNull);

    await queue.dispose();
    await player.dispose();
  });

  test('completion plays queued item when wave is disabled', () async {
    final now = DateTime(2026);
    final completed = _track(id: 1, title: 'Done', artist: 'A', now: now);
    final queued = _track(id: 2, title: 'Queued', artist: 'B', now: now);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([completed, queued]),
      now: now,
    );

    await queue.addToQueue(queued);
    player.emit(_completedState(completed));

    await _waitUntil(() => player.playedTracks.isNotEmpty);

    expect(player.playedTracks.single.id, 2);
    expect(queue.state.manualQueue, isEmpty);
    expect(queue.state.isWaveEnabled, isFalse);

    await queue.dispose();
    await player.dispose();
  });

  test('transition guard is cleared after playback failure', () async {
    final now = DateTime(2026);
    final failing = _track(id: 1, title: 'Failing', now: now);
    final recovery = _track(id: 2, title: 'Recovery', now: now);
    final player = _FakePlayerService()
      ..playTrackError = StateError('load failed');
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([failing, recovery]),
      now: now,
    );

    await queue.addToQueue(failing);
    await queue.next();

    expect(player.playedTracks, isEmpty);
    expect(queue.state.isChoosingNext, isFalse);
    expect(queue.state.lastError, contains('load failed'));

    player.playTrackError = null;
    await queue.addToQueue(recovery);
    await queue.next();

    expect(player.playedTracks.single.id, 2);
    expect(queue.state.isChoosingNext, isFalse);

    await queue.dispose();
    await player.dispose();
  });

  test('manually queued disliked track can still play', () async {
    final now = DateTime(2026);
    final disliked = _track(id: 1, title: 'Disliked', artist: 'A', now: now);
    final alternative =
        _track(id: 2, title: 'Alternative', artist: 'B', now: now);
    final userState = _FakeTrackUserStateRepository({
      1: TrackUserState(trackId: 1, isHidden: true, updatedAt: now),
    });
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([disliked, alternative]),
      userState: userState,
      now: now,
    );

    await queue.addToQueue(disliked);
    await queue.next();

    expect(player.playedTracks.single.id, 1);
    expect(queue.state.manualQueue, isEmpty);

    await queue.dispose();
    await player.dispose();
  });

  test('empty library is handled gracefully', () async {
    final now = DateTime(2026);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: const _FakeTrackRepository([]),
      now: now,
    );

    await queue.playSmartNext();

    expect(player.playedTracks, isEmpty);
    expect(queue.state.lastError, contains('No playable tracks'));

    await queue.dispose();
    await player.dispose();
  });

  test('start wave enables wave and stop wave disables it', () async {
    final now = DateTime(2026);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: _FakeTrackRepository([
        _track(id: 1, title: 'One', now: now),
      ]),
      now: now,
    );

    expect(queue.state.isWaveEnabled, isFalse);

    await queue.playSmartNext();

    expect(queue.state.isWaveEnabled, isTrue);

    queue.disableWave();

    expect(queue.state.isWaveEnabled, isFalse);

    await queue.dispose();
    await player.dispose();
  });

  test('wave mode changes affect recommendation input', () async {
    final now = DateTime(2026);
    final favorite = _track(id: 1, title: 'Favorite', artist: 'A', now: now);
    final fresh = _track(id: 2, title: 'Fresh', artist: 'B', now: now);
    final tracks = _FakeTrackRepository([favorite, fresh]);
    final userState = _FakeTrackUserStateRepository({
      1: TrackUserState(
        trackId: 1,
        isFavorite: true,
        playCount: 20,
        updatedAt: now,
      ),
    });
    final events = _FakePlaybackEventRepository([
      PlaybackEvent(
        trackId: 1,
        type: PlaybackEventType.started,
        occurredAt: now,
      ),
    ]);
    final player = _FakePlayerService();
    final queue = _queue(
      player: player,
      tracks: tracks,
      events: events,
      userState: userState,
      now: now,
    );

    queue.setWaveMode(WaveMode.discovery);
    await queue.playSmartNext();
    final discoveryPick = player.playedTracks.single.id;

    player.playedTracks.clear();
    queue.setWaveMode(WaveMode.favorites);
    await queue.playSmartNext();
    final favoritesPick = player.playedTracks.single.id;

    expect(discoveryPick, 2);
    expect(favoritesPick, 1);

    await queue.dispose();
    await player.dispose();
  });
}

Future<void> _startPlaylist(
  PlaybackQueueService queue,
  List<Track> tracks, {
  required int startTrackId,
  required DateTime now,
}) {
  return queue.playPlaylist(
    playlistId: 42,
    playlistName: 'Road Mix',
    entries: [
      for (var index = 0; index < tracks.length; index++)
        _playlistEntry(
          tracks[index],
          playlistId: 42,
          position: index,
          now: now.add(Duration(milliseconds: index)),
        ),
    ],
    startTrackId: startTrackId,
  );
}

PlaylistEntry _playlistEntry(
  Track track, {
  required int playlistId,
  required int position,
  required DateTime now,
  String? unavailableReason,
}) {
  return PlaylistEntry(
    playlistId: playlistId,
    trackId: track.id!,
    position: position,
    addedAt: now,
    track: track,
    unavailableReason:
        unavailableReason ?? (track.isMissing ? 'Missing' : null),
  );
}

PlaybackQueueService _queue({
  required _FakePlayerService player,
  required _FakeTrackRepository tracks,
  _FakeTrackUserStateRepository? userState,
  _FakePlaybackEventRepository? events,
  required DateTime now,
  double Function()? randomDouble,
}) {
  final stateRepository = userState ?? _FakeTrackUserStateRepository();
  final eventRepository = events ?? _FakePlaybackEventRepository();
  final recommendation = RecommendationService(
    tracks: tracks,
    trackUserState: stateRepository,
    playbackEvents: eventRepository,
  );

  return PlaybackQueueService(
    playerService: player,
    tracks: tracks,
    trackUserState: stateRepository,
    playbackEvents: eventRepository,
    recommendationService: recommendation,
    clock: () => now,
    randomDouble: randomDouble ?? () => 0,
  );
}

Track _track({
  required int id,
  required String title,
  String artist = 'Artist',
  String? album,
  bool isMissing = false,
  required DateTime now,
}) {
  return Track(
    id: id,
    filePath: '/music/$title.flac',
    title: title,
    artist: artist,
    album: album ?? 'Album $artist',
    duration: const Duration(minutes: 3),
    isMissing: isMissing,
    addedAt: now,
    updatedAt: now,
  );
}

PlaybackEvent _started({
  required int trackId,
  required DateTime now,
}) {
  return PlaybackEvent(
    trackId: trackId,
    type: PlaybackEventType.started,
    occurredAt: now,
  );
}

PlayerState _completedState(Track track) {
  return PlayerState(
    currentTrack: track,
    isPlaying: false,
    position: track.duration ?? Duration.zero,
    duration: track.duration,
    status: PlayerPlaybackStatus.completed,
  );
}

PlayerState _playingState(
  Track track, {
  required Duration position,
}) {
  return PlayerState(
    currentTrack: track,
    isPlaying: true,
    position: position,
    duration: track.duration,
    status: PlayerPlaybackStatus.playing,
  );
}

RecommendationResult _recommendationResult({
  required int id,
  required String title,
  required double score,
  required DateTime now,
}) {
  return RecommendationResult(
    track: _track(id: id, title: title, now: now),
    score: score,
    waveMode: WaveMode.balanced,
    reasons: const [],
    generatedAt: now,
  );
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met before timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

final class _FakePlayerService implements PlayerService {
  final StreamController<PlayerState> _controller =
      StreamController<PlayerState>.broadcast();

  final List<Track> playedTracks = [];
  final List<Track> playTrackCalls = [];
  final List<Duration> seekCalls = [];
  Completer<void>? playTrackBlocker;
  Object? playTrackError;
  PlayerState _state = const PlayerState.idle();

  @override
  PlayerState get state => _state;

  @override
  Track? get currentTrack => _state.currentTrack;

  @override
  bool get isPlaying => _state.isPlaying;

  @override
  Duration get position => _state.position;

  @override
  Duration? get duration => _state.duration;

  @override
  double get volume => _state.volume;

  @override
  Stream<PlayerState> get stateStream => _controller.stream;

  @override
  Future<void> playTrack(Track track) async {
    playTrackCalls.add(track);
    final error = playTrackError;
    if (error != null) {
      throw error;
    }

    final blocker = playTrackBlocker;
    if (blocker != null) {
      await blocker.future;
    }

    playedTracks.add(track);
    emit(
      PlayerState(
        currentTrack: track,
        isPlaying: true,
        duration: track.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );
  }

  @override
  Future<void> play() async {
    emit(
        _state.copyWith(isPlaying: true, status: PlayerPlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    emit(
      _state.copyWith(isPlaying: false, status: PlayerPlaybackStatus.paused),
    );
  }

  @override
  Future<void> stop() async {
    emit(const PlayerState(status: PlayerPlaybackStatus.stopped));
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls.add(position);
    emit(_state.copyWith(position: position));
  }

  @override
  Future<void> setVolume(double volume) async {
    emit(_state.copyWith(volume: volume));
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void emit(PlayerState state) {
    _state = state;
    _controller.add(state);
  }
}

final class _FakeTrackRepository implements TrackRepository {
  const _FakeTrackRepository(this._tracks);

  final List<Track> _tracks;

  @override
  Future<int> upsertTrack(Track track) async {
    return track.id ?? 0;
  }

  @override
  Future<void> updateTrackMetadata(TrackMetadataUpdate metadata) async {}

  @override
  Future<Track?> findById(int id) async {
    for (final track in _tracks) {
      if (track.id == id) {
        return track;
      }
    }
    return null;
  }

  @override
  Future<Track?> findByStableId(String stableId) async {
    for (final track in _tracks) {
      if (track.stableId == stableId) {
        return track;
      }
    }
    return null;
  }

  @override
  Future<Track?> findByPath(String filePath) async {
    for (final track in _tracks) {
      if (track.filePath == filePath) {
        return track;
      }
    }
    return null;
  }

  @override
  Future<List<Track>> listTracks({
    int limit = 100,
    int offset = 0,
    bool includeDisabledFolders = false,
  }) async {
    return _tracks.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<List<Track>> listTracksByLibraryFolder(
    int libraryFolderId, {
    bool includeMissing = true,
  }) async {
    return _tracks
        .where((track) => track.libraryFolderId == libraryFolderId)
        .where((track) => includeMissing || !track.isMissing)
        .toList(growable: false);
  }

  @override
  Stream<List<Track>> watchAllTracks({
    bool includeMissing = false,
    bool includeDisabledFolders = false,
  }) {
    return Stream.value(
      _tracks
          .where((track) => includeMissing || !track.isMissing)
          .toList(growable: false),
    );
  }

  @override
  Stream<List<Track>> watchTracks({
    int limit = 100,
    bool includeDisabledFolders = false,
  }) {
    return Stream.value(_tracks.take(limit).toList(growable: false));
  }

  @override
  Future<void> deleteTracksByLibraryFolder(int libraryFolderId) async {}

  @override
  Future<void> deleteTrack(int id) async {}
}

final class _FakeTrackUserStateRepository implements TrackUserStateRepository {
  _FakeTrackUserStateRepository([Map<int, TrackUserState>? states])
      : states = states ?? {};

  final Map<int, TrackUserState> states;

  @override
  Future<void> upsertState(TrackUserState state) async {
    states[state.trackId] = state;
  }

  @override
  Future<TrackUserState?> findByTrackId(int trackId) async {
    return states[trackId];
  }

  @override
  Future<Map<int, TrackUserState>> findByTrackIds(
    Iterable<int> trackIds,
  ) async {
    return {
      for (final trackId in trackIds)
        if (states[trackId] != null) trackId: states[trackId]!,
    };
  }

  @override
  Stream<TrackUserState?> watchTrackState(int trackId) {
    return Stream.value(states[trackId]);
  }

  @override
  Stream<Map<int, TrackUserState>> watchTrackStatesByTrackIds(
    Iterable<int> trackIds,
  ) {
    return Stream.value({
      for (final trackId in trackIds)
        if (states[trackId] != null) trackId: states[trackId]!,
    });
  }

  @override
  Future<void> deleteState(int trackId) async {
    states.remove(trackId);
  }
}

final class _FakePlaybackEventRepository implements PlaybackEventRepository {
  _FakePlaybackEventRepository([List<PlaybackEvent>? events])
      : events = events ?? [];

  final List<PlaybackEvent> events;

  @override
  Future<int> addEvent(PlaybackEvent event) async {
    events.add(event);
    return events.length;
  }

  @override
  Future<List<PlaybackEvent>> recentEvents({int limit = 100}) async {
    return events.reversed.take(limit).toList(growable: false);
  }

  @override
  Future<List<PlaybackEvent>> recentForTrack(int trackId, {int limit = 50}) {
    return Future.value(
      events.where((event) => event.trackId == trackId).toList(growable: false),
    );
  }
}
