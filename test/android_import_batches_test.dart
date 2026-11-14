import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/android/android_import_controller.dart';
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
  group('bounded Android imports', () {
    late _Fixture f;
    setUp(() => f = _Fixture());
    tearDown(() => f.close());

    test('130 fast files use three atomic writes and bounded notifications',
        () async {
      f.documents.count = 130;
      var notifications = 0;
      f.importer.addListener(() => notifications++);
      await f.importer.importFolder();
      expect(f.imports.sizes, [64, 64, 2]);
      expect(await f.rows(), hasLength(130));
      expect(f.documents.reads, 130);
      expect(f.importer.processed, 130);
      expect(notifications, lessThanOrEqualTo(4));
      expect(f.profile[DiagnosticField.importBatches], 3);
      expect(f.profile[DiagnosticField.importRows], 130);
      expect(f.profile[DiagnosticField.errorCount], 0);
      expect(f.profile.values, everyElement(anyOf(isA<num>(), isA<bool>())));
    });

    test('time budget commits slow results before reaching 64 rows', () async {
      f.documents.count = 5;
      f.documents.read = (_) async {
        f.us += 300000;
        return const AudioDocumentMetadata(title: 'Slow');
      };
      await f.importer.importFolder();
      expect(f.imports.sizes, [2, 2, 1]);
      expect(f.profile[DiagnosticField.metadataUs], 1500000);
      expect(f.profile[DiagnosticField.elapsedMs], 1500);
      expect(f.importer.message, contains('Время: 1.5 с.'));
    });

    test('failed batch isolates one bad row and continues the next page',
        () async {
      f.documents.count = 67;
      f.imports.reject = f.documents.source(1).storageValue;
      await f.importer.importFolder();
      final rows = await f.rows();
      expect(rows, hasLength(66));
      expect(rows.any((row) => row.filePath == f.imports.reject), isFalse);
      expect(
          rows.any(
              (row) => row.filePath == f.documents.source(66).storageValue),
          isTrue);
      expect(f.imports.sizes, [64, ...List.filled(64, 1), 3]);
      expect(f.importer.processed, 67);
      expect(f.importer.message, contains('Не добавлено: 1'));
      expect(f.profile[DiagnosticField.importFallbackRows], 64);
      expect(f.profile[DiagnosticField.importRows], 66);
      expect(f.profile[DiagnosticField.errorCount], 1);
    });

    test('failed single row is not retried forever', () async {
      f.documents.count = 1;
      f.imports.reject = f.documents.source(0).storageValue;
      await f.importer.importFolder();
      expect(f.imports.sizes, [1]);
      expect(await f.rows(), isEmpty);
      expect(f.profile[DiagnosticField.errorCount], 1);
    });

    test('cancel flushes ready partial batch and discards late metadata',
        () async {
      final late = Completer<AudioDocumentMetadata>();
      f.documents.read = (_) => f.documents.reads == 4
          ? late.future
          : Future.value(const AudioDocumentMetadata(title: 'Ready'));
      final running = f.importer.importFolder();
      await _until(() => f.documents.reads == 4);
      expect(await f.rows(), isEmpty);
      await f.importer.cancel();
      late.complete(const AudioDocumentMetadata(title: 'Late'));
      await running;
      expect(f.imports.sizes, [3]);
      expect(await f.rows(), hasLength(3));
      expect(f.importer.processed, 3);
      expect(f.profile[DiagnosticField.importCancelled], isTrue);
      expect(f.documents.closes, 1);
    });

    test('close drains partial batch after metadata without notifying disposal',
        () async {
      final late = Completer<AudioDocumentMetadata>();
      final commit = Completer<void>();
      f.documents.read = (_) => f.documents.reads == 3
          ? late.future
          : Future.value(const AudioDocumentMetadata(title: 'Ready'));
      f.imports.beforeWrite = (_) => commit.future;
      final running = f.importer.importFolder();
      await _until(() => f.documents.reads == 3);
      var closed = false;
      final closing = f.importer.close().then((_) => closed = true);
      f.importer.dispose();
      f.disposed = true;
      late.complete(const AudioDocumentMetadata(title: 'Late'));
      await _until(() => f.imports.sizes.isNotEmpty);
      expect(closed, isFalse);
      expect(await f.rows(), isEmpty);
      commit.complete();
      await running;
      await closing;
      expect(f.imports.sizes, [2]);
      expect(await f.rows(), hasLength(2));
      expect(f.profile[DiagnosticField.importRows], 2);
      expect(closed, isTrue);
    });

    test('cancel during cover write keeps earlier results only', () async {
      final late = Completer<CachedArtwork?>();
      var covers = 0;
      f.cache.save = (_) async {
        if (++covers == 3) return late.future;
        return null;
      };
      final running = f.importer.importFolder();
      await _until(() => covers == 3);
      await f.importer.cancel();
      late.complete(const CachedArtwork(path: '/late', hash: 'late'));
      await running;
      expect(f.imports.sizes, [2]);
      expect(await f.rows(), hasLength(2));
    });

    test('bad metadata and cover do not lose neighbouring prepared rows',
        () async {
      f.documents.count = 5;
      f.documents.read = (source) async {
        if (source == f.documents.source(1)) throw StateError('Unreadable');
        return const AudioDocumentMetadata(title: 'Song');
      };
      f.cache.save = (_) async => throw StateError('Cover write failed');
      await f.importer.importFolder();
      expect(f.imports.sizes, [4]);
      expect(await f.rows(), hasLength(4));
      expect(f.importer.processed, 5);
      expect(f.profile[DiagnosticField.metadataReads], 5);
      expect(f.profile[DiagnosticField.errorCount], 1);
    });

    test('batch keeps per-source link semantics and stable IDs on repeat',
        () async {
      f.documents.count = 3;
      var repeated = false;
      f.documents.read = (source) async => AudioDocumentMetadata(
          title: 'Identical title',
          sourceComments: repeated
              ? (source == f.documents.source(1) ? const [] : null)
              : ['https://music.yandex.ru/album/10/track/20']);
      await f.importer.importFolder();
      final before = await f.rows();
      expect(f.imports.links.single.values, everyElement(isNotNull));
      repeated = true;
      await f.importer.importFolder();
      expect(f.imports.links.last, {f.documents.source(1).storageValue: null});
      final after = await f.rows();
      expect({for (final row in after) row.filePath: row.id},
          {for (final row in before) row.filePath: row.id});
      final refs = await f.database
          .customSelect(
              'SELECT track_id FROM external_track_refs ORDER BY track_id')
          .get();
      expect(refs, hasLength(2));
    });

    test('aggregate timings distinguish nested native work and reset each run',
        () async {
      f.documents.count = 2;
      f.documents.read = (_) async {
        f.us += 200;
        return const AudioDocumentMetadata(
            title: 'Private title',
            sourceComments: ['private comment'],
            readTimings: AudioDocumentReadTimings(
                totalUs: 150,
                queryUs: 10,
                sourceUs: 20,
                tagsUs: 70,
                artworkUs: 40));
      };
      f.cache.save = (_) async {
        f.us += 30;
        return null;
      };
      f.imports.beforeWrite = (_) async => f.us += 50;
      await f.importer.importFolder();
      expect(f.profile[DiagnosticField.metadataUs], 400);
      expect(f.profile[DiagnosticField.artworkUs], 60);
      expect(f.profile[DiagnosticField.databaseUs], 50);
      expect(f.profile[DiagnosticField.nativeMetadataReads], 2);
      expect(f.profile[DiagnosticField.nativeReadUs], 300);
      expect(f.profile[DiagnosticField.nativeTagsUs], 140);
      expect(f.profile[DiagnosticField.nativeArtworkUs], 80);
      expect(f.profile.toString(), isNot(contains('Private')));
      expect(f.profile.toString(), isNot(contains('content:')));
      await f.importer.importFolder();
      expect(f.diagnostics.entries, hasLength(2));
      expect(f.profile[DiagnosticField.metadataReads], 2);
      expect(f.profile[DiagnosticField.importBatches], 1);
    });

    test('cancelled picker emits no import measurements', () async {
      f.documents.cancelPicker = true;
      await f.importer.importFolder();
      expect(f.diagnostics.entries, isEmpty);
    });

    test('completion listener can start a new run without mixing profiles',
        () async {
      Future<void>? second;
      f.importer.addListener(() {
        if (!f.importer.busy && second == null) {
          f.documents.count = 2;
          second = f.importer.importFolder();
        }
      });
      await f.importer.importFolder();
      await second;
      expect(
          f.diagnostics.entries
              .map((entry) => entry.fields[DiagnosticField.importRows]),
          [5, 2]);
    });

    test('broken diagnostic sink does not fail import or close', () async {
      f.diagnostics.fail = true;
      await f.importer.importFolder();
      expect(await f.rows(), hasLength(5));
      expect(f.importer.message, contains('Добавлено в библиотеку: 5'));
      expect(f.importer.busy, isFalse);
    });
  });

  const channel = MethodChannel('test/import-timings');
  const adapter = AndroidAudioDocuments(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  final source = ContentUriAudioSource('content://test/document/song');
  test('native timing payload is optional and accepts codec long integers',
      () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
              'title': 'Song',
              'readTimings': {
                'version': 1,
                'totalUs': 3000000000,
                'queryUs': 100,
                'sourceUs': 200,
                'tagsUs': 2000000000,
                'artworkUs': 300,
              }
            });
    final metadata = await adapter.readAudio(source);
    expect(metadata.readTimings!.tagsUs, 2000000000);
    expect(metadata.title, 'Song');
  });
  test('malformed timing payload never prevents ordinary metadata import',
      () async {
    final valid = {
      'version': 1,
      'totalUs': 100,
      'queryUs': 10,
      'sourceUs': 10,
      'tagsUs': 10,
      'artworkUs': 10,
    };
    for (final payload in [
      null,
      [],
      {...valid, 'version': 2},
      {...valid, 'queryUs': -1},
      {...valid, 'tagsUs': 3.5},
      {...valid, 'totalUs': 3600000001},
      {...valid}..remove('tagsUs'),
      {...valid, 'totalUs': 39},
      {...valid, 'artworkUs': 'private string'},
    ]) {
      messenger.setMockMethodCallHandler(
          channel, (_) async => {'title': 'Song', 'readTimings': payload});
      final metadata = await adapter.readAudio(source);
      expect(metadata.title, 'Song');
      expect(metadata.readTimings, isNull);
    }
  });
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

