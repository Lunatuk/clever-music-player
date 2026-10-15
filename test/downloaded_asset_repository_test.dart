import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/downloaded_asset_repository.dart';
import 'package:clever_music_player/src/domain/repositories/library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('downloaded asset contract', () {
    test('publication IDs are bounded tokens, never remote URLs', () {
      final f = _Fixture();
      addTearDown(f.database.close);
      for (final id in [
        '',
        'a' * 129,
        'a\n',
        'https://signed.example/file',
        'a/b'
      ]) {
        expect(
            () => f.publication(1, id: id, source: FileAudioSource('/a.mp3')),
            throwsFormatException);
      }
      expect(() => f.publication(0, source: FileAudioSource('/a.mp3')),
          throwsArgumentError);
    });
    test('verification requires positive properties and full SHA-256', () {
      final f = _Fixture();
      addTearDown(f.database.close);
      for (final quality in ['', ' ', 'high\n', 'a' * 129]) {
        expect(() => f.proof(quality: quality), throwsFormatException);
      }
      for (final hash in ['', 'abc', 'g' * 64]) {
        expect(() => f.proof(hash: hash), throwsFormatException);
      }
      expect(() => f.proof(size: 0), throwsArgumentError);
      expect(() => f.proof(duration: Duration.zero), throwsArgumentError);
      expect(() => f.proof(codec: 'MP3'), throwsFormatException);
      expect(() => f.proof(container: 'file.mp3\n'), throwsFormatException);
      expect(f.proof(hash: 'A' * 64).contentHash, 'a' * 64);
    });
    test('unknown states and invalid revisions fail closed', () {
      final f = _Fixture();
      addTearDown(f.database.close);
      expect(() => DownloadedAssetState.fromStorageKey('future'),
          throwsFormatException);
      expect(
          () => DownloadedAsset(
              publication: f.publication(1, source: FileAudioSource('/a.mp3')),
              verification: f.proof(),
              state: DownloadedAssetState.verified,
              revision: 0),
          throwsArgumentError);
    });
  });
  group('SQLite downloaded assets', () {
    late _Fixture f;
    setUp(() => f = _Fixture());
    tearDown(() async {
      expect(await f.database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty);
      await f.database.close();
    });
    test('registration requires existing track and exact external reference',
        () async {
      await expectLater(
          f.assets.registerVerified(
              f.publication(999, source: FileAudioSource('/missing.mp3')),
              f.proof()),
          throwsStateError);
      final track = await f.track(link: false);
      await expectLater(f.register(track), throwsStateError);
      expect(await f.assets.findForTrack(track), isNull);
      await f.link(track);
      final asset = await f.register(track);
      expect(await f.assets.findForTrack(track), asset);
      expect(asset.revision, 1);
      expect(asset.verification.checkedAt, f.now);
    });
    test('source, known size and hash must match current track', () async {
      final track = await f.track();
      await expectLater(
          f.assets.registerVerified(
              f.publication(track, source: FileAudioSource('/different.mp3')),
              f.proof()),
          throwsStateError);
      final original = (await f.repo.tracks.findById(track))!;
      await f.repo.tracks.upsertTrack(
          original.copyWith(fileSizeBytes: 101, contentHash: 'b' * 64));
      await expectLater(f.register(track), throwsStateError);
      expect(await f.assets.findForTrack(track), isNull);
      await f.repo.tracks.upsertTrack(
          original.copyWith(fileSizeBytes: 100, contentHash: 'a' * 64));
      expect((await f.register(track)).verification.contentHash, 'a' * 64);
    });
    test('publication replay preserves first evidence, state and revision',
        () async {
      final track = await f.track();
      final first = await f.register(track);
      expect(
          await f.assets.registerVerified(f.publication(track),
              f.proof(at: f.now.add(const Duration(seconds: 1)))),
          first);
      await f.assets.invalidate(first, DownloadedAssetState.missing);
      final missing = (await f.assets.findForTrack(track))!;
      expect(await f.register(track), missing);
      expect(missing.state, DownloadedAssetState.missing);
      expect(missing.revision, 2);
    });
    test('one publication cannot describe different bytes or another copy',
        () async {
      final a = await f.track(), b = await f.track();
      final first = await f.register(a);
      await expectLater(
          f.assets.registerVerified(f.publication(a), f.proof(hash: 'b' * 64)),
          throwsStateError);
      await expectLater(
          f.assets.registerVerified(
              f.publication(b, id: first.publication.publicationId), f.proof()),
          throwsStateError);
      expect(await f.assets.findForTrack(a), first);
      expect(await f.assets.findForTrack(b), isNull);
    });
    test('actual quality wins over requested label and filename extension',
        () async {
      final track = await f.track(path: '/library/looks-lossless.flac');
      final asset = await f.assets.registerVerified(
          f.publication(track, quality: 'lossless'),
          f.proof(quality: 'high', container: 'm4a', codec: 'aac'));
      expect(asset.fulfillsRequestedQuality, isFalse);
      expect(asset.verification.container, 'm4a');
      expect(await f.candidates(quality: 'lossless'), isEmpty);
      expect(await f.candidates(), [asset]);
    });
    test('providers, IDs and musical versions are exact boundaries', () async {
      final keys = [
        f.identity,
        ExternalTrackIdentity(provider: 'other', externalId: '1'),
        ExternalTrackIdentity(provider: 'yandex_music', externalId: '001'),
        ExternalTrackIdentity(
            provider: 'yandex_music', externalId: '1', variantKey: 'album:live')
      ];
      for (final key in keys) {
        final track = await f.track(identity: key);
        final asset = await f.assets
            .registerVerified(f.publication(track, identity: key), f.proof());
        expect(
            await f.assets
                .findCandidates(key, quality: 'high', libraryFolderId: null),
            [asset]);
      }
      expect(await f.candidates(), hasLength(1));
    });
    test('copies and destination folders remain separate', () async {
      final a = await f.folder('/library/a'), b = await f.folder('/library/b');
      final plain = await f.track(),
          inA = await f.track(folder: a),
          inB = await f.track(folder: b);
      for (final track in [plain, inA, inB]) {
        await f.register(track);
      }
      expect((await f.candidates()).single.publication.trackId, plain);
      expect((await f.candidates(folder: a)).single.publication.trackId, inA);
      expect((await f.candidates(folder: b)).single.publication.trackId, inB);
      await f.repo.libraryFolders
          .setFolderEnabled(a, isEnabled: false, updatedAt: f.now);
      expect(await f.candidates(folder: a), isEmpty);
      expect(await f.assets.findForTrack(inA), isNotNull);
    });
    test('missing tracks retain evidence but are not candidates', () async {
      final track = await f.track(missing: true);
      final asset = await f.register(track);
      expect(await f.candidates(), isEmpty);
      expect(await f.assets.findForTrack(track), asset);
    });
    for (final state in [
      DownloadedAssetState.missing,
      DownloadedAssetState.accessDenied,
      DownloadedAssetState.invalid
    ]) {
      test('$state requires a fresh confirmation before reuse', () async {
        final track = await f.track();
        final asset = await f.register(track);
        expect(await f.assets.invalidate(asset, state), isTrue);
        expect(await f.candidates(), isEmpty);
        final current = (await f.assets.findForTrack(track))!;
        expect(current.state, state);
        expect(await f.assets.invalidate(current, state), isTrue);
        expect(await f.assets.findForTrack(track), current);
        expect(
            await f.assets.confirm(
                current, f.proof(at: f.now.add(const Duration(seconds: 1)))),
            isTrue);
        expect(
            (await f.candidates()).single.state, DownloadedAssetState.verified);
      });
    }
    test('late confirmation cannot revive a newer missing/access state',
        () async {
      final track = await f.track();
      final old = await f.register(track);
      await f.assets.invalidate(old, DownloadedAssetState.accessDenied);
      expect(
          await f.assets
              .confirm(old, f.proof(at: f.now.add(const Duration(seconds: 1)))),
          isFalse);
      expect((await f.assets.findForTrack(track))!.state,
          DownloadedAssetState.accessDenied);
    });
    test('late invalidation cannot overwrite a newer confirmation', () async {
      final track = await f.track();
      final old = await f.register(track);
      expect(
          await f.assets
              .confirm(old, f.proof(at: f.now.add(const Duration(seconds: 1)))),
          isTrue);
      expect(await f.assets.invalidate(old, DownloadedAssetState.invalid),
          isFalse);
      expect((await f.assets.findForTrack(track))!.state,
          DownloadedAssetState.verified);
      await expectLater(
          Future.sync(
              () => f.assets.invalidate(old, DownloadedAssetState.verified)),
          throwsArgumentError);
    });
    test('confirmation cannot substitute different bytes or regress time',
        () async {
      final track = await f.track();
      final asset = await f.register(track);
      expect(await f.assets.confirm(asset, f.proof(hash: 'b' * 64)), isFalse);
      expect(
          await f.assets.confirm(
              asset, f.proof(at: f.now.subtract(const Duration(seconds: 1)))),
          isFalse);
      expect(await f.assets.confirm(asset, f.proof()), isTrue);
      expect(await f.assets.findForTrack(track), asset);
    });
    test('quality replacement needs current snapshot and a new publication',
        () async {
      final track = await f.track();
      final old = await f.register(track);
      final publication =
          f.publication(track, id: 'replacement', quality: 'lossless');
      final proof = f.proof(
          quality: 'lossless',
          container: 'flac',
          codec: 'flac',
          hash: 'b' * 64);
      await expectLater(
          f.assets.registerVerified(publication, proof), throwsStateError);
      final newer =
          await f.assets.registerVerified(publication, proof, replaces: old);
      expect(newer.revision, 2);
      expect(newer.publication.trackId, track);
      expect(await f.candidates(), isEmpty);
      expect(await f.candidates(quality: 'lossless'), [newer]);
      expect(await f.assets.confirm(old, f.proof()), isFalse);
      expect(await f.assets.invalidate(old, DownloadedAssetState.missing),
          isFalse);
      await expectLater(f.register(track), throwsStateError);
    });
    test('stale replacement and another musical identity are rejected',
        () async {
      final track = await f.track();
      final old = await f.register(track);
      await f.assets.invalidate(old, DownloadedAssetState.missing);
      await expectLater(
          f.assets.registerVerified(f.publication(track, id: 'new'), f.proof(),
              replaces: old),
          throwsStateError);
      final current = (await f.assets.findForTrack(track))!;
      final other =
          ExternalTrackIdentity(provider: 'yandex_music', externalId: '2');
      await f.link(track, identity: other);
      await expectLater(
          f.assets.registerVerified(
              f.publication(track, id: 'new', identity: other), f.proof(),
              replaces: current),
          throwsStateError);
      expect(await f.assets.findForTrack(track), current);
    });
    test('address changes need checked registration at the new source',
        () async {
      final track = await f.track(
          path: 'content://test.documents/tree/Music/document/a%2Fb');
      final old = await f.register(track);
      final source = ContentUriAudioSource(
          'content://test.documents/tree/Other/document/a%2Fb');
      await f.repo.tracks.upsertTrack(
          (await f.repo.tracks.findById(track))!.copyWith(source: source));
      expect(await f.candidates(), isEmpty);
      expect(await f.assets.confirm(old, f.proof()), isFalse);
      final moved = await f.assets.registerVerified(
          f.publication(track, id: 'moved', source: source), f.proof(),
          replaces: old);
      expect(await f.candidates(), [moved]);
      expect(moved.publication.source.storageValue, source.storageValue);
    });
    test('changed track size/hash excludes old evidence', () async {
      final track = await f.track();
      final old = await f.register(track);
      await f.repo.tracks.upsertTrack((await f.repo.tracks.findById(track))!
          .copyWith(fileSizeBytes: 200, contentHash: 'b' * 64));
      expect(await f.candidates(), isEmpty);
      expect(await f.assets.confirm(old, f.proof()), isFalse);
      final updated = await f.assets.registerVerified(
          f.publication(track, id: 'changed'),
          f.proof(size: 200, hash: 'b' * 64),
          replaces: old);
      expect(await f.candidates(), [updated]);
    });
    test('registration and checks preserve metadata and user data', () async {
      final track = await f.track();
      await f.repo.tracks.updateTrackMetadata(TrackMetadataUpdate(
          trackId: track, title: 'Manual', updatedAt: f.now));
      await f.repo.tracks.updateCustomArtwork(
          trackId: track,
          path: '/private/cover',
          hash: 'cover',
          mimeType: 'image/png',
          updatedAt: f.now);
      await f.repo.trackUserState.upsertState(TrackUserState(
          trackId: track, isFavorite: true, playCount: 7, updatedAt: f.now));
      await f.repo.playbackEvents.addEvent(PlaybackEvent(
          trackId: track, type: PlaybackEventType.started, occurredAt: f.now));
      final playlist = await f.repo.playlists.createPlaylist('Keep');
      await f.repo.playlists.addTrackToPlaylist(playlist, track);
      final before = await f.repo.tracks.findById(track);
      final state = await f.repo.trackUserState.findByTrackId(track);
      final events = await f.repo.playbackEvents.recentForTrack(track);
      final asset = await f.register(track);
      await f.assets.invalidate(asset, DownloadedAssetState.missing);
      await f.assets.confirm((await f.assets.findForTrack(track))!,
          f.proof(at: f.now.add(const Duration(seconds: 1))));
      expect(await f.repo.tracks.findById(track), before);
      expect(await f.repo.trackUserState.findByTrackId(track), state);
      expect(await f.repo.playbackEvents.recentForTrack(track), events);
      expect(
          (await f.repo.playlists.watchPlaylistTracks(playlist).first)
              .single
              .trackId,
          track);
      await f.repo.resetLearningState();
      expect(await f.assets.findForTrack(track), isNotNull);
    });
    test('unlink cleans exact asset without affecting another reference',
        () async {
      final track = await f.track();
      final asset = await f.register(track);
      final other = ExternalTrackIdentity(provider: 'other', externalId: '1');
      await f.link(track, identity: other);
      await f.repo.externalTracks.unlink(track, other);
      expect(await f.assets.findForTrack(track), asset);
      await f.repo.externalTracks.unlink(track, f.identity);
      expect(await f.assets.findForTrack(track), isNull);
      expect(await f.repo.tracks.findById(track), isNotNull);
    });
    test('track/folder deletion cleans only their assets', () async {
      final folder = await f.folder('/library');
      final a = await f.track(folder: folder), b = await f.track();
      await f.register(a);
      final saved = await f.register(b);
      await f.repo.libraryFolders
          .setFolderEnabled(folder, isEnabled: false, updatedAt: f.now);
      await (f.repo.libraryFolders as LibraryFolderRemovalRepository)
          .removeDisabledFolder(folder);
      expect(await f.assets.findForTrack(a), isNull);
      expect(await f.assets.findForTrack(b), saved);
      await f.repo.tracks.deleteTrack(b);
      expect(await f.assets.findForTrack(b), isNull);
    });
    test('SQLite update failure rolls back proof, publication and revision',
        () async {
      final track = await f.track();
      final old = await f.register(track);
      await f.database.customStatement(
          "CREATE TRIGGER reject_asset_update BEFORE UPDATE ON downloaded_assets BEGIN SELECT RAISE(ABORT, 'test failure'); END");
      await expectLater(
          f.assets.registerVerified(
              f.publication(track, id: 'new'), f.proof(hash: 'b' * 64),
              replaces: old),
          throwsA(anything));
      expect(await f.assets.findForTrack(track), old);
      await expectLater(f.assets.invalidate(old, DownloadedAssetState.invalid),
          throwsA(anything));
      expect(await f.assets.findForTrack(track), old);
    });
    test('failed unlink restores both asset and ref', () async {
      final track = await f.track();
      final old = await f.register(track);
      await f.database.customStatement(
          "CREATE TRIGGER reject_ref_delete BEFORE DELETE ON external_track_refs BEGIN SELECT RAISE(ABORT, 'test failure'); END");
      await expectLater(
          f.repo.externalTracks.unlink(track, f.identity), throwsA(anything));
      expect(await f.assets.findForTrack(track), old);
      expect(await f.repo.externalTracks.listForTrack(track), hasLength(1));
    });
    test('deleted/recreated slot never accepts its previous snapshot',
        () async {
      final track = await f.track();
      final old = await f.register(track);
      await f.repo.externalTracks.unlink(track, f.identity);
      await f.link(track);
      final newer = await f.assets
          .registerVerified(f.publication(track), f.proof(hash: 'b' * 64));
      expect(newer.revision, old.revision);
      expect(newer.publication, old.publication);
      expect(await f.assets.invalidate(old, DownloadedAssetState.invalid),
          isFalse);
      expect(await f.assets.confirm(old, f.proof()), isFalse);
      await expectLater(
          f.assets.registerVerified(f.publication(track, id: 'late'), f.proof(),
              replaces: old),
          throwsStateError);
      expect(await f.assets.findForTrack(track), newer);
    });
    test('concurrent state changes accept one matching revision', () async {
      final track = await f.track();
      final old = await f.register(track);
      final results = await Future.wait([
        f.assets.invalidate(old, DownloadedAssetState.missing),
        f.assets.invalidate(old, DownloadedAssetState.invalid)
      ]);
      expect(results.where((value) => value), hasLength(1));
      expect((await f.assets.findForTrack(track))!.revision, 2);
    });
    test('concurrent publication replays create one stable record', () async {
      final track = await f.track();
      final results =
          await Future.wait([for (var i = 0; i < 8; i++) f.register(track)]);
      expect(results.toSet(), hasLength(1));
      expect((await f.candidates()).single.revision, 1);
    });
    test('composite reference FK cascades with enforcement enabled', () async {
      await f.database.customStatement('PRAGMA foreign_keys = ON');
      final track = await f.track();
      await f.register(track);
      await f.database.customStatement(
          'DELETE FROM external_track_refs WHERE track_id = ?', [track]);
      expect(await f.assets.findForTrack(track), isNull);
      expect(await f.repo.tracks.findById(track), isNotNull);
    });
    test('identity/quality candidate lookup has an index', () async {
      final plan = await f.database
          .customSelect(
              "EXPLAIN QUERY PLAN SELECT * FROM downloaded_assets WHERE provider='yandex_music' AND external_id='1' AND variant_key='' AND actual_quality='high' AND state='verified' ORDER BY track_id")
          .get();
      expect(plan.map((row) => row.read<String>('detail')).join(' '),
          contains('idx_downloaded_assets_identity'));
    });
  });
  test('file-backed SQLite preserves microseconds and revisions', () async {
    final dir = await Directory.systemTemp.createTemp('cmp_assets_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'library.sqlite'));
    final first = _Fixture(database: AppDatabase(NativeDatabase(file)));
    final track = await first.track();
    await first.assets.invalidate(
        await first.register(track), DownloadedAssetState.accessDenied);
    final snapshot = (await first.assets.findForTrack(track))!;
    await first.database.close();
    final second = _Fixture(database: AppDatabase(NativeDatabase(file)));
    addTearDown(second.database.close);
    expect(await second.assets.findForTrack(track), snapshot);
    expect(snapshot.verification.checkedAt.microsecondsSinceEpoch,
        first.now.microsecondsSinceEpoch);
    expect(
        await second.assets.confirm(snapshot,
            second.proof(at: second.now.add(const Duration(seconds: 1)))),
        isTrue);
    expect((await second.candidates()).single.revision, 3);
  });
}

