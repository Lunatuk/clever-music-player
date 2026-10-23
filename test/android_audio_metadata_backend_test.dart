import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clever_music_player/src/android/android_audio_metadata_backend.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/download_workspace.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/android-media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late Future<Object?> Function(MethodCall) handler;
  late AndroidAudioMetadataBackend backend;
  final file = File('media-source.part').absolute;
  final output = File('media-output.part').absolute;
  final image = File('media-cover.part').absolute;
  Map<String, Object?> inspection() => {
        'container': 'mp3',
        'codec': 'mp3',
        'durationUs': 600000,
        'sizeBytes': 100,
        'audioStreamIndex': 0,
        'sampleRate': 48000,
        'channels': 1,
        'bitRate': 192000,
        'bitDepth': null,
        'coverStreamIndex': 1,
        'tags': {
          'title': 'Название 😀',
          'artist': 'Один',
          'album_artist': 'Другой'
        },
      };
  Map<String, Object?> ok(MethodCall call,
          [Map<String, Object?> values = const {}]) =>
      {'requestId': call.arguments['requestId'], 'status': 'ok', ...values};
  setUp(() {
    calls.clear();
    backend = AndroidAudioMetadataBackend(channel: channel);
    handler = (call) async => call.method == 'cancelMediaOperation'
        ? null
        : ok(call, {
            'inspection': inspection(),
            'digest': 'a' * 64,
            'durationUs': 600000
          });
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  });
  tearDown(() async {
    await backend.close();
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('inspection preserves separate artists and UTF-8 metadata', () async {
    final info = await backend.inspect(file, LibraryScanControl());
    expect(info.tags['title'], 'Название 😀');
    expect(info.tags['artist'], 'Один');
    expect(info.tags['album_artist'], 'Другой');
    expect(calls.single.method, 'runMediaOperation');
    expect(calls.single.arguments, {
      'requestId': calls.single.arguments['requestId'],
      'op': 1,
      'source': file.path
    });
  });
  test('capability probe requires the pinned profile, version and license',
      () async {
    handler = (call) async => ok(call, {
          'profile': 'cmp-android-audio-1',
          'version': '7.1.5',
          'license': 'LGPL version 2.1 or later'
        });
    expect(await backend.capabilities(LibraryScanControl()), '7.1.5');
    handler = (call) async => ok(call, {
          'profile': 'other',
          'version': '7.1.5',
          'license': 'LGPL version 2.1 or later'
        });
    await expectLater(
        backend.capabilities(LibraryScanControl()),
        throwsA(isA<AudioValidationException>().having((e) => e.outcome,
            'outcome', AudioValidationOutcome.backendUnavailable)));
  });
  final invalid = <String, Object?>{
    'durationUs': 0,
    'sizeBytes': 0,
    'container': 'wav',
    'codec': 'opus',
    'audioStreamIndex': -1,
    'sampleRate': 0,
    'channels': 9,
    'tags': {'title': '\u0000'},
    'coverStreamIndex': 0,
    'bitRate': '192000'
  };
  for (final entry in invalid.entries) {
    test('rejects malformed inspection ${entry.key}', () async {
      handler = (call) async =>
          ok(call, {'inspection': inspection()..[entry.key] = entry.value});
      await expectLater(backend.inspect(file, LibraryScanControl()),
          throwsA(isA<AudioValidationException>()));
    });
  }
  test('decode/digest modes use the native full-read operations', () async {
    final info = await backend.inspect(file, LibraryScanControl());
    calls.clear();
    expect(await backend.decodeAudio(file, info, LibraryScanControl()),
        const Duration(milliseconds: 600));
    await backend.decodeCover(file, info, LibraryScanControl());
    for (final mode in AudioCopyDigest.values) {
      expect(await backend.digest(file, info, mode, LibraryScanControl()),
          'a' * 64);
    }
    expect(calls.map((c) => c.arguments['op']), [2, 3, 4, 4, 4]);
    expect(calls.skip(2).map((c) => c.arguments['mode']), [0, 1, 2]);
  });
  test('remux forwards only source/output, expected tags, cover type and quota',
      () async {
    final info = await backend.inspect(file, LibraryScanControl());
    calls.clear();
    final expected = DownloadedAudioExpectation(
        quality: 'high',
        container: DownloadedAudioContainer.mp3,
        codec: DownloadedAudioCodec.mp3,
        fileSizeBytes: 100,
        duration: const Duration(milliseconds: 600),
        minimumBitRate: 128000,
        tags: {
          'title': 'Название 😀',
          'artist': 'Один',
          'album_artist': 'Другой'
        });
    await backend.writeMetadata(
        file, output, info, expected, LibraryScanControl(),
        cover: image,
        coverFormat: EmbeddedCoverFormat.jpeg,
        maxOutputBytes: 1000);
    expect(calls.single.arguments, {
      'requestId': calls.single.arguments['requestId'],
      'op': 5,
      'source': file.path,
      'output': output.path,
      'tags': expected.tags,
      'cover': image.path,
      'coverFormat': 2,
      'maxOutputBytes': 1000
    });
    await expectLater(
        backend.writeMetadata(file, file, info, expected, LibraryScanControl()),
        throwsArgumentError);
    await expectLater(
        backend.writeMetadata(
            file, output, info, expected, LibraryScanControl(),
            cover: image),
        throwsArgumentError);
  });
  for (final pair in [
    ('invalidAudio', AudioValidationOutcome.invalidAudio),
    ('invalidCover', AudioValidationOutcome.invalidCover),
    ('coverMissing', AudioValidationOutcome.coverMissing),
    ('timedOut', AudioValidationOutcome.timedOut),
    ('backendUnavailable', AudioValidationOutcome.backendUnavailable),
    ('busy', AudioValidationOutcome.backendUnavailable),
    ('unexpected', AudioValidationOutcome.unreadable)
  ]) {
    test('fixed native failure ${pair.$1} is typed', () async {
      handler = (call) async =>
          {'requestId': call.arguments['requestId'], 'status': pair.$1};
      await expectLater(
          backend.inspect(file, LibraryScanControl()),
          throwsA(isA<AudioValidationException>()
              .having((e) => e.outcome, 'outcome', pair.$2)));
    });
  }
  test('native quota remains a workspace quota failure', () async {
    handler = (call) async =>
        {'requestId': call.arguments['requestId'], 'status': 'quotaExceeded'};
    await expectLater(
        backend.inspect(file, LibraryScanControl()),
        throwsA(isA<DownloadWorkspaceException>().having((e) => e.failure,
            'failure', DownloadWorkspaceFailure.quotaExceeded)));
  });
  test('wrong request ID is rejected', () async {
    handler = (call) async => ok(call, {'requestId': 0});
    await expectLater(backend.inspect(file, LibraryScanControl()),
        throwsA(isA<AudioValidationException>()));
  });
  test('close cancels and drains accepted native work before returning',
      () async {
    final response = Completer<Object?>();
    final entered = Completer<void>();
    handler = (call) async {
      if (call.method == 'cancelMediaOperation') return null;
      entered.complete();
      return response.future;
    };
    final control = LibraryScanControl();
    final running = expectLater(
        backend.inspect(file, control), throwsA(isA<LibraryScanCancelled>()));
    await entered.future;
    var closed = false;
    final closing = backend.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, false);
    expect(calls.last.method, 'cancelMediaOperation');
    expect(
        calls.last.arguments['requestId'], calls.first.arguments['requestId']);
    await expectLater(
        backend.inspect(file, LibraryScanControl()), throwsStateError);
    response.complete(ok(calls.first, {'inspection': inspection()}));
    await running;
    await closing;
    expect(closed, true);
  });
  test('pre-cancelled work never invokes the native channel', () async {
    await expectLater(backend.inspect(file, LibraryScanControl()..cancel()),
        throwsA(isA<LibraryScanCancelled>()));
    expect(calls, isEmpty);
  });
  test('platform exception does not expose its message', () async {
    handler = (_) async =>
        throw PlatformException(code: 'io', message: 'private-token-and-path');
    await expectLater(
        backend.inspect(file, LibraryScanControl()),
        throwsA(isA<AudioValidationException>().having(
            (e) => e.toString(), 'text', isNot(contains('private-token')))));
  });
}
