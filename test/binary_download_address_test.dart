import 'dart:io';

import 'package:clever_music_player/src/library_sync/binary_download.dart';
import 'package:clever_music_player/src/library_sync/binary_http_download_transport.dart';
import 'package:clever_music_player/src/library_sync/raw_download_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTPS exact trusted host accepts signed URL without exposing it', () {
    final value = BinaryDownloadAddress.https(
        'https://cdn.example.com/get/track?sign=PRIVATE&expires=123',
        trustedHosts: {'cdn.example.com'});
    expect(value.toString(), 'BinaryDownloadAddress(<redacted>)');
  });
  for (final uri in [
    'http://cdn.example.com/audio',
    'file:///PRIVATE/audio',
    'https://other.example.com/audio',
    'https://child.cdn.example.com/audio',
    'https://cdn.example.com.evil.invalid/audio',
    'https://PRIVATE@cdn.example.com/audio',
    'https://cdn.example.com:444/audio',
    'https://cdn.example.com:PRIVATE/audio',
    'https://cdn.example.com/audio#PRIVATE',
    'https://cdn.example.com/',
    'https://cdn.example.com',
    'https://cdn.example.com/audio\r\nPRIVATE',
    'https://cdn.example.com/PRI VATE',
    r'https://cdn.example.com\PRIVATE/audio',
    'https://127.0.0.1/audio',
    'https://[::1]/audio',
    '//cdn.example.com/audio',
    '',
  ]) {
    test(
        'rejects unsafe/mismatched address ${uri.replaceAll(RegExp(r"\s"), "_")}',
        () {
      expect(
          () => BinaryDownloadAddress.https(uri,
              trustedHosts: {'cdn.example.com'}),
          _invalid);
    });
  }
  for (final hosts in [
    <String>{},
    {'127.0.0.1'},
    {'cdn.local'},
    {'metadata.google.internal'},
    {'CDN.example.com'},
    {'*.example.com'},
    {'https://cdn.example.com'},
    {for (var i = 0; i < 33; i++) '$i.example.com'}
  ]) {
    test('malformed or broad trust configuration is rejected ($hosts)', () {
      expect(
          () => BinaryDownloadAddress.https('https://cdn.example.com/audio',
              trustedHosts: hosts),
          _invalid);
    });
  }
  test('very long signed URL is rejected without embedding it in exception',
      () {
    expect(
        () => BinaryDownloadAddress.https(
            'https://cdn.example.com/audio?${'a' * 8192}',
            trustedHosts: {'cdn.example.com'}),
        _invalid);
  });
  test('production transport never accepts a loopback test address', () async {
    final pool = RawDownloadPool(parent: Directory.systemTemp);
    final transport = BinaryHttpDownloadTransport(pool: pool);
    try {
      await expectLater(
          transport.download(
              BinaryDownloadAddress.loopbackForTesting(
                  'http://127.0.0.1:12345/audio'),
              maxBytes: 1),
          _invalid);
      expect(pool.reservedFiles, 0);
    } finally {
      await transport.close();
    }
  });
  test('loopback transport accepts neither HTTPS nor a different test origin',
      () async {
    final pool = RawDownloadPool(parent: Directory.systemTemp);
    final transport = BinaryHttpDownloadTransport.loopbackForTesting(
        Uri.parse('http://127.0.0.1:12345'),
        pool: pool);
    try {
      for (final address in [
        BinaryDownloadAddress.loopbackForTesting(
            'http://127.0.0.1:12346/audio'),
        BinaryDownloadAddress.https('https://cdn.example.com/audio',
            trustedHosts: {'cdn.example.com'})
      ]) {
        await expectLater(transport.download(address, maxBytes: 1), _invalid);
      }
      expect(pool.reservedFiles, 0);
    } finally {
      await transport.close();
    }
  });
}

final _invalid = throwsA(isA<BinaryDownloadException>()
    .having((e) => e.failure, 'failure', BinaryDownloadFailure.invalidAddress)
    .having((e) => e.toString(), 'safe message',
        'BinaryDownloadException(invalidAddress)'));