final class _Fixture {
  _Fixture({AppDatabase? database})
      : database = database ?? AppDatabase(NativeDatabase.memory()) {
    repo = DriftRepositories(this.database);
  }
  final AppDatabase database;
  late final DriftRepositories repo;
  final now = DateTime.utc(2026, 10, 15, 0, 0, 0, 0, 123);
  final identity =
      ExternalTrackIdentity(provider: 'yandex_music', externalId: '1');
  final sources = <int, AudioSourceReference>{};
  DownloadedAssetRepository get assets => repo.downloadedAssets;
  Future<int> track(
      {String? path,
      int? folder,
      bool missing = false,
      bool link = true,
      ExternalTrackIdentity? identity}) async {
    final source = AudioSourceReference.fromStorage(
        path ?? '/library/${sources.length}.mp3');
    final id = await repo.tracks.upsertTrack(Track.fromSource(
        source: source,
        libraryFolderId: folder,
        isMissing: missing,
        title: 'Same title',
        addedAt: now,
        updatedAt: now));
    sources[id] = source;
    if (link) await this.link(id, identity: identity);
    return id;
  }

  Future<void> link(int track, {ExternalTrackIdentity? identity}) =>
      repo.externalTracks.linkAll([
        ExternalTrackRef(
            trackId: track,
            identity: identity ?? this.identity,
            origin: ExternalTrackRefOrigin.providerResponse,
            linkedAt: now)
      ]);
  DownloadedAssetPublication publication(int track,
          {String? id,
          String quality = 'high',
          AudioSourceReference? source,
          ExternalTrackIdentity? identity}) =>
      DownloadedAssetPublication(
          trackId: track,
          identity: identity ?? this.identity,
          source: source ?? sources[track]!,
          publicationId: id ?? 'pub-$track',
          requestedQuality: quality);
  DownloadedAssetVerification proof(
          {String quality = 'high',
          String container = 'mp3',
          String codec = 'mp3',
          int size = 100,
          Duration duration = const Duration(minutes: 3),
          String? hash,
          DateTime? at}) =>
      DownloadedAssetVerification(
          actualQuality: quality,
          container: container,
          codec: codec,
          fileSizeBytes: size,
          duration: duration,
          contentHash: hash ?? 'a' * 64,
          checkedAt: at ?? now);
  Future<DownloadedAsset> register(int track) =>
      assets.registerVerified(publication(track), proof());
  Future<List<DownloadedAsset>> candidates(
          {String quality = 'high', int? folder}) =>
      assets.findCandidates(identity,
          quality: quality, libraryFolderId: folder);
  Future<int> folder(String path) => repo.libraryFolders
      .upsertFolder(LibraryFolder(path: path, createdAt: now, updatedAt: now));
}
