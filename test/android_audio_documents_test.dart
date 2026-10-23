import 'dart:async';

import 'package:clever_music_player/src/android/android_import_controller.dart';
import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/track_repository.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      MethodChannel('dev.lunatuk.clever_music_player/audio_documents');
  const adapter = AndroidAudioDocuments(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final source =
      ContentUriAudioSource('content://music.documents/Tree/A%2FB?x=Q');
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('native picker cancellation and raw persisted URI round trip', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await adapter.pickAudio(), isNull);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickAudio');
      return {
        'uris': [source.storageValue, source.storageValue],
        'skipped': 2
      };
    });
    final selection = (await adapter.pickAudio())!;
    expect(selection.sources, [source]);
    expect(selection.skipped, 2);
  });

  test('channel rejects malformed selection and unsupported address', () async {
    for (final payload in [
      {
        'uris': ['https://music.example/audio'],
        'skipped': 0
      },
      {
        'uris': [42],
        'skipped': 0
      },
      {'uris': [], 'skipped': -1},
      {'uris': List.filled(65, source.storageValue), 'skipped': 0},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => payload);
      await expectLater(adapter.pickAudio(), throwsA(isA<FormatException>()));
    }
  });

  test('metadata channel sends original address and bounds optional fields',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readAudio');
      expect(call.arguments, {'uri': source.storageValue});
      return {
        'title': ' Song ',
        'artist': ' ',
        'durationMs': '1234',
        'size': -1,
        'artwork': Uint8List(256 * 1024 + 1)
      };
    });
    final metadata = await adapter.readAudio(source);
    expect(metadata.title, 'Song');
    expect(metadata.artist, isNull);
    expect(metadata.duration, const Duration(milliseconds: 1234));
    expect(metadata.size, isNull);
    expect(metadata.artwork, isNull);
  });

  test('document reader accepts track/disc totals and a bounded year',
      () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
              'trackNumber': '2/10',
              'discNumber': '1/2',
              'year': '2026',
            });
    final result = await adapter.readAudio(source);
    expect(result.trackNumber, 2);
    expect(result.discNumber, 1);
    expect(result.year, 2026);
  });
  for (final text in ['0', '-1', '1000001', 'not a number', '1' * 33]) {
    test('invalid document indices are ignored: $text', () async {
      messenger.setMockMethodCallHandler(
          channel,
          (_) async => {
                'trackNumber': text,
                'discNumber': text,
                'year': text,
              });
      final result = await adapter.readAudio(source);
      expect(result.trackNumber, isNull);
      expect(result.discNumber, isNull);
      expect(result.year, isNull);
    });
  }

  group('document import ownership', () {
    late AppDatabase database;
    late DriftRepositories repositories;
    late _Documents documents;
    late AndroidImportController importer;
    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      repositories = DriftRepositories(database);
      documents = _Documents(source);
      importer = AndroidImportController(
          documents: documents,
          imports: repositories.tracks as TrackImportRepository,
          artworkCache: const NoopArtworkCacheService());
    });
    tearDown(() async {
      await importer.close();
      importer.dispose();
      await database.close();
    });

    test('repeat selection preserves identity, feedback and manual title',
        () async {
      await importer.importSelection();
      final first = (await repositories.tracks.listTracks()).single;
      expect(first.filePath, source.storageValue);
      expect(first.title, 'Track');
      await repositories.tracks.upsertTrack(first.copyWith(
          title: 'Моя правка', metadataSource: MetadataSource.manual));
      final now = DateTime.now();
      await repositories.trackUserState.upsertState(
          TrackUserState(trackId: first.id!, isFavorite: true, updatedAt: now));
      await importer.importSelection();
      final repeated = (await repositories.tracks.listTracks()).single;
      expect(repeated.id, first.id);
      expect(repeated.title, 'Моя правка');
      expect(
          (await repositories.trackUserState.findByTrackId(first.id!))!
              .isFavorite,
          isTrue);
    });

    test('cancellation does not read documents or create rows', () async {
      documents.pick = () async => null;
      await importer.importSelection();
      expect(documents.reads, 0);
      expect(await repositories.tracks.listTracks(), isEmpty);
      expect(importer.busy, isFalse);
    });

    test('one unreadable document does not stop the remaining selection',
        () async {
      final other = ContentUriAudioSource('content://music.documents/other');
      documents.pick =
          () async => AudioDocumentSelection([source, other], skipped: 1);
      documents.read = (s) async {
        if (s == source) throw PlatformException(code: 'access_lost');
        return const AudioDocumentMetadata(name: 'untagged.flac');
      };
      await importer.importSelection();
      expect((await repositories.tracks.listTracks()).single.title, 'untagged');
      expect(importer.processed, 2);
      expect(importer.message, contains('Не добавлено: 2'));
    });

    test('busy rejects duplicate picker and close invalidates its late result',
        () async {
      final picker = Completer<AudioDocumentSelection?>();
      documents.pick = () => picker.future;
      final selection = importer.importSelection();
      await importer.importSelection();
      expect(documents.picks, 1);
      await importer.close().timeout(const Duration(seconds: 1));
      picker.complete(AudioDocumentSelection([source]));
      await selection;
      expect(documents.reads, 0);
      expect(await repositories.tracks.listTracks(), isEmpty);
    });

    test('close drains metadata and prevents its later DB write', () async {
      final read = Completer<AudioDocumentMetadata>();
      documents.read = (_) => read.future;
      final selection = importer.importSelection();
      await Future<void>.delayed(Duration.zero);
      var closed = false;
      final closing = importer.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      read.complete(const AudioDocumentMetadata(title: 'late'));
      await selection;
      await closing;
      expect(await repositories.tracks.listTracks(), isEmpty);
    });
  });

  test('close waits for accepted database transaction and rejects new work',
      () async {
    final imports = _DelayedImport();
    final importer = AndroidImportController(
        documents: _Documents(source),
        imports: imports,
        artworkCache: const NoopArtworkCacheService());
    final selection = importer.importSelection();
    await imports.entered.future;
    final closing = importer.close();
    expect(identical(importer.close(), closing), isTrue);
    var closed = false;
    unawaited(closing.then((_) => closed = true));
    await importer.importSelection();
    expect(closed, isFalse);
    imports.gate.complete([1]);
    await selection;
    await closing;
    expect(imports.calls, 1);
    importer.dispose();
  });
}

final class _Documents implements AudioDocuments {
  _Documents(this.source);
  final ContentUriAudioSource source;
  Future<AudioDocumentSelection?> Function()? pick;
  Future<AudioDocumentMetadata> Function(ContentUriAudioSource)? read;
  int picks = 0, reads = 0;
  @override
  Future<AudioDocumentSelection?> pickAudio() {
    picks++;
    return pick?.call() ?? Future.value(AudioDocumentSelection([source]));
  }

  @override
  Future<AudioDocumentMetadata> readAudio(ContentUriAudioSource source) {
    reads++;
    return read?.call(source) ??
        Future.value(const AudioDocumentMetadata(title: 'Track'));
  }
}

final class _DelayedImport implements TrackImportRepository {
  final entered = Completer<void>();
  final gate = Completer<List<int>>();
  int calls = 0;
  @override
  Future<List<int>> upsertScannedTracks(List<Track> tracks) {
    calls++;
    entered.complete();
    return gate.future;
  }
}
