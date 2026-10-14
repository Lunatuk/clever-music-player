import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/library/file_content_hasher.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/library_track_list.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:clever_music_player/src/recommendation/recommendation_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.create());
  tearDown(() => fixture.close());

  test('copies in separate folders have one visible entry but retain both IDs',
      () async {
    await fixture.scanBoth();
    final tracks = await fixture.tracks();
    expect(tracks, hasLength(2));
    expect(tracks[0].id, isNot(tracks[1].id));
    expect(tracks[0].contentHash, tracks[1].contentHash);
    expect(fixture.visible(tracks), hasLength(1));
    expect(fixture.visible(tracks, showCopies: true), hasLength(2));
    final ids = tracks.map((track) => track.id).toList();
    await fixture.scanBoth();
    expect((await fixture.tracks()).map((track) => track.id), ids);
    expect(await fixture.first.readAsBytes(), [1, 2, 3]);
    expect(await fixture.second.readAsBytes(), [1, 2, 3]);
  });

  test('different bytes with identical tags, sizes and times stay separate',
      () async {
    await fixture.second.writeAsBytes([1, 2, 4]);
    final stat = await fixture.first.stat();
    await fixture.second.setLastModified(stat.modified);
    await fixture.scanBoth();
    final tracks = await fixture.tracks();
    expect(tracks.map((track) => track.title).toSet(), {'Same title'});
    expect(tracks.map((track) => track.stableId).toSet(), hasLength(1));
    expect(tracks.map((track) => track.contentHash).toSet(), hasLength(2));
    expect(fixture.visible(tracks), hasLength(2));
  });

  test(
      'existing library backfill preserves both states, history and playlist order',
      () async {
    await fixture.scanBoth();
    final originalTracks = await fixture.tracks();
    final playlist =
        await fixture.repositories.playlists.createPlaylist('Keep');
    for (var index = 0; index < originalTracks.length; index++) {
      final track = originalTracks[index];
      await fixture.repositories.tracks.upsertTrack(track.copyWith(
        contentHash: index == 0 ? null : 'legacy-hash',
        metadataSource: MetadataSource.manual,
        title: 'Manual $index',
        customArtworkPath: '/cover/$index.jpg',
        customArtworkHash: 'cover$index',
      ));
      await fixture.repositories.trackUserState.upsertState(TrackUserState(
        trackId: track.id!,
        rating: 5 - index,
        isFavorite: index == 0,
        playCount: 7 + index,
        skipCount: index,
        updatedAt: DateTime(2026),
      ));
      await fixture.repositories.playbackEvents.addEvent(PlaybackEvent(
        trackId: track.id!,
        type: PlaybackEventType.started,
        occurredAt: DateTime(2026),
      ));
      await fixture.repositories.playlists
          .addTrackToPlaylist(playlist, track.id!);
    }
    final ids = originalTracks.map((track) => track.id!).toList();
    final states =
        await fixture.repositories.trackUserState.findByTrackIds(ids);
    final events = await fixture.repositories.playbackEvents.recentEvents();
    expect(fixture.visible(await fixture.tracks()), hasLength(2));
    fixture.reader.fail =
        true; // No need to re-read unchanged tags for backfill.
    await fixture.scanBoth();
    final tracks = await fixture.tracks();
    expect(fixture.visible(tracks), hasLength(1));
    expect(tracks.map((track) => track.id), ids);
    expect(tracks.map((track) => track.title), ['Manual 0', 'Manual 1']);
    expect(
        tracks.map((track) => track.customArtworkHash), ['cover0', 'cover1']);
    expect(
        await fixture.repositories.trackUserState.findByTrackIds(ids), states);
    expect(await fixture.repositories.playbackEvents.recentEvents(), events);
    final entries = await fixture.repositories.playlists
        .watchPlaylistTracks(playlist)
        .first;
    expect(entries.map((entry) => entry.trackId), ids);
    expect(entries.map((entry) => entry.position), [0, 1]);
  });

  test(
      'disabled folder cannot hide an available copy; reenable restores original',
      () async {
    await fixture.scanBoth();
    final tracks = await fixture.tracks();
    final original = tracks.first;
    await fixture.repositories.libraryFolders.setFolderEnabled(
      original.libraryFolderId!,
      isEnabled: false,
      updatedAt: DateTime(2026),
    );
    expect(fixture.visible(await fixture.tracks()).single.id, tracks.last.id);
    await fixture.repositories.libraryFolders.setFolderEnabled(
      original.libraryFolderId!,
      isEnabled: true,
      updatedAt: DateTime(2026),
    );
    expect(fixture.visible(await fixture.tracks()).single.id, original.id);
  });

  test('missing original uses remaining copy even when missing files are shown',
      () async {
    await fixture.scanBoth();
    final tracks = await fixture.tracks();
    await fixture.first.delete();
    await fixture.scanner().scanFolder(fixture.first.parent.path);
    final all = await fixture.repositories.tracks
        .watchAllTracks(includeMissing: true)
        .first;
    expect(fixture.visible(all).single.id, tracks.last.id);
    expect(fixture.visible(all, showMissing: true).single.id, tracks.last.id);
    expect(fixture.visible(all, showMissing: true, showCopies: true),
        hasLength(2));
  });

  test(
      'deleting a disabled source leaves the other copy playable in the library',
      () async {
    await fixture.scanBoth();
    final tracks = await fixture.tracks();
    final id = tracks.first.libraryFolderId!;
    await fixture.repositories.libraryFolders.setFolderEnabled(
      id,
      isEnabled: false,
      updatedAt: DateTime(2026),
    );
    await (fixture.repositories.libraryFolders
            as LibraryFolderRemovalRepository)
        .removeDisabledFolder(id);
    expect(fixture.visible(await fixture.tracks()).single.id, tracks.last.id);
    expect(await fixture.first.exists(), isTrue);
    expect(await fixture.second.exists(), isTrue);
  });

  test('rescan detects changed bytes even with original size and mtime',
      () async {
    await fixture.scanBoth();
    final stat = await fixture.second.stat();
    await fixture.second.writeAsBytes([1, 2, 4]);
    await fixture.second.setLastModified(stat.modified);
    final readsBefore = fixture.reader.reads;
    final result =
        await fixture.scanner().scanFolder(fixture.second.parent.path);
    expect(result.errors, isEmpty);
    expect(fixture.reader.reads, readsBefore + 1);
    expect(fixture.visible(await fixture.tracks()), hasLength(2));
  });

  test('hash failure clears stale identity while keeping readable tracks',
      () async {
    await fixture.scanBoth();
    final failing = fixture.scanner(hasher: const _FailingHasher());
    final result = await failing.scanFolder(fixture.second.parent.path);
    expect(result.errors, hasLength(1));
    final tracks = await fixture.tracks();
    expect(tracks.last.contentHash, isNull);
    expect(tracks.last.isMissing, isFalse);
    expect(fixture.visible(tracks), hasLength(2));
    await fixture.scanner().scanFolder(fixture.second.parent.path);
    expect(fixture.visible(await fixture.tracks()), hasLength(1));
  });

  test('hash failure does not block initial import', () async {
    final result = await fixture
        .scanner(hasher: const _FailingHasher())
        .scanFolder(fixture.first.parent.path);
    expect(result.addedTracks, 1);
    expect(result.errors, hasLength(1));
    expect((await fixture.tracks()).single.contentHash, isNull);
  });

  test(
      'changed content and broken tags invalidate old hash without losing state',
      () async {
    await fixture.scanBoth();
    final track = (await fixture.tracks()).last;
    await fixture.repositories.trackUserState.upsertState(TrackUserState(
      trackId: track.id!,
      rating: 5,
      playCount: 9,
      updatedAt: DateTime(2026),
    ));
    await fixture.second.writeAsBytes([8, 9, 0, 1]);
    fixture.reader.fail = true;
    final result =
        await fixture.scanner().scanFolder(fixture.second.parent.path);
    expect(result.errors, hasLength(1));
    final kept = (await fixture.repositories.tracks.findById(track.id!))!;
    expect(kept.contentHash, isNull);
    expect(kept.isMissing, isFalse);
    expect(
        (await fixture.repositories.trackUserState.findByTrackId(track.id!))!
            .playCount,
        9);
    expect(fixture.visible(await fixture.tracks()), hasLength(2));
  });

  test('mutation during metadata reading cannot publish the pre-mutation hash',
      () async {
    await fixture.scanBoth();
    await fixture.second.writeAsBytes([8, 9, 0, 1]);
    fixture.reader.afterRead =
        (file) async => file.writeAsBytes([2, 3, 4, 5, 6]);
    final result =
        await fixture.scanner().scanFolder(fixture.second.parent.path);
    expect(result.errors, hasLength(1));
    expect((await fixture.tracks()).last.contentHash, isNull);
    expect(fixture.visible(await fixture.tracks()), hasLength(2));
  });

  test('hash-only writes preserve a concurrent manual metadata update',
      () async {
    await fixture.scanBoth();
    final original = (await fixture.tracks()).first;
    await fixture.repositories.tracks.upsertTrack(original.copyWith(
      title: 'New manual title',
      metadataSource: MetadataSource.manual,
    ));
    await (fixture.repositories.tracks as TrackContentHashRepository)
        .updateContentHashes({original.id!: null});
    final track = (await fixture.repositories.tracks.findById(original.id!))!;
    expect(track.title, 'New manual title');
    expect(track.contentHash, isNull);
  });

  test('Wave suppresses exact copies but keeps different files with same tags',
      () async {
    await fixture.scanBoth();
    final wave = RecommendationService(
      tracks: fixture.repositories.tracks,
      trackUserState: fixture.repositories.trackUserState,
      playbackEvents: fixture.repositories.playbackEvents,
    );
    expect(await wave.recommend(), hasLength(1));
    await fixture.second.writeAsBytes([1, 2, 4]);
    await fixture.scanner().scanFolder(fixture.second.parent.path);
    expect(await wave.recommend(), hasLength(2));
  });
}

