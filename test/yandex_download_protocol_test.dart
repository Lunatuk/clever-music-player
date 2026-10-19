import 'package:clever_music_player/src/domain/models/external_track_ref.dart';
import 'package:clever_music_player/src/domain/models/downloaded_asset.dart';
import 'package:clever_music_player/src/library_sync/yandex_audio_selection.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_protocol.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/yandex_download_fixture.dart';
import 'support/yandex_fixture.dart';

void main() {
  const parser = YandexDownloadParser();
  final metadata =
      parser.metadata(yandexDownloadTrack(), yandexDownloadIdentity);
  YandexDownloadVariant parse(Map<String, dynamic> value,
          {YandexAudioSelection selection = yandexFlacSelection}) =>
      parser.variant(value, yandexAccount, metadata, selection);
  Matcher rejected([YandexDownloadFailure? reason]) =>
      throwsA(isA<YandexDownloadException>().having(
          (e) => e.failure, 'failure', reason ?? isA<YandexDownloadFailure>()));

  test(
      'file-info signature matches independent Python HMAC vectors using bare ID and preserving zeroes',
      () {
    final cases = [
      (yandexFlacSelection, 'aQt4SBTJesbqr9qeVLu/OHXg54xxyiqbT/2FdCh2TIw'),
      (yandexMp3Selection, 'aHFHvL84oWq8Lv5Yc8YyI8AeaKNac4ctjcCaCdNpE+M'),
      (
        YandexAudioSelection.lossy(
            quality: YandexFileQuality.nq,
            encoding: YandexFileEncoding.aacMp4,
            minimumDeclaredKbps: 96,
            minimumMeasuredBitRate: 64000),
        'U8lbEl0tN6MgFHFRDpqeqsimPL8LEJE0YeZ8DeJOMV4'
      ),
    ];
    for (final (selection, expected) in cases) {
      final request = YandexReadRequest.fileInfo('001',
          album: '009', selection: selection, timestamp: 1700000000);
      expect(request.relativeUri.path, '/get-file-info');
      expect(request.relativeUri.queryParameters, {
        'ts': '1700000000',
        'trackId': '001',
        'quality': selection.quality.name,
        'codecs': selection.encoding.apiKey,
        'transports': 'encraw',
        'sign': expected,
      });
      expect(request.usesFormPost, isFalse);
      expect(request.clientHeader, 'YandexMusicDesktopAppWindows/5.95.0');
      expect(request.toString(), isNot(contains(expected)));
      expect(request.toString(), isNot(contains('001')));
      validateAssetQuality(selection.resourceQuality);
    }
  });
  test('track metadata uses one fixed read-only POST and composite identity',
      () {
    final request = YandexReadRequest.track('001', album: '009');
    expect(request.relativeUri.toString(), '/tracks');
    expect(request.usesFormPost, isTrue);
    expect(Uri.splitQueryString(request.formBody!),
        {'track-ids': '001:009', 'with-positions': 'True'});
    expect(request.clientHeader, 'YandexMusicAndroid/24023621');
  });
  for (final id in [
    '0',
    '',
    '../abc',
    '1:2',
    ' 1',
    '1&token=x',
    '1\n',
    'a' * 129
  ]) {
    test('request rejects invalid identity ${id.length}', () {
      expect(() => YandexReadRequest.track(id),
          throwsA(isA<YandexLibraryException>()));
      expect(
          () => YandexReadRequest.fileInfo('1',
              album: id, selection: yandexFlacSelection, timestamp: 1700000000),
          id.isEmpty
              ? returnsNormally
              : throwsA(isA<YandexLibraryException>()));
    });
  }
  test('explicit lossy floors produce distinct job quality keys', () {
    final other = YandexAudioSelection.lossy(
        quality: YandexFileQuality.hq,
        encoding: YandexFileEncoding.mp3,
        minimumDeclaredKbps: 128,
        minimumMeasuredBitRate: 100000);
    expect(other.resourceQuality, isNot(yandexMp3Selection.resourceQuality));
    expect(
        () => YandexAudioSelection.lossy(
            quality: YandexFileQuality.lossless,
            encoding: YandexFileEncoding.mp3,
            minimumDeclaredKbps: 320,
            minimumMeasuredBitRate: 240000),
        throwsArgumentError);
    expect(
        () => YandexAudioSelection.lossy(
            quality: YandexFileQuality.hq,
            encoding: YandexFileEncoding.flac,
            minimumDeclaredKbps: 320,
            minimumMeasuredBitRate: 240000),
        throwsArgumentError);
  });
  test('metadata keeps track and album artists distinct with album context',
      () {
    expect(metadata.identity, yandexDownloadIdentity);
    expect(metadata.duration.inMilliseconds, 3000);
    expect(metadata.tags, {
      'title': 'Provider title',
      'artist': 'Artist',
      'album': 'Album',
      'album_artist': 'Album artist',
      'genre': 'Rock',
      'date': '2026',
      'track': '2',
      'disc': '1'
    });
    expect(() => metadata.tags['title'] = 'changed', throwsUnsupportedError);
    final value = yandexDownloadTrack();
    (value.single as Map)['version'] = 'Live';
    expect(parser.metadata(value, yandexDownloadIdentity).tags['title'],
        'Provider title (Live)');
    final bare = parser.metadata(value,
        ExternalTrackIdentity(provider: 'yandex_music', externalId: '001'));
    expect(bare.tags.keys, unorderedEquals(['title', 'artist']));
  });
  final metadataMutations = <String, void Function(Map<String, dynamic>)>{
    'other track': (v) => v['id'] = '002',
    'different real id': (v) => v['realId'] = '002',
    'different album': (v) => v['albums'] = [
          {'id': '010'}
        ],
    'missing album': (v) => v['albums'] = [],
    'substitution': (v) => v['substituted'] = {'id': '002'},
    'matched alternative': (v) => v['matchedTrack'] = {'id': '002'},
    'unavailable': (v) => v['available'] = false,
    'server error': (v) => v['error'] = 'private message',
    'podcast': (v) => v['type'] = 'podcast',
    'missing duration': (v) => v.remove('durationMs'),
    'zero duration': (v) => v['durationMs'] = 0,
    'oversize duration': (v) => v['durationMs'] = 43200001,
    'missing artists': (v) => v['artists'] = [],
    'invalid artist': (v) => v['artists'] = [
          {'name': '\nPrivate'}
        ],
    'invalid title': (v) => v['title'] = 'x' * 1025,
    'metadata argument budget': (v) =>
        v['artists'] = List.generate(64, (_) => {'name': '🎵' * 128}),
  };
  for (final entry in metadataMutations.entries) {
    test('metadata rejects ${entry.key}', () {
      final data =
          (yandexDownloadTrack().single as Map).cast<String, dynamic>();
      entry.value(data);
      expect(() => parser.metadata([data], yandexDownloadIdentity), rejected());
    });
  }
  test('raw FLAC permits unknown zero size and yields immutable expectation',
      () {
    for (final size in [null, 0, 123]) {
      final variant = parse(yandexDownloadInfo(size: size));
      expect(variant.expectedBytes, size == 123 ? 123 : isNull);
      final expected = variant.expectation(123);
      expect(expected.quality, yandexFlacSelection.resourceQuality);
      expect(expected.tags, metadata.tags);
      expect(expected.fileSizeBytes, 123);
      if (size == 123) {
        expect(() => variant.expectation(124),
            rejected(YandexDownloadFailure.invalidResponse));
      }
      expect(variant.toString(), isNot(contains('strm')));
      expect(variant.address.toString(), isNot(contains('strm')));
      expect(variant.metadata.toString(), isNot(contains('Artist')));
    }
  });
  test('lossy checks nominal AND explicit measured floors without assuming CBR',
      () {
    final variant = parse(yandexDownloadInfo(selection: yandexMp3Selection),
        selection: yandexMp3Selection);
    expect(variant.declaredKbps, 128);
    expect(variant.expectation(123).minimumBitRate, 96000);
    final value = yandexDownloadInfo(selection: yandexMp3Selection);
    (value['downloadInfo'] as Map)['bitrate'] = 127;
    expect(() => parse(value, selection: yandexMp3Selection),
        rejected(YandexDownloadFailure.qualityMismatch));
  });
  test('best available lossy profile accepts nq192 without claiming HQ320', () {
    final value = yandexDownloadInfo(selection: yandexMp3Selection);
    (value['downloadInfo'] as Map)['quality'] = 'nq';
    (value['downloadInfo'] as Map)['bitrate'] = 192;
    final variant = parse(value, selection: yandexMp3Selection);
    expect(variant.declaredKbps, 192);
    expect(variant.expectation(100).minimumBitRate, 96000);
    expect(() => parse(value), rejected(YandexDownloadFailure.qualityMismatch));
  });
  test('raw delivery permits an empty optional key', () {
    final value = yandexDownloadInfo();
    (value['downloadInfo'] as Map)['key'] = '';
    expect(parse(value), isA<YandexDownloadVariant>());
  });
  test('encraw requires a valid key and crypt path from the trusted CDN', () {
    final value = yandexDownloadInfo(
        url: 'https://media.strm.yandex.net/music-v2/crypt/synthetic/flac');
    final info = value['downloadInfo'] as Map;
    info['transport'] = 'encraw';
    info['key'] = '000102030405060708090a0b0c0d0e0f';
    final variant = parse(value);
    expect(variant.toString(), isNot(contains(info['key'])));
    info['url'] = 'https://media.strm.yandex.net/music-v2/raw/synthetic/flac';
    info['urls'] = [info['url']];
    expect(() => parse(value), rejected(YandexDownloadFailure.invalidAddress));
  });
  final variantMutations = <String, void Function(Map<String, dynamic>)>{
    'different track': (v) => v['trackId'] = '002',
    'different album': (v) => v['trackId'] = '001:010',
    'different real id': (v) => v['realId'] = '002',
    'lower quality': (v) => v['quality'] = 'hq',
    'other codec': (v) => v['codec'] = 'mp3',
    'unsupported FLAC MP4': (v) => v['codec'] = 'flac-mp4',
    'encrypted bytes': (v) => v['transport'] = 'encraw',
    'key with raw': (v) => v['key'] = '0123456789abcdef',
    'invalid bitrate': (v) => v['bitrate'] = -1,
    'missing bitrate': (v) => v.remove('bitrate'),
    'negative size': (v) => v['size'] = -1,
    'oversize': (v) => v['size'] = 8589934593,
    'noninteger size': (v) => v['size'] = 1.5,
    'empty urls': (v) => v['urls'] = [],
    'too many urls': (v) => v['urls'] = List.filled(9, v['url']),
    'unlisted primary': (v) =>
        v['url'] = 'https://other.strm.yandex.net/music-v2/raw/synthetic/flac',
  };
  for (final entry in variantMutations.entries) {
    test('variant rejects ${entry.key}', () {
      final value = yandexDownloadInfo();
      entry.value((value['downloadInfo'] as Map).cast<String, dynamic>());
      expect(() => parse(value), rejected());
    });
  }
  for (final url in [
    'http://media.strm.yandex.net/music-v2/raw/file',
    'https://media.strm.yandex.net:444/music-v2/raw/file',
    'https://media.strm.yandex.net.attacker.test/music-v2/raw/file',
    'https://evilstrm.yandex.net/music-v2/raw/file',
    'https://strm.yandex.net/music-v2/raw/file',
    'https://127.0.0.1/music-v2/raw/file',
    'https://localhost/music-v2/raw/file',
    'https://user@media.strm.yandex.net/music-v2/raw/file',
    'https://media.strm.yandex.net/music-v2/raw/file#fragment',
    'https://media.strm.yandex.net/music-v2/smart_preview/file',
    'https://media.strm.yandex.net/music-v2/crypt/file',
    'https://media.strm.yandex.net/other/file',
    'https://media.strm.yandex.net/music-v2/raw/encraw/file',
    'https://media.strm.yandex.net/music-v2/raw/file\n',
  ]) {
    test('CDN policy rejects address ${url.length}', () {
      expect(() => parse(yandexDownloadInfo(url: url)),
          rejected(YandexDownloadFailure.invalidAddress));
    });
  }
  test(
      'missing download info is unavailable; missing optional primary uses first URL',
      () {
    expect(() => parse({}), rejected(YandexDownloadFailure.unavailable));
    final value = yandexDownloadInfo();
    (value['downloadInfo'] as Map).remove('url');
    expect(parse(value), isA<YandexDownloadVariant>());
  });
}
