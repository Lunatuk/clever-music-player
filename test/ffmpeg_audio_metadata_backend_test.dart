import 'dart:io';

import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:clever_music_player/src/library_sync/ffmpeg_audio_metadata_backend.dart';
import 'package:clever_music_player/src/library_sync/media_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Runner runner;
  late FfmpegAudioMetadataBackend backend;
  final source = File('source with spaces.part');
  final output = File('new output.part');
  final picture = File('picture part');
  setUp(() {
    runner = _Runner();
    backend = FfmpegAudioMetadataBackend(
        ffprobePath: File('ffprobe').absolute.path,
        ffmpegPath: File('ffmpeg').absolute.path,
        runner: runner);
  });
  tearDown(() => backend.close());
  Matcher failure(AudioValidationOutcome outcome) =>
      throwsA(isA<AudioValidationException>()
          .having((error) => error.outcome, 'outcome', outcome));

  for (final container in DownloadedAudioContainer.values) {
    test('${container.name} writes known tags with copy and explicit muxer',
        () async {
      await backend.writeMetadata(source, output, _info(container),
          _expected(container), LibraryScanControl());
      final args = runner.arguments!;
      expect(args, containsAllInOrder(['-map', '0:2', '-c:a', 'copy']));
      expect(args.last, output.absolute.path);
      expect(args[args.lastIndexOf('-f') + 1],
          container == DownloadedAudioContainer.m4a ? 'ipod' : container.name);
      expect(args, containsAll(['-map_metadata', '-1', 'file,pipe', '-y']));
      expect(args, contains('title=Тест "\$()" = ; #'));
      expect(args, isNot(contains('-b:a')));
      expect(args, isNot(contains('-ar')));
      expect(args, isNot(contains('-frames:v')));
    });
  }
  test('replacement cover maps the new input and excludes the previous picture',
      () async {
    await backend.writeMetadata(
        source,
        output,
        _info(DownloadedAudioContainer.mp3, cover: true),
        _expected(DownloadedAudioContainer.mp3),
        LibraryScanControl(),
        cover: picture,
        coverFormat: EmbeddedCoverFormat.jpeg);
    expect(
        runner.arguments,
        containsAll([
          'jpeg_pipe',
          picture.absolute.path,
          '1:v:0',
          '-c:v',
          'copy',
          'attached_pic'
        ]));
    expect(runner.arguments, isNot(contains('0:4')));
  });
  test('missing replacement retains precisely the existing attached picture',
      () async {
    await backend.writeMetadata(
        source,
        output,
        _info(DownloadedAudioContainer.flac, cover: true),
        _expected(DownloadedAudioContainer.flac),
        LibraryScanControl());
    expect(runner.arguments, containsAll(['0:4', 'attached_pic']));
    expect(runner.arguments!.where((value) => value == '-i'), hasLength(1));
  });
  test(
      'same source/output and inconsistent cover arguments fail before process',
      () async {
    await expectLater(
        backend.writeMetadata(
            source,
            source,
            _info(DownloadedAudioContainer.mp3),
            _expected(DownloadedAudioContainer.mp3),
            LibraryScanControl()),
        throwsArgumentError);
    await expectLater(
        backend.writeMetadata(
            source,
            output,
            _info(DownloadedAudioContainer.mp3),
            _expected(DownloadedAudioContainer.mp3),
            LibraryScanControl(),
            cover: picture),
        throwsArgumentError);
    expect(runner.arguments, isNull);
  });
  for (final mode in AudioCopyDigest.values) {
    test('$mode digest selects the exact stream and deterministic encoding',
        () async {
      runner.result = MediaProcessOutput(0, 'SHA256=${'a' * 64}\r\n');
      expect(
          await backend.digest(
              source,
              _info(DownloadedAudioContainer.mp3, cover: true),
              mode,
              LibraryScanControl()),
          'a' * 64);
      final args = runner.arguments!;
      expect(args, containsAll(['-f', 'hash', '-hash', 'SHA256', 'pipe:1']));
      expect(args, contains(mode == AudioCopyDigest.cover ? '0:4' : '0:2'));
      expect(args,
          contains(mode == AudioCopyDigest.decodedPcm ? 'pcm_s32le' : 'copy'));
    });
  }
  for (final hash in [
    '',
    'SHA256=bad\n',
    'SHA256=${'a' * 64}\nextra',
    'SHA256=${'a' * 64}\n\n',
    'SHA256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n'
  ]) {
    test(
        'malformed, trailing or empty-content digest is rejected: ${hash.length}',
        () async {
      runner.result = MediaProcessOutput(0, hash);
      await expectLater(
          backend.digest(source, _info(DownloadedAudioContainer.mp3),
              AudioCopyDigest.packets, LibraryScanControl()),
          failure(AudioValidationOutcome.invalidAudio));
    });
  }
  test('cover digest requires an actual cover stream', () async {
    await expectLater(
        backend.digest(source, _info(DownloadedAudioContainer.mp3),
            AudioCopyDigest.cover, LibraryScanControl()),
        failure(AudioValidationOutcome.coverMissing));
    expect(runner.arguments, isNull);
  });
  for (final kind in MediaProcessFailureKind.values) {
    test('typed helper failure $kind does not expose process output', () async {
      runner.error = MediaProcessFailure(kind);
      await expectLater(
          backend.digest(source, _info(DownloadedAudioContainer.mp3),
              AudioCopyDigest.packets, LibraryScanControl()),
          failure(kind == MediaProcessFailureKind.unavailable
              ? AudioValidationOutcome.backendUnavailable
              : AudioValidationOutcome.unreadable));
    });
  }
  test('nonzero exit and error-level stderr cannot produce a digest', () async {
    for (final result in [
      const MediaProcessOutput(1, ''),
      MediaProcessOutput(0, 'SHA256=${'a' * 64}\n', hadStderr: true)
    ]) {
      runner.result = result;
      await expectLater(
          backend.digest(source, _info(DownloadedAudioContainer.mp3),
              AudioCopyDigest.packets, LibraryScanControl()),
          failure(AudioValidationOutcome.invalidAudio));
    }
  });
}

