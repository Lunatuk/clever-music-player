import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/embedded_yandex_identity.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late AppDatabase database;
  late DriftRepositories repositories;
  late List<File> files;
  late _Reader reader;
  final now = DateTime.utc(2030);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cmp_scan_source_ids_');
    database = AppDatabase(NativeDatabase.memory());
    repositories = DriftRepositories(database);
    files = [
      for (var i = 1; i <= 2; i++)
        await File(p.join(root.path, '$i.m4a')).writeAsBytes([i, 2, 3]),
    ];
    reader = _Reader();
  });
  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });
  LibraryScannerService scanner({MetadataReaderService? metadata}) =>
      LibraryScannerService(
          libraryRepository: repositories.libraryFolders,
          trackRepository: repositories.tracks,
          settingsRepository: repositories.settings,
          metadataReader: metadata ?? reader,
          clock: () => now,
          importBatchSize: 1,
          listEntities: (_) => Stream.fromIterable(files));

  Future<String> marker() async {
    final folder = (await repositories.libraryFolders.listFolders()).single;
    return 'scan.yandex-source-ids.v1.${folder.id}';
  }

  test(
      'fresh files receive durable source identities in their import transaction',
      () async {
    final result = await scanner().scanFolder(root.path);
    expect(result.errors, isEmpty);
    expect(result.yandexLinkedTracks, 2);
    expect(result.summary, contains('Связано с Яндексом: 2'));
    expect(reader.fullReads, 2);
    expect(reader.identityReads, 0);
    expect(await repositories.settings.readString(await marker()), '1');
    final tracks = await repositories.tracks.listTracks();
    for (final track in tracks) {
      final refs = await repositories.externalTracks.listForTrack(track.id!);
      expect(refs.single.identity, reader.identity(File(track.filePath)));
      expect(refs.single.origin, ExternalTrackRefOrigin.embeddedTag);
    }
  });
  test(
      'old unchanged files backfill once while preserving manual metadata and IDs',
      () async {
    await scanner(metadata: const FallbackMetadataReaderService())
        .scanFolder(root.path);
    final original = (await repositories.tracks.listTracks()).first;
    await repositories.tracks.upsertTrack(original.copyWith(
        title: 'Edited title', metadataSource: MetadataSource.manual));
    await repositories.trackUserState.upsertState(TrackUserState(
        trackId: original.id!, playCount: 7, isFavorite: true, updatedAt: now));
    final result = await scanner().scanFolder(root.path);
    expect(result.errors, isEmpty);
    expect(result.yandexLinkedTracks, 2);
    expect(reader.fullReads, 0);
    expect(reader.identityReads, 2);
    final refreshed = (await repositories.tracks.findById(original.id!))!;
    expect(refreshed.title, 'Edited title');
    expect(
        (await repositories.trackUserState.findByTrackId(original.id!))!
            .playCount,
        7);
    final repeated = await scanner().scanFolder(root.path);
    expect(repeated.yandexLinkedTracks, 2);
    expect(reader.identityReads, 2);
    expect(reader.fullReads, 0);
  });
  test('cancellation commits completed files and keeps the backfill retryable',
      () async {
    await scanner(metadata: const FallbackMetadataReaderService())
        .scanFolder(root.path);
    final control = LibraryScanControl();
    reader.onIdentityRead = (_) async {
      if (reader.identityReads == 2) control.cancel();
    };
    final cancelled = await scanner().scanFolder(root.path, control: control);
    expect(cancelled.wasCancelled, isTrue);
    expect(cancelled.yandexLinkedTracks, 1);
    expect(await repositories.settings.readString(await marker()), isNull);
    reader.onIdentityRead = null;
    final resumed = await scanner().scanFolder(root.path);
    expect(resumed.errors, isEmpty);
    expect(resumed.yandexLinkedTracks, 2);
    expect(await repositories.tracks.listTracks(), hasLength(2));
    expect(await repositories.settings.readString(await marker()), '1');
  });
  test('a failed source read leaves that file eligible for the next backfill',
      () async {
    await scanner(metadata: const FallbackMetadataReaderService())
        .scanFolder(root.path);
    reader.onIdentityRead = (file) async {
      if (file == files.first) throw const FileSystemException('synthetic');
    };
    final failed = await scanner().scanFolder(root.path);
    expect(failed.errors, hasLength(1));
    expect(await repositories.settings.readString(await marker()), isNull);
    reader.onIdentityRead = null;
    expect((await scanner().scanFolder(root.path)).yandexLinkedTracks, 2);
    expect(await repositories.settings.readString(await marker()), '1');
  });
  test(
      'a file changed during reference reading cannot publish its old identity',
      () async {
    await scanner(metadata: const FallbackMetadataReaderService())
        .scanFolder(root.path);
    reader.onIdentityRead = (file) async {
      if (file == files.first) {
        await file.writeAsBytes([9], mode: FileMode.append);
      }
    };
    final result = await scanner().scanFolder(root.path);
    expect(result.errors, hasLength(1));
    expect(result.yandexLinkedTracks, 1);
    expect(await repositories.settings.readString(await marker()), isNull);
  });
  test('changed source comments replace earlier embedded associations',
      () async {
    await scanner().scanFolder(root.path);
    final old = reader.identity(files.first)!;
    reader.overrides[files.first.path] =
        'https://music.yandex.ru/album/12/track/99';
    await files.first.writeAsBytes([9], mode: FileMode.append);
    final result = await scanner().scanFolder(root.path);
    expect(result.errors, isEmpty);
    expect(result.yandexLinkedTracks, 2);
    expect(await repositories.externalTracks.findRefs(old), isEmpty);
    expect(
        await repositories.externalTracks
            .findRefs(reader.identity(files.first)!),
        hasLength(1));
  });
  test('a metadata fallback schedules a later source-only backfill', () async {
    reader.sourceEvidenceMissing = true;
    final first = await scanner().scanFolder(root.path);
    expect(first.errors, isEmpty);
    expect(first.yandexLinkedTracks, 0);
    expect(await repositories.settings.readString(await marker()), '0');
    reader.sourceEvidenceMissing = false;
    final repeated = await scanner().scanFolder(root.path);
    expect(repeated.yandexLinkedTracks, 2);
    expect(reader.fullReads, 2);
    expect(reader.identityReads, 2);
    expect(await repositories.settings.readString(await marker()), '1');
  });
}

final class _Reader
    implements MetadataReaderService, EmbeddedYandexIdentityReader {
  int fullReads = 0, identityReads = 0;
  bool sourceEvidenceMissing = false;
  final overrides = <String, String>{};
  Future<void> Function(File)? onIdentityRead;
  ExternalTrackIdentity? identity(File file) => embeddedYandexIdentity([
        overrides[file.path] ??
            'https://music.yandex.ru/album/12/track/${p.basenameWithoutExtension(file.path)}',
      ]);
  @override
  Future<ExternalTrackIdentity?> readYandexIdentity(File file) async {
    identityReads++;
    final result = identity(file);
    await onIdentityRead?.call(file);
    return result;
  }

  @override
  Future<AudioMetadata> read(File file) async {
    fullReads++;
    final stat = await file.stat();
    return AudioMetadata(
        filePath: file.path,
        fileSizeBytes: stat.size,
        modifiedAt: stat.modified,
        title: 'Tagged title',
        codec: 'm4a',
        metadataSource: MetadataSource.embeddedTags,
        metadataConfidence: 0.95,
        yandexIdentity: identity(file),
        yandexIdentityRead: !sourceEvidenceMissing);
  }
}
