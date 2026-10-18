import 'dart:io';

import '../library/library_scan_control.dart';
import 'downloaded_audio_metadata.dart';
import 'downloaded_audio_validation.dart';
import 'ffmpeg_audio_validation_backend.dart';
import 'media_process_runner.dart';

/// Stream copy only. Uses the same explicit helper paths and bounded runner as
/// validation; the future packaged-helper owner supplies qualified executables.
final class FfmpegAudioMetadataBackend implements AudioMetadataBackend {
  FfmpegAudioMetadataBackend(
      {required String ffprobePath,
      required this.ffmpegPath,
      MediaProcessRunner? runner})
      : _runner = runner ?? BoundedMediaProcessRunner() {
    _validation = FfmpegAudioValidationBackend(
        ffprobePath: ffprobePath, ffmpegPath: ffmpegPath, runner: _runner);
  }
  final String ffmpegPath;
  final MediaProcessRunner _runner;
  late final FfmpegAudioValidationBackend _validation;
  static const _common = [
    '-hide_banner',
    '-nostdin',
    '-v',
    'error',
    '-xerror',
    '-max_error_rate',
    '0',
    '-threads',
    '1',
  ];
  static const _input = [
    '-max_alloc',
    '67108864',
    '-protocol_whitelist',
    'file,pipe',
    '-format_whitelist',
    'mp3,mov,flac',
    '-max_streams',
    '2',
    '-probesize',
    '2097152',
    '-analyzeduration',
    '10000000',
  ];

  @override
  Future<DownloadedAudioInspection> inspect(
          File file, LibraryScanControl control) =>
      _validation.inspect(file, control);
  @override
  Future<Duration> decodeAudio(File file, DownloadedAudioInspection info,
          LibraryScanControl control) =>
      _validation.decodeAudio(file, info, control);
  @override
  Future<void> decodeCover(File file, DownloadedAudioInspection info,
          LibraryScanControl control) =>
      _validation.decodeCover(file, info, control);

  @override
  Future<String> digest(File file, DownloadedAudioInspection info,
      AudioCopyDigest mode, LibraryScanControl control) async {
    final picture = mode == AudioCopyDigest.cover;
    final index = picture ? info.coverStreamIndex : info.audioStreamIndex;
    if (index == null) {
      throw const AudioValidationException(AudioValidationOutcome.coverMissing);
    }
    final output = await _run([
      ..._common,
      ..._input,
      '-err_detect',
      'crccheck+bitstream+buffer+explode',
      '-i',
      file.absolute.path,
      '-map',
      '0:$index',
      '-sn',
      '-dn',
      if (picture) ...[
        '-an',
        '-c:v',
        'copy',
        '-frames:v',
        '1',
      ] else ...[
        '-vn',
        '-c:a',
        mode == AudioCopyDigest.packets ? 'copy' : 'pcm_s32le',
      ],
      '-f',
      'hash',
      '-hash',
      'SHA256',
      'pipe:1',
    ], control);
    final match = RegExp(r'^SHA256=([0-9a-f]{64})\r?\n?$').firstMatch(output);
    if (match == null ||
        match.end != output.length ||
        match[1] ==
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') {
      throw AudioValidationException(picture
          ? AudioValidationOutcome.invalidCover
          : AudioValidationOutcome.invalidAudio);
    }
    return match[1]!;
  }

  @override
  Future<void> writeMetadata(
      File source,
      File output,
      DownloadedAudioInspection info,
      DownloadedAudioExpectation expected,
      LibraryScanControl control,
      {File? cover,
      EmbeddedCoverFormat? coverFormat,
      int? maxOutputBytes}) async {
    if (maxOutputBytes != null &&
        (maxOutputBytes <= 0 || maxOutputBytes > 8589934592)) {
      throw ArgumentError('Некорректный предел подготовки.');
    }
    if ((cover == null) != (coverFormat == null) ||
        source.absolute.path == output.absolute.path) {
      throw ArgumentError('Некорректное назначение метаданных.');
    }
    final withCover = cover != null || info.coverStreamIndex != null;
    final keys = expected.tags.keys.toList()..sort();
    await _run([
      ..._common,
      '-y',
      ..._input,
      '-i',
      source.absolute.path,
      if (cover != null) ...[
        '-max_alloc',
        '67108864',
        '-protocol_whitelist',
        'file,pipe',
        '-max_streams',
        '1',
        '-f',
        coverFormat == EmbeddedCoverFormat.png ? 'png_pipe' : 'jpeg_pipe',
        '-i',
        cover.absolute.path,
      ],
      '-map',
      '0:${info.audioStreamIndex}',
      if (withCover) ...[
        '-map',
        cover != null ? '1:v:0' : '0:${info.coverStreamIndex}',
      ],
      '-map_metadata',
      '-1',
      '-map_metadata:s',
      '-1',
      '-map_chapters',
      '-1',
      '-c:a',
      'copy',
      if (withCover) ...[
        '-c:v',
        'copy',
        '-disposition:v:0',
        'attached_pic',
        '-metadata:s:v:0',
        'title=Album cover',
        '-metadata:s:v:0',
        'comment=Cover (front)',
      ],
      for (final key in keys) ...['-metadata', '$key=${expected.tags[key]}'],
      if (expected.container == DownloadedAudioContainer.mp3) ...[
        '-id3v2_version',
        '4',
      ],
      if (expected.container == DownloadedAudioContainer.m4a) ...[
        '-movflags',
        '+faststart',
      ],
      '-fs',
      '${maxOutputBytes ?? 8589934592}',
      '-f',
      switch (expected.container) {
        DownloadedAudioContainer.mp3 => 'mp3',
        DownloadedAudioContainer.m4a => 'ipod',
        DownloadedAudioContainer.flac => 'flac',
      },
      output.absolute.path,
    ], control);
  }

  Future<String> _run(
      List<String> arguments, LibraryScanControl control) async {
    try {
      final result = await _runner.run(ffmpegPath, arguments, control);
      if (result.exitCode != 0 || result.hadStderr) {
        throw const AudioValidationException(
            AudioValidationOutcome.invalidAudio);
      }
      return result.stdout;
    } on MediaProcessFailure catch (error) {
      throw AudioValidationException(
          error.kind == MediaProcessFailureKind.unavailable
              ? AudioValidationOutcome.backendUnavailable
              : AudioValidationOutcome.unreadable);
    }
  }

  @override
  Future<void> close() => _validation.close();
}
