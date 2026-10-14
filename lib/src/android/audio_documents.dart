import 'package:flutter/services.dart';

import '../domain/models/audio_source_reference.dart';

final class AudioDocumentSelection {
  const AudioDocumentSelection(this.sources, {this.skipped = 0});
  final List<ContentUriAudioSource> sources;
  final int skipped;
}

final class AudioDocumentMetadata {
  const AudioDocumentMetadata(
      {this.name,
      this.title,
      this.artist,
      this.album,
      this.albumArtist,
      this.genre,
      this.duration,
      this.size,
      this.artwork});
  final String? name, title, artist, album, albumArtist, genre;
  final Duration? duration;
  final int? size;
  final Uint8List? artwork;
}

abstract interface class AudioDocuments {
  /// Null means the user cancelled. Every returned source has a persisted grant.
  Future<AudioDocumentSelection?> pickAudio();
  Future<AudioDocumentMetadata> readAudio(ContentUriAudioSource source);
}

final class AndroidAudioDocuments implements AudioDocuments {
  const AndroidAudioDocuments({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
                'dev.lunatuk.clever_music_player/audio_documents');
  final MethodChannel _channel;

  @override
  Future<AudioDocumentSelection?> pickAudio() async {
    final data = await _channel.invokeMapMethod<String, Object?>('pickAudio');
    if (data == null) return null;
    final uris = data['uris'];
    final skipped = data['skipped'];
    if (uris is! List || uris.length > 64 || skipped is! int || skipped < 0) {
      throw const FormatException('Некорректный результат выбора музыки.');
    }
    return AudioDocumentSelection(
        List.unmodifiable(uris.map((value) {
          if (value is! String) {
            throw const FormatException('Некорректный источник.');
          }
          return ContentUriAudioSource(value);
        }).toSet()),
        skipped: skipped);
  }

  @override
  Future<AudioDocumentMetadata> readAudio(ContentUriAudioSource source) async {
    final data = await _channel.invokeMapMethod<String, Object?>(
        'readAudio', {'uri': source.storageValue});
    if (data == null) throw const FormatException('Нет метаданных файла.');
    String? tag(String key) {
      final value = data[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final milliseconds = int.tryParse(tag('durationMs') ?? '');
    final size = data['size'];
    final artwork = data['artwork'];
    return AudioDocumentMetadata(
      name: tag('name'),
      title: tag('title'),
      artist: tag('artist'),
      album: tag('album'),
      albumArtist: tag('albumArtist'),
      genre: tag('genre'),
      duration: milliseconds != null && milliseconds > 0
          ? Duration(milliseconds: milliseconds)
          : null,
      size: size is int && size >= 0 ? size : null,
      artwork:
          artwork is Uint8List && artwork.length <= 256 * 1024 ? artwork : null,
    );
  }
}
