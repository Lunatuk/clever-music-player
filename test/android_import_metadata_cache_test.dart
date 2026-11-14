import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clever_music_player/src/android/android_folder_bookmarks.dart';
import 'package:clever_music_player/src/android/android_import_controller.dart';
import 'package:clever_music_player/src/android/android_import_metadata_cache.dart';
import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/track_repository.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/metadata_enrichment.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('persistent Android metadata cache', () {
    late _Fixture f;
    setUp(() async => f = await _Fixture.create());
    tearDown(() => f.close());

    test('repeat skips actual metadata and artwork calls for 130 documents',
        () async {
      f.documents.count = 130;
      await f.importer.importFolder();
      expect(f.documents.reads, 130);
      expect(f.artwork.calls, 130);
      expect(await f.cacheCount(), 130);
      expect(f.profile[DiagnosticField.metadataCacheWrites], 130);
      final before = await f.rows();
      f.documents.reads = f.artwork.calls = 0;
      await f.importer.importFolder();
      expect(f.documents.reads, 0);
      expect(f.artwork.calls, 0);
      expect(f.profile[DiagnosticField.metadataReads], 0);
      expect(f.profile[DiagnosticField.metadataCacheHits], 130);
      expect(f.profile[DiagnosticField.metadataCacheWrites], 0);
      expect(f.profile[DiagnosticField.importRows], 130);
      expect(f.importer.message, contains('Без повторного чтения: 130'));
      expect({for (final t in await f.rows()) t.filePath: t.id},
          {for (final t in before) t.filePath: t.id});
    });

    test('reliable absence of artwork is cached without repeated reader work',
        () async {
      f.documents.noArtwork = true;
      await f.importer.importFolder();
      expect(await f.cacheCount(), 3);
      f.documents.reads = f.artwork.calls = 0;
      await f.importer.importFolder();
      expect(f.documents.reads, 0);
      expect(f.artwork.calls, 0);
      expect((await f.rows()).every((t) => t.artworkPath == null), isTrue);
    });

    test('cache survives database/controller restart', () async {
      await f.importer.importFolder();
      await f.restart();
      f.documents.reads = f.artwork.calls = 0;
      await f.importer.importFolder();
      expect(f.profile[DiagnosticField.metadataCacheHits], 3);
      expect(f.documents.reads, 0);
      expect(f.artwork.calls, 0);
    });

    for (final change in ['size', 'modified', 'name', 'document', 'provider']) {
      test('changed $change causes an ordinary read of only that document',
          () async {
        await f.importer.importFolder();
        final old = f.documents.revision(1);
        f.documents.revisions[1] = AudioDocumentRevision(
            authority: change == 'provider' ? 'other.documents' : old.authority,
            documentId: change == 'document' ? 'different-id' : old.documentId,
            name: change == 'name' ? 'renamed.m4a' : old.name,
            size: old.size + (change == 'size' ? 1 : 0),
            modifiedMs: old.modifiedMs + (change == 'modified' ? 1 : 0));
        f.documents.reads = f.artwork.calls = 0;
        await f.importer.importFolder();
        expect(f.documents.reads, 1);
        expect(f.artwork.calls, 1);
        expect(f.profile[DiagnosticField.metadataCacheHits], 2);
      });
    }

    test('new document is read while old ones reuse their snapshots', () async {
      await f.importer.importFolder();
      f.documents.count = 4;
      f.documents.reads = 0;
      await f.importer.importFolder();
      expect(f.documents.reads, 1);
      expect(f.profile[DiagnosticField.metadataCacheHits], 3);
      expect(await f.rows(), hasLength(4));
    });

    test('missing revision and partial reads never become successful cache',
        () async {
      f.documents.unsupported.add(1);
      await f.importer.importFolder();
      expect(await f.cacheCount(), 2);
      f.documents.reads = 0;
      await f.importer.importFolder();
      expect(f.documents.reads, 1);
      expect(f.profile[DiagnosticField.metadataCacheHits], 2);
    });

    test('unknown comments are retried and do not clear a former source link',
        () async {
      f.documents.unknownComments = true;
      await f.importer.importFolder();
      expect(await f.cacheCount(), 0);
      f.documents.unknownComments = false;
      await f.importer.importFolder();
      expect(await f.cacheCount(), 3);
      expect(
          await f.database
              .customSelect('SELECT * FROM external_track_refs')
              .get(),
          hasLength(3));
    });

    test('removed thumbnail is rebuilt and cached again', () async {
      await f.importer.importFolder();
      final track = (await f.rows())[1];
      await File(track.artworkPath!).delete();
      f.documents.reads = f.artwork.calls = 0;
      await f.importer.importFolder();
      expect(f.documents.reads, 1);
      expect(f.artwork.calls, 1);
      expect(await File(track.artworkPath!).exists(), isTrue);
      expect(f.profile[DiagnosticField.metadataCacheHits], 2);
    });

    for (final invalid in [
      'old-reader',
      'bad-json',
      'oversized',
      'bad-cover',
      'unknown-comments'
    ]) {
      test('$invalid snapshot falls back safely', () async {
        await f.importer.importFolder();
        final table = await f.database
            .customSelect('SELECT payload FROM android_audio_caches LIMIT 1')
            .getSingle();
        var payload = table.read<String>('payload');
        if (invalid == 'bad-json') payload = '{broken';
        if (invalid == 'oversized') payload = 'x' * 262145;
        if (invalid == 'bad-cover' || invalid == 'unknown-comments') {
          final map = jsonDecode(payload) as Map<String, Object?>;
          if (invalid == 'bad-cover') map['artwork'] = {'path': 3};
          if (invalid == 'unknown-comments') map['sourceComments'] = null;
          payload = jsonEncode(map);
        }
        await f.database.customStatement(
            'UPDATE android_audio_caches SET payload = ?, reader_version = ? WHERE document_id = ?',
            [
              payload,
              invalid == 'old-reader' ? 0 : androidMetadataReaderVersion,
              f.documents.revision(0).documentId
            ]);
        f.documents.reads = 0;
        await f.importer.importFolder();
        expect(f.documents.reads, 1);
        expect(f.profile[DiagnosticField.errorCount], 0);
      });
    }

    test('forced refresh bypasses matching stamps and replaces raw metadata',
        () async {
      await f.importer.importFolder();
      f.documents.title = 'Changed without timestamp';
      f.documents.reads = 0;
      await f.importer
          .refreshFolder(SavedAudioFolder(f.documents.tree), forceRead: true);
      expect(f.documents.reads, 3);
      expect(f.profile[DiagnosticField.metadataCacheHits], 0);
      expect(f.profile[DiagnosticField.metadataForceRead], isTrue);
      f.documents.reads = 0;
      await f.importer.importFolder();
      expect(f.documents.reads, 0);
      expect(
          (await f.rows()).every((t) => t.title == f.documents.title), isTrue);
    });

    test('forced partial read cannot resurrect the former successful snapshot',
        () async {
      await f.importer.importFolder();
      f.documents.unknownComments = true;
      await f.importer
          .refreshFolder(SavedAudioFolder(f.documents.tree), forceRead: true);
      expect(await f.cacheCount(), 0);
      f.documents.reads = 0;
      await f.importer.importFolder();
      expect(f.documents.reads, 3);
      expect(f.profile[DiagnosticField.metadataCacheHits], 0);
    });

    test('empty cached thumbnail triggers reconstruction', () async {
      await f.importer.importFolder();
      final track = (await f.rows()).first;
      await File(track.artworkPath!).writeAsBytes([]);
      f.documents.reads = 0;
      await f.importer.importFolder();
      expect(f.documents.reads, 1);
      expect(await File(track.artworkPath!).length(), greaterThan(0));
    });

    test(
        'cached raw tags preserve manual clears, cover, user state and playlist',
        () async {
      await f.importer.importFolder();
      final track = (await f.rows()).first;
      await f.repositories.tracks.updateTrackMetadata(TrackMetadataUpdate(
          trackId: track.id!,
          title: 'Manual title',
          artist: null,
          album: null,
          updatedAt: DateTime(2026)));
      await f.repositories.tracks.updateCustomArtwork(
          trackId: track.id!,
          path: '/custom',
          hash: 'manual',
          mimeType: 'image/png',
          updatedAt: DateTime(2026));
      await f.repositories.trackUserState.upsertState(TrackUserState(
          trackId: track.id!, isFavorite: true, updatedAt: DateTime(2026)));
      await f.database.customStatement(
          "INSERT INTO playlists (id,name,created_at,updated_at) VALUES (50,'Keep',1,1)");
      await f.database.customStatement(
          'INSERT INTO playlist_tracks (playlist_id,track_id,position,added_at) VALUES (50,?,0,1)',
          [track.id!]);
      await f.importer.importFolder();
      final after = (await f.repositories.tracks.findById(track.id!))!;
      expect(after.title, 'Manual title');
      expect(after.artist, isNull);
      expect(after.album, isNull);
      expect(after.customArtworkPath, '/custom');
      expect(
          (await f.repositories.trackUserState.findByTrackId(track.id!))!
              .isFavorite,
          isTrue);
      expect(
          await f.database.customSelect('SELECT * FROM playlist_tracks').get(),
          hasLength(1));
      expect(
          await f.database
              .customSelect('SELECT * FROM external_track_refs')
              .get(),
          hasLength(3));
      expect(f.profile[DiagnosticField.metadataReads], 0);
    });

    test('other tree grants reuse the same provider/document identity',
        () async {
      await f.importer.importFolder();
      f.documents.treeName = 'nested';
      f.documents.reads = 0;
      await f.importer.importFolder();
      expect(f.documents.reads, 0);
      expect(f.profile[DiagnosticField.metadataCacheHits], 3);
      expect(await f.cacheCount(), 3);
    });

    test('permission failure cannot authorize a cached import', () async {
      await f.importer.importFolder();
      f.documents.revoked.add(1);
      await f.importer.importFolder();
      expect(f.profile[DiagnosticField.importRows], 2);
      expect(f.profile[DiagnosticField.errorCount], 1);
      expect(f.profile[DiagnosticField.metadataCacheHits], 2);
    });

    test('cache write failure rolls back and retries music without cache',
        () async {
      await f.database.customStatement(
          "CREATE TRIGGER reject_cache BEFORE INSERT ON android_audio_caches BEGIN SELECT RAISE(ABORT, 'cache unavailable'); END");
      await f.importer.importFolder();
      expect(await f.rows(), hasLength(3));
      expect(await f.cacheCount(), 0);
      expect(f.profile[DiagnosticField.metadataCacheFailures], 1);
      expect(f.profile[DiagnosticField.importRows], 3);
      expect(f.profile[DiagnosticField.errorCount], 0);
    });

    test('track write failure cannot publish a cache entry', () async {
      f.documents.count = 1;
      await f.database.customStatement(
          "CREATE TRIGGER reject_track BEFORE INSERT ON tracks BEGIN SELECT RAISE(ABORT, 'track unavailable'); END");
      await f.importer.importFolder();
      expect(await f.cacheCount(), 0);
      expect(await f.rows(), isEmpty);
      expect(f.profile[DiagnosticField.errorCount], 1);
    });

    test('failed cache lookup disables it for run and imports readable music',
        () async {
      await f.importer.importFolder();
      await f.database.customStatement('DROP TABLE android_audio_caches');
      f.documents.reads = 0;
      await f.importer.importFolder();
      expect(f.documents.reads, 3);
      expect(f.profile[DiagnosticField.metadataCacheFailures], 1);
      expect(f.profile[DiagnosticField.errorCount], 0);
    });

    test('cancel discards late read and commits only prepared cache entries',
        () async {
      final late = Completer<AudioDocumentMetadata>();
      f.documents.readAction =
          (i) => i == 1 ? late.future : Future.value(f.documents.metadata(i));
      final running = f.importer.importFolder();
      await _until(() => f.documents.reads == 2);
      await f.importer.cancel();
      late.complete(f.documents.metadata(1));
      await running;
      expect(await f.rows(), hasLength(1));
      expect(await f.cacheCount(), 1);
      expect(f.profile[DiagnosticField.importCancelled], isTrue);
    });

    test('close during pending cache hit drains it without late writes',
        () async {
      await f.importer.importFolder();
      final late = Completer<AudioDocumentRevision?>();
      f.documents.inspectAction =
          (i) => i == 1 ? late.future : Future.value(f.documents.revision(i));
      f.documents.inspections = 0;
      final running = f.importer.importFolder();
      await _until(() => f.documents.inspections == 2);
      var closed = false;
      final closing = f.importer.close().then((_) => closed = true);
      expect(closed, isFalse);
      late.complete(f.documents.revision(1));
      await running;
      await closing;
      expect(f.profile[DiagnosticField.importRows], 1);
      expect(await f.cacheCount(), 3);
    });

    test('close drains the transaction containing both tracks and snapshots',
        () async {
      await f.importer.close();
      f.importer.dispose();
      final cache = _GatedCache(DriftAndroidImportMetadataCache(f.database));
      f.importer = AndroidImportController(
          documents: f.documents,
          imports: f.repositories.tracks as TrackImportRepository,
          artworkCache: f.artwork,
          metadataCache: cache,
          diagnostics: f.diagnostics);
      final importing = f.importer.importFolder();
      await cache.entered.future;
      var closed = false;
      final closing = f.importer.close().then((_) => closed = true);
      expect(closed, isFalse);
      cache.release.complete();
      await importing;
      await closing;
      expect(await f.rows(), hasLength(3));
      expect(await f.cacheCount(), 3);
    });

    test('failed artwork write is retried instead of caching a missing cover',
        () async {
      f.artwork.fail = true;
      await f.importer.importFolder();
      expect(await f.rows(), hasLength(3));
      expect(await f.cacheCount(), 0);
      f.artwork.fail = false;
      await f.importer.importFolder();
      expect(await f.cacheCount(), 3);
    });
  });

  const channel = MethodChannel('test/document-revisions');
  const documents = AndroidAudioDocuments(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
      'optional revision messages are bounded and malformed ones mean no cache',
      () async {
    final valid = {
      'version': 1,
      'authority': 'com.android.externalstorage.documents',
      'documentId': 'primary:Music/track.m4a',
      'name': 'track.m4a',
      'size': 100,
      'modifiedMs': 1000
    };
    final source = ContentUriAudioSource(
        'content://com.android.externalstorage.documents/document/song');
    messenger.setMockMethodCallHandler(channel, (_) async => valid);
    expect((await documents.inspectAudio(source))!.size, 100);
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
              'name': 'track.m4a',
              'size': 100,
              'sourceComments': [],
              'cacheRevision': valid
            });
    expect((await documents.readAudio(source)).cacheRevision!.documentId,
        valid['documentId']);
    for (final value in [
      null,
      [],
      {...valid, 'version': 2},
      {...valid, 'size': 0},
      {...valid, 'modifiedMs': null},
      {...valid, 'modifiedMs': -1},
      {...valid, 'modifiedMs': 1.5},
      {...valid, 'documentId': ''},
      {...valid, 'name': 'x' * 4097}
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      expect(await documents.inspectAudio(source), isNull);
    }
  });
}

