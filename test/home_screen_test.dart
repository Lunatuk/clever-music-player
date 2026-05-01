import 'dart:async';

import 'package:clever_music_player/src/app/clever_music_player_app.dart';
import 'package:clever_music_player/src/app/dependency_scope.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/library/directory_picker_service.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:clever_music_player/src/player/player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/queue/playback_queue_service.dart';
import 'package:clever_music_player/src/recommendation/recommendation_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home shows Liquid Wave actions and bottom player bar',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create();
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);

    expect(find.text('Пустить жидкого'), findsOneWidget);
    expect(find.text('Настроить'), findsOneWidget);
    expect(find.text('Добавить папку'), findsOneWidget);
    expect(find.text('Еще раз'), findsOneWidget);
    expect(find.text('Моя музыка'), findsOneWidget);
    expect(find.text('No track playing'), findsOneWidget);
    expect(find.text('Liquid Wave'), findsNothing);
    expect(find.text('Local-first music flow'), findsNothing);
    expect(
      find.text('Волна играет. Нажатие поставит воспроизведение на паузу.'),
      findsNothing,
    );
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
  });

  testWidgets('central launch icon switches to pause while playing',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);

    await fixture.player.playTrack(_testTrack());
    await fixture.pump(tester);

    expect(find.byIcon(Icons.pause_circle_filled_rounded), findsOneWidget);
  });

  testWidgets('My Music navigation shows track library and keeps player bar',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    await tester.tap(find.text('Моя музыка'));
    await tester.pumpAndSettle();

    expect(find.text('Track library'), findsOneWidget);
    expect(find.text('Все треки'), findsOneWidget);
    expect(find.text('Test Track'), findsOneWidget);
    expect(find.text('No track playing'), findsOneWidget);
  });

  testWidgets('settings gear opens library folders and recommendation debug',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Library folders'), findsOneWidget);
    expect(find.text('Почему выбран трек'), findsOneWidget);
    expect(find.text('No track playing'), findsOneWidget);
  });

  testWidgets('wave mode dialog updates selected mode', (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create();
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    await tester.tap(find.text('Настроить'));
    await tester.pumpAndSettle();

    expect(find.text('Текущий режим: Balanced'), findsOneWidget);

    await tester.tap(find.text('Discovery'));
    await tester.pumpAndSettle();

    expect(fixture.queue.state.selectedWaveMode, WaveMode.discovery);
    expect(find.text('Текущий режим: Discovery'), findsOneWidget);
  });
}

Future<void> _setLargeSurface(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void _addFixtureTearDown(
  WidgetTester tester,
  _HomeScreenFixture fixture,
) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
    await tester.pump();
  });
}

final class _HomeScreenFixture {
  _HomeScreenFixture._({
    required this.dependencies,
    required this.queue,
    required this.player,
  });

  final AppDependencies dependencies;
  final PlaybackQueueService queue;
  final _FakePlayerService player;

  static Future<_HomeScreenFixture> create({
    bool seedLibrary = false,
  }) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repositories = _FakeAppRepositories(
      seedLibrary ? [_testTrack()] : const [],
      seedLibrary ? [_testFolder()] : const [],
    );
    final recommendationService = RecommendationService(
      tracks: repositories.tracks,
      trackUserState: repositories.trackUserState,
      playbackEvents: repositories.playbackEvents,
    );
    final libraryScanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: const FallbackMetadataReaderService(),
    );
    final player = _FakePlayerService();
    final queue = PlaybackQueueService(
      playerService: player,
      tracks: repositories.tracks,
      trackUserState: repositories.trackUserState,
      playbackEvents: repositories.playbackEvents,
      recommendationService: recommendationService,
    );
    final dependencies = AppDependencies(
      database: database,
      repositories: repositories,
      recommendationService: recommendationService,
      libraryScanner: libraryScanner,
      directoryPicker: const _NoopDirectoryPickerService(),
      playerService: player,
      playbackQueue: queue,
    );
    return _HomeScreenFixture._(
      dependencies: dependencies,
      queue: queue,
      player: player,
    );
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: const CleverMusicPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    await dependencies.dispose();
  }
}

