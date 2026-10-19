import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/yandex_audio_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vectors =
      jsonDecode(File('test/fixtures/yandex_aes_ctr.json').readAsStringSync())
          as List;
  for (final vector in vectors) {
    test('independent OpenSSL AES-CTR ${vector['bits']} with fragmented blocks',
        () async {
      final encrypted = base64Decode(vector['encrypted'] as String);
      final decoder = YandexAudioDecoder('encraw', vector['key']);
      final input = Stream<List<int>>.fromIterable([
        encrypted.sublist(0, 1),
        encrypted.sublist(1, 16),
        [],
        encrypted.sublist(16, 35),
        encrypted.sublist(35)
      ]);
      final actual = await decoder.decode(input).expand((v) => v).toList();
      expect(actual, base64Decode(vector['plain'] as String));
      expect(decoder.toString(), isNot(contains(vector['key'])));
      // Each response/stream starts a fresh counter, never reuses old position.
      expect(
          await decoder
              .decode(Stream.value(encrypted))
              .expand((v) => v)
              .toList(),
          actual);
    });
  }
  for (final key in [null, '']) {
    test(
        'raw delivery with ${key == null ? 'null' : 'empty'} key passes through',
        () {
      final stream = Stream<List<int>>.value([1, 2]);
      expect(identical(YandexAudioDecoder('raw', key).decode(stream), stream),
          isTrue);
    });
  }
  for (final (transport, key) in [
    ('encraw', null),
    ('encraw', ''),
    ('encraw', 'a' * 31),
    ('encraw', 'z' * 32),
    ('encraw', 'a' * 66),
    ('raw', 'a' * 32),
    ('unknown', 'a' * 32),
    ('encraw', ['a' * 32])
  ]) {
    test(
        'invalid transport/key pair is rejected ($transport/${key.runtimeType}/${key.toString().length})',
        () {
      expect(() => YandexAudioDecoder(transport, key), throwsFormatException);
    });
  }
  test(
      'large input is processed in bounded chunks and cancellation stops source',
      () async {
    final control = LibraryScanControl();
    final cancelled = Completer<void>();
    final source = StreamController<List<int>>(onCancel: cancelled.complete);
    final decoder = YandexAudioDecoder('encraw', '00' * 16);
    source.add(Uint8List(1024 * 1024));
    final first = Completer<void>();
    final values = <List<int>>[];
    final subscription =
        decoder.decode(source.stream, control: control).listen((chunk) {
      values.add(chunk);
      control.cancel();
      first.complete();
    });
    final error = Completer<Object>();
    subscription.onError(error.complete);
    await first.future;
    expect(await error.future, isA<LibraryScanCancelled>());
    await cancelled.future;
    expect(values, hasLength(1));
    expect(values.single, hasLength(16 * 1024));
    await subscription.cancel();
    await source.close();
  });
  test('source errors propagate and do not become decoded success', () async {
    final error = StateError('synthetic input failure');
    await expectLater(
        YandexAudioDecoder('encraw', '00' * 16)
            .decode(Stream.error(error))
            .drain<void>(),
        throwsA(same(error)));
  });
}
