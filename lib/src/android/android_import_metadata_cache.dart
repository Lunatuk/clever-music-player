import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../data/drift/app_database.dart';
import '../domain/models/audio_document_identity.dart';
import '../domain/models/audio_source_reference.dart';
import '../domain/repositories/track_repository.dart';
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

/// An optional bounded prefetch. Provider inspection remains per document.
abstract interface class AndroidImportMetadataCachePages {
  Future<AndroidMetadataCachePage> prepareSources(
      List<ContentUriAudioSource> sources);
}

final class AndroidCacheLookupResult {
  const AndroidCacheLookupResult(this.value,
      {this.decodeUs = 0, this.artworkStatUs = 0});
  final CachedAndroidAudio? value;
  final int decodeUs, artworkStatUs;
}

final class AndroidMetadataCachePage {
  AndroidMetadataCachePage(
      Map<AudioDocumentIdentity, AndroidAudioCacheRow> rows,
      {required this.databaseUs,
      required this.databaseQueries})
      : _rows = Map.unmodifiable(rows);
  final Map<AudioDocumentIdentity, AndroidAudioCacheRow> _rows;
  final int databaseUs, databaseQueries;

  bool mayContain(ContentUriAudioSource source) {
    final identity = audioDocumentIdentity(source.storageValue);
    return identity != null &&
        _rows[identity]?.readerVersion == androidMetadataReaderVersion;
  }

  /// Only a candidate. It still needs a fresh native access/revision proof and
  /// a thumbnail check before it can be used as an import result.
  AndroidCacheLookupResult candidate(ContentUriAudioSource source) {
    final row = _rows[audioDocumentIdentity(source.storageValue)];
    if (row == null || row.readerVersion != androidMetadataReaderVersion) {
      return const AndroidCacheLookupResult(null);
    }
    final timer = Stopwatch()..start();
    final revision = AudioDocumentRevision(
        authority: row.authority,
        documentId: row.documentId,
        name: row.name,
        size: row.sizeBytes,
        modifiedMs: row.modifiedMs);
    return AndroidCacheLookupResult(
        CachedAndroidAudio.decode(revision, row.payload),
        decodeUs: timer.elapsedMicroseconds);
  }

  Future<AndroidCacheLookupResult> lookup(AudioDocumentRevision revision) =>
      _resolveCachedAudio(
          revision,
          _rows[(
            authority: revision.authority,
            documentId: revision.documentId
          )]);
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
    implements AndroidImportMetadataCache, AndroidImportMetadataCachePages {
  const DriftAndroidImportMetadataCache(this.database);
  final AppDatabase database;

  @override
  Future<AndroidMetadataCachePage> prepareSources(
      List<ContentUriAudioSource> sources) async {
    if (sources.length > TrackImportRepository.maxBatchSize) {
      throw ArgumentError.value(sources.length, 'sources.length');
    }
    final identities = sources
        .map((source) => audioDocumentIdentity(source.storageValue))
        .nonNulls
        .toSet();
    if (identities.isEmpty) {
      return AndroidMetadataCachePage({}, databaseUs: 0, databaseQueries: 0);
    }
    final timer = Stopwatch()..start();
    final table = database.androidAudioCaches;
    final byAuthority = <String, List<String>>{};
    for (final id in identities) {
      (byAuthority[id.authority] ??= []).add(id.documentId);
    }
    final rows = await (database.select(table)
          ..where((t) {
            final matches = byAuthority.entries
                .map((group) =>
                    t.authority.equals(group.key) &
                    t.documentId.isIn(group.value))
                .reduce((left, right) => left | right);
            return matches & t.payload.length.isSmallerOrEqualValue(262144);
          }))
        .get();
    return AndroidMetadataCachePage({
      for (final row in rows)
        (authority: row.authority, documentId: row.documentId): row,
    }, databaseUs: timer.elapsedMicroseconds, databaseQueries: 1);
  }

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
    return (await _resolveCachedAudio(revision, row)).value;
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

Future<AndroidCacheLookupResult> _resolveCachedAudio(
    AudioDocumentRevision revision, AndroidAudioCacheRow? row) async {
  if (row == null ||
      row.readerVersion != androidMetadataReaderVersion ||
      row.name != revision.name ||
      row.sizeBytes != revision.size ||
      row.modifiedMs != revision.modifiedMs) {
    return const AndroidCacheLookupResult(null);
  }
  final decodeTimer = Stopwatch()..start();
  final cached = CachedAndroidAudio.decode(revision, row.payload);
  final decodeUs = decodeTimer.elapsedMicroseconds;
  final cover = cached?.artwork;
  if (cover != null) {
    final statTimer = Stopwatch()..start();
    final stat = await File(cover.path).stat();
    final statUs = statTimer.elapsedMicroseconds;
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
      return AndroidCacheLookupResult(null,
          decodeUs: decodeUs, artworkStatUs: statUs);
    }
    return AndroidCacheLookupResult(cached,
        decodeUs: decodeUs, artworkStatUs: statUs);
  }
  return AndroidCacheLookupResult(cached, decodeUs: decodeUs);
}