final class _Fixture {
  _Fixture(this.directory, this.database, this.repositories, this.first,
      this.second);
  final Directory directory;
  final AppDatabase database;
  final DriftRepositories repositories;
  final File first;
  final File second;
  final reader = _MetadataReader();

  static Future<_Fixture> create() async {
    final directory =
        await Directory.systemTemp.createTemp('cmp_exact_copies_');
    final first = File(p.join(directory.path, 'first', 'song.mp3'));
    final second = File(p.join(directory.path, 'second', 'song.mp3'));
    for (final file in [first, second]) {
      await file.parent.create();
      await file.writeAsBytes([1, 2, 3]);
      await file.setLastModified(DateTime(2026));
    }
    final database = AppDatabase(NativeDatabase.memory());
    return _Fixture(
        directory, database, DriftRepositories(database), first, second);
  }

  LibraryScannerService scanner({FileContentHasher? hasher}) =>
      LibraryScannerService(
        libraryRepository: repositories.libraryFolders,
        trackRepository: repositories.tracks,
        metadataReader: reader,
        contentHasher: hasher ?? const Sha256FileContentHasher(),
      );

  Future<void> scanBoth() async {
    for (final file in [first, second]) {
      final result = await scanner().scanFolder(file.parent.path);
      expect(result.errors, isEmpty);
    }
  }

