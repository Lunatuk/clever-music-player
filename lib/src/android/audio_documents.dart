import 'package:flutter/services.dart';

import '../domain/models/audio_source_reference.dart';
import 'audio_document_inspection.dart';
export 'audio_document_inspection.dart';

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
      this.artwork,
      this.trackNumber,
      this.discNumber,
      this.year,
      this.sourceComments,
      this.readTimings,
      this.cacheRevision});
  final String? name, title, artist, album, albumArtist, genre;
  final Duration? duration;
  final int? size, trackNumber, discNumber, year;
  final Uint8List? artwork;

  /// null: no reliable read; empty: comments were read and absent.
  final List<String>? sourceComments;
  final AudioDocumentReadTimings? readTimings;

  /// Supplied only after complete reading with unchanged provider stamps.
  final AudioDocumentRevision? cacheRevision;
}

/// Optional native measurements; these are subsets of the Dart channel time.
final class AudioDocumentReadTimings {
  const AudioDocumentReadTimings(
      {required this.totalUs,
      required this.queryUs,
      required this.sourceUs,
      required this.tagsUs,
      required this.artworkUs});
  final int totalUs, queryUs, sourceUs, tagsUs, artworkUs;

  static AudioDocumentReadTimings? parse(Object? value) {
    if (value is! Map || value['version'] != 1) return null;
    const keys = ['totalUs', 'queryUs', 'sourceUs', 'tagsUs', 'artworkUs'];
    for (final key in keys) {
      final time = value[key];
      if (time is! int || time < 0 || time > 3600000000) return null;
    }
    final total = value['totalUs'] as int;
    if (keys.skip(1).fold<int>(0, (sum, key) => sum + (value[key] as int)) >
        total) {
      return null;
    }
    return AudioDocumentReadTimings(
        totalUs: total,
        queryUs: value['queryUs'] as int,
        sourceUs: value['sourceUs'] as int,
        tagsUs: value['tagsUs'] as int,
        artworkUs: value['artworkUs'] as int);
  }
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
    implements
        AudioDocuments,
        AudioDocumentFolders,
        AudioDocumentFolderAccess,
        AudioDocumentInspection,
        ProfiledAudioDocumentInspection,
        BatchedAudioDocumentInspection {
  const AndroidAudioDocuments({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
                'dev.lunatuk.clever_music_player/audio_documents');
  final MethodChannel _channel;

  @override
  Future<AudioInspectionBatchResult> inspectAudioBatch(
      int batch, List<AudioInspectionBatchRequest> items) async {
    AudioInspectionBatchRequest.validate(batch, items);
    final frozen = List<AudioInspectionBatchRequest>.unmodifiable(items);
    final value = await _channel.invokeMethod<Object?>('inspectAudioBatch', {
      'batch': batch,
      'items': [for (final item in frozen) item.message()]
    });
    return AudioInspectionBatchResult.parse(value, frozen);
  }

  @override
  Future<void> cancelAudioInspectionBatch(int batch) => _channel
      .invokeMethod<void>('cancelAudioInspectionBatch', {'batch': batch});

  @override
  Future<AudioDocumentRevision?> inspectAudio(
          ContentUriAudioSource source) async =>
      (await inspectProfiledAudio(source)).revision;

  @override
  Future<AudioDocumentInspectionResult> inspectProfiledAudio(
      ContentUriAudioSource source) async {
    final value = await _channel
        .invokeMethod<Object?>('inspectAudio', {'uri': source.storageValue});
    return AudioDocumentInspectionResult(AudioDocumentRevision.parse(value),
        timings: AudioDocumentInspectionTimings.parse(
            value is Map ? value['inspectionTimings'] : null));
  }

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

    int? number(String key, int maximum) {
      final text = tag(key);
      if (text == null || text.length > 32) return null;
      final value = int.tryParse(text.split('/').first);
      return value != null && value > 0 && value <= maximum ? value : null;
    }

    final milliseconds = int.tryParse(tag('durationMs') ?? '');
    final size = data['size'];
    final artwork = data['artwork'];
    final rawComments = data['sourceComments'];
    final comments = rawComments is List &&
            rawComments.length <= 32 &&
            rawComments
                .every((value) => value is String && value.length <= 4096)
        ? List<String>.unmodifiable(rawComments.cast<String>())
        : null;
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
      trackNumber: number('trackNumber', 1000000),
      discNumber: number('discNumber', 1000000),
      year: number('year', 9999),
      sourceComments: comments,
      readTimings: AudioDocumentReadTimings.parse(data['readTimings']),
      cacheRevision: AudioDocumentRevision.parse(data['cacheRevision']),
      artwork:
          artwork is Uint8List && artwork.length <= 256 * 1024 ? artwork : null,
    );
  }
}
