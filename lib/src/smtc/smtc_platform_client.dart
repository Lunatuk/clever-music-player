import 'dart:async';

final class SmtcButtonConfig {
  const SmtcButtonConfig({
    required this.playEnabled,
    required this.pauseEnabled,
    required this.stopEnabled,
    required this.nextEnabled,
    required this.previousEnabled,
    required this.fastForwardEnabled,
    required this.rewindEnabled,
  });

  final bool playEnabled;
  final bool pauseEnabled;
  final bool stopEnabled;
  final bool nextEnabled;
  final bool previousEnabled;
  final bool fastForwardEnabled;
  final bool rewindEnabled;
}

enum SmtcButton {
  play,
  pause,
  next,
  previous,
  fastForward,
  rewind,
  stop,
  record,
  channelUp,
  channelDown,
}

enum SmtcPlaybackStatus {
  closed,
  changing,
  stopped,
  playing,
  paused,
}

final class SmtcMetadata {
  const SmtcMetadata({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.thumbnail,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? thumbnail;

  SmtcMetadata withoutThumbnail() {
    return SmtcMetadata(
      title: title,
      artist: artist,
      album: album,
      albumArtist: albumArtist,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SmtcMetadata &&
            other.title == title &&
            other.artist == artist &&
            other.album == album &&
            other.albumArtist == albumArtist &&
            other.thumbnail == thumbnail;
  }

  @override
  int get hashCode {
    return Object.hash(title, artist, album, albumArtist, thumbnail);
  }
}

final class SmtcTimeline {
  const SmtcTimeline({
    required this.start,
    required this.end,
    required this.position,
    required this.minSeekTime,
    required this.maxSeekTime,
  });

  final Duration start;
  final Duration end;
  final Duration position;
  final Duration minSeekTime;
  final Duration maxSeekTime;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SmtcTimeline &&
            other.start == start &&
            other.end == end &&
            other.position == position &&
            other.minSeekTime == minSeekTime &&
            other.maxSeekTime == maxSeekTime;
  }

  @override
  int get hashCode {
    return Object.hash(start, end, position, minSeekTime, maxSeekTime);
  }
}

abstract interface class SmtcPlatformClient {
  Stream<SmtcButton> get buttonPressStream;

  Future<void> initialize(SmtcButtonConfig config);

  Future<void> enable();

  Future<void> disable();

  Future<void> updateMetadata(SmtcMetadata metadata);

  Future<void> updateTimeline(SmtcTimeline timeline);

  Future<void> clearMetadata();

  Future<void> setPlaybackStatus(SmtcPlaybackStatus status);

  Future<void> dispose();
}
