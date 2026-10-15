import 'dart:async';

import 'package:clever_music_player/src/android/android_source_fingerprint_probe.dart';
import 'package:clever_music_player/src/domain/models/audio_source_reference.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/asset_check_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/audio_fingerprint');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final source =
      ContentUriAudioSource('content://test/tree/music/document/track');
  late AndroidSourceFingerprintProbe probe;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) handler;
  setUp(() {
    calls = [];
    handler = (call) async => {
          'requestId': call.arguments['requestId'],
          'status': 'fingerprinted',
          'sizeBytes': 3,
          'digest': abcHash
        };
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
    probe = AndroidSourceFingerprintProbe(channel: channel);
  });
  tearDown(() async {
    await probe.close();
    messenger.setMockMethodCallHandler(channel, null);
  });
  Future<SourceFingerprintResult> read({LibraryScanControl? control}) =>
      probe.fingerprint(source,
          expectedSize: 3, control: control ?? LibraryScanControl());

  test('URI and exact expected size are sent without converting into a path',
      () async {
    expect((await read()).digest, abcHash);
    expect(calls.single.method, 'fingerprintAudio');
    expect(calls.single.arguments,
        {'requestId': 1, 'uri': source.storageValue, 'expectedSize': 3});
    await read();
    expect(calls.last.arguments['requestId'], 2);
  });
  for (final status in SourceFingerprintStatus.values
      .where((s) => s != SourceFingerprintStatus.fingerprinted)) {
    test('typed native status $status preserved', () async {
      handler = (call) async =>
          {'requestId': call.arguments['requestId'], 'status': status.name};
      expect((await read()).status, status);
    });
  }
  for (final malformed in <Object?>[
    null,
    {'requestId': 2, 'status': 'missing'},
    {'requestId': 1.0, 'status': 'missing'},
    {'requestId': 1, 'status': 'unknown'},
    {
      'requestId': 1,
      'status': 'fingerprinted',
      'sizeBytes': 4,
      'digest': abcHash
    },
    {
      'requestId': 1,
      'status': 'fingerprinted',
      'sizeBytes': 3.0,
      'digest': abcHash
    },
    {
      'requestId': 1,
      'status': 'fingerprinted',
      'sizeBytes': 3,
      'digest': 'abc'
    },
  ]) {
    test('malformed result rejected: $malformed', () async {
      handler = (_) async => malformed;
      await expectLater(read(), throwsFormatException);
    });
  }
  test('pre-cancelled read does not call native code', () async {
    expect((await read(control: LibraryScanControl()..cancel())).status,
        SourceFingerprintStatus.cancelled);
    expect(calls, isEmpty);
  });
  test('cancellation sends matching ID and drains late native reply', () async {
    final gate = Completer<Object?>();
    handler = (call) =>
        call.method == 'fingerprintAudio' ? gate.future : Future.value(null);
    final control = LibraryScanControl();
    final reading = read(control: control);
    control.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((call) => call.method),
        ['fingerprintAudio', 'cancelAudioFingerprint']);
    expect(
        calls.last.arguments['requestId'], calls.first.arguments['requestId']);
    var closed = false;
    final closing = probe.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    gate.complete({
      'requestId': 1,
      'status': 'fingerprinted',
      'sizeBytes': 3,
      'digest': abcHash
    });
    expect((await reading).status, SourceFingerprintStatus.cancelled);
    await closing;
    await expectLater(read(), throwsStateError);
  });
  test('busy rejection bounds admission and native errors release it',
      () async {
    final gate = Completer<Object?>();
    handler = (_) => gate.future;
    final reading = read();
    await expectLater(read(), throwsStateError);
    gate.completeError(PlatformException(code: 'provider_failure'));
    await expectLater(reading, throwsA(isA<PlatformException>()));
    handler = (_) async => {'requestId': 2, 'status': 'missing'};
    expect((await read()).status, SourceFingerprintStatus.missing);
  });
}
