import 'dart:async';

import 'package:flutter/services.dart';

enum MacosNowPlayingCommand { play, pause, next, previous }

enum MacosNowPlayingPlaybackStatus { unknown, playing, paused, stopped }

final class MacosNowPlayingMetadata {
  const MacosNowPlayingMetadata({
    required this.title,
    required this.artist,
    this.album,
    this.albumArtist,
    this.artworkPath,
  });

  final String title;
  final String artist;
  final String? album;
  final String? albumArtist;
  final String? artworkPath;

  MacosNowPlayingMetadata withoutArtwork() {
    return MacosNowPlayingMetadata(
      title: title,
      artist: artist,
      album: album,
      albumArtist: albumArtist,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'albumArtist': albumArtist,
      'artworkPath': artworkPath,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MacosNowPlayingMetadata &&
            other.title == title &&
            other.artist == artist &&
            other.album == album &&
            other.albumArtist == albumArtist &&
            other.artworkPath == artworkPath;
  }

  @override
  int get hashCode {
    return Object.hash(title, artist, album, albumArtist, artworkPath);
  }
}

abstract interface class MacosNowPlayingClient {
  Stream<MacosNowPlayingCommand> get commandStream;

  Future<void> initialize();

  Future<void> updateMetadata(MacosNowPlayingMetadata metadata);

  Future<void> setPlaybackStatus(MacosNowPlayingPlaybackStatus status);

  Future<void> clearMetadata();

  Future<void> dispose();
}

final class MethodChannelMacosNowPlayingClient
    implements MacosNowPlayingClient {
  MethodChannelMacosNowPlayingClient({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel =
           methodChannel ??
           const MethodChannel('clever_music_player/macos_now_playing'),
       _eventChannel =
           eventChannel ??
           const EventChannel('clever_music_player/macos_now_playing_events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  @override
  Stream<MacosNowPlayingCommand> get commandStream {
    return _eventChannel.receiveBroadcastStream().asyncExpand((event) {
      final command = _commandForEvent(event);
      if (command == null) {
        return const Stream<MacosNowPlayingCommand>.empty();
      }
      return Stream<MacosNowPlayingCommand>.value(command);
    });
  }

  @override
  Future<void> initialize() {
    return _methodChannel.invokeMethod<void>('initialize');
  }

  @override
  Future<void> updateMetadata(MacosNowPlayingMetadata metadata) {
    return _methodChannel.invokeMethod<void>(
      'updateMetadata',
      metadata.toJson(),
    );
  }

  @override
  Future<void> setPlaybackStatus(MacosNowPlayingPlaybackStatus status) {
    return _methodChannel.invokeMethod<void>('setPlaybackStatus', status.name);
  }

  @override
  Future<void> clearMetadata() {
    return _methodChannel.invokeMethod<void>('clearMetadata');
  }

  @override
  Future<void> dispose() {
    return _methodChannel.invokeMethod<void>('dispose');
  }

  MacosNowPlayingCommand? _commandForEvent(Object? event) {
    return switch (event) {
      'play' => MacosNowPlayingCommand.play,
      'pause' => MacosNowPlayingCommand.pause,
      'next' => MacosNowPlayingCommand.next,
      'previous' => MacosNowPlayingCommand.previous,
      _ => null,
    };
  }
}
