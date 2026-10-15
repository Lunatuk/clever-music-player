import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' as tags;
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/flac_metadata_fixture.dart';

void main() {
  late Directory root;
  setUp(() async =>
      root = await Directory.systemTemp.createTemp('cmp_artist_roles_'));
  tearDown(() async {
    final allowed = await Directory.systemTemp.resolveSymbolicLinks();
    final target = await root.resolveSymbolicLinks();
    expect(p.isWithin(allowed, target), isTrue);
    await Directory(target).delete(recursive: true);
  });
  Future<void> check(List<int> bytes, String extension, String artist,
      String? albumArtist) async {
    final file =
        await File(p.join(root.path, 'fixture.$extension')).writeAsBytes(bytes);
    final direct = tags.readMetadata(file);
    final background = await const AudioMetadataReaderService().read(file);
    expect(direct.artist, artist);
    expect(direct.albumArtist, albumArtist);
    expect(background.artist, artist);
    expect(background.albumArtist, albumArtist);
    expect(await file.readAsBytes(), bytes);
    await file.delete(); // Both parser paths must have released their readers.
  }

  test('MP3 TPE1 is the track artist, TPE2 is the album artist', () async {
    await check(
        _id3({
          'TIT2': 'Fixture song',
          'TPE2': 'Various artists',
          'TPE1': 'Solo singer'
        }),
        'mp3',
        'Solo singer',
        'Various artists');
  });
  test('MP3 with only TPE2 retains its legacy artist fallback', () async {
    await check(_id3({'TIT2': 'Fixture song', 'TPE2': 'Orchestra'}), 'mp3',
        'Orchestra', 'Orchestra');
  });
  test('MP3 with only TPE1 does not invent an album artist', () async {
    await check(_id3({'TIT2': 'Fixture song', 'TPE1': 'Singer'}), 'mp3',
        'Singer', null);
  });
  for (final albumFirst in [true, false]) {
    test('M4A artist roles do not depend on atom order: $albumFirst', () async {
      final roles = albumFirst
          ? {'aART': 'Various artists', '©ART': 'Solo singer'}
          : {'©ART': 'Solo singer', 'aART': 'Various artists'};
      await check(_mp4({'©nam': 'Fixture song', ...roles}), 'm4a',
          'Solo singer', 'Various artists');
    });
  }
  test('M4A with only album artist retains a useful artist fallback', () async {
    await check(_mp4({'©nam': 'Fixture song', 'aART': 'Orchestra'}), 'm4a',
        'Orchestra', 'Orchestra');
  });
  for (final key in ['ALBUMARTIST', 'ALBUM_ARTIST', 'ALBUM ARTIST']) {
    test('FLAC $key before ARTIST cannot replace the track artist', () async {
      await check(
          flacMetadataFixture(tagValues: [
            'TITLE=Fixture song',
            '$key=Various artists',
            'ARTIST=Solo singer'
          ]),
          'flac',
          'Solo singer',
          'Various artists');
    });
  }
  test('FLAC ARTIST before ALBUMARTIST remains the track artist', () async {
    await check(
        flacMetadataFixture(tagValues: [
          'TITLE=Fixture song',
          'ARTIST=Solo singer',
          'ALBUMARTIST=Various artists'
        ]),
        'flac',
        'Solo singer',
        'Various artists');
  });
  for (final flac in [true, false]) {
    test('${flac ? 'FLAC' : 'M4A'} low-level writer retains both artist roles',
        () async {
      final file =
          await File(p.join(root.path, flac ? 'rewrite.flac' : 'rewrite.m4a'))
              .writeAsBytes(flac
                  ? flacMetadataFixture(tagValues: [
                      'TITLE=Before',
                      'ARTIST=Track singer',
                      'ALBUMARTIST=Album singer'
                    ])
                  : _mp4({
                      '©nam': 'Before',
                      '©ART': 'Track singer',
                      'aART': 'Album singer'
                    }));
      final metadata = tags.readAllMetadata(file);
      if (flac) {
        final vorbis = metadata as tags.VorbisMetadata;
        vorbis.title = ['After'];
        tags.FlacWriter().write(file, vorbis);
      } else {
        final mp4 = metadata as tags.Mp4Metadata;
        mp4.title = 'After';
        tags.Mp4Writer().write(file, mp4);
      }
      final after = tags.readMetadata(file);
      expect(after.title, 'After');
      expect(after.artist, 'Track singer');
      expect(after.albumArtist, 'Album singer');
      await file.delete();
    });
  }
  test('FLAC writer adds comments even when STREAMINFO was the only block',
      () async {
    final bytes = flacMetadataFixture().sublist(0, 42);
    bytes[4] |= 128;
    final file = await File(p.join(root.path, 'streaminfo-only.flac'))
        .writeAsBytes([...bytes, 1, 2, 3, 4]);
    final metadata = tags.readAllMetadata(file) as tags.VorbisMetadata;
    metadata.title = ['After'];
    metadata.artist = ['Track singer'];
    metadata.albumArtist = ['Album singer'];
    tags.FlacWriter().write(file, metadata);
    final after = tags.readMetadata(file);
    expect(after.title, 'After');
    expect(after.artist, 'Track singer');
    expect(after.albumArtist, 'Album singer');
    expect((await file.readAsBytes()).sublist((await file.length()) - 4),
        [1, 2, 3, 4]);
    await file.delete();
  });
  test('FLAC with only album artist retains its useful legacy fallback',
      () async {
    await check(
        flacMetadataFixture(
            tagValues: ['TITLE=Fixture song', 'ALBUMARTIST=Orchestra']),
        'flac',
        'Orchestra',
        'Orchestra');
  });
}

// Parser-only independent tag/container fixtures. No encoded audio or playback.
List<int> _id3(Map<String, String> values) {
  List<int> syncSafe(int size) =>
      [size >> 21 & 127, size >> 14 & 127, size >> 7 & 127, size & 127];
  final frames = <int>[];
  for (final entry in values.entries) {
    final body = [3, ...utf8.encode(entry.value)];
    frames.addAll(
        [...ascii.encode(entry.key), ...syncSafe(body.length), 0, 0, ...body]);
  }
  return [
    ...ascii.encode('ID3'),
    4,
    0,
    0,
    ...syncSafe(frames.length),
    ...frames
  ];
}

List<int> _mp4(Map<String, String> values) {
  List<int> atom(String type, List<int> body) => [
        ...(ByteData(4)..setUint32(0, body.length + 8)).buffer.asUint8List(),
        ...latin1.encode(type),
        ...body
      ];
  final text = <int>[];
  for (final entry in values.entries) {
    text.addAll(atom(entry.key,
        atom('data', [0, 0, 0, 1, 0, 0, 0, 0, ...utf8.encode(entry.value)])));
  }
  return [
    ...atom(
        'ftyp', [...ascii.encode('M4A '), 0, 0, 0, 0, ...ascii.encode('isom')]),
    ...atom('moov',
        atom('udta', atom('meta', [0, 0, 0, 0, ...atom('ilst', text)]))),
  ];
}