final class _FakeAppRepositories implements AppRepositories {
  _FakeAppRepositories(List<Track> initialTracks, List<LibraryFolder> folders)
      : libraryFolders = _FakeLibraryRepository(folders),
        tracks = _FakeTrackRepository(initialTracks),
        playbackEvents = _FakePlaybackEventRepository(),
        trackUserState = _FakeTrackUserStateRepository(),
        settings = _FakeSettingsRepository();

  @override
  final LibraryRepository libraryFolders;

  @override
  final TrackRepository tracks;

  @override
  final PlaybackEventRepository playbackEvents;

  @override
  final TrackUserStateRepository trackUserState;

  @override
  final SettingsRepository settings;
}

final class _FakeLibraryRepository implements LibraryRepository {
  _FakeLibraryRepository(List<LibraryFolder> folders) : _folders = [...folders];

  final List<LibraryFolder> _folders;

  @override
  Future<int> upsertFolder(LibraryFolder folder) async {
    final existingIndex = _folders.indexWhere((item) => item.id == folder.id);
    if (existingIndex >= 0) {
      _folders[existingIndex] = folder;
      return folder.id!;
    }

    final id = folder.id ?? _folders.length + 1;
    _folders.add(folder.copyWith(id: id));
    return id;
  }

  @override
  Future<LibraryFolder?> findFolderByPath(String path) async {
    for (final folder in _folders) {
      if (folder.path == path) {
        return folder;
      }
    }
    return null;
  }

  @override
  Future<List<LibraryFolder>> listFolders({bool includeDisabled = true}) async {
    return _folders
        .where((folder) => includeDisabled || folder.isEnabled)
        .toList(growable: false);
  }

  @override
  Stream<List<LibraryFolder>> watchFolders({bool includeDisabled = true}) {
    return Stream.value(
      _folders
          .where((folder) => includeDisabled || folder.isEnabled)
          .toList(growable: false),
    );
  }