DownloadedAudioInspection _info(DownloadedAudioContainer container,
        {bool cover = false}) =>
    DownloadedAudioInspection(
        container: container,
        codec: _codec(container),
        duration: const Duration(seconds: 2),
        sizeBytes: 3,
        audioStreamIndex: 2,
        sampleRate: 48000,
        channels: 2,
        tags: {},
        coverStreamIndex: cover ? 4 : null);
DownloadedAudioExpectation _expected(DownloadedAudioContainer container) =>
    DownloadedAudioExpectation(
        quality: 'high',
        container: container,
        codec: _codec(container),
        fileSizeBytes: 3,
        duration: const Duration(seconds: 2),
        minimumBitRate:
            container == DownloadedAudioContainer.flac ? null : 96000,
        tags: {'title': 'Тест "\$()" = ; #'});
DownloadedAudioCodec _codec(DownloadedAudioContainer container) =>
    switch (container) {
      DownloadedAudioContainer.mp3 => DownloadedAudioCodec.mp3,
      DownloadedAudioContainer.m4a => DownloadedAudioCodec.aac,
      DownloadedAudioContainer.flac => DownloadedAudioCodec.flac,
    };

final class _Runner implements MediaProcessRunner {
  List<String>? arguments;
  MediaProcessOutput result = const MediaProcessOutput(0, '');
  Object? error;
  @override
  Future<MediaProcessOutput> run(String executable, List<String> arguments,
      LibraryScanControl control) async {
    this.arguments = arguments;
    if (error != null) throw error!;
    return result;
  }

  @override
  Future<void> close() async {}
}
