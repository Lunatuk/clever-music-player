import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/external_track_repository.dart';
import 'package:clever_music_player/src/domain/repositories/library_repository.dart';
import 'package:clever_music_player/src/domain/repositories/track_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('external identity contract', () {
    test('provider namespace is bounded, lowercase and contains no controls',
        () {
      for (final provider in [
        '',
        'Yandex',
        ' yandex',
        'yandex\n',
        'a' * 65,
        'a/b'
      ]) {
        expect(() => ExternalTrackIdentity(provider: provider, externalId: '1'),
            throwsFormatException,
            reason: provider);
      }
      expect(
          ExternalTrackIdentity(provider: 'yandex_music', externalId: '1')
              .provider,
          'yandex_music');
    });
    test('opaque IDs preserve case, leading zeros and special characters', () {
      final a = ExternalTrackIdentity(provider: 'test', externalId: '001:A%_/');
      final b = ExternalTrackIdentity(provider: 'test', externalId: '001:a%_/');
      expect(a.externalId, '001:A%_/');
      expect(a, isNot(b));
      expect(
          {a, ExternalTrackIdentity(provider: 'test', externalId: '001:A%_/')},
          hasLength(1));
    });
    test('IDs and context reject empty/control/oversized values', () {
      for (final id in ['', ' ', 'a\u0000b', 'a\nb', 'a\u007fb', 'a' * 513]) {
        expect(() => ExternalTrackIdentity(provider: 'test', externalId: id),
            throwsFormatException);
      }
      for (final context in [' ', 'a\u0000b', 'a' * 513]) {
        expect(
            () => ExternalTrackIdentity(
                provider: 'test', externalId: '1', variantKey: context),
            throwsFormatException);
      }
      expect(
          ExternalTrackIdentity(provider: 'test', externalId: '1').variantKey,
          '');
    });
    test('variants participate in identity and provenance fails closed', () {
      final plain = ExternalTrackIdentity(provider: 'test', externalId: '1');
      final live = ExternalTrackIdentity(
          provider: 'test', externalId: '1', variantKey: 'album:live');
      expect(plain, isNot(live));
      expect(() => ExternalTrackRefOrigin.fromStorageKey('future'),
          throwsFormatException);
      expect(
          () => ExternalTrackRef(
              trackId: 0,
              identity: plain,
              origin: ExternalTrackRefOrigin.manual,
              linkedAt: DateTime(2026)),
          throwsArgumentError);
    });
  });

  group('SQLite associations', () {
    late _Fixture f;
    setUp(() => f = _Fixture());
    tearDown(() => f.database.close());

    test('same ID in several incoming lists creates one stable association',
        () async {
      final track = await f.track('/music/a.mp3');
      final ref = f.ref(track);
      await f.external.linkAll([ref, ref]);
      await f.external.linkAll([f.ref(track, at: DateTime.utc(2027))]);
      expect(await f.external.findRefs(ref.identity), [ref]);
      expect(await f.external.listForTrack(track), [ref]);
    });
    test('one external ID may reference independent copies with the same title',
        () async {
      final a = await f.track('/music/a.mp3');
      final b = await f.track('/copies/a.mp3');
      await f.external.linkAll([f.ref(a), f.ref(b)]);
      expect((await f.external.findRefs(f.identity())).map((r) => r.trackId),
          [a, b]);
      expect(await f.repo.tracks.listTracks(), hasLength(2));
    });
    test('provider, opaque ID and version are all exact lookup boundaries',
        () async {
      final track = await f.track('/music/a.mp3');
      final identities = [
        f.identity(),
        f.identity(provider: 'other'),
        f.identity(id: '001'),
        f.identity(id: 'A%_'),
        f.identity(id: 'a%_'),
        f.identity(version: 'album:original'),
        f.identity(version: 'album:live')
      ];
      await f.external.linkAll([
        for (final identity in identities) f.ref(track, identity: identity)
      ]);
      for (final identity in identities) {
        expect((await f.external.findRefs(identity)).single.identity, identity);
      }
      expect(await f.external.findRefs(f.identity(id: '%')), isEmpty);
      expect(await f.external.listForTrack(track), hasLength(7));
    });
    test('matching metadata never invents an association', () async {
      final a = await f.track('/music/a.mp3');
      final b = await f.track('/music/b.mp3');
      await f.external.linkAll([f.ref(a)]);
      expect(await f.external.listForTrack(b), isEmpty);
      expect((await f.external.findRefs(f.identity())).single.trackId, a);
    });
    test('provenance is promoted, never downgraded; original link time remains',
        () async {
      final track = await f.track('/music/a.mp3');
      await f.external
          .linkAll([f.ref(track, origin: ExternalTrackRefOrigin.embeddedTag)]);
      await f.external.linkAll([
        f.ref(track,
            origin: ExternalTrackRefOrigin.providerResponse,
            at: DateTime.utc(2027))
      ]);
      var ref = (await f.external.listForTrack(track)).single;
      expect(ref.origin, ExternalTrackRefOrigin.providerResponse);
      expect(ref.linkedAt, f.now);
      await f.external
          .linkAll([f.ref(track, origin: ExternalTrackRefOrigin.manual)]);
      await f.external.linkAll([f.ref(track)]);
      ref = (await f.external.listForTrack(track)).single;
      expect(ref.origin, ExternalTrackRefOrigin.manual);
      expect(ref.linkedAt, f.now);
    });
    test(
        'duplicates in one batch keep strongest provenance and first link time',
        () async {
      final track = await f.track('/music/a.mp3');
      await f.external.linkAll([
        f.ref(track, origin: ExternalTrackRefOrigin.manual),
        f.ref(track,
            origin: ExternalTrackRefOrigin.embeddedTag, at: DateTime.utc(2027))
      ]);
      final ref = (await f.external.listForTrack(track)).single;
      expect(ref.origin, ExternalTrackRefOrigin.manual);
      expect(ref.linkedAt, f.now);
    });
    test('missing track rejects whole batch without a partial association',
        () async {
      final track = await f.track('/music/a.mp3');
      await expectLater(f.external.linkAll([f.ref(track), f.ref(track + 100)]),
          throwsStateError);
      expect(await f.external.listForTrack(track), isEmpty);
      expect(await f.database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty);
    });
    test('SQLite failure rolls back inserts and provenance promotion together',
        () async {
      final track = await f.track('/music/a.mp3');
      final original = f.ref(track, origin: ExternalTrackRefOrigin.embeddedTag);
      await f.external.linkAll([original]);
      await f.database.customStatement('''
        CREATE TRIGGER reject_external_link BEFORE INSERT ON external_track_refs
        WHEN NEW.external_id = 'fail'
        BEGIN SELECT RAISE(ABORT, 'test failure'); END
      ''');
      await expectLater(
          f.external.linkAll([
            f.ref(track),
            f.ref(track, identity: f.identity(id: 'new')),
            f.ref(track, identity: f.identity(id: 'fail'))
          ]),
          throwsA(anything));
      expect(await f.external.listForTrack(track), [original]);
      await f.database.customStatement('DROP TRIGGER reject_external_link');
      await f.external.linkAll([f.ref(track)]);
      expect((await f.external.listForTrack(track)).single.origin,
          ExternalTrackRefOrigin.providerResponse);
    });
    test('concurrent repeated links remain a single record', () async {
      final track = await f.track('/music/a.mp3');
      await Future.wait([
        for (var i = 0; i < 12; i++) f.external.linkAll([f.ref(track)])
      ]);
      expect(await f.external.listForTrack(track), [f.ref(track)]);
    });
    test('bounded batches accept 64 associations and reject an oversized batch',
        () async {
      final track = await f.track('/music/a.mp3');
      final refs = [
        for (var i = 0; i < 64; i++)
          f.ref(track, identity: f.identity(id: '$i'))
      ];
      await f.external.linkAll(refs);
      await expectLater(
          Future.sync(() => f.external.linkAll([...refs, refs.first])),
          throwsArgumentError);
      expect(await f.external.listForTrack(track), hasLength(64));
      await f.external.linkAll([]);
    });
    test('link/unlink preserve manual metadata, covers, feedback and playlists',
        () async {
      final track = await f.track('/music/a.mp3');
      await f.repo.tracks.updateTrackMetadata(TrackMetadataUpdate(
          trackId: track,
          title: 'Manual title',
          artist: 'Artist',
          genre: 'Rock',
          updatedAt: f.now));
      await f.repo.tracks.updateCustomArtwork(
          trackId: track,
          path: '/private/cover',
          hash: 'cover',
          mimeType: 'image/png',
          updatedAt: f.now);
      await f.repo.trackUserState.upsertState(TrackUserState(
          trackId: track, isFavorite: true, playCount: 8, updatedAt: f.now));
      await f.repo.playbackEvents.addEvent(PlaybackEvent(
          trackId: track, type: PlaybackEventType.started, occurredAt: f.now));
      final playlist = await f.repo.playlists.createPlaylist('Keep');
      await f.repo.playlists.addTrackToPlaylist(playlist, track);
      final before = await f.repo.tracks.findById(track);
      final state = await f.repo.trackUserState.findByTrackId(track);
      final events = await f.repo.playbackEvents.recentForTrack(track);
      await f.external.linkAll([f.ref(track)]);
      await f.external.unlink(track, f.identity());
      await f.external.unlink(track, f.identity());
      expect(await f.repo.tracks.findById(track), before);
      expect(await f.repo.trackUserState.findByTrackId(track), state);
      expect(await f.repo.playbackEvents.recentForTrack(track), events);
      expect(
          (await f.repo.playlists.watchPlaylistTracks(playlist).first)
              .single
              .trackId,
          track);
      expect(await f.external.listForTrack(track), isEmpty);
    });
    test('ordinary tag/cover updates and reimports retain external refs',
        () async {
      final track = await f.track('/music/a.mp3');
      await f.external.linkAll([f.ref(track)]);
      await f.repo.tracks.upsertTrack(
          (await f.repo.tracks.findById(track))!.copyWith(title: 'Renamed'));
      await (f.repo.tracks as TrackImportRepository).upsertScannedTracks([
        Track(
            filePath: '/music/a.mp3',
            title: 'Imported',
            addedAt: f.now,
            updatedAt: f.now)
      ]);
      await f.repo.tracks.updateCustomArtwork(
          trackId: track,
          path: '/private/cover',
          hash: 'cover',
          mimeType: 'image/png',
          updatedAt: f.now);
      expect(await f.external.listForTrack(track), [f.ref(track)]);
    });
    test('missing/disabled tracks retain associations for later recovery',
        () async {
      final folder = await f.folder();
      final track =
          await f.track('/music/a.mp3', folder: folder, missing: true);
      await f.external.linkAll([f.ref(track)]);
      await f.repo.libraryFolders
          .setFolderEnabled(folder, isEnabled: false, updatedAt: f.now);
      expect(await f.repo.tracks.listTracks(), isEmpty);
      expect(await f.external.findRefs(f.identity()), [f.ref(track)]);
      await f.repo.resetLearningState();
      expect(await f.external.findRefs(f.identity()), [f.ref(track)]);
    });
    test('deleting a track removes only its links, preserving other copies',
        () async {
      final a = await f.track('/music/a.mp3');
      final b = await f.track('/copies/a.mp3');
      await f.external.linkAll([f.ref(a), f.ref(b)]);
      await f.repo.tracks.deleteTrack(a);
      expect(await f.external.listForTrack(a), isEmpty);
      expect(await f.external.findRefs(f.identity()), [f.ref(b)]);
      expect(await f.database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty);
    });
    test('atomic folder removal cleans links of owned tracks only', () async {
      final folder = await f.folder();
      final a = await f.track('/music/a.mp3', folder: folder);
      final b = await f.track('/elsewhere/a.mp3');
      await f.external.linkAll([f.ref(a), f.ref(b)]);
      await f.repo.libraryFolders
          .setFolderEnabled(folder, isEnabled: false, updatedAt: f.now);
      await (f.repo.libraryFolders as LibraryFolderRemovalRepository)
          .removeDisabledFolder(folder);
      expect(await f.external.listForTrack(a), isEmpty);
      expect(await f.external.findRefs(f.identity()), [f.ref(b)]);
    });
    test('failed track deletion restores associations with the track',
        () async {
      final track = await f.track('/music/a.mp3');
      await f.external.linkAll([f.ref(track)]);
      await f.database.customStatement('''
        CREATE TRIGGER reject_track_delete BEFORE DELETE ON tracks
        BEGIN SELECT RAISE(ABORT, 'test failure'); END
      ''');
      await expectLater(f.repo.tracks.deleteTrack(track), throwsA(anything));
      expect(await f.repo.tracks.findById(track), isNotNull);
      expect(await f.external.listForTrack(track), [f.ref(track)]);
    });
    test('lookup uses the external identity index', () async {
      final track = await f.track('/music/a.mp3');
      await f.external.linkAll([f.ref(track)]);
      final plan = await f.database
          .customSelect(
              "EXPLAIN QUERY PLAN SELECT * FROM external_track_refs WHERE provider='yandex_music' AND external_id='1' AND variant_key='' ORDER BY track_id")
          .get();
      expect(plan.map((row) => row.read<String>('detail')).join(' '),
          contains('idx_external_track_refs_identity'));
    });
  });

  test('associations persist after reopening a real SQLite file', () async {
    final dir = await Directory.systemTemp.createTemp('cmp_external_refs_');
    addTearDown(() => dir.delete(recursive: true));
    final path = File(p.join(dir.path, 'library.sqlite'));
    final first = _Fixture(database: AppDatabase(NativeDatabase(path)));
    final track = await first.track('/music/a.mp3');
    await first.external.linkAll([first.ref(track)]);
    await first.database.close();
    final second = _Fixture(database: AppDatabase(NativeDatabase(path)));
    addTearDown(second.database.close);
    expect(
        await second.external.findRefs(second.identity()), [second.ref(track)]);
    expect(
        await second.database
            .customSelect('PRAGMA integrity_check')
            .get()
            .then((rows) => rows.single.data.values.single),
        'ok');
  });
}

