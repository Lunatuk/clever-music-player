import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../data/drift/app_database.dart';
import '../domain/models/audio_document_identity.dart';
import '../domain/models/audio_source_reference.dart';
import '../library/artwork_cache_service.dart';
import 'audio_documents.dart';

/// Bump when native reading, source comments, parsing or thumbnail rules change.
const androidMetadataReaderVersion = 1;

abstract interface class AndroidImportMetadataCache {
  Future<CachedAndroidAudio?> lookup(AudioDocumentRevision revision);
  Future<void> invalidateSource(ContentUriAudioSource source);

  /// The callback must use the same database as the cache. Cache rows and track
  /// updates commit together. A cache-write failure rolls both back explicitly.
  Future<T> commit<T>(
      List<CachedAndroidAudio> entries, Future<T> Function() importTracks);
}

final class AndroidMetadataCacheWriteFailure implements Exception {
  const AndroidMetadataCacheWriteFailure();
}

final class CachedAndroidAudio {
  const CachedAndroidAudio(this.revision, this.metadata, this.artwork);
  factory CachedAndroidAudio.fromRead(AudioDocumentRevision revision,
          AudioDocumentMetadata metadata, CachedArtwork? artwork) =>
      CachedAndroidAudio(
          revision,
          AudioDocumentMetadata(
              name: metadata.name,
              size: metadata.size,
              title: metadata.title,
              artist: metadata.artist,
              album: metadata.album,
              albumArtist: metadata.albumArtist,
              genre: metadata.genre,
              duration: metadata.duration,
              trackNumber: metadata.trackNumber,
              discNumber: metadata.discNumber,
              year: metadata.year,
              sourceComments: metadata.sourceComments == null
                  ? null
                  : List.unmodifiable(metadata.sourceComments!)),
          artwork);
  final AudioDocumentRevision revision;
  final AudioDocumentMetadata metadata;
  final CachedArtwork? artwork;

  String encode() {
    final value = jsonEncode({
      'format': 1,
      'title': metadata.title,
      'artist': metadata.artist,
      'album': metadata.album,
      'albumArtist': metadata.albumArtist,
      'genre': metadata.genre,
      'durationMs': metadata.duration?.inMilliseconds,
      'trackNumber': metadata.trackNumber,
      'discNumber': metadata.discNumber,
      'year': metadata.year,
      'sourceComments': metadata.sourceComments,
      'artwork': artwork == null
          ? null
          : {
              'path': artwork!.path,
              'hash': artwork!.hash,
              'mime': artwork!.mimeType
            },
    });
    if (value.length > 262144) throw const FormatException('Cache too large');
    return value;
  }

  static CachedAndroidAudio? decode(
      AudioDocumentRevision revision, String text) {
    if (text.length > 262144) return null;
    try {
      final value = jsonDecode(text);
      if (value is! Map || value['format'] != 1) return null;
      for (final key in ['title', 'artist', 'album', 'albumArtist', 'genre']) {
        final tag = value[key];
        if (tag != null && (tag is! String || tag.length > 16384)) return null;
      }
      for (final key in ['durationMs', 'trackNumber', 'discNumber', 'year']) {
        final number = value[key];
        if (number != null &&
            (number is! int || number <= 0 || number > 8640000000000000)) {
          return null;
        }
      }
      final comments = value['sourceComments'];
      // Unknown/partial comment reads never qualify for this cache.
      if (comments is! List ||
          comments.length > 32 ||
          comments.any((v) => v is! String || v.length > 4096)) {
        return null;
      }
      CachedArtwork? artwork;
      final cover = value['artwork'];
      if (cover != null) {
        if (cover is! Map ||
            cover['path'] is! String ||
            (cover['path'] as String).isEmpty ||
            (cover['path'] as String).length > 4096 ||
            cover['hash'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(cover['hash'] as String) ||
            (cover['mime'] != null && cover['mime'] != 'image/webp')) {
          return null;
        }
        artwork = CachedArtwork(
            path: cover['path'] as String,
            hash: cover['hash'] as String,
            mimeType: cover['mime'] as String?);
      }
      return CachedAndroidAudio(
          revision,
          AudioDocumentMetadata(
              name: revision.name,
              size: revision.size,
              title: value['title'] as String?,
              artist: value['artist'] as String?,
              album: value['album'] as String?,
              albumArtist: value['albumArtist'] as String?,
              genre: value['genre'] as String?,
              duration: value['durationMs'] == null
                  ? null
                  : Duration(milliseconds: value['durationMs'] as int),
              trackNumber: value['trackNumber'] as int?,
              discNumber: value['discNumber'] as int?,
              year: value['year'] as int?,
              sourceComments: List.unmodifiable(comments.cast<String>())),
          artwork);
    } on Object {
      return null;
    }
  }
}

final class DriftAndroidImportMetadataCache
    implements AndroidImportMetadataCache {
  const DriftAndroidImportMetadataCache(this.database);
  final AppDatabase database;

  @override
  Future<void> invalidateSource(ContentUriAudioSource source) async {
    final identity = audioDocumentIdentity(source.storageValue);
    if (identity == null) return;
    await (database.delete(database.androidAudioCaches)
          ..where((t) =>
              t.authority.equals(identity.authority) &
              t.documentId.equals(identity.documentId)))
        .go();
  }

  @override
  Future<CachedAndroidAudio?> lookup(AudioDocumentRevision revision) async {
    final table = database.androidAudioCaches;
    final row = await (database.select(table)
          ..where((t) =>
              t.authority.equals(revision.authority) &
              t.documentId.equals(revision.documentId)))
        .getSingleOrNull();
    if (row == null ||
        row.readerVersion != androidMetadataReaderVersion ||
        row.name != revision.name ||
        row.sizeBytes != revision.size ||
        row.modifiedMs != revision.modifiedMs) {
      return null;
    }
    final cached = CachedAndroidAudio.decode(revision, row.payload);
    final cover = cached?.artwork;
    if (cover != null) {
      final stat = await File(cover.path).stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) return null;
    }
    return cached;
  }

  @override
  Future<T> commit<T>(List<CachedAndroidAudio> entries,
          Future<T> Function() importTracks) =>
      database.transaction(() async {
        final result = await importTracks();
        try {
          await database.batch((batch) {
            for (final entry in entries) {
              batch.insert(
                  database.androidAudioCaches,
                  AndroidAudioCachesCompanion.insert(
                      authority: entry.revision.authority,
                      documentId: entry.revision.documentId,
                      readerVersion: androidMetadataReaderVersion,
                      name: entry.revision.name,
                      sizeBytes: entry.revision.size,
                      modifiedMs: entry.revision.modifiedMs,
                      payload: entry.encode()),
                  mode: InsertMode.insertOrReplace);
            }
          });
        } on Object {
          throw const AndroidMetadataCacheWriteFailure();
        }
        return result;
      });
}