final class _Fixture {
  _Fixture() {
    repositories = DriftRepositories(database);
    imports = _Imports(repositories.tracks as TrackImportRepository);
    importer = AndroidImportController(
        documents: documents,
        imports: imports,
        artworkCache: cache,
        diagnostics: diagnostics,
        monotonicMicroseconds: () => us);
  }
  final database = AppDatabase(NativeDatabase.memory());
  final documents = _Documents();
  final cache = _Cache();
  final diagnostics = _Diagnostics();
  late final DriftRepositories repositories;
  late final _Imports imports;
  late final AndroidImportController importer;
  int us = 0;
  bool disposed = false;
  Future<List<Track>> rows() => repositories.tracks.listTracks(limit: 1000);
  Map<DiagnosticField, Object?> get profile => diagnostics.entries.last.fields;
  Future<void> close() async {
    await importer.close();
    if (!disposed) importer.dispose();
    await database.close();
  }
}

final class _Documents implements AudioDocuments, AudioDocumentFolders {
  int count = 5, reads = 0, page = 0, closes = 0;
  bool cancelPicker = false;
  Future<AudioDocumentMetadata> Function(ContentUriAudioSource)? read;
  ContentUriAudioSource source(int i) =>
      ContentUriAudioSource('content://test/tree/music/document/$i');
  @override
  Future<AudioDocumentSelection?> pickAudio() async => null;
  @override
  Future<ContentUriAudioSource?> pickAudioFolder() async =>
      cancelPicker ? null : ContentUriAudioSource('content://test/tree/music');
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
  Future<void> closeAudioFolder(int session) async => closes++;
  @override
  Future<AudioDocumentMetadata> readAudio(ContentUriAudioSource source) {
    reads++;
    return read?.call(source) ??
        Future.value(const AudioDocumentMetadata(title: 'Song'));
  }
}

