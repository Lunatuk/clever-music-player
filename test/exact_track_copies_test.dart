import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/exact_track_copies.dart';
import 'package:clever_music_player/src/library/library_track_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hash = 'file-sha256-v1:3:${'a' * 64}';
  Track track(int id, {String? contentHash, bool missing = false}) => Track(
        id: id,
        filePath: '/folder$id/song.mp3',
        title: 'Same title',
        artist: 'Same artist',
        album: 'Same album',
        duration: const Duration(minutes: 3),
        fileSizeBytes: 3,
        contentHash: contentHash,
        isMissing: missing,
        addedAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
  List<Track> visible(
    List<Track> tracks, {
    String search = '',
    bool showCopies = false,
    bool showMissing = false,
  }) =>
      buildVisibleLibraryTracks(
        tracks: tracks,
        searchQuery: search,
        showMissingTracks: showMissing,
        showExactCopies: showCopies,
        sortOption: LibraryTrackSortOption.title,
      );

  test(
      'identical tags, sizes and duration never hide unknown/different content',
      () {
    final tracks = [
      track(1),
      track(2),
      track(3, contentHash: hash),
      track(4, contentHash: 'file-sha256-v1:3:${'b' * 64}'),
      track(5, contentHash: 'old-signature'),
      track(6, contentHash: 'old-signature'),
    ];
    expect(visible(tracks), hasLength(6));
  });

  test('exact copies use original ID independently of input order and sort',
      () {
    final original = track(1, contentHash: hash);
    final copy = track(2, contentHash: hash);
    expect(visible([copy, original]), [original]);
    expect(visible([original, copy]), [original]);
    expect(visible([original, copy], showCopies: true), hasLength(2));
    expect(original.copyWith().contentHash, hash);
    expect(original.copyWith(contentHash: null).contentHash, isNull);
  });

  test('searching an alternate path still finds its exact copy', () {
    final original = track(1, contentHash: hash);
    final copy = track(2, contentHash: hash);
    expect(visible([original, copy], search: 'folder2'), [copy]);
  });

  test('available copy takes precedence over missing original', () {
    final missing = track(1, contentHash: hash, missing: true);
    final available = track(2, contentHash: hash);
    expect(visible([missing, available], showMissing: true), [available]);
    expect(visible([missing, available]), [available]);
    expect(visible([missing], showMissing: true), [missing]);
    expect(visible([missing]), isEmpty);
  });

  test('unpersisted copies choose a deterministic path after persisted copies',
      () {
    final a = track(1, contentHash: hash);
    final b = Track(
      filePath: '/a/song.mp3',
      contentHash: hash,
      addedAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final c = b.copyWith(filePath: '/z/song.mp3');
    expect(withoutExactTrackCopies([b, a]), [a]);
    expect(withoutExactTrackCopies([c, b]), [b]);
  });
}