Future<void> _until(bool Function() check) async {
  for (var i = 0; i < 200 && !check(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(check(), isTrue);
}

final class _GatedCache implements AndroidImportMetadataCache {
  _GatedCache(this.delegate);
  final AndroidImportMetadataCache delegate;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<CachedAndroidAudio?> lookup(AudioDocumentRevision revision) =>
      delegate.lookup(revision);
  @override
  Future<void> invalidateSource(ContentUriAudioSource source) =>
      delegate.invalidateSource(source);
  @override
  Future<T> commit<T>(List<CachedAndroidAudio> entries,
          Future<T> Function() importTracks) =>
      delegate.commit(entries, () async {
        entered.complete();
        await release.future;
        return importTracks();
      });
}

final class _Fixture {
  _Fixture(this.directory);
  static Future<_Fixture> create() async {
    final f = _Fixture(
        await Directory.systemTemp.createTemp('cmp_android_metadata_'));
    f.artwork = _Artwork(f.directory);
    f.open();
    return f;
  }

  final Directory directory;
  final documents = _Documents();
  final diagnostics = RecordingDiagnostics();
  late _Artwork artwork;
  late AppDatabase database;
  late DriftRepositories repositories;
  late AndroidImportController importer;
  void open() {
    database =
        AppDatabase(NativeDatabase(File('${directory.path}/cache.sqlite')));
    repositories = DriftRepositories(database);
    importer = AndroidImportController(
        documents: documents,
        imports: repositories.tracks as TrackImportRepository,
        artworkCache: artwork,
        metadataCache: DriftAndroidImportMetadataCache(database),
        diagnostics: diagnostics,
        monotonicMicroseconds: () => 0);
  }

  Future<void> restart() async {
    await importer.close();
    importer.dispose();
    await database.close();
    open();
  }

  Map<DiagnosticField, Object?> get profile => diagnostics.entries.last.fields;
  Future<List<Track>> rows() => repositories.tracks.listTracks(limit: 1000);
  Future<int> cacheCount() async => (await database
          .customSelect('SELECT COUNT(*) AS n FROM android_audio_caches')
          .getSingle())
      .read<int>('n');
  Future<void> close() async {
    await importer.close();
    importer.dispose();
    await database.close();
    await directory.delete(recursive: true);
  }
}

final class _Documents
    implements AudioDocuments, AudioDocumentFolders, AudioDocumentInspection {
  String treeName = 'root';
  ContentUriAudioSource get tree => ContentUriAudioSource(
      'content://com.android.externalstorage.documents/tree/$treeName');
  ContentUriAudioSource source(int i) => ContentUriAudioSource(
      '${tree.storageValue}/document/${Uri.encodeComponent('primary:Music/$i')}');
  final revisions = <int, AudioDocumentRevision>{};
  final unsupported = <int>{}, revoked = <int>{};
  int count = 3, reads = 0, inspections = 0, page = 0;
  String title = 'Title';
  bool unknownComments = false, noArtwork = false;
  Future<AudioDocumentMetadata> Function(int)? readAction;
  Future<AudioDocumentRevision?> Function(int)? inspectAction;
  AudioDocumentRevision revision(int i) =>
      revisions[i] ??
      AudioDocumentRevision(
          authority: 'com.android.externalstorage.documents',
          documentId: 'primary:Music/$i',
          name: '$i.m4a',
          size: 100 + i,
          modifiedMs: 1000);
  AudioDocumentMetadata metadata(int i) => AudioDocumentMetadata(
      name: revision(i).name,
      size: revision(i).size,
      title: title,
      artist: 'Artist',
      album: 'Album',
      sourceComments: unknownComments
          ? null
          : ['https://music.yandex.ru/album/10/track/${100 + i}'],
      artwork: noArtwork ? null : Uint8List.fromList([i % 256, 1, 2]),
      cacheRevision: unsupported.contains(i) ? null : revision(i));
  int index(ContentUriAudioSource source) =>
      int.parse(source.uri.pathSegments.last.split('/').last);
  @override
  Future<AudioDocumentRevision?> inspectAudio(ContentUriAudioSource source) {
    inspections++;
    final i = index(source);
    if (revoked.contains(i)) throw PlatformException(code: 'access_lost');
    return inspectAction?.call(i) ??
        Future.value(unsupported.contains(i) ? null : revision(i));
  }

  @override
  Future<AudioDocumentMetadata> readAudio(ContentUriAudioSource source) {
    reads++;
    final i = index(source);
    if (revoked.contains(i)) throw PlatformException(code: 'access_lost');
    return readAction?.call(i) ?? Future.value(metadata(i));
  }

  @override
  Future<AudioDocumentSelection?> pickAudio() async => null;
  @override
  Future<ContentUriAudioSource?> pickAudioFolder() async => tree;
  @override
  Future<int> openAudioFolder(ContentUriAudioSource tree) async {
    page = 0;
    return 1;
  }

  @override
  Future<AudioFolderPage> readAudioFolderPage(int session) async {
    final start = page++ * 64, end = (start + 64).clamp(0, count);
    return AudioFolderPage([for (var i = start; i < end; i++) source(i)],
        visited: end, done: end == count);
  }

  @override
  Future<void> closeAudioFolder(int session) async {}
}

final class _Artwork implements ArtworkCacheService {
  _Artwork(this.directory);
  final Directory directory;
  int calls = 0;
  bool fail = false;
  @override
  Future<CachedArtwork?> saveEmbeddedArtwork(EmbeddedArtwork? artwork) async {
    calls++;
    if (fail) throw StateError('cover unavailable');
    if (artwork == null) return null;
    final id = artwork.bytes.first;
    final file = await File('${directory.path}/cover$id.webp')
        .writeAsBytes(artwork.bytes);
    return CachedArtwork(
        path: file.path,
        hash: id.toRadixString(16).padLeft(64, '0'),
        mimeType: 'image/webp');
  }

  @override
  Future<CachedArtwork> saveCustomArtworkFile(File imageFile) =>
      throw UnsupportedError('unused');
}