final class _Fixture {
  _Fixture({AppDatabase? database})
      : database = database ?? AppDatabase(NativeDatabase.memory()) {
    repo = DriftRepositories(this.database);
  }
  final AppDatabase database;
  late final DriftRepositories repo;
  ExternalTrackRepository get external => repo.externalTracks;
  final now = DateTime.utc(2026, 10, 15);
  ExternalTrackIdentity identity(
          {String provider = 'yandex_music',
          String id = '1',
          String version = ''}) =>
      ExternalTrackIdentity(
          provider: provider, externalId: id, variantKey: version);
  ExternalTrackRef ref(int track,
          {ExternalTrackIdentity? identity,
          ExternalTrackRefOrigin origin =
              ExternalTrackRefOrigin.providerResponse,
          DateTime? at}) =>
      ExternalTrackRef(
          trackId: track,
          identity: identity ?? this.identity(),
          origin: origin,
          linkedAt: at ?? now);
  Future<int> track(String path, {int? folder, bool missing = false}) =>
      repo.tracks.upsertTrack(Track(
          filePath: path,
          libraryFolderId: folder,
          isMissing: missing,
          title: 'Same title',
          artist: 'Same artist',
          addedAt: now,
          updatedAt: now));
  Future<int> folder() => repo.libraryFolders.upsertFolder(
      LibraryFolder(path: '/music', createdAt: now, updatedAt: now));
}
