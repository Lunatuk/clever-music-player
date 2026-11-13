import 'package:clever_music_player/src/library/embedded_yandex_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final host in [
    'music.yandex.ru',
    'music.yandex.com',
    'music.yandex.by',
    'music.yandex.kz',
    'music.yandex.uz'
  ]) {
    test('reads a source URL on $host', () {
      final identity = embeddedYandexIdentity([
        'https://$host/album/11673234/track/69610353',
      ])!;
      expect(identity.provider, 'yandex_music');
      expect(identity.externalId, '69610353');
      expect(identity.variantKey, '11673234');
    });
  }
  test('retains numeric identities, handles whitespace and tracking suffixes',
      () {
    final identity = embeddedYandexIdentity([
      'ordinary comment',
      '  http://MUSIC.YANDEX.RU/album/001/track/002/?from=share#section\x00 ',
      'https://music.yandex.ru/album/001/track/002',
    ])!;
    expect(identity.externalId, '002');
    expect(identity.variantKey, '001');
  });
  test('accepts a track-only source without inventing an album', () {
    final identity =
        embeddedYandexIdentity(['https://music.yandex.ru/track/123'])!;
    expect(identity.externalId, '123');
    expect(identity.variantKey, isEmpty);
  });
  test('handles null padding exposed by older ID3 text readers', () {
    expect(
        embeddedYandexIdentity([
          '\x00https://music.yandex.ru/album/12/track/34\x00',
        ])?.externalId,
        '34');
  });
  for (final text in [
    '',
    'AMNESIA - LXST CXNTURY',
    'https://example.org/album/1/track/2',
    'https://music.yandex.ru.example.org/album/1/track/2',
    'https://music.yandex.ru@evil.test/album/1/track/2',
    'https://user@music.yandex.ru/album/1/track/2',
    'https://music.yandex.ru:123/album/1/track/2',
    'file://music.yandex.ru/album/1/track/2',
    'music.yandex.ru/album/1/track/2',
    'https://music.yandex.ru/album/0/track/2',
    'https://music.yandex.ru/album/1/track/0',
    'https://music.yandex.ru/album/-1/track/2',
    'https://music.yandex.ru/album/1/track/abc',
    'https://music.yandex.ru/album/1/track/2/extra',
    'https://music.yandex.ru/album/1/track/2%00',
    'https://music.yandex.ru/album/1/track/2%0a',
    'https://music.yandex.ru/album/1/track/%ff',
  ]) {
    test('ignores an unrelated or malformed comment $text', () {
      expect(embeddedYandexIdentity([text]), isNull);
    });
  }
  test('conflicting source URLs remain unassigned', () {
    expect(
        embeddedYandexIdentity([
          'https://music.yandex.ru/album/1/track/2',
          'https://music.yandex.ru/album/1/track/3',
        ]),
        isNull);
  });
  test('oversized comments and excessive comment counts remain unassigned', () {
    expect(embeddedYandexIdentity(['x' * 4097]), isNull);
    expect(
        embeddedYandexIdentity([
          'https://music.yandex.ru/album/1/track/2',
          ...List.filled(32, 'other'),
        ]),
        isNull);
  });
}
