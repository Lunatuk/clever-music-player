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

const _url = 'https://music.yandex.ru/album/12/track/34';
final _source =
    ContentUriAudioSource('content://music.documents/document/song');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      MethodChannel('dev.lunatuk.clever_music_player/audio_documents');
  const adapter = AndroidAudioDocuments(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('channel preserves raw comment text in an immutable bounded snapshot',
      () async {
    final comments = [' $_url\u0000 ', 'https://music.yandex.ru/track/99'];
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'sourceComments': comments});
    final metadata = await adapter.readAudio(_source);
    expect(metadata.sourceComments, comments);
    expect(() => metadata.sourceComments!.add('extra'), throwsUnsupportedError);
  });

  for (final bad in <Object?>[
    null,
    'not a list',
    [42],
    List.filled(33, _url),
    ['x' * 4097]
  ]) {
    test(
        'unreliable channel comments preserve normal metadata: ${bad.runtimeType}',
        () async {
      messenger.setMockMethodCallHandler(
          channel, (_) async => {'title': 'Readable', 'sourceComments': bad});
      final metadata = await adapter.readAudio(_source);
      expect(metadata.title, 'Readable');
      expect(metadata.sourceComments, isNull);
    });
  }
  test('empty channel list is a completed read without comments', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'sourceComments': <String>[]});
    expect((await adapter.readAudio(_source)).sourceComments, isEmpty);
  });

  group('source annotations in the real Android import transaction', () {
    late AppDatabase db;
    late DriftRepositories repo;
    late _Documents documents;
    late AndroidImportController importer;
    final now = DateTime.utc(2026, 11, 14);
    ExternalTrackIdentity identity(String id) => ExternalTrackIdentity(
        provider: 'yandex_music', externalId: id, variantKey: '12');
    Future<Track> track() async =>
        (await repo.tracks.findByPath(_source.storageValue))!;
    Future<List<ExternalTrackRef>> refs() async =>
        repo.externalTracks.listForTrack((await track()).id!);
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftRepositories(db);
      documents = _Documents();
      importer = AndroidImportController(
          documents: documents,
          imports: repo.tracks as TrackImportRepository,
          artworkCache: const NoopArtworkCacheService(),
          clock: () => now);
    });
    tearDown(() async {
      await importer.close();
      importer.dispose();
      await db.close();
    });
    test(
        'imports source ID with the file, and rescan retains local ID and linkedAt',
        () async {
      await importer.importSelection();
      final first = await track();
      final links = await refs();
      expect(links.single.identity, identity('34'));
      expect(links.single.origin, ExternalTrackRefOrigin.embeddedTag);
      expect(importer.message, contains('Ссылок Яндекса: 1'));
      await importer.importSelection();
      expect((await track()).id, first.id);
      expect(await refs(), links);
    });
    test(
        'new source comments update weak links while a failed read preserves them',
        () async {
      await importer.importSelection();
      documents.comments = ['https://music.yandex.ru/album/12/track/99'];
      await importer.importSelection();
      expect((await refs()).single.identity, identity('99'));
      documents.comments = null;
      await importer.importSelection();
      expect((await refs()).single.identity, identity('99'));
      expect(importer.message, isNot(contains('Не добавлено')));
    });
    for (final comments in [
      <String>[],
      ['not a source'],
      [_url, 'https://music.yandex.ru/track/99']
    ]) {
      test(
          'reliable read without one identity removes only an embedded link: $comments',
          () async {
        await importer.importSelection();
        documents.comments = comments;
        await importer.importSelection();
        expect(await refs(), isEmpty);
        expect((await repo.tracks.listTracks()).length, 1);
      });
    }
    for (final origin in [
      ExternalTrackRefOrigin.manual,
      ExternalTrackRefOrigin.providerResponse
    ]) {
      test('refresh preserves stronger $origin provenance', () async {
        await importer.importSelection();
        final saved = await track();
        await repo.externalTracks.linkAll([
          ExternalTrackRef(
              trackId: saved.id!,
              identity: identity('34'),
              origin: origin,
              linkedAt: now)
        ]);
        documents.comments = [];
        await importer.importSelection();
        expect((await refs()).single.origin, origin);
      });
    }
    test(
        'equal display names do not associate distinct files without annotations',
        () async {
      await importer.importSelection();
      documents.sources = [
        _source,
        ContentUriAudioSource('content://music.documents/document/other')
      ];
      documents.comments = [];
      await importer.importSelection();
      final tracks = await repo.tracks.listTracks();
      expect(tracks, hasLength(2));
      expect(tracks.map((t) => t.title).toSet(), {'Same title'});
      for (final file in tracks) {
        expect(await repo.externalTracks.listForTrack(file.id!), isEmpty);
      }
    });
    test(
        'DB failure cannot leave a track without its corresponding source link',
        () async {
      await db.customStatement(
          '''CREATE TRIGGER reject_source BEFORE INSERT ON external_track_refs
        BEGIN SELECT RAISE(FAIL, 'synthetic source failure'); END''');
      await importer.importSelection();
      expect(await repo.tracks.listTracks(), isEmpty);
      expect(importer.message, contains('Не добавлено: 1'));
      expect(importer.message, isNot(contains('Ссылок Яндекса')));
    });
    test('cancellation during reading does not commit a late source annotation',
        () async {
      final result = Completer<AudioDocumentMetadata>();
      final entered = Completer<void>();
      documents.read = () {
        entered.complete();
        return result.future;
      };
      final operation = importer.importSelection();
      await entered.future;
      await importer.cancel();
      result.complete(
          const AudioDocumentMetadata(title: 'Late', sourceComments: [_url]));
      await operation;
      expect(await repo.tracks.listTracks(), isEmpty);
      expect(importer.message, contains('Импорт остановлен'));
    });
    test('closing drains a pending read without writing links to a closed DB',
        () async {
      final result = Completer<AudioDocumentMetadata>();
      final entered = Completer<void>();
      documents.read = () {
        entered.complete();
        return result.future;
      };
      final operation = importer.importSelection();
      await entered.future;
      var closed = false;
      final closing = importer.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      result.complete(const AudioDocumentMetadata(sourceComments: [_url]));
      await operation;
      await closing;
      expect(await repo.tracks.listTracks(), isEmpty);
    });
  });
}

final class _Documents implements AudioDocuments {
  List<String>? comments = [_url];
  List<ContentUriAudioSource> sources = [_source];
  Future<AudioDocumentMetadata> Function()? read;
  @override
  Future<AudioDocumentSelection?> pickAudio() async =>
      AudioDocumentSelection(sources);
  @override
  Future<AudioDocumentMetadata> readAudio(ContentUriAudioSource source) =>
      read?.call() ??
      Future.value(AudioDocumentMetadata(
          name: 'Same title.mp3',
          title: 'Same title',
          sourceComments: comments));
}
