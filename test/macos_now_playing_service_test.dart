import 'dart:async';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/player/player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/system_media/macos_now_playing_client.dart';
import 'package:clever_music_player/src/system_media/macos_now_playing_service.dart';
import 'package:clever_music_player/src/system_media/system_media_controls_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no-op system media controls service is safe', () async {
    const service = NoopSystemMediaControlsService();

    await service.initialize();
    await service.dispose();
  });

  test('service initializes and disposes on macOS only', () async {
    final player = _FakePlayerService();
    final client = _FakeMacosNowPlayingClient();
    final service = MacosNowPlayingService(
      playerService: player,
      onNext: () async {},
      onPrevious: () async {},
      client: client,
      isMacOS: true,
    );

    await service.initialize();
    await _waitUntil(() => client.clearMetadataCalls == 1);
    await service.dispose();

    expect(client.initializeCalls, 1);
    expect(client.statuses, [MacosNowPlayingPlaybackStatus.stopped]);
    expect(client.disposeCalls, 1);

    final unsupportedClient = _FakeMacosNowPlayingClient();
    final unsupportedService = MacosNowPlayingService(
      playerService: player,
      onNext: () async {},
      onPrevious: () async {},
      client: unsupportedClient,
      isMacOS: false,
    );

    await unsupportedService.initialize();
    await unsupportedService.dispose();

    expect(unsupportedClient.initializeCalls, 0);
    expect(unsupportedClient.disposeCalls, 0);
    await player.dispose();
  });

  test('metadata mapper uses title and artist fallbacks', () {
    final metadata = macosNowPlayingMetadataForTrack(
      _track(
        title: '  Song Title  ',
        artist: '  ',
        albumArtist: '  Album Artist  ',
        album: '  Album  ',
      ),
      fileExists: (_) => false,
    );

    expect(metadata.title, 'Song Title');
    expect(metadata.artist, 'Album Artist');
    expect(metadata.album, 'Album');
    expect(metadata.albumArtist, 'Album Artist');
    expect(metadata.artworkPath, isNull);
  });

  test('metadata mapper prefers custom artwork over embedded artwork', () {
    const customPath = '/music/custom cover.jpg';
    const embeddedPath = '/music/embedded cover.jpg';
    final metadata = macosNowPlayingMetadataForTrack(
      _track(customArtworkPath: customPath, artworkPath: embeddedPath),
      fileExists: (path) => path == customPath || path == embeddedPath,
    );

    expect(metadata.artworkPath, customPath);
  });

  test('metadata mapper ignores missing artwork files', () {
    const customPath = '/music/missing custom.jpg';
    const embeddedPath = '/music/embedded cover.jpg';
    final metadata = macosNowPlayingMetadataForTrack(
      _track(customArtworkPath: customPath, artworkPath: embeddedPath),
      fileExists: (path) => path == embeddedPath,
    );

    expect(metadata.artworkPath, embeddedPath);
  });

  test('playback status mapper follows player state', () {
    final track = _track();

    expect(
      macosPlaybackStatusForPlayerState(
        PlayerState(currentTrack: track, status: PlayerPlaybackStatus.loading),
      ),
      MacosNowPlayingPlaybackStatus.unknown,
    );
    expect(
      macosPlaybackStatusForPlayerState(
        PlayerState(currentTrack: track, status: PlayerPlaybackStatus.playing),
      ),
      MacosNowPlayingPlaybackStatus.playing,
    );
    expect(
      macosPlaybackStatusForPlayerState(
        PlayerState(currentTrack: track, status: PlayerPlaybackStatus.paused),
      ),
      MacosNowPlayingPlaybackStatus.paused,
    );

    for (final status in [
      PlayerPlaybackStatus.idle,
      PlayerPlaybackStatus.stopped,
      PlayerPlaybackStatus.completed,
      PlayerPlaybackStatus.error,
    ]) {
      expect(
        macosPlaybackStatusForPlayerState(
          PlayerState(currentTrack: track, status: status),
        ),
        MacosNowPlayingPlaybackStatus.stopped,
      );
    }

    expect(
      macosPlaybackStatusForPlayerState(const PlayerState.idle()),
      MacosNowPlayingPlaybackStatus.stopped,
    );
  });

  test(
    'service publishes metadata, status, and retries failed artwork',
    () async {
      const artworkPath = '/music/cover.jpg';
      final player = _FakePlayerService();
      final client = _FakeMacosNowPlayingClient()
        ..throwOnMetadataWithArtwork = true;
      final service = MacosNowPlayingService(
        playerService: player,
        onNext: () async {},
        onPrevious: () async {},
        client: client,
        fileExists: (path) => path == artworkPath,
        isMacOS: true,
      );

      await service.initialize();
      player.emit(
        PlayerState(
          currentTrack: _track(
            title: 'Title',
            artist: 'Artist',
            customArtworkPath: artworkPath,
          ),
          isPlaying: true,
          status: PlayerPlaybackStatus.playing,
        ),
      );

      await _waitUntil(
        () => client.statuses.contains(MacosNowPlayingPlaybackStatus.playing),
      );

      expect(client.metadataUpdates, hasLength(2));
      expect(client.metadataUpdates.first.artworkPath, artworkPath);
      expect(client.metadataUpdates.last.artworkPath, isNull);
      expect(client.metadataUpdates.last.title, 'Title');
      expect(client.metadataUpdates.last.artist, 'Artist');

      await service.dispose();
      await player.dispose();
    },
  );

  test(
    'service clears metadata and sets stopped for terminal states',
    () async {
      final player = _FakePlayerService();
      final client = _FakeMacosNowPlayingClient();
      final service = MacosNowPlayingService(
        playerService: player,
        onNext: () async {},
        onPrevious: () async {},
        client: client,
        fileExists: (_) => false,
        isMacOS: true,
      );

      await service.initialize();
      await _waitUntil(() => client.clearMetadataCalls == 1);
      player.emit(
        PlayerState(
          currentTrack: _track(),
          isPlaying: true,
          status: PlayerPlaybackStatus.playing,
        ),
      );
      await _waitUntil(() => client.metadataUpdates.isNotEmpty);

      player.emit(
        PlayerState(currentTrack: _track(), status: PlayerPlaybackStatus.error),
      );
      await _waitUntil(() => client.clearMetadataCalls == 2);

      expect(client.statuses.last, MacosNowPlayingPlaybackStatus.stopped);

      await service.dispose();
      await player.dispose();
    },
  );

  test('command events route to existing playback commands only', () async {
    var nextCalls = 0;
    var previousCalls = 0;
    final player = _FakePlayerService();
    final client = _FakeMacosNowPlayingClient();
    final service = MacosNowPlayingService(
      playerService: player,
      onNext: () async {
        nextCalls += 1;
      },
      onPrevious: () async {
        previousCalls += 1;
      },
      client: client,
      isMacOS: true,
    );

    await service.initialize();

    client
      ..addCommand(MacosNowPlayingCommand.play)
      ..addCommand(MacosNowPlayingCommand.pause)
      ..addCommand(MacosNowPlayingCommand.next)
      ..addCommand(MacosNowPlayingCommand.previous);

    await _waitUntil(() => previousCalls == 1);

    expect(player.playCalls, 1);
    expect(player.pauseCalls, 1);
    expect(player.playTrackCalls, 0);
    expect(nextCalls, 1);
    expect(previousCalls, 1);

    await service.dispose();
    await player.dispose();
  });

  test('command handling is serialized', () async {
    var nextCalls = 0;
    final player = _FakePlayerService();
    final client = _FakeMacosNowPlayingClient();
    final service = MacosNowPlayingService(
      playerService: player,
      onNext: () async {
        nextCalls += 1;
      },
      onPrevious: () async {},
      client: client,
      isMacOS: true,
    );

    player.playBlocker = Completer<void>();
    await service.initialize();

    client
      ..addCommand(MacosNowPlayingCommand.play)
      ..addCommand(MacosNowPlayingCommand.next);
    await _waitUntil(() => player.playCalls == 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(nextCalls, 0);

    player.playBlocker!.complete();
    await _waitUntil(() => nextCalls == 1);

    await service.dispose();
    await player.dispose();
  });
}

