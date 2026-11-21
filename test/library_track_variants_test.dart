import 'dart:async';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_library_variant_repository.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/audio_comparison.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/library_track_list.dart';
import 'package:clever_music_player/src/library/library_track_variants.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search finds all known versions and tags outrank verified audio', () {
    final rich = track(1, 'Andromeda').copyWith(album: 'Andromeda', year: 2019);
    final sparse = track(2, 'Alternate title');
    final namesake = track(3, 'Andromeda');
    final evidence = LibraryVariantEvidence(
      identities: {
        1: {release},
        2: {identity()},
        3: {identity(id: '22')}
      },
      quality: {2: (codec: 'flac', profile: 'yandex_flac_lossless')},
    );
    final view = build([sparse, rich, namesake], evidence);
    expect(view.tracks, [rich, namesake]);
    expect(view.versions[rich.filePath]!.tracks, [rich, sparse]);
    final searched =
        build([sparse, rich, namesake], evidence, query: 'Alternate');
    expect(searched.tracks, [rich]);
    expect(
        view.versions[rich.filePath]!.withPlaybackVersion(sparse, view.tracks),
        [sparse, namesake]);
  });

  test(
      'ambiguous releases, contradictory sources and different cuts stay visible',
      () {
    final tracks = [for (var id = 1; id <= 5; id++) track(id, 'Song')];
    tracks[4] = tracks[4].copyWith(duration: const Duration(seconds: 72));
    final view = build(
        tracks,
        LibraryVariantEvidence(identities: {
          1: {release},
          2: {identity(album: '328')},
          3: {identity()},
          4: {release, identity(id: '22')},
          5: {release},
        }));
    expect(view.tracks, hasLength(5));
    expect(view.versions, isEmpty);
  });

  test(
      'verified lossless breaks a metadata tie and preference respects availability',
      () {
    final first = track(1, 'Song');
    final second = track(2, 'Song');
    final quality = {2: (codec: 'flac', profile: 'yandex_flac_lossless')};
    final links = {
      1: {release},
      2: {release}
    };
    expect(
        build([first, second],
                LibraryVariantEvidence(identities: links, quality: quality))
            .tracks,
        [second]);
    final evidence = LibraryVariantEvidence(
        identities: links, quality: quality, preferred: {release: 1});
    expect(build([first, second], evidence).tracks, [first]);
    expect(
        build([first.copyWith(isMissing: true), second], evidence,
                showMissing: true)
            .tracks,
        [second]);
  });

  test(
      'exact copies keep their original control including inside a version group',
      () {
    final key = FileContentIdentity(sizeBytes: 10, sha256: 'a' * 64).storageKey;
    final first =
        track(1, 'Song').copyWith(fileSizeBytes: 10, contentHash: key);
    final copy =
        track(2, 'A copy').copyWith(fileSizeBytes: 10, contentHash: key);
    final third = track(3, 'Song');
    final evidence = LibraryVariantEvidence(identities: {
      1: {release},
      2: {release},
      3: {release}
    }, preferred: {
      release: 2
    });
    expect(build([first, copy], evidence).tracks, [first]);
    expect(
        build([first, copy], evidence, showCopies: true).tracks, hasLength(2));
    final collapsed = build([first, copy, third], evidence);
    expect(collapsed.tracks, [copy]);
    expect(collapsed.versions[copy.filePath]!.tracks, [copy, third]);
    final withCopies = build([first, copy, third], evidence, showCopies: true);
    expect(withCopies.versions[copy.filePath]!.tracks, [copy, first, third]);
    // The path of a hidden byte-for-byte copy is still searchable.
    expect(
        build([first, copy, third], evidence, query: '/1.m4a').tracks, [copy]);
  });

  test('stored selection, scope and evidence survive repository recreation',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repo = DriftRepositories(database);
    final folder = await repo.libraryFolders.upsertFolder(
        LibraryFolder(path: '/folder', createdAt: now, updatedAt: now));
    final first = await repo.tracks
        .upsertTrack(track(1, 'Song').copyWith(libraryFolderId: folder));
    final second = await repo.tracks.upsertTrack(track(2, 'Version'));
    final stale = await repo.tracks.upsertTrack(track(3, 'Replaced file'));
    ExternalTrackRef link(int id, ExternalTrackRefOrigin source) =>
        ExternalTrackRef(
            trackId: id, identity: release, origin: source, linkedAt: now);
    await repo.externalTracks.linkAll([
      link(first, ExternalTrackRefOrigin.embeddedTag),
      link(second, ExternalTrackRefOrigin.embeddedTag),
      link(stale, ExternalTrackRefOrigin.providerResponse),
    ]);
    final pinned = DriftLibraryVariantRepository(database, repo.settings);
    await pinned.setPreferred(release, second);
    final restored = DriftLibraryVariantRepository(database, repo.settings);
    final evidence = await restored.watchEvidence().first;
    expect(evidence.identities.keys, unorderedEquals([first, second]));
    expect(evidence.preferred[release], second);
    await repo.libraryFolders
        .setFolderEnabled(folder, isEnabled: false, updatedAt: now);
    expect((await restored.watchEvidence().first).identities.keys, [second]);
    await restored.setPreferred(release, null);
    expect((await restored.watchEvidence().first).preferred, isEmpty);
  });

  test('Android aliases of a member stay one source under a different grant',
      () {
    final first = track(1, 'Original title')
        .copyWith(filePath: 'content://test/tree/music/document/shared');
    final alias = track(2, 'Other grant')
        .copyWith(filePath: 'content://test/tree/album/document/shared');
    final second =
        track(3, 'New title').copyWith(filePath: 'content://test/document/new');
    final evidence = LibraryVariantEvidence(identities: {
      1: {release},
      3: {release}
    });
    final view = build([first, alias, second], evidence, showCopies: true);
    expect(view.tracks, [first]);
    expect(view.versions[first.filePath]!.tracks, [first, second]);
    expect(build([first, alias, second], evidence, query: 'Other grant').tracks,
        [first]);
  });

  test('an imported provider link is bound to its verified bytes', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repo = DriftRepositories(database);
    final evidenceRepo = DriftLibraryVariantRepository(database, repo.settings);
    final proof = DownloadedAssetVerification(
        actualQuality: 'yandex_flac_lossless',
        container: 'flac',
        codec: 'flac',
        fileSizeBytes: 10,
        duration: const Duration(seconds: 60),
        contentHash: 'a' * 64,
        checkedAt: now);
    final file = track(1, 'Song').copyWith(
        filePath: '/folder/1.flac',
        fileSizeBytes: 10,
        contentHash: proof.fileContentKey);
    final id = await repo.tracks.upsertTrack(file);
    await repo.externalTracks.linkAll([
      ExternalTrackRef(
          trackId: id,
          identity: release,
          origin: ExternalTrackRefOrigin.providerResponse,
          linkedAt: now),
    ]);
    await repo.downloadedAssets.registerVerified(
        DownloadedAssetPublication(
            trackId: id,
            identity: release,
            source: file.source,
            publicationId: 'test-publication',
            requestedQuality: proof.actualQuality),
        proof);
    final verified = await evidenceRepo.watchEvidence().first;
    expect(verified.identities[id], {release});
    expect(verified.quality[id]?.codec, 'flac');
    await repo.tracks.upsertTrack(file.copyWith(
        contentHash:
            FileContentIdentity(sizeBytes: 10, sha256: 'b' * 64).storageKey));
    final changed = await evidenceRepo.watchEvidence().first;
    expect(changed.identities, isEmpty);
    expect(changed.quality, isEmpty);
  });

  test('PCM variants persist and react to replacement after a scan', () async {
    final fixture = _AudioGroupFixture();
    addTearDown(fixture.database.close);
    final (first, second) = await fixture.pair();
    final proof = await fixture.proof(first, second);
    expect(await fixture.matches.rememberAudioMatch(proof),
        AudioMatchSaveResult.saved);
    final fresh = DriftLibraryVariantRepository(
        fixture.database, fixture.repo.settings,
        revisionReader: fixture.readRevision);
    final stream = StreamIterator(fresh.watchEvidence());
    addTearDown(stream.cancel);
    expect(await stream.moveNext(), isTrue);
    final group = build([first, second], stream.current).versions.values.single;
    expect(group.identity.provider, 'local_pcm');
    expect(group.tracks, [first, second]);
    expect(build([first, second], stream.current, query: 'Alternate').tracks,
        [first]);
    final readCount = fixture.revisionReads;
    await fixture.repo.settings.writeString('player.volume', '0.5');
    await fresh.setPreferred(group.identity, second.id);
    expect(await stream.moveNext(), isTrue);
    expect(build([first, second], stream.current).tracks, [second]);
    expect(fixture.revisionReads, readCount);
    fixture.revisions[second.filePath] = 'c' * 64;
    await fixture.repo.tracks.upsertTrack(
        second.copyWith(lastSeenAt: now.add(const Duration(seconds: 5))));
    expect(await stream.moveNext(), isTrue);
    expect(build([first, second], stream.current).tracks, hasLength(2));
    expect(await fresh.rememberAudioMatch(proof), AudioMatchSaveResult.changed);
  });

  test(
      'a matching unlinked version can join a known album without crossing releases',
      () async {
    final fixture = _AudioGroupFixture();
    addTearDown(fixture.database.close);
    final (first, second) = await fixture.pair();
    Future<void> link(Track track, ExternalTrackIdentity identity) =>
        fixture.repo.externalTracks.linkAll([
          ExternalTrackRef(
              trackId: track.id!,
              identity: identity,
              origin: ExternalTrackRefOrigin.embeddedTag,
              linkedAt: now)
        ]);
    await link(first, release);
    final proof = await fixture.proof(first, second);
    expect(await fixture.matches.rememberAudioMatch(proof),
        AudioMatchSaveResult.saved);
    final before = await fixture.matches.watchEvidence().first;
    expect(build([first, second], before).versions.values.single.identity,
        release);
    await link(second, identity(album: '225'));
    final after = await fixture.matches.watchEvidence().first;
    expect(build([first, second], after).tracks, hasLength(2));
    expect(await fixture.matches.rememberAudioMatch(proof),
        AudioMatchSaveResult.releaseConflict);
  });

  test('an unsuccessful save leaves no partial match', () async {
    final fixture = _AudioGroupFixture();
    addTearDown(fixture.database.close);
    final (first, second) = await fixture.pair();
    final proof = await fixture.proof(first, second);
    await fixture.database.customStatement("""
      CREATE TRIGGER reject_second_audio_match BEFORE INSERT ON app_settings
      WHEN NEW.key = '${audioMatchSettingKey(second.id!)}'
      BEGIN SELECT RAISE(ABORT, 'blocked match'); END
    """);
    await expectLater(
        fixture.matches.rememberAudioMatch(proof), throwsException);
    expect((await fixture.matches.watchEvidence().first).audioMatches, isEmpty);
  });

  test('forgetting a saved match and deleting a track respect existing IDs',
      () async {
    final fixture = _AudioGroupFixture();
    addTearDown(fixture.database.close);
    final (first, second) = await fixture.pair();
    final proof = await fixture.proof(first, second);
    await fixture.matches.rememberAudioMatch(proof);
    final evidence = await fixture.matches.watchEvidence().first;
    await fixture.matches
        .forgetAudioMatches({first.id!: '1:48000:2:${'f' * 64}'});
    expect((await fixture.matches.watchEvidence().first).audioMatches,
        evidence.audioMatches);
    await fixture.matches.forgetAudioMatches(evidence.audioMatches);
    expect((await fixture.matches.watchEvidence().first).audioMatches, isEmpty);
    expect(await fixture.repo.tracks.findById(first.id!), isNotNull);
    expect(await fixture.repo.tracks.findById(second.id!), isNotNull);
    await fixture.matches.rememberAudioMatch(proof);
    await fixture.repo.tracks.deleteTrack(first.id!);
    expect(
        await fixture.repo.settings.readString(audioMatchSettingKey(first.id!)),
        isNull);
    expect(await fixture.repo.tracks.findById(second.id!), isNotNull);
  });
}

