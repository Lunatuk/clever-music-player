import 'dart:async';

import 'package:clever_music_player/src/android/android_download_destination_check.dart';
import 'package:clever_music_player/src/domain/models/audio_source_reference.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/download_destination');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final tree = ContentUriAudioSource('content://test/tree/music');
  late AndroidDownloadDestinationCheck checker;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) handler;
  Map<String, Object> response({String status = 'ready'}) => {
        'requestId': 1,
        'status': status,
        'stage': 6,
        'verifiedBytes': 4096,
        'recovered': 0,
        'retained': status == 'retained' ? 1 : 0,
      };
  setUp(() {
    calls = [];
    handler = (_) async => response();
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
    checker = AndroidDownloadDestinationCheck(channel: channel);
  });
  tearDown(() async {
    await checker.close();
    messenger.setMockMethodCallHandler(channel, null);
  });
  Future<DownloadDestinationResult> check([LibraryScanControl? control]) =>
      checker.check(tree, control ?? LibraryScanControl());

  test('selected URI stays a URI and only explicit check invokes native IO',
      () async {
    expect(calls, isEmpty);
    expect((await check()).status, DownloadDestinationStatus.ready);
    expect(calls.single.method, 'checkDownloadDestination');
    expect(calls.single.arguments, {'requestId': 1, 'uri': tree.storageValue});
  });
  for (final status in DownloadDestinationStatus.values) {
    test('preserves typed status ${status.name}', () async {
      handler = (_) async => response(status: status.name);
      expect((await check()).status, status);
    });
  }
  for (final malformed in <Object?>[
    null,
    {...response(), 'requestId': 2},
    {...response(), 'requestId': 1.0},
    {...response(), 'status': 'unknown'},
    {...response(), 'stage': 7},
    {...response(), 'verifiedBytes': 4095},
    {...response(), 'retained': 1},
    {...response(), 'recovered': -1},
    {...response(), 'recovered': 65},
    {...response(), 'status': 'retained'},
    {...response(), 'stage': 5},
    {...response(), 'verifiedBytes': 0},
  ]) {
    test('rejects malformed provider result $malformed', () async {
      handler = (_) async => malformed;
      await expectLater(check(), throwsFormatException);
    });
  }
  test('pre-cancelled check does no IO', () async {
    final control = LibraryScanControl()..cancel();
    expect((await check(control)).status, DownloadDestinationStatus.cancelled);
    expect(calls, isEmpty);
  });
  test('cancel and close wait for native cleanup and preserve retained result',
      () async {
    final pending = Completer<Object?>();
    handler = (call) => call.method == 'checkDownloadDestination'
        ? pending.future
        : Future.value();
    final control = LibraryScanControl();
    final action = check(control);
    await Future<void>.delayed(Duration.zero);
    await expectLater(check(), throwsStateError);
    var closed = false;
    final closing = checker.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(calls.map((call) => call.method),
        ['checkDownloadDestination', 'cancelDownloadDestinationCheck']);
    pending.complete(response(status: 'retained'));
    expect((await action).status, DownloadDestinationStatus.retained);
    await closing;
    expect(closed, isTrue);
    await expectLater(check(), throwsStateError);
  });
  test('late cancellation cannot return success', () async {
    final pending = Completer<Object?>();
    handler = (call) => call.method == 'checkDownloadDestination'
        ? pending.future
        : Future.value();
    final control = LibraryScanControl();
    final action = check(control);
    control.cancel();
    pending.complete(response());
    expect((await action).status, DownloadDestinationStatus.cancelled);
  });
  test('native error releases admission so the next check can run', () async {
    handler = (_) async => throw PlatformException(code: 'busy');
    await expectLater(check(), throwsA(isA<PlatformException>()));
    handler = (_) async => {...response(), 'requestId': 2};
    expect((await check()).status, DownloadDestinationStatus.ready);
  });
}
