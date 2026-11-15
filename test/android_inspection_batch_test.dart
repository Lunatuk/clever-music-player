import 'dart:async';

import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/domain/models/audio_source_reference.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/inspection-batches');
  const adapter = AndroidAudioDocuments(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  ContentUriAudioSource source(int i) =>
      ContentUriAudioSource('content://test/document/$i');
  List<AudioInspectionBatchRequest> requests(int n) =>
      [for (var i = 0; i < n; i++) AudioInspectionBatchRequest(source(i))];
  Map<String, Object?> frame(int i) => {
        'version': 1,
        'authority': 'test',
        'documentId': '$i',
        'name': '$i.m4a',
        'size': 100,
        'modifiedMs': 1000,
        'source': source(i).storageValue,
        'failed': false,
        'artwork': 3,
        'ageUs': 0
      };
  Map<String, Object?> response(List<Object?> frames,
          {bool cancelled = false}) =>
      {
        'version': 1,
        'results': frames,
        'consumed': frames.length,
        'cancelled': cancelled
      };

  test('one call returns a bounded prefix bound to the original request',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      expect(call.method, 'inspectAudioBatch');
      expect((call.arguments as Map)['batch'], 7);
      expect(((call.arguments as Map)['items'] as List), hasLength(3));
      return response([frame(0), frame(1)]);
    });
    final result = await adapter.inspectAudioBatch(7, requests(3));
    expect(calls, 1);
    expect(result.entries, hasLength(2));
    expect(result.entries[1].inspection.revision!.documentId, '1');
    expect(() => result.entries.clear(), throwsUnsupportedError);
  });

  test('a caller cannot mutate request bindings while native work is pending',
      () async {
    final gate = Completer<Object?>(), entered = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) {
      entered.complete();
      return gate.future;
    });
    final mutable = requests(2);
    final pending = adapter.inspectAudioBatch(1, mutable);
    await entered.future;
    mutable.clear();
    gate.complete(response([frame(0), frame(1)]));
    expect((await pending).entries, hasLength(2));
  });

  test('failed position and cancelled prefix cannot fabricate a revision',
      () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => response([
              frame(0),
              {...frame(1), 'failed': true, 'artwork': 0}
            ]));
    final result = await adapter.inspectAudioBatch(1, requests(2));
    expect(result.entries[1].failed, isTrue);
    expect(result.entries[1].inspection.revision, isNull);
    messenger.setMockMethodCallHandler(
        channel, (_) async => response([], cancelled: true));
    expect((await adapter.inspectAudioBatch(2, requests(2))).cancelled, isTrue);
  });

  test(
      'malformed order, identity, ages, status and prefix lengths are rejected',
      () async {
    for (final payload in [
      null,
      [],
      response([]),
      {
        ...response([frame(0)]),
        'version': 2
      },
      response([frame(1)]),
      response([
        {...frame(0), 'documentId': 'other'}
      ]),
      response([
        {...frame(0), 'ageUs': -1}
      ]),
      response([
        {...frame(0), 'ageUs': 3600000001}
      ]),
      response([
        {...frame(0), 'failed': 'yes'}
      ]),
      response([
        {...frame(0), 'artwork': 99}
      ]),
      response([
        {...frame(0), 'artwork': 1}
      ]),
      {
        ...response([frame(0)]),
        'consumed': 2
      },
      response([frame(0), frame(0)]),
      response([frame(0), frame(1), frame(2)])
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => payload);
      await expectLater(
          adapter.inspectAudioBatch(1, requests(2)), throwsFormatException);
    }
  });

  test('invalid input is rejected before a platform call', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    for (final batch in [
      requests(0),
      requests(9),
      [...requests(1), ...requests(1)],
      [AudioInspectionBatchRequest(source(0), artworkPath: '/cache/cover')]
    ]) {
      await expectLater(
          adapter.inspectAudioBatch(1, batch), throwsArgumentError);
    }
    await expectLater(
        adapter.inspectAudioBatch(0, requests(1)), throwsArgumentError);
    expect(calls, 0);
  });

  test(
      'thumbnail proof and optional native timings are validated independently',
      () async {
    final request = AudioInspectionBatchRequest(source(0),
        artworkPath: '/cache/cover.webp', artworkHash: 'a' * 64);
    final timings = {
      'version': 1,
      'totalUs': 110,
      'permissionUs': 10,
      'revisionUs': 50,
      'visibilityUs': 20,
      'descriptorUs': 30,
      'artworkUs': 10
    };
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => response([
              {...frame(0), 'artwork': 1, 'inspectionTimings': timings}
            ]));
    expect(
        (await adapter.inspectAudioBatch(1, [request]))
            .entries
            .single
            .inspection
            .timings!
            .artworkUs,
        10);
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => response([
              {
                ...frame(0),
                'artwork': 1,
                'inspectionTimings': {...timings, 'artworkUs': 30}
              }
            ]));
    final result = await adapter.inspectAudioBatch(2, [request]);
    expect(result.entries.single.inspection.revision, isNotNull);
    expect(result.entries.single.inspection.timings, isNull);
  });

  test('cancellation addresses exactly the supplied batch token', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'cancelAudioInspectionBatch');
      expect(call.arguments, {'batch': 35});
      return null;
    });
    await adapter.cancelAudioInspectionBatch(35);
  });
}