final class _AudioGroupFixture {
  final database = AppDatabase(NativeDatabase.memory());
  late final repo = DriftRepositories(database);
  late final matches = DriftLibraryVariantRepository(database, repo.settings,
      revisionReader: readRevision);
  final revisions = <String, String>{};
  int revisionReads = 0;

  Future<String?> readRevision(AudioSourceReference source) async {
    revisionReads++;
    return revisions[source.storageValue];
  }

  Future<(Track, Track)> pair() async {
    final left = track(1, 'Original');
    final right = track(2, 'Alternate');
    final firstId =
        await repo.tracks.upsertTrack(left.copyWith(lastSeenAt: now));
    final secondId =
        await repo.tracks.upsertTrack(right.copyWith(lastSeenAt: now));
    revisions[left.filePath] = 'a' * 64;
    revisions[right.filePath] = 'b' * 64;
    return (
      (await repo.tracks.findById(firstId))!,
      (await repo.tracks.findById(secondId))!
    );
  }

  Future<AudioMatchProof> proof(Track first, Track second) async =>
      (await AudioComparisonService((_) async => const _EqualAudioReader(),
                  revisionReader: readRevision)
              .compareWithProof(first, second, control: LibraryScanControl()))
          .proof!;
}

final class _EqualAudioReader implements AudioComparisonReader {
  const _EqualAudioReader();

  @override
  Future<AudioPcmSignature> read(
          AudioSourceReference source, LibraryScanControl control) async =>
      (digest: 'e' * 64, sampleRate: 48000, channels: 2);

  @override
  Future<void> close() async {}
}

final now = DateTime.utc(2026);
final release = identity(album: '127');

ExternalTrackIdentity identity({String id = '11', String album = ''}) =>
    ExternalTrackIdentity(
        provider: 'yandex_music', externalId: id, variantKey: album);

Track track(int id, String title) => Track(
    id: id,
    filePath: '/folder/$id.m4a',
    title: title,
    artist: 'Artist',
    duration: const Duration(seconds: 60),
    metadataSource: MetadataSource.embeddedTags,
    addedAt: now,
    updatedAt: now);

LibraryTrackView build(List<Track> tracks, LibraryVariantEvidence evidence,
        {String query = '',
        bool showMissing = false,
        bool showCopies = false}) =>
    buildLibraryTrackView(
        tracks: tracks,
        evidence: evidence,
        searchQuery: query,
        showMissingTracks: showMissing,
        showExactCopies: showCopies,
        sortOption: LibraryTrackSortOption.title);
