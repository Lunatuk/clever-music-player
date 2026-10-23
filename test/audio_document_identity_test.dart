import 'package:clever_music_player/src/domain/models/audio_document_identity.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/exact_track_copies.dart';
import 'package:clever_music_player/src/library/library_track_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String document(String tree, String id,
          {String authority = 'music.documents'}) =>
      'content://$authority/tree/${Uri.encodeComponent(tree)}/document/${Uri.encodeComponent(id)}';
  Track track(int id, String path, {bool missing = false, String? hash}) =>
      Track(
          id: id,
          filePath: path,
          title: 'Same title',
          artist: 'Same artist',
          isMissing: missing,
          contentHash: hash,
          addedAt: DateTime(2026),
          updatedAt: DateTime(2026));
  final parent = document('primary:Music', 'primary:Music/Загрузки/song.mp3');
  final child =
      document('primary:Music/Загрузки', 'primary:Music/Загрузки/song.mp3');

  test(
      'different tree grants identify one exact provider/document without a hash',
      () {
    expect(audioDocumentIdentity(parent), audioDocumentIdentity(child));
    final a = track(1, parent), b = track(2, child);
    expect(withoutExactTrackCopies([b, a]), [a]);
    expect(withoutExactTrackCopies([a, b]), [a]);
  });
  test('direct document and a tree document use the same opaque identity', () {
    final id = Uri.encodeComponent('primary:Music/Загрузки/song.mp3');
    expect(audioDocumentIdentity('content://music.documents/document/$id'),
        audioDocumentIdentity(child));
  });
  test(
      'percent escape case is normalized once, literal escaped ID stays distinct',
      () {
    expect(audioDocumentIdentity(parent.toLowerCase()),
        isNot(audioDocumentIdentity(parent)));
    expect(
        audioDocumentIdentity(
            parent.replaceAll('%3A', '%3a').replaceAll('%2F', '%2f')),
        audioDocumentIdentity(parent));
    expect(audioDocumentIdentity(document('opaque', 'a%2Fb')),
        isNot(audioDocumentIdentity(document('opaque', 'a/b'))));
  });
  test('opaque IDs never infer directory relationships or compare names', () {
    final rows = [
      track(1, document('one', 'A')),
      track(2, document('two', 'A/child')),
      track(3, document('two', 'a'))
    ];
    expect(withoutExactTrackCopies(rows), rows);
  });
  test('provider authority is part of the document identity', () {
    final rows = [
      track(1, parent),
      track(
          2,
          document('primary:Music', 'primary:Music/Загрузки/song.mp3',
              authority: 'other.documents'))
    ];
    expect(withoutExactTrackCopies(rows), rows);
  });
  for (final address in [
    '/music/song.mp3',
    'C:\\Music\\song.mp3',
    'content://media/external/audio/media/42',
    'content://music.documents/tree/one',
    'content://music.documents/tree//document/id',
    'content://music.documents/tree/one/document/',
    'content://music.documents/document/',
    'content://music.documents/tree/one/document/id/extra',
    'content://music.documents/document/id?variant=2',
    'content://music.documents/document/id#fragment',
    'content://music.documents/document/%00',
    'content://music.documents/document/%ZZ',
  ]) {
    test('unproven address never authorizes collapse: $address', () {
      expect(audioDocumentIdentity(address), isNull);
      final rows = [track(1, address), track(2, address)];
      expect(withoutRepeatedAudioSources(rows), rows);
    });
  }
  test(
      'available alias wins over missing alias, lowest saved ID wins otherwise',
      () {
    final missing = track(1, parent, missing: true),
        available = track(2, child);
    expect(withoutExactTrackCopies([missing, available]), [available]);
    expect(withoutExactTrackCopies([available, missing]), [available]);
  });
  test('distinct documents with identical title and size remain visible', () {
    final rows = [
      track(1, parent),
      track(2, document('primary:Music', 'other-song.mp3'))
    ];
    expect(withoutExactTrackCopies(rows), rows);
  });
  test('showing physical byte copies still never duplicates one document grant',
      () {
    final rows = [track(2, child), track(1, parent)];
    for (final showCopies in [false, true]) {
      final visible = buildVisibleLibraryTracks(
          tracks: rows,
          searchQuery: '',
          showMissingTracks: false,
          sortOption: LibraryTrackSortOption.title,
          showExactCopies: showCopies);
      expect(visible.map((t) => t.id), [1]);
    }
    expect(rows, hasLength(2));
  });
  test(
      'search filters aliases before collapse so the matching address is playable',
      () {
    final rows = [track(1, parent), track(2, child)];
    final visible = buildVisibleLibraryTracks(
        tracks: rows,
        searchQuery: 'unique',
        showMissingTracks: false,
        sortOption: LibraryTrackSortOption.title);
    expect(visible, isEmpty);
    final matching = buildVisibleLibraryTracks(
        tracks: [rows[0], rows[1].copyWith(title: 'Unique')],
        searchQuery: 'unique',
        showMissingTracks: false,
        sortOption: LibraryTrackSortOption.title);
    expect(matching.single.source, rows[1].source);
  });
  test('verified physical copies still collapse after the document alias pass',
      () {
    final hash = 'file-sha256-v1:3:${'a' * 64}';
    final rows = [
      track(2, child, hash: hash),
      track(1, parent, hash: hash),
      track(3, '/separate/file.mp3', hash: hash)
    ];
    expect(withoutExactTrackCopies(rows).map((t) => t.id), [1]);
    expect(withoutRepeatedAudioSources(rows).map((t) => t.id), [1, 3]);
  });
}