final class _Imports implements TrackImportRepository {
  _Imports(this.delegate);
  final TrackImportRepository delegate;
  final sizes = <int>[];
  final links = <Map<String, ExternalTrackIdentity?>>[];
  String? reject;
  Future<void> Function(List<Track>)? beforeWrite;
  @override
  Future<List<int>> upsertScannedTracks(List<Track> tracks,
      {Map<String, ExternalTrackIdentity?> embeddedYandexIdentities =
          const {}}) async {
    sizes.add(tracks.length);
    links.add(Map.of(embeddedYandexIdentities));
    await beforeWrite?.call(tracks);
    if (reject != null && tracks.any((track) => track.filePath == reject)) {
      throw StateError('Atomic write failed');
    }
    return delegate.upsertScannedTracks(tracks,
        embeddedYandexIdentities: embeddedYandexIdentities);
  }
}

final class _Cache implements ArtworkCacheService {
  Future<CachedArtwork?> Function(EmbeddedArtwork?)? save;
  @override
  Future<CachedArtwork?> saveEmbeddedArtwork(EmbeddedArtwork? artwork) =>
      save?.call(artwork) ?? Future.value();
  @override
  Future<CachedArtwork> saveCustomArtworkFile(File imageFile) =>
      throw UnsupportedError('Not used');
}

final class _Diagnostics implements DiagnosticsService {
  final delegate = RecordingDiagnostics();
  bool fail = false;
  get entries => delegate.entries;
  @override
  void record(DiagnosticEvent event,
      {Map<DiagnosticField, Object?> fields = const {}, Object? error}) {
    if (fail) throw StateError('Unavailable');
    delegate.record(event, fields: fields, error: error);
  }

  @override
  Future<void> flush() async {}
  @override
  Future<Directory> directory() => throw UnsupportedError('Not used');
  @override
  Future<File> exportReport() => throw UnsupportedError('Not used');
}
