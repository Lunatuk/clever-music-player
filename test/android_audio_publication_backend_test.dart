import 'dart:async';

import 'package:clever_music_player/src/android/android_audio_publication_backend.dart';
import 'package:clever_music_player/src/android/android_download_destination_check.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/android_publication_fixture.dart';
import 'support/download_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/audio_publication');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late DownloadFixture f;
  late AudioPublicationRequest request;
  late AndroidAudioPublicationBackend backend;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) handler;
  Map<String, Object> ready(MethodCall call) => {
        'requestId': call.arguments['requestId'],
        'status': 'published',
        'stage': 6,
        'intent': request.intent.encode(),
        'document':
            'content://music.documents/tree/primary%3AMusic/document/opaque',
        'sizeBytes': 3,
        'digest': request.intent.verification.contentHash
      };
  setUp(() async {
    f = await androidPublicationFixture();
    final job = await f.claim(stage: DownloadJobStage.publication);
    request = AudioPublicationRequest(
        intent: androidReceipt(f, job).intent,
        tree: androidPublicationTree,
        owner: job.attemptToken!);
    calls = [];
    handler = (call) async => ready(call);
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
    backend = AndroidAudioPublicationBackend(channel: channel);
  });
  tearDown(() async {
    await backend.close();
    messenger.setMockMethodCallHandler(channel, null);
    await f.close();
  });
  Future<void> prepare() => backend.prepare(request);
  Future<Object> publish([LibraryScanControl? control]) => backend.publish(
      request, FileAudioSource(f.raw.path), control ?? LibraryScanControl());
  test(
      'admission and provider write have separate methods with exact intent bytes',
      () async {
    handler = (call) async => call.method == 'prepareAudioPublication'
        ? {
            'requestId': call.arguments['requestId'],
            'status': 'prepared',
            'stage': 2
          }
        : ready(call);
    await prepare();
    await publish();
    expect(calls.map((c) => c.method),
        ['prepareAudioPublication', 'publishPreparedAudio']);
    expect(calls[0].arguments['sourcePath'], isNull);
    expect(calls[1].arguments['sourcePath'], f.raw.path);
    expect(calls[1].arguments['tree'], androidPublicationTree.storageValue);
    expect(calls[1].arguments['intent'], request.intent.encode());
    expect(calls[0].arguments['requestId'],
        isNot(calls[1].arguments['requestId']));
  });
  for (final status in AudioPublicationStatus.values.where((s) => !const {
        AudioPublicationStatus.prepared,
        AudioPublicationStatus.published,
        AudioPublicationStatus.pending,
        AudioPublicationStatus.acknowledged
      }.contains(s))) {
    test('typed native failure $status does not become success', () async {
      handler = (call) async => {
            'requestId': call.arguments['requestId'],
            'status': status.name,
            'stage': 3
          };
      await expectLater(
          publish(),
          throwsA(isA<AudioPublicationException>()
              .having((e) => e.status, 'status', status)));
    });
  }
  for (final key in [
    'requestId',
    'status',
    'stage',
    'intent',
    'document',
    'digest',
    'sizeBytes'
  ]) {
    test('rejects malformed reply $key', () async {
      handler = (call) async => {...ready(call), key: 'invalid'};
      await expectLater(publish(), throwsA(anything));
    });
  }
  test('rejects a published response before READY and a foreign tree',
      () async {
    handler = (call) async => {...ready(call), 'stage': 5};
    await expectLater(publish(), throwsFormatException);
    handler = (call) async =>
        {...ready(call), 'document': 'content://other/tree/root/document/x'};
    await expectLater(publish(), throwsFormatException);
  });
  test('pending list is bounded, canonical and cannot repeat an operation',
      () async {
    handler = (call) async => {
          'requestId': call.arguments['requestId'],
          'status': 'pending',
          'stage': 1,
          'operations': [request.intent.encode()]
        };
    expect((await backend.pending(request.tree)).single.encode(),
        request.intent.encode());
    handler = (call) async => {
          'requestId': call.arguments['requestId'],
          'status': 'pending',
          'stage': 1,
          'operations': [request.intent.encode(), request.intent.encode()]
        };
    await expectLater(backend.pending(request.tree), throwsFormatException);
    handler = (call) async => {
          'requestId': call.arguments['requestId'],
          'status': 'pending',
          'stage': 1,
          'operations': List.filled(65, request.intent.encode())
        };
    await expectLater(backend.pending(request.tree), throwsFormatException);
  });
  test(
      'close cancels streaming and drains a published response without hiding it',
      () async {
    final finish = Completer<Object?>();
    MethodCall? accepted;
    handler = (call) {
      if (call.method == 'publishPreparedAudio') {
        accepted = call;
        return finish.future;
      }
      return Future.value();
    };
    final action = publish();
    await Future<void>.delayed(Duration.zero);
    var closed = false;
    final closing = backend.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(calls.last.method, 'cancelAudioPublication');
    finish.complete(ready(accepted!));
    expect(await action, isNotNull);
    await closing;
    expect(closed, isTrue);
    await expectLater(publish(), throwsStateError);
  });
  test('close drains private admission without sending cancellation', () async {
    final finish = Completer<Object?>();
    MethodCall? accepted;
    handler = (call) {
      accepted = call;
      return finish.future;
    };
    final action = prepare();
    await Future<void>.delayed(Duration.zero);
    var closed = false;
    final closing = backend.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(calls.length, 1);
    finish.complete({
      'requestId': accepted!.arguments['requestId'],
      'status': 'prepared',
      'stage': 2
    });
    await action;
    await closing;
  });
  test('pre-cancelled stream never invokes native IO', () async {
    await expectLater(publish(LibraryScanControl()..cancel()),
        throwsA(isA<LibraryScanCancelled>()));
    expect(calls, isEmpty);
  });
  test('physical qualification uses its own cancellation method', () async {
    final check =
        AndroidDownloadDestinationCheck.audioPublication(channel: channel);
    handler = (call) async => {
          'requestId': call.arguments['requestId'],
          'status': 'ready',
          'stage': 6,
          'verifiedBytes': 4096,
          'recovered': 0,
          'retained': 0
        };
    expect((await check.check(request.tree, LibraryScanControl())).status,
        DownloadDestinationStatus.ready);
    expect(calls.single.method, 'checkAudioPublication');
    expect(calls.single.arguments, {
      'requestId': calls.single.arguments['requestId'],
      'tree': request.tree.storageValue,
    });
    await check.close();
  });
}
