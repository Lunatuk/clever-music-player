import 'package:clever_music_player/src/library_sync/binary_download.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/yandex_download_fixture.dart';

void main() {
  test(
      'optional cover and known CDN template parse without exposing private data',
      () {
    const parser = YandexDownloadParser();
    final data = yandexDownloadTrack();
    expect(parser.metadata(data, yandexDownloadIdentity).cover, isNull);
    for (final value in [yandexCoverTemplate, 'https://$yandexCoverTemplate']) {
      (data.single as Map)['coverUri'] = value;
      final cover = parser.metadata(data, yandexDownloadIdentity).cover!;
      expect(cover.toString(), 'YandexCoverAddress(<redacted>)');
      expect(cover.address.toString(), 'BinaryDownloadAddress(<redacted>)');
    }
  });
  for (final value in <Object>[
    '',
    10,
    <String>[],
    'http://$yandexCoverTemplate',
    '//$yandexCoverTemplate',
    'avatars.yandex.net.evil/get-music-content/1/a/%%',
    'evil.avatars.yandex.net/get-music-content/1/a/%%',
    'avatars.yandex.net@evil/get-music-content/1/a/%%',
    'avatars.yandex.net:443/get-music-content/1/a/%%',
    '127.0.0.1/get-music-content/1/a/%%',
    'avatars.yandex.net/get-music-content/1/../%%',
    'avatars.yandex.net/get-music-content/1/./%%',
    'avatars.yandex.net/get-music-content/1/%2e%2e/%%',
    'avatars.yandex.net/get-music-content/1/a/b/%%',
    'avatars.yandex.net/get-music-content/1/a/600x600',
    '$yandexCoverTemplate?token=SECRET',
    '$yandexCoverTemplate#SECRET',
    '$yandexCoverTemplate\n',
    '$yandexCoverTemplate/%%',
    'avatars.yandex.net/get-userpic/1/a/%%',
    'avatars.yandex.net/get-music-content/1/${'a' * 2048}/%%',
  ].indexed) {
    test('reject malformed/untrusted cover template ${value.$1}', () {
      final data = yandexDownloadTrack();
      (data.single as Map)['coverUri'] = value.$2;
      expect(
          () => const YandexDownloadParser()
              .metadata(data, yandexDownloadIdentity),
          throwsA(isA<YandexDownloadException>().having((e) => e.failure,
              'failure', YandexDownloadFailure.invalidAddress)));
    });
  }
  test('failure text contains only the stable failure code', () {
    expect(
        const BinaryDownloadException(BinaryDownloadFailure.invalidAddress)
            .toString(),
        'BinaryDownloadException(invalidAddress)');
  });
}
