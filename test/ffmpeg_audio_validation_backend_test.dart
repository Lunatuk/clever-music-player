import 'dart:convert';
import 'dart:io';

import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:clever_music_player/src/library_sync/ffmpeg_audio_validation_backend.dart';
import 'package:clever_music_player/src/library_sync/media_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MP3 format/stream facts and case-insensitive canonical tags parsed',
      () {
    final info = parseFfprobeAudioInspection(jsonEncode(_json()));
    expect(info.container, DownloadedAudioContainer.mp3);
    expect(info.codec, DownloadedAudioCodec.mp3);
    expect(info.bitRate, 320000);
    expect(info.tags, {'title': 'Песня', 'album_artist': 'Артист'});
    expect(info.coverStreamIndex, 1);
  });
  for (final entry in [
    ('flac', 'flac', DownloadedAudioContainer.flac),
    ('mov,mp4,m4a,3gp,3g2,mj2', 'aac', DownloadedAudioContainer.m4a)
  ]) {
    test('real format name ${entry.$1} canonicalized', () {
      final raw = _json();
      (raw['format'] as Map)['format_name'] = entry.$1;
      ((raw['streams'] as List).first as Map)['codec_name'] = entry.$2;
      final result = parseFfprobeAudioInspection(jsonEncode(raw));
      expect(result.container, entry.$3);
      expect(result.codec.name, entry.$2);
    });
  }
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'no streams': (raw) => raw['streams'] = [],
    'too many streams': (raw) => (raw['streams'] as List).add({'index': 2}),
    'duplicate index': (raw) =>
        ((raw['streams'] as List)[1] as Map)['index'] = 0,
    'float index': (raw) => ((raw['streams'] as List)[0] as Map)['index'] = 0.0,
    'ordinary movie is not artwork': (raw) => (((raw['streams'] as List)[1]
        as Map)['disposition'] as Map)['attached_pic'] = 0,
    'unsupported picture codec': (raw) =>
        ((raw['streams'] as List)[1] as Map)['codec_name'] = 'h264',
    'huge picture': (raw) =>
        ((raw['streams'] as List)[1] as Map)['width'] = 4097,
    'unknown container': (raw) => (raw['format'] as Map)['format_name'] = 'hls',
    'unsupported audio codec': (raw) =>
        ((raw['streams'] as List)[0] as Map)['codec_name'] = 'opus',
    'zero duration': (raw) => (raw['format'] as Map)['duration'] = '0',
    'non finite duration': (raw) => (raw['format'] as Map)['duration'] = 'NaN',
    'huge duration': (raw) => (raw['format'] as Map)['duration'] = '43201',
    'float size': (raw) => (raw['format'] as Map)['size'] = 3.0,
    'negative sample rate': (raw) =>
        ((raw['streams'] as List)[0] as Map)['sample_rate'] = '-1',
    'channels out of bounds': (raw) =>
        ((raw['streams'] as List)[0] as Map)['channels'] = 9,
    'conflicting tag case': (raw) =>
        ((raw['format'] as Map)['tags'] as Map)['title'] = 'Other',
    'conflicting stream tag': (raw) =>
        ((raw['streams'] as List)[0] as Map)['tags'] = {'title': 'Other'},
  };
  for (final entry in mutations.entries) {
    test('reject ${entry.key}', () {
      final raw = _json();
      entry.value(raw);
      expect(() => parseFfprobeAudioInspection(jsonEncode(raw)),
          throwsFormatException);
    });
  }
  test('unknown numeric evidence remains unknown rather than invented', () {
    final raw = _json();
    ((raw['streams'] as List)[0] as Map)['bit_rate'] = 'N/A';
    final info = parseFfprobeAudioInspection(jsonEncode(raw));
    expect(info.bitRate, isNull);
    expect(info.bitDepth, isNull);
  });
  test('response bounds and malformed JSON fail closed', () {
    for (final raw in ['[]', '{}', 'invalid', 'a' * 262145]) {
      expect(() => parseFfprobeAudioInspection(raw), throwsFormatException);
    }
  });

  group('helper protocol', () {
    late _Runner runner;
    late FfmpegAudioValidationBackend backend;
    final file = File('a quote " and spaces.mp3');
    setUp(() {
      runner = _Runner();
      backend = FfmpegAudioValidationBackend(
          ffprobePath: File('ffprobe').absolute.path,
          ffmpegPath: File('ffmpeg').absolute.path,
          runner: runner);
    });
    tearDown(() => backend.close());
    test(
        'separate arguments, file protocols, bounded formats and stream probing',
        () async {
      runner.output = MediaProcessOutput(0, jsonEncode(_json()));
      await backend.inspect(file, LibraryScanControl());
      expect(runner.args!.last, file.absolute.path);
      expect(runner.args,
          containsAll(['file,pipe', 'mp3,mov,flac', '-max_streams', '2']));
      expect(runner.args, contains('-show_entries'));
    });
    test(
        'audio decoder requires final progress and reports positive decoded time',
        () async {
      runner.output = const MediaProcessOutput(0,
          'out_time_us=1000000\nprogress=continue\nout_time_us=3000000\nprogress=end\n');
      expect(
          await backend.decodeAudio(
              file,
              parseFfprobeAudioInspection(jsonEncode(_json())),
              LibraryScanControl()),
          const Duration(seconds: 3));
      expect(
          runner.args,
          containsAll([
            '-nostdin',
            '-xerror',
            '-vn',
            '-f',
            'null',
            '0:0',
            '-af',
            'asetpts=N/SR/TB'
          ]));
    });
    for (final raw in [
      '',
      'out_time_us=0\nprogress=end\n',
      'out_time_us=3000000\nprogress=continue\n',
      'out_time_us=3000000\nout_time_us=3\nprogress=end\n',
      'out_time_us=3000000\nprogress=end\nextra=1\n'
    ]) {
      test('incomplete/invalid decoder progress rejected: $raw', () async {
        runner.output = MediaProcessOutput(0, raw);
        await expectLater(
            backend.decodeAudio(
                file,
                parseFfprobeAudioInspection(jsonEncode(_json())),
                LibraryScanControl()),
            throwsA(isA<AudioValidationException>()));
      });
    }
    test('cover must decode exactly one frame', () async {
      final info = parseFfprobeAudioInspection(jsonEncode(_json()));
      runner.output = const MediaProcessOutput(0, 'frame=1\nprogress=end\n');
      await backend.decodeCover(file, info, LibraryScanControl());
      expect(runner.args, containsAll(['0:1', '-frames:v', '1', '-an']));
      runner.output = const MediaProcessOutput(0, 'frame=0\nprogress=end\n');
      await expectLater(backend.decodeCover(file, info, LibraryScanControl()),
          throwsA(isA<AudioValidationException>()));
    });
    test('exit failure and error-level stderr cannot be accepted as success',
        () async {
      for (final output in [
        const MediaProcessOutput(1, '{}'),
        const MediaProcessOutput(0, '{}', hadStderr: true)
      ]) {
        runner.output = output;
        await expectLater(
            backend.inspect(file, LibraryScanControl()),
            throwsA(isA<AudioValidationException>().having((e) => e.outcome,
                'outcome', AudioValidationOutcome.invalidAudio)));
      }
    });
    for (final kind in MediaProcessFailureKind.values) {
      test('process $kind sanitized and typed', () async {
        runner.error = MediaProcessFailure(kind);
        await expectLater(
            backend.inspect(file, LibraryScanControl()),
            throwsA(isA<AudioValidationException>().having(
                (e) => e.outcome,
                'outcome',
                kind == MediaProcessFailureKind.unavailable
                    ? AudioValidationOutcome.backendUnavailable
                    : AudioValidationOutcome.unreadable)));
      });
    }
    test('relative helper paths rejected, no PATH fallback', () {
      expect(
          () => FfmpegAudioValidationBackend(
              ffprobePath: 'ffprobe', ffmpegPath: 'ffmpeg'),
          throwsArgumentError);
    });
  });
}

Map<String, dynamic> _json() => {
      'format': {
        'format_name': 'mp3',
        'duration': '3.0',
        'size': '3',
        'tags': {'TITLE': 'Песня', 'ALBUMARTIST': 'Артист'}
      },
      'streams': [
        {
          'index': 0,
          'codec_type': 'audio',
          'codec_name': 'mp3',
          'sample_rate': '48000',
          'channels': 2,
          'bit_rate': '320000',
          'bits_per_raw_sample': '0'
        },
        {
          'index': 1,
          'codec_type': 'video',
          'codec_name': 'png',
          'width': 100,
          'height': 100,
          'disposition': {'attached_pic': 1}
        }
      ]
    };

final class _Runner implements MediaProcessRunner {
  MediaProcessOutput output = const MediaProcessOutput(0, '');
  Object? error;
  List<String>? args;
  @override
  Future<MediaProcessOutput> run(String executable, List<String> arguments,
      LibraryScanControl control) async {
    args = arguments;
    if (error != null) throw error!;
    return output;
  }

  @override
  Future<void> close() async {}
}