Track _track({
  String? title = 'Track',
  String? artist,
  String? album,
  String? albumArtist,
  String? artworkPath,
  String? customArtworkPath,
}) {
  final now = DateTime(2026);
  return Track(
    id: 1,
    filePath: '/music/track.mp3',
    title: title,
    artist: artist,
    album: album,
    albumArtist: albumArtist,
    artworkPath: artworkPath,
    customArtworkPath: customArtworkPath,
    addedAt: now,
    updatedAt: now,
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

final class _FakeMacosNowPlayingClient implements MacosNowPlayingClient {
  final StreamController<MacosNowPlayingCommand> _commandController =
      StreamController<MacosNowPlayingCommand>.broadcast();

  final List<MacosNowPlayingMetadata> metadataUpdates = [];
  final List<MacosNowPlayingPlaybackStatus> statuses = [];
  bool throwOnMetadataWithArtwork = false;
  int initializeCalls = 0;
  int clearMetadataCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<MacosNowPlayingCommand> get commandStream => _commandController.stream;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<void> updateMetadata(MacosNowPlayingMetadata metadata) async {
    metadataUpdates.add(metadata);
    if (throwOnMetadataWithArtwork && metadata.artworkPath != null) {
      throw StateError('artwork rejected');
    }
  }

  @override
  Future<void> setPlaybackStatus(MacosNowPlayingPlaybackStatus status) async {
    statuses.add(status);
  }

  @override
  Future<void> clearMetadata() async {
    clearMetadataCalls += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _commandController.close();
  }

  void addCommand(MacosNowPlayingCommand command) {
    _commandController.add(command);
  }
}

final class _FakePlayerService implements PlayerService {
  final StreamController<PlayerState> _controller =
      StreamController<PlayerState>.broadcast();

  int playCalls = 0;
  int pauseCalls = 0;
  int playTrackCalls = 0;
  Completer<void>? playBlocker;
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
    playTrackCalls += 1;
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    await playBlocker?.future;
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void emit(PlayerState state) {
    _state = state;
    _controller.add(state);
  }
}
