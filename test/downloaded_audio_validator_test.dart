import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/audio_source_reference.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/asset_check_fixture.dart';

void main() {
  late Directory temp;
  late File file;
  late _Backend backend;
  late DownloadedAudioValidator validator;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cmp_new_audio_');
    file = await File('${temp.path}/unknown.data').writeAsString('abc');
    backend = _Backend();
    validator =
        DownloadedAudioValidator(backend: backend, clock: () => assetCheckedAt);
  });
  tearDown(() async {
    await validator.close();
    await temp.delete(recursive: true);
  });
  Future<AudioValidationResult> validate(
          {DownloadedAudioExpectation? expected,
          LibraryScanControl? control}) =>
      validator.validate(FileAudioSource(file.path), expected ?? _expected(),
          control: control);

  test('evidence produced only after inspection, full decode and final hash',
      () async {
    final result = await validate();
    expect(result.outcome, AudioValidationOutcome.verified);
    expect(result.verification!.contentHash, abcHash);
    expect(result.verification!.duration, const Duration(seconds: 3));
    expect(result.verification!.container, 'mp3');
    expect(result.verification!.codec, 'mp3');
    expect(result.verification!.actualQuality, 'high');
    expect(result.verification!.checkedAt, assetCheckedAt);
    expect(backend.calls, ['inspect', 'audio', 'cover']);
  });
  test('expectation and inspection keep immutable tag copies', () {
    final tags = {'title': 'Title'};
    final expected = _expected(tags: tags);
    final info = _info(tags: tags);
    tags['title'] = 'Changed';
    expect(expected.tags['title'], 'Title');
    expect(info.tags['title'], 'Title');
    expect(() => expected.tags.clear(), throwsUnsupportedError);
  });
  for (final bad in [0, -1, 8 * 1024 * 1024 * 1024 + 1]) {
    test('invalid expected size $bad rejected',
        () => expect(() => _expected(size: bad), throwsArgumentError));
  }
  test('invalid encoding pair, duration, limits and tags rejected', () {
    expect(
        () => DownloadedAudioExpectation(
            quality: 'high',
            container: DownloadedAudioContainer.mp3,
            codec: DownloadedAudioCodec.mp3,
            fileSizeBytes: 3,
            duration: const Duration(seconds: 3),
            tags: {}),
        throwsArgumentError);
    expect(() => _expected(container: DownloadedAudioContainer.flac),
        throwsArgumentError);
    expect(() => _expected(duration: Duration.zero), throwsArgumentError);
    expect(() => _expected(duration: const Duration(hours: 13)),
        throwsArgumentError);
    expect(() => _expected(tolerance: const Duration(seconds: 11)),
        throwsArgumentError);
    expect(() => _expected(minBitRate: 0), throwsArgumentError);
    expect(() => _expected(tags: {'unknown': 'value'}), throwsArgumentError);
    expect(() => _expected(tags: {'title': 'a' * 4097}), throwsArgumentError);
    expect(() => AudioValidationResult.failure(AudioValidationOutcome.verified),
        throwsArgumentError);
  });
  test('content URI requires a native backend instead of using File', () async {
    expect(
        (await validator.validate(
                ContentUriAudioSource('content://test/1'), _expected()))
            .outcome,
        AudioValidationOutcome.unsupportedSource);
    expect(backend.calls, isEmpty);
  });
  test('unexpected physical size rejected before metadata or decoding',
      () async {
    expect((await validate(expected: _expected(size: 4))).outcome,
        AudioValidationOutcome.changed);
    expect(backend.calls, isEmpty);
  });
  test('backend size must describe the same file', () async {
    backend.info = _info(size: 4);
    expect((await validate()).outcome, AudioValidationOutcome.changed);
  });
  for (final info in [
    _info(
        container: DownloadedAudioContainer.flac,
        codec: DownloadedAudioCodec.flac),
    _info(bitRate: 128000),
    _info(bitRate: null),
    _info(sampleRate: 22050),
  ]) {
    test(
        'actual encoding must meet policy ${info.container}/${info.bitRate}/${info.sampleRate}',
        () async {
      backend.info = info;
      expect(
          (await validate()).outcome, AudioValidationOutcome.encodingMismatch);
      expect(backend.calls, ['inspect']);
    });
  }
  test('wrong tag rejected without silent metadata fallback', () async {
    backend.info = _info(tags: {'title': 'Other'});
    expect((await validate()).outcome, AudioValidationOutcome.metadataMismatch);
  });
  test('missing required cover rejected', () async {
    backend.info = _info(cover: null);
    expect((await validate()).outcome, AudioValidationOutcome.coverMissing);
  });
  test('optional absent cover accepted and does not call cover decoder',
      () async {
    backend.info = _info(cover: null);
    expect((await validate(expected: _expected(cover: false))).outcome,
        AudioValidationOutcome.verified);
    expect(backend.calls, ['inspect', 'audio']);
  });
  for (final duration in [
    Duration.zero,
    const Duration(seconds: 1),
    const Duration(seconds: 5)
  ]) {
    test(
        'decoded duration $duration checked against metadata and expected track',
        () async {
      backend.decoded = duration;
      expect((await validate()).outcome, AudioValidationOutcome.invalidAudio);
    });
  }
  test('metadata duration mismatch fails before decode', () async {
    backend.info = _info(duration: const Duration(seconds: 1));
    expect((await validate()).outcome, AudioValidationOutcome.invalidAudio);
    expect(backend.calls, ['inspect']);
  });
  test('configured duration tolerance has an exact boundary', () async {
    backend.decoded = const Duration(milliseconds: 3500);
    expect((await validate()).outcome, AudioValidationOutcome.verified);
    backend.decoded = const Duration(milliseconds: 3501);
    expect((await validate()).outcome, AudioValidationOutcome.invalidAudio);
  });
  test('lossless bit depth policy is required when specified', () async {
    backend.info = _info(
        container: DownloadedAudioContainer.flac,
        codec: DownloadedAudioCodec.flac,
        bitDepth: 16);
    final expected = DownloadedAudioExpectation(
        quality: 'lossless24',
        container: DownloadedAudioContainer.flac,
        codec: DownloadedAudioCodec.flac,
        fileSizeBytes: 3,
        duration: const Duration(seconds: 3),
        tags: {},
        minimumBitDepth: 24);
    expect((await validate(expected: expected)).outcome,
        AudioValidationOutcome.encodingMismatch);
  });
  for (final outcome in [
    AudioValidationOutcome.invalidAudio,
    AudioValidationOutcome.invalidCover,
    AudioValidationOutcome.backendUnavailable,
    AudioValidationOutcome.unreadable
  ]) {
    test('typed backend failure $outcome yields no evidence', () async {
      backend.error = AudioValidationException(outcome);
      final result = await validate();
      expect(result.outcome, outcome);
      expect(result.verification, isNull);
    });
  }
  test('unexpected backend error yields no evidence and releases admission',
      () async {
    backend.error = StateError('private helper detail');
    expect((await validate()).outcome, AudioValidationOutcome.unreadable);
    backend.error = null;
    expect((await validate()).outcome, AudioValidationOutcome.verified);
  });
  test('same size mutation during decode detected by final full hash',
      () async {
    backend.beforeDecode = () async {
      await file.writeAsString('xyz');
    };
    expect((await validate()).outcome, AudioValidationOutcome.changed);
  });
  test('missing staging file is unreadable without touching backend', () async {
    await file.delete();
    expect((await validate()).outcome, AudioValidationOutcome.unreadable);
    expect(backend.calls, isEmpty);
  });
  test('pre-cancel does no inspection', () async {
    expect((await validate(control: LibraryScanControl()..cancel())).outcome,
        AudioValidationOutcome.cancelled);
    expect(backend.calls, isEmpty);
  });
  test('close cancels and drains accepted decode, never emits evidence',
      () async {
    final entered = Completer<void>(), gate = Completer<void>();
    backend.beforeDecode = () {
      entered.complete();
      return gate.future;
    };
    final reading = validate();
    await entered.future;
    final closing = validator.close();
    expect(identical(closing, validator.close()), isTrue);
    expect(backend.control!.isCancellationRequested, isTrue);
    expect(backend.closed, isFalse);
    await expectLater(validate(), throwsStateError);
    gate.complete();
    expect((await reading).outcome, AudioValidationOutcome.cancelled);
    await closing;
    expect(backend.closed, isTrue);
  });
  test('concurrent validation rejected instead of queued', () async {
    final entered = Completer<void>(), gate = Completer<void>();
    backend.beforeDecode = () {
      entered.complete();
      return gate.future;
    };
    final first = validate();
    await entered.future;
    await expectLater(validate(), throwsStateError);
    gate.complete();
    await first;
  });
  test('timeout cancels and drains decode without evidence', () async {
    await validator.close();
    backend = _Backend();
    final gate = Completer<void>();
    backend.beforeDecode = () {
      backend.control!.addCancellationListener(() {
        if (!gate.isCompleted) gate.complete();
      });
      return gate.future;
    };
    validator = DownloadedAudioValidator(
        backend: backend, timeout: const Duration(milliseconds: 150));
    expect((await validate()).outcome, AudioValidationOutcome.timedOut);
  });
}