  Future<List<Track>> tracks() async {
    final tracks = await repositories.tracks.listTracks();
    tracks.sort((a, b) => a.id!.compareTo(b.id!));
    return tracks;
  }

  List<Track> visible(List<Track> tracks,
          {bool showCopies = false, bool showMissing = false}) =>
      buildVisibleLibraryTracks(
          tracks: tracks,
          searchQuery: '',
          showMissingTracks: showMissing,
          showExactCopies: showCopies,
          sortOption: LibraryTrackSortOption.title);

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}

final class _MetadataReader implements MetadataReaderService {
  var reads = 0;
  var fail = false;
  Future<void> Function(File)? afterRead;
  @override
  Future<AudioMetadata> read(File file) async {
    reads++;
    if (fail) throw StateError('Broken tags');
    final stat = await file.stat();
    final result = AudioMetadata(
      filePath: file.path,
      fileSizeBytes: stat.size,
      modifiedAt: stat.modified,
      title: 'Same title',
      artist: 'Same artist',
      album: 'Same album',
      duration: const Duration(minutes: 3),
      codec: 'mp3',
      metadataSource: MetadataSource.embeddedTags,
      metadataConfidence: 1,
    );
    await afterRead?.call(file);
    return result;
  }
}

final class _FailingHasher implements FileContentHasher {
  const _FailingHasher();
  @override
  Future<FileContentFingerprint> hashFile(File file) async =>
      throw FileSystemException('Read failed', file.path);
}
