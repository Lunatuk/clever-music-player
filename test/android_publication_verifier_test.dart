import 'dart:async';

import 'package:clever_music_player/src/android/android_publication_verifier.dart';
import 'package:clever_music_player/src/android/android_publication_receipt.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/android_publication_fixture.dart';
import 'support/download_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/publication_verifier');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AndroidPublicationVerifier verifier;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) handler;
  // Domain receipt/verification test fixture uses a small private SQLite DB.
  late DownloadFixture f;
  late AndroidPublicationReceipt receipt;
  Map<String, Object> response() => {
        'requestId': 1,
        'status': 'fingerprinted',
        'sizeBytes': 3,
        'digest': receipt.intent.verification.contentHash
      };
  setUp(() async {
    f = await androidPublicationFixture();
    final job = await f.claim();
    receipt = androidReceipt(f, job);
    calls = [];
    handler = (_) async => response();
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
    verifier = AndroidPublicationVerifier(channel: channel);
  });
  tearDown(() async {
    await verifier.close();
    messenger.setMockMethodCallHandler(channel, null);
    await f.close();
  });
  Future<SourceFingerprintResult> verify([LibraryScanControl? control]) =>
      verifier.verify(receipt, control ?? LibraryScanControl());
  test(
      'passes selected tree, opaque URI, expected provider name and exact bytes',
      () async {
    expect((await verify()).status, SourceFingerprintStatus.fingerprinted);
    expect(calls.single.method, 'verifyPublishedAudio');
    expect(calls.single.arguments, {
      'requestId': 1,
      'tree': receipt.location.tree.storageValue,
      'document': receipt.location.document.storageValue,
      'displayName': receipt.intent.fileName,
      'expectedSize': 3,
      'digest': receipt.intent.verification.contentHash
    });
  });
  for (final status in SourceFingerprintStatus.values
      .where((s) => s != SourceFingerprintStatus.fingerprinted)) {
    test('preserves $status', () async {
      handler = (_) async => {'requestId': 1, 'status': status.name};
      expect((await verify()).status, status);
    });
  }
  for (final field in ['requestId', 'status', 'sizeBytes', 'digest']) {
    test('rejects malformed $field', () async {
      handler = (_) async => {...response(), field: 'invalid'};
      await expectLater(verify(), throwsFormatException);
    });
  }
  test('matching-looking numeric and mismatched bytes are rejected', () async {
    for (final changed in [
      {'requestId': 1.0},
      {'sizeBytes': 3.0},
      {'sizeBytes': 4},
      {'digest': 'b' * 64}
    ]) {
      handler = (call) async =>
          {...response(), 'requestId': call.arguments['requestId'], ...changed};
      await expectLater(verify(), throwsFormatException);
    }
  });
  test('pre-cancelled verification does no platform IO', () async {
    expect((await verify(LibraryScanControl()..cancel())).status,
        SourceFingerprintStatus.cancelled);
    expect(calls, isEmpty);
  });
  test('cancel sends after admission and close waits for provider drain',
      () async {
    final finish = Completer<Object?>();
    handler = (call) =>
        call.method == 'verifyPublishedAudio' ? finish.future : Future.value();
    final action = verify();
    await expectLater(verify(), throwsStateError);
    var closed = false;
    final closing = verifier.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(calls.map((c) => c.method),
        ['verifyPublishedAudio', 'cancelPublishedAudioVerification']);
    finish.complete(response());
    expect((await action).status, SourceFingerprintStatus.cancelled);
    await closing;
    expect(closed, isTrue);
  });
  test('native failure releases the next request admission', () async {
    handler = (_) async => throw PlatformException(
        code: 'unavailable', message: 'content://private');
    await expectLater(verify(), throwsA(isA<PlatformException>()));
    handler = (call) async =>
        {...response(), 'requestId': call.arguments['requestId']};
    expect((await verify()).status, SourceFingerprintStatus.fingerprinted);
  });
}