DownloadedAudioExpectation _expected(
        {int size = 3,
        DownloadedAudioContainer container = DownloadedAudioContainer.mp3,
        Duration duration = const Duration(seconds: 3),
        Duration tolerance = const Duration(milliseconds: 500),
        int minBitRate = 300000,
        Map<String, String> tags = const {'title': 'Title'},
        bool cover = true}) =>
    DownloadedAudioExpectation(
        quality: 'high',
        container: container,
        codec: DownloadedAudioCodec.mp3,
        fileSizeBytes: size,
        duration: duration,
        tags: tags,
        minimumBitRate: minBitRate,
        minimumSampleRate: 44100,
        requireCover: cover,
        durationTolerance: tolerance);

DownloadedAudioInspection _info(
        {int size = 3,
        DownloadedAudioContainer container = DownloadedAudioContainer.mp3,
        DownloadedAudioCodec codec = DownloadedAudioCodec.mp3,
        Duration duration = const Duration(seconds: 3),
        int? bitRate = 320000,
        int sampleRate = 48000,
        int? bitDepth,
        int? cover = 1,
        Map<String, String> tags = const {'title': 'Title'}}) =>
    DownloadedAudioInspection(
        container: container,
        codec: codec,
        duration: duration,
        sizeBytes: size,
        audioStreamIndex: 0,
        sampleRate: sampleRate,
        channels: 2,
        tags: tags,
        bitRate: bitRate,
        bitDepth: bitDepth,
        coverStreamIndex: cover);

final class _Backend implements AudioValidationBackend {
  DownloadedAudioInspection info = _info();
  Duration decoded = const Duration(seconds: 3);
  Object? error;
  Future<void> Function()? beforeDecode;
  LibraryScanControl? control;
  final calls = <String>[];
  bool closed = false;
  @override
  Future<DownloadedAudioInspection> inspect(
      File file, LibraryScanControl control) async {
    calls.add('inspect');
    this.control = control;
    if (error != null) throw error!;
    return info;
  }

  @override
  Future<Duration> decodeAudio(File file, DownloadedAudioInspection inspection,
      LibraryScanControl control) async {
    calls.add('audio');
    this.control = control;
    await beforeDecode?.call();
    return decoded;
  }

  @override
  Future<void> decodeCover(File file, DownloadedAudioInspection inspection,
      LibraryScanControl control) async {
    calls.add('cover');
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
