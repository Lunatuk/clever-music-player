import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/library_track_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search matches title artist album and file path', () {
    final tracks = [
      _track(
        id: 1,
        title: 'Midnight City',
        artist: 'M83',
        album: 'Hurry Up',
        filePath: '/library/electronic/midnight.mp3',
      ),
      _track(
        id: 2,
        title: 'Reckoner',
        artist: 'Radiohead',
        album: 'In Rainbows',
        filePath: '/library/rock/reckoner.flac',
      ),
      _track(
        id: 3,
        title: 'Intro',
        artist: 'The xx',
        album: 'xx',
        filePath: '/library/dream-pop/intro.m4a',
      ),
    ];

    expect(_matchingTitles(tracks, 'midnight'), ['Midnight City']);
    expect(_matchingTitles(tracks, 'radiohead'), ['Reckoner']);
    expect(_matchingTitles(tracks, 'rain'), ['Reckoner']);
    expect(_matchingTitles(tracks, 'dream-pop'), ['Intro']);
  });

  test('search is case insensitive', () {
    final tracks = [
      _track(
        id: 1,
        title: 'Sparks',
        artist: 'Coldplay',
        album: 'Parachutes',
        filePath: '/library/Sparks.mp3',
      ),
    ];

    expect(_matchingTitles(tracks, 'SPARKS'), ['Sparks']);
    expect(_matchingTitles(tracks, 'coldPLAY'), ['Sparks']);
  });

  test('sort by title uses display title', () {
    final tracks = [
      _track(id: 1, title: 'Beta', filePath: '/music/b.mp3'),
      _track(id: 2, title: null, filePath: '/music/alpha-file.mp3'),
      _track(id: 3, title: 'Alpha', filePath: '/music/a.mp3'),
    ];

    final sorted = sortLibraryTracks(
      tracks,
      sortOption: LibraryTrackSortOption.title,
    );

    expect(sorted.map((track) => track.displayTitle), [
      'Alpha',
      'alpha-file.mp3',
      'Beta',
    ]);
  });

  test('sort by artist uses artist then title', () {
    final tracks = [
      _track(id: 1, title: 'Zulu', artist: 'Beta'),
      _track(id: 2, title: 'Bravo', artist: 'Alpha'),
      _track(id: 3, title: 'Alpha', artist: 'Alpha'),
    ];

    final sorted = sortLibraryTracks(
      tracks,
      sortOption: LibraryTrackSortOption.artist,
    );

    expect(sorted.map((track) => track.title), ['Alpha', 'Bravo', 'Zulu']);
  });

  test('sort by album uses album then track number then title', () {
    final tracks = [
      _track(id: 1, title: 'Second', album: 'Album A', trackNumber: 2),
      _track(id: 2, title: 'Other', album: 'Album B', trackNumber: 1),
      _track(id: 3, title: 'First', album: 'Album A', trackNumber: 1),
      _track(id: 4, title: 'Untitled', album: 'Album A'),
    ];

    final sorted = sortLibraryTracks(
      tracks,
      sortOption: LibraryTrackSortOption.album,
    );

    expect(sorted.map((track) => track.title), [
      'First',
      'Second',
      'Untitled',
      'Other',
    ]);
  });

  test('missing tracks are hidden by default', () {
    final tracks = [
      _track(id: 1, title: 'Visible'),
      _track(id: 2, title: 'Missing', isMissing: true),
    ];

    final visible = buildVisibleLibraryTracks(
      tracks: tracks,
      searchQuery: '',
      showMissingTracks: false,
      sortOption: LibraryTrackSortOption.title,
    );

    expect(visible.map((track) => track.title), ['Visible']);
  });

  test('missing tracks can be shown when enabled', () {
    final tracks = [
      _track(id: 1, title: 'Visible'),
      _track(id: 2, title: 'Missing', isMissing: true),
    ];

    final visible = buildVisibleLibraryTracks(
      tracks: tracks,
      searchQuery: '',
      showMissingTracks: true,
      sortOption: LibraryTrackSortOption.title,
    );

    expect(visible.map((track) => track.title), ['Missing', 'Visible']);
  });
}

List<String> _matchingTitles(List<Track> tracks, String query) {
  return buildVisibleLibraryTracks(
    tracks: tracks,
    searchQuery: query,
    showMissingTracks: false,
    sortOption: LibraryTrackSortOption.title,
  ).map((track) => track.displayTitle).toList(growable: false);
}

Track _track({
  required int id,
  String? title,
  String? artist,
  String? album,
  String? albumArtist,
  String? filePath,
  int? trackNumber,
  bool isMissing = false,
}) {
  final now = DateTime(2026);
  return Track(
    id: id,
    filePath: filePath ?? '/music/$id.mp3',
    title: title,
    artist: artist,
    album: album,
    albumArtist: albumArtist,
    trackNumber: trackNumber,
    isMissing: isMissing,
    addedAt: now,
    updatedAt: now,
  );
}
