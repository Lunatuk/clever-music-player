import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/domain/models/audio_source_reference.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/profiled-inspection');
  const adapter = AndroidAudioDocuments(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final source = ContentUriAudioSource('content://test/document/song');
  final revision = {
    'version': 1,
    'authority': 'test',
    'documentId': 'song',
    'name': 'song.m4a',
    'size': 100,
    'modifiedMs': 1000
  };
  final profile = {
    'version': 1,
    'totalUs': 100,
    'permissionUs': 10,
    'revisionUs': 50,
    'visibilityUs': 20,
    'descriptorUs': 30
  };
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('one channel call supplies revision and numeric inspection profile',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      expect(call.method, 'inspectAudio');
      expect(call.arguments, {'uri': source.storageValue});
      return {...revision, 'inspectionTimings': profile};
    });
    final result = await adapter.inspectProfiledAudio(source);
    expect(calls, 1);
    expect(result.revision!.documentId, 'song');
    expect(result.timings!.descriptorUs, 30);
    expect((await adapter.inspectAudio(source))!.size, 100);
    expect(calls, 2);
  });

  test('unsupported cache revision can still supply a valid profile', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'inspectionTimings': profile});
    final result = await adapter.inspectProfiledAudio(source);
    expect(result.revision, isNull);
    expect(result.timings!.totalUs, 100);
  });

  test('old native messages retain their revision without inspection timings',
      () async {
    messenger.setMockMethodCallHandler(channel, (_) async => revision);
    final result = await adapter.inspectProfiledAudio(source);
    expect(result.revision, isNotNull);
    expect(result.timings, isNull);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect((await adapter.inspectProfiledAudio(source)).revision, isNull);
  });

  test('malformed profile never discards an otherwise valid revision',
      () async {
    for (final invalid in [
      null,
      [],
      {...profile, 'version': 2},
      {...profile, 'permissionUs': -1},
      {...profile, 'revisionUs': 1.5},
      {...profile, 'descriptorUs': 'private'},
      {...profile, 'totalUs': 3600000001},
      {...profile, 'visibilityUs': 51},
      {...profile, 'totalUs': 89},
      {...profile}..remove('descriptorUs')
    ]) {
      messenger.setMockMethodCallHandler(
          channel, (_) async => {...revision, 'inspectionTimings': invalid});
      final result = await adapter.inspectProfiledAudio(source);
      expect(result.revision, isNotNull);
      expect(result.timings, isNull);
    }
  });

  test('platform access error is not converted to a usable cached revision',
      () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'access_lost'));
    await expectLater(adapter.inspectProfiledAudio(source),
        throwsA(isA<PlatformException>()));
  });
}
