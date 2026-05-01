import 'dart:async';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/player/player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/queue/playback_queue_service.dart';
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
    expect(queue.state.lastRecommendationResult?.track.id, 2);
    expect(player.playedTracks.single.id, 2);

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
