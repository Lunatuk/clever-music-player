import 'dart:async';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/player/player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/smtc/smtc_platform_client.dart';
import 'package:clever_music_player/src/smtc/smtc_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('metadata mapper uses title and artist fallbacks', () {
    final metadata = smtcMetadataForTrack(
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
    expect(metadata.thumbnail, isNull);
  });

  test('metadata mapper prefers custom artwork over embedded artwork', () {
    const customPath = r'C:\music\custom cover.jpg';
    const embeddedPath = r'C:\music\embedded cover.jpg';
    final metadata = smtcMetadataForTrack(
      _track(
        customArtworkPath: customPath,
        artworkPath: embeddedPath,
      ),
      fileExists: (path) => path == customPath || path == embeddedPath,
    );

    expect(metadata.thumbnail, Uri.file(customPath).toString());
  });

  test('metadata mapper ignores missing artwork files', () {
    const customPath = r'C:\music\missing custom.jpg';
    const embeddedPath = r'C:\music\embedded cover.jpg';
    final metadata = smtcMetadataForTrack(
      _track(
        customArtworkPath: customPath,
        artworkPath: embeddedPath,
      ),
      fileExists: (path) => path == embeddedPath,
    );

    expect(metadata.thumbnail, Uri.file(embeddedPath).toString());
  });

  test('playback status mapper follows player state', () {
    final track = _track();

    expect(
      smtcStatusForPlayerState(
        PlayerState(currentTrack: track, status: PlayerPlaybackStatus.loading),
      ),
      SmtcPlaybackStatus.changing,
    );
    expect(
      smtcStatusForPlayerState(
        PlayerState(currentTrack: track, status: PlayerPlaybackStatus.playing),
      ),
      SmtcPlaybackStatus.playing,
    );
    expect(
      smtcStatusForPlayerState(
        PlayerState(currentTrack: track, status: PlayerPlaybackStatus.paused),
      ),
      SmtcPlaybackStatus.paused,
    );

    for (final status in [
      PlayerPlaybackStatus.idle,
      PlayerPlaybackStatus.stopped,
      PlayerPlaybackStatus.completed,
      PlayerPlaybackStatus.error,
    ]) {
      expect(
        smtcStatusForPlayerState(
          PlayerState(currentTrack: track, status: status),
        ),
        SmtcPlaybackStatus.stopped,
      );
    }

    expect(
      smtcStatusForPlayerState(const PlayerState.idle()),
      SmtcPlaybackStatus.stopped,
    );
  });

  test('timeline mapper clamps invalid positions and durations', () {
    final timeline = smtcTimelineForPlayerState(
      PlayerState(
        currentTrack: _track(),
        status: PlayerPlaybackStatus.playing,
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 3),
      ),
    );

    expect(timeline.start, Duration.zero);
    expect(timeline.end, const Duration(minutes: 3));
    expect(timeline.position, const Duration(minutes: 3));
    expect(timeline.minSeekTime, Duration.zero);
    expect(timeline.maxSeekTime, const Duration(minutes: 3));
  });

  test('non-Windows SMTC service is a no-op', () async {
    const service = NoopSmtcService();

    await service.initialize();
    await service.dispose();
  });

  test('service updates metadata, status, and retries failed artwork',
      () async {
    const artworkPath = r'C:\music\cover.jpg';
    final player = _FakePlayerService();
    final client = _FakeSmtcClient()..throwOnMetadataWithThumbnail = true;
    final service = WindowsSmtcService(
      playerService: player,
      onNext: () async {},
      onPrevious: () async {},
      client: client,
      fileExists: (path) => path == artworkPath,
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
        () => client.statuses.contains(SmtcPlaybackStatus.playing));

    expect(client.enableCalls, 0);
    expect(client.metadataUpdates, hasLength(2));
    expect(client.metadataUpdates.first.thumbnail, isNotNull);
    expect(client.metadataUpdates.last.thumbnail, isNull);
    expect(client.metadataUpdates.last.title, 'Title');
    expect(client.metadataUpdates.last.artist, 'Artist');
    expect(client.timelines, hasLength(1));

    await service.dispose();
    await player.dispose();
  });

  test('service clears metadata and disables SMTC for terminal states',
      () async {
    final player = _FakePlayerService();
    final client = _FakeSmtcClient();
    final service = WindowsSmtcService(
      playerService: player,
      onNext: () async {},
      onPrevious: () async {},
      client: client,
      fileExists: (_) => false,
    );

    await service.initialize();
    player.emit(
      PlayerState(
        currentTrack: _track(),
        isPlaying: true,
        status: PlayerPlaybackStatus.playing,
      ),
    );
    await _waitUntil(() => client.metadataUpdates.isNotEmpty);

    player.emit(
      PlayerState(
        currentTrack: _track(),
        status: PlayerPlaybackStatus.completed,
      ),
    );
    await _waitUntil(() => client.disableCalls == 1);

    expect(client.clearMetadataCalls, 1);
    expect(client.statuses.last, SmtcPlaybackStatus.stopped);

    await service.dispose();
    await player.dispose();
  });

  test('button events route to existing playback commands only', () async {
    var nextCalls = 0;
    var previousCalls = 0;
    final player = _FakePlayerService();
    final client = _FakeSmtcClient();
    final service = WindowsSmtcService(
      playerService: player,
      onNext: () async {
        nextCalls += 1;
      },
      onPrevious: () async {
        previousCalls += 1;
      },
      client: client,
      fileExists: (_) => false,
    );

    await service.initialize();

    client
      ..addButton(SmtcButton.play)
      ..addButton(SmtcButton.pause)
      ..addButton(SmtcButton.next)
      ..addButton(SmtcButton.previous)
      ..addButton(SmtcButton.stop)
      ..addButton(SmtcButton.fastForward);

    await _waitUntil(() => previousCalls == 1);

    expect(player.playCalls, 1);
    expect(player.pauseCalls, 1);
    expect(player.playTrackCalls, 0);
    expect(nextCalls, 1);
    expect(previousCalls, 1);

    await service.dispose();
    await player.dispose();
  });

  test('button command handling is serialized', () async {
    var nextCalls = 0;
    final player = _FakePlayerService();
    final client = _FakeSmtcClient();
    final service = WindowsSmtcService(
      playerService: player,
      onNext: () async {
        nextCalls += 1;
      },
      onPrevious: () async {},
      client: client,
      fileExists: (_) => false,
    );

    player.playBlocker = Completer<void>();
    await service.initialize();

    client
      ..addButton(SmtcButton.play)
      ..addButton(SmtcButton.next);
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
    filePath: r'C:\music\track.mp3',
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

final class _FakeSmtcClient implements SmtcPlatformClient {
  final StreamController<SmtcButton> _buttonController =
      StreamController<SmtcButton>.broadcast();

  final List<SmtcButtonConfig> configs = [];
  final List<SmtcMetadata> metadataUpdates = [];
  final List<SmtcTimeline> timelines = [];
  final List<SmtcPlaybackStatus> statuses = [];
  bool throwOnMetadataWithThumbnail = false;
  int enableCalls = 0;
  int disableCalls = 0;
  int clearMetadataCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<SmtcButton> get buttonPressStream => _buttonController.stream;

  @override
  Future<void> initialize(SmtcButtonConfig config) async {
    configs.add(config);
  }

  @override
  Future<void> enable() async {
    enableCalls += 1;
  }

  @override
  Future<void> disable() async {
    disableCalls += 1;
  }

  @override
  Future<void> updateMetadata(SmtcMetadata metadata) async {
    metadataUpdates.add(metadata);
    if (throwOnMetadataWithThumbnail && metadata.thumbnail != null) {
      throw StateError('thumbnail rejected');
    }
  }

  @override
  Future<void> updateTimeline(SmtcTimeline timeline) async {
    timelines.add(timeline);
  }

  @override
  Future<void> clearMetadata() async {
    clearMetadataCalls += 1;
  }

  @override
  Future<void> setPlaybackStatus(SmtcPlaybackStatus status) async {
    statuses.add(status);
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _buttonController.close();
  }

  void addButton(SmtcButton button) {
    _buttonController.add(button);
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
  Future<void> increaseVolume() async {}

  @override
  Future<void> decreaseVolume() async {}

  @override
  Future<void> toggleMute() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void emit(PlayerState state) {
    _state = state;
    _controller.add(state);
  }
}