  @override
  Future<void> setFolderEnabled(
    int id, {
    required bool isEnabled,
    required DateTime updatedAt,
  }) async {
    final index = _folders.indexWhere((folder) => folder.id == id);
    if (index < 0) {
      return;
    }
    _folders[index] = _folders[index].copyWith(
      isEnabled: isEnabled,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> deleteFolder(int id) async {
    _folders.removeWhere((folder) => folder.id == id);
  }
}

final class _FakeTrackRepository implements TrackRepository {
  _FakeTrackRepository(List<Track> tracks) : _tracks = [...tracks];

  final List<Track> _tracks;

  @override
  Future<int> upsertTrack(Track track) async {
    final existingIndex = _tracks.indexWhere(
      (item) =>
          (track.id != null && item.id == track.id) ||
          item.filePath == track.filePath,
    );
    if (existingIndex >= 0) {
      final id = _tracks[existingIndex].id ?? track.id ?? existingIndex + 1;
      _tracks[existingIndex] = track.copyWith(id: id);
      return id;
    }

    final id = track.id ?? _tracks.length + 1;
    _tracks.add(track.copyWith(id: id));
    return id;
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
    return _visibleTracks(includeMissing: false)
        .skip(offset)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<Track>> listTracksByLibraryFolder(
    int libraryFolderId, {
    bool includeMissing = true,
  }) async {
    return _tracks
        .where((track) =>
            track.libraryFolderId == libraryFolderId &&
            (includeMissing || !track.isMissing))
        .toList(growable: false);
  }

  @override
  Stream<List<Track>> watchAllTracks({
    bool includeMissing = false,
    bool includeDisabledFolders = false,
  }) {
    return Stream.value(_visibleTracks(includeMissing: includeMissing));
  }

  @override
  Stream<List<Track>> watchTracks({
    int limit = 100,
    bool includeDisabledFolders = false,
  }) {
    return Stream.value(
      _visibleTracks(includeMissing: false).take(limit).toList(growable: false),
    );
  }

  @override
  Future<void> deleteTracksByLibraryFolder(int libraryFolderId) async {
    _tracks.removeWhere((track) => track.libraryFolderId == libraryFolderId);
  }

  @override
  Future<void> deleteTrack(int id) async {
    _tracks.removeWhere((track) => track.id == id);
  }

  List<Track> _visibleTracks({required bool includeMissing}) {
    return _tracks
        .where((track) => includeMissing || !track.isMissing)
        .toList(growable: false);
  }
}

final class _FakeTrackUserStateRepository implements TrackUserStateRepository {
  final Map<int, TrackUserState> _states = {};

  @override
  Future<void> upsertState(TrackUserState state) async {
    _states[state.trackId] = state;
  }

  @override
  Future<TrackUserState?> findByTrackId(int trackId) async => _states[trackId];

  @override
  Future<Map<int, TrackUserState>> findByTrackIds(
    Iterable<int> trackIds,
  ) async {
    return {
      for (final id in trackIds)
        if (_states[id] != null) id: _states[id]!,
    };
  }

  @override
  Stream<TrackUserState?> watchTrackState(int trackId) {
    return Stream.value(_states[trackId]);
  }

  @override
  Stream<Map<int, TrackUserState>> watchTrackStatesByTrackIds(
    Iterable<int> trackIds,
  ) {
    return Stream.value({
      for (final id in trackIds)
        if (_states[id] != null) id: _states[id]!,
    });
  }

  @override
  Future<void> deleteState(int trackId) async {
    _states.remove(trackId);
  }
}

final class _FakePlaybackEventRepository implements PlaybackEventRepository {
  final List<PlaybackEvent> _events = [];

  @override
  Future<int> addEvent(PlaybackEvent event) async {
    _events.add(event);
    return _events.length;
  }

  @override
  Future<List<PlaybackEvent>> recentEvents({int limit = 100}) async {
    return _events.reversed.take(limit).toList(growable: false);
  }

  @override
  Future<List<PlaybackEvent>> recentForTrack(
    int trackId, {
    int limit = 50,
  }) async {
    return _events
        .where((event) => event.trackId == trackId)
        .toList(growable: false)
        .reversed
        .take(limit)
        .toList(growable: false);
  }
}

final class _FakeSettingsRepository implements SettingsRepository {
  final Map<String, AppSetting> _settings = {};

  @override
  Future<AppSetting?> read(String key) async => _settings[key];

  @override
  Future<String?> readString(String key) async => _settings[key]?.value;

  @override
  Future<void> writeString(String key, String value) async {
    _settings[key] = AppSetting(
      key: key,
      value: value,
      updatedAt: DateTime(2026, 5),
    );
  }

  @override
  Future<void> delete(String key) async {
    _settings.remove(key);
  }
}

LibraryFolder _testFolder() {
  final now = DateTime(2026, 5);
  return LibraryFolder(
    id: 1,
    path: '/music',
    displayName: 'Music',
    createdAt: now,
    updatedAt: now,
  );
}

Track _testTrack() {
  final now = DateTime(2026, 5);
  return Track(
    id: 1,
    libraryFolderId: 1,
    filePath: '/music/test-track.mp3',
    title: 'Test Track',
    artist: 'Test Artist',
    album: 'Test Album',
    codec: 'mp3',
    duration: const Duration(minutes: 3, seconds: 15),
    addedAt: now,
    updatedAt: now,
  );
}

final class _NoopDirectoryPickerService implements DirectoryPickerService {
  const _NoopDirectoryPickerService();

  @override
  Future<String?> pickMusicFolder() async => null;
}

final class _FakePlayerService implements PlayerService {
  final StreamController<PlayerState> _controller =
      StreamController<PlayerState>.broadcast();
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
    _emit(
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
    final track = _state.currentTrack;
    if (track == null) {
      return;
    }
    _emit(
      _state.copyWith(
        isPlaying: true,
        status: PlayerPlaybackStatus.playing,
      ),
    );
  }

  @override
  Future<void> pause() async {
    _emit(
      _state.copyWith(
        isPlaying: false,
        status: PlayerPlaybackStatus.paused,
      ),
    );
  }

  @override
  Future<void> stop() async {
    _emit(const PlayerState.idle().copyWith(
      status: PlayerPlaybackStatus.stopped,
    ));
  }

  @override
  Future<void> seek(Duration position) async {
    _emit(_state.copyWith(position: position));
  }

  @override
  Future<void> setVolume(double volume) async {
    _emit(_state.copyWith(volume: volume));
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void _emit(PlayerState state) {
    _state = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }
}
