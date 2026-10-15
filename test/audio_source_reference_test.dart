import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/stable_track_id.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'desktop path storage preserves Unicode case percent hashes and separators',
      () {
    for (final path in [
      r'C:\Музыка\100% #.mp3',
      'C:/Music/Song.MP3',
      'C://Music/Song.mp3',
      r'\\server\Music\Song.flac',
      '/Users/test/Music/Песня.m4a',
      'music/../Song.mp3',
      'content:local-song.mp3'
    ]) {
      final source = AudioSourceReference.fromStorage(path);
      expect(source, isA<FileAudioSource>());
      expect((source as FileAudioSource).path, path);
      expect(source.storageValue, path);
      expect(FileAudioSource(path), source);
    }
  });

  test(
      'provider addresses preserve encoded document IDs query and original storage',
      () {
    for (final value in [
      'content://media/external/audio/media/123',
      'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AMusic%2F%D0%9F%D0%B5%D1%81%D0%BD%D1%8F.mp3',
      'content://10@provider/document/Artist%2FSong%25%23.flac?version=2#part',
      'CONTENT://Provider/document/ID%2fValue'
    ]) {
      final source = AudioSourceReference.fromStorage(value);
      expect(source, isA<ContentUriAudioSource>());
      expect(source.storageValue, value);
      expect((source as ContentUriAudioSource).uri.scheme, 'content');
      expect(source.uri.hasAuthority, isTrue);
      expect(ContentUriAudioSource(value), source);
    }
  });

  test('opaque provider identities are not lowercased or path-normalized', () {
    final a =
        ContentUriAudioSource('content://provider/document/Artist%2FSong');
    final b =
        ContentUriAudioSource('content://provider/document/artist%2FSong');
    final c = ContentUriAudioSource('content://provider/document/Artist/Song');
    expect(a, isNot(b));
    expect(a, isNot(c));
    expect(a.hashCode, ContentUriAudioSource(a.storageValue).hashCode);
    expect({a, b, c, ContentUriAudioSource(a.storageValue)}, hasLength(3));
  });

  test('malformed content URIs fail without including private input in errors',
      () {
    for (final value in [
      'content://',
      'content:///PRIVATE',
      'content://PRIVATE',
      'content://provider/PRIVATE%zz',
      'content://provider/PRIVATE%2',
      'content://provider/PRIVATE space',
      'content://provider/PRIVATE\n',
      'content://provider/PRIVATE\u0000',
      'https://PRIVATE/path',
      'PRIVATE/relative'
    ]) {
      try {
        ContentUriAudioSource(value);
        fail('Expected invalid URI');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains('PRIVATE')));
      }
    }
  });

  test('file references reject URI addresses and invalid paths', () {
    for (final value in [
      '',
      'file://PRIVATE/file.mp3',
      'content://PRIVATE/document/1',
      'https://PRIVATE/song.mp3',
      'PRIVATE\u0000.mp3'
    ]) {
      expect(() => FileAudioSource(value), throwsFormatException);
    }
    expect(() => AudioSourceReference.fromStorage('https://PRIVATE/song.mp3'),
        throwsUnsupportedError);
    expect(() => AudioSourceReference.fromStorage('file:///PRIVATE/song.mp3'),
        throwsUnsupportedError);
  });

  test('typed track factory and metadata edits retain the original source', () {
    final source =
        ContentUriAudioSource('content://provider/document/Artist%2FSong');
    final track = Track.fromSource(
        source: source,
        id: 41,
        libraryFolderId: 2,
        stableId: 'metadata',
        contentHash: 'hash',
        title: 'Title',
        artist: 'Artist',
        album: 'Album',
        albumArtist: 'Album artist',
        genre: 'Rock',
        artworkPath: '/cover.jpg',
        artworkHash: 'coverhash',
        artworkMimeType: 'image/jpeg',
        customArtworkPath: '/custom.jpg',
        customArtworkHash: 'customhash',
        customArtworkMimeType: 'image/jpeg',
        codec: 'flac',
        duration: const Duration(minutes: 3),
        trackNumber: 2,
        discNumber: 1,
        year: 2026,
        metadataSource: MetadataSource.manual,
        metadataConfidence: 1,
        fileSizeBytes: 300,
        modifiedAt: DateTime(2026),
        lastSeenAt: DateTime(2026),
        addedAt: DateTime(2026),
        updatedAt: DateTime(2026));
    expect(track.copyWith(), track);
    expect(track.source, source);
    expect(track.filePath, source.storageValue);
    final edited = track.copyWith(title: 'Edited');
    expect(edited.source, source);
    expect(edited.id, 41);
    expect(edited.customArtworkHash, 'customhash');
    expect(edited.duration, const Duration(minutes: 3));
    final moved = edited.copyWith(source: FileAudioSource('/music/Song.flac'));
    expect(moved.source, isA<FileAudioSource>());
    expect(moved.id, 41);
    expect(moved.title, 'Edited');
    expect(() => track.copyWith(source: source, filePath: '/other'),
        throwsArgumentError);
  });

  test('URI fallback title does not expose an opaque provider address', () {
    final track =
        _track(ContentUriAudioSource('content://PRIVATE/document/123'));
    expect(track.displayTitle, 'Без названия');
    expect(track.copyWith(title: ' Песня ').displayTitle, 'Песня');
    expect(_track(FileAudioSource(r'C:\music\Песня #1.mp3')).displayTitle,
        'Песня #1.mp3');
  });

  test('metadata-free URI signatures preserve case and encoded path separators',
      () {
    final a = generateStableTrackId(
        filePath: 'content://provider/document/Song%2FOne');
    expect(
        a,
        generateStableTrackId(
            filePath: 'content://provider/document/Song%2FOne'));
    expect(
        a,
        isNot(generateStableTrackId(
            filePath: 'content://provider/document/song%2FOne')));
    expect(
        a,
        isNot(generateStableTrackId(
            filePath: 'content://provider/document/Song/One')));
  });

  test('schema 11 persists both address types and distinguishes provider IDs',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final values = [
      '/music/Песня #1.mp3',
      'content://provider/document/Song%2FOne',
      'content://provider/document/song%2FOne',
      'content://provider/document/Song/One'
    ];
    final ids = <int>[];
    for (final value in values) {
      final track = _track(AudioSourceReference.fromStorage(value));
      final id = await repositories.tracks.upsertTrack(track);
      ids.add(id);
      final saved = (await repositories.tracks.findById(id))!;
      expect(saved.source, track.source);
      expect(saved.filePath, value);
      expect(await repositories.tracks.upsertTrack(track), id);
    }
    expect(ids.toSet(), hasLength(values.length));
    expect(await repositories.tracks.listTracks(), hasLength(values.length));
    expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        11);
  });

  test(
      'explicit address change retains persisted ID feedback and playback history',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final id = await repositories.tracks
        .upsertTrack(_track(FileAudioSource('/music/original.mp3')));
    await repositories.trackUserState
        .toggleFeedback(id, TrackFeedback.like, updatedAt: DateTime(2026));
    await repositories.playbackEvents.recordEvent(PlaybackEvent.recording(
        trackId: id,
        type: PlaybackEventType.started,
        occurredAt: DateTime(2026)));
    final playlist = await repositories.playlists.createPlaylist('Test');
    await repositories.playlists.addTrackToPlaylist(playlist, id);
    final original = (await repositories.tracks.findById(id))!;
    final source =
        ContentUriAudioSource('content://provider/document/New%2FAddress');
    expect(
        await repositories.tracks
            .upsertTrack(original.copyWith(source: source)),
        id);
    final saved = (await repositories.tracks.findById(id))!;
    expect(saved.source, source);
    final state = (await repositories.trackUserState.findByTrackId(id))!;
    expect(state.isFavorite, isTrue);
    expect(state.playCount, 1);
    expect(await repositories.playbackEvents.recentForTrack(id), hasLength(1));
    final entry =
        (await repositories.playlists.watchPlaylistTracks(playlist).first)
            .single;
    expect(entry.trackId, id);
    expect(entry.track.source, source);
  });
}

Track _track(AudioSourceReference source) => Track.fromSource(
    source: source, addedAt: DateTime(2026), updatedAt: DateTime(2026));
