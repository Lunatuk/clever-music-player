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

final class AudioFolderPage {
  const AudioFolderPage(this.sources,
      {required this.visited, required this.done});
  final List<ContentUriAudioSource> sources;
  final int visited;
  final bool done;
}

/// Separate capability so single-document clients do not need folder support.
abstract interface class AudioDocumentFolders {
  Future<ContentUriAudioSource?> pickAudioFolder();
  Future<int> openAudioFolder(ContentUriAudioSource tree);
  Future<AudioFolderPage> readAudioFolderPage(int session);
  Future<void> closeAudioFolder(int session);
}

bool isAudioFolderUri(ContentUriAudioSource source) {
  final parts = source.uri.pathSegments;
  return parts.length == 2 && parts.first == 'tree' && parts.last.isNotEmpty;
}

final class AudioFolderAccess {
  const AudioFolderAccess({required this.readable, this.name});
  final bool readable;
  final String? name;
}

abstract interface class AudioDocumentFolderAccess {
  Future<List<ContentUriAudioSource>> listAudioFolderGrants();
  Future<AudioFolderAccess> inspectAudioFolder(ContentUriAudioSource tree);
}

final class AndroidAudioDocuments
    implements AudioDocuments, AudioDocumentFolders, AudioDocumentFolderAccess {
  const AndroidAudioDocuments({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
                'dev.lunatuk.clever_music_player/audio_documents');
  final MethodChannel _channel;

  @override
  Future<List<ContentUriAudioSource>> listAudioFolderGrants() async {
    final values =
        await _channel.invokeListMethod<Object?>('listAudioFolderGrants');
    if (values == null || values.length > 128) {
      throw const FormatException('Некорректный список папок.');
    }
    final sources = values.map((value) {
      if (value is! String) throw const FormatException('Некорректная папка.');
      final source = ContentUriAudioSource(value);
      if (!isAudioFolderUri(source)) {
        throw const FormatException('Некорректная папка.');
      }
      return source;
    }).toSet();
    return List.unmodifiable(sources);
  }

  @override
  Future<AudioFolderAccess> inspectAudioFolder(
      ContentUriAudioSource tree) async {
    if (!isAudioFolderUri(tree)) {
      throw const FormatException('Некорректная папка.');
    }
    final data = await _channel.invokeMapMethod<String, Object?>(
        'inspectAudioFolder', {'uri': tree.storageValue});
    final readable = data?['readable'], name = data?['name'];
    if (readable is! bool ||
        (name != null && (name is! String || name.length > 256))) {
      throw const FormatException('Некорректный доступ к папке.');
    }
    return AudioFolderAccess(
        readable: readable,
        name: name is String && name.trim().isNotEmpty ? name.trim() : null);
  }

  @override
  Future<ContentUriAudioSource?> pickAudioFolder() async {
    final data =
        await _channel.invokeMapMethod<String, Object?>('pickAudioFolder');
    if (data == null) return null;
    final value = data['uri'];
    if (value is! String) throw const FormatException('Некорректная папка.');
    final tree = ContentUriAudioSource(value);
    if (!isAudioFolderUri(tree)) {
      throw const FormatException('Некорректная папка.');
    }
    return tree;
  }

  @override
  Future<int> openAudioFolder(ContentUriAudioSource tree) async {
    if (!isAudioFolderUri(tree)) {
      throw const FormatException('Некорректная папка.');
    }
    final id = await _channel
        .invokeMethod<Object?>('openAudioFolder', {'uri': tree.storageValue});
    if (id is! int || id <= 0) {
      throw const FormatException('Некорректный обход.');
    }
    return id;
  }

  @override
  Future<AudioFolderPage> readAudioFolderPage(int session) async {
    final data = await _channel.invokeMapMethod<String, Object?>(
        'readAudioFolderPage', {'session': session});
    final uris = data?['uris'],
        visited = data?['visited'],
        done = data?['done'];
    if (uris is! List ||
        uris.length > 64 ||
        visited is! int ||
        visited < 0 ||
        visited > 100000 ||
        done is! bool) {
      throw const FormatException('Некорректный результат обхода.');
    }
    return AudioFolderPage(
        List.unmodifiable(uris.map((value) {
          if (value is! String) {
            throw const FormatException('Некорректный источник.');
          }
          return ContentUriAudioSource(value);
        }).toSet()),
        visited: visited,
        done: done);
  }

  @override
  Future<void> closeAudioFolder(int session) =>
      _channel.invokeMethod<void>('closeAudioFolder', {'session': session});

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
