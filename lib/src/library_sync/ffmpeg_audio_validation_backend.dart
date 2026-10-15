import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../library/library_scan_control.dart';
import 'downloaded_audio_validation.dart';
import 'downloaded_audio_validator.dart';
import 'media_process_runner.dart';

/// Executables are explicitly supplied by the future packaged-helper owner.
/// No PATH lookup, downloads, Python dependency or local development path here.
final class FfmpegAudioValidationBackend implements AudioValidationBackend {
  FfmpegAudioValidationBackend(
      {required this.ffprobePath,
      required this.ffmpegPath,
      MediaProcessRunner? runner})
      : _runner = runner ?? BoundedMediaProcessRunner() {
    for (final path in [ffprobePath, ffmpegPath]) {
      if (!p.isAbsolute(path) || path.contains('\u0000')) {
        throw ArgumentError('Требуется полный путь к медиапомощнику.');
      }
    }
  }
  final String ffprobePath, ffmpegPath;
  final MediaProcessRunner _runner;

  static const _inputOptions = [
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
      File file, LibraryScanControl control) async {
    final output = await _run(
        ffprobePath,
        [
          '-v',
          'error',
          ..._inputOptions,
          '-show_entries',
          'format=format_name,duration,size:format_tags:'
              'stream=index,codec_type,codec_name,duration,bit_rate,sample_rate,channels,bits_per_raw_sample,width,height:'
              'stream_disposition=attached_pic:stream_tags',
          '-of',
          'json',
          '-i',
          file.absolute.path
        ],
        control,
        AudioValidationOutcome.invalidAudio);
    try {
      return parseFfprobeAudioInspection(output);
    } on FormatException {
      throw const AudioValidationException(AudioValidationOutcome.invalidAudio);
    }
  }

  @override
  Future<Duration> decodeAudio(File file, DownloadedAudioInspection inspection,
      LibraryScanControl control) async {
    final output = await _run(
        ffmpegPath,
        [
          ..._decodeOptions,
          '-i',
          file.absolute.path,
          '-map',
          '0:${inspection.audioStreamIndex}',
          '-vn',
          '-sn',
          '-dn',
          '-af',
          'asetpts=N/SR/TB',
          '-f',
          'null',
          '-'
        ],
        control,
        AudioValidationOutcome.invalidAudio);
    final progress = _finalProgress(output);
    final micros = int.tryParse(progress['out_time_us'] ?? '');
    if (micros == null ||
        micros <= 0 ||
        micros > const Duration(hours: 12).inMicroseconds) {
      throw const AudioValidationException(AudioValidationOutcome.invalidAudio);
    }
    return Duration(microseconds: micros);
  }

  static const _decodeOptions = [
    '-hide_banner',
    '-nostdin',
    '-v',
    'error',
    '-xerror',
    '-max_error_rate',
    '0',
    '-nostats',
    '-progress',
    'pipe:1',
    '-stats_period',
    '60',
    '-threads',
    '1',
    '-filter_threads',
    '1',
    '-err_detect',
    'crccheck+bitstream+buffer+explode',
    ..._inputOptions,
  ];

  @override
  Future<void> decodeCover(File file, DownloadedAudioInspection inspection,
      LibraryScanControl control) async {
    if (inspection.coverStreamIndex == null) {
      throw ArgumentError('Обложки нет.');
    }
    final output = await _run(
        ffmpegPath,
        [
          ..._decodeOptions,
          '-i',
          file.absolute.path,
          '-map',
          '0:${inspection.coverStreamIndex}',
          '-an',
          '-sn',
          '-dn',
          '-frames:v',
          '1',
          '-f',
          'null',
          '-'
        ],
        control,
        AudioValidationOutcome.invalidCover);
    final frames = int.tryParse(_finalProgress(output)['frame'] ?? '');
    if (frames != 1) {
      throw const AudioValidationException(AudioValidationOutcome.invalidCover);
    }
  }

  Future<String> _run(String executable, List<String> arguments,
      LibraryScanControl control, AudioValidationOutcome invalid) async {
    try {
      final output = await _runner.run(executable, arguments, control);
      if (output.exitCode != 0 || output.hadStderr) {
        throw AudioValidationException(invalid);
      }
      return output.stdout;
    } on MediaProcessFailure catch (error) {
      throw AudioValidationException(
          error.kind == MediaProcessFailureKind.unavailable
              ? AudioValidationOutcome.backendUnavailable
              : AudioValidationOutcome.unreadable);
    }
  }

  @override
  Future<void> close() => _runner.close();
}

Map<String, String> _finalProgress(String output) {
  var block = <String, String>{};
  Map<String, String>? finalBlock;
  for (final line in const LineSplitter().convert(output)) {
    final index = line.indexOf('=');
    if (index <= 0 || finalBlock != null) {
      throw const AudioValidationException(AudioValidationOutcome.unreadable);
    }
    final key = line.substring(0, index);
    if (block.containsKey(key)) {
      throw const AudioValidationException(AudioValidationOutcome.unreadable);
    }
    block[key] = line.substring(index + 1);
    if (key == 'progress') {
      if (block[key] == 'end') {
        finalBlock = block;
      } else if (block[key] != 'continue') {
        throw const AudioValidationException(AudioValidationOutcome.unreadable);
      }
      block = {};
    }
  }
  if (finalBlock == null || block.isNotEmpty) {
    throw const AudioValidationException(AudioValidationOutcome.unreadable);
  }
  return finalBlock;
}

/// Bounded ffprobe JSON, independent of the filename and requested encoding.
DownloadedAudioInspection parseFfprobeAudioInspection(String output) {
  if (output.length > 256 * 1024) throw const FormatException('Большой ответ.');
  final decoded = jsonDecode(output);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Нет объекта.');
  }
  final format = decoded['format'];
  final streams = decoded['streams'];
  if (format is! Map<String, dynamic> ||
      streams is! List ||
      streams.isEmpty ||
      streams.length > 2) {
    throw const FormatException('Нет аудиопотока.');
  }
  final container = switch (format['format_name']) {
    'mp3' => DownloadedAudioContainer.mp3,
    'mov,mp4,m4a,3gp,3g2,mj2' => DownloadedAudioContainer.m4a,
    'flac' => DownloadedAudioContainer.flac,
    _ => throw const FormatException('Неподдерживаемый контейнер.'),
  };
  Map<String, dynamic>? audio;
  int? coverIndex;
  final indexes = <int>{};
  for (final entry in streams) {
    if (entry is! Map<String, dynamic>) {
      throw const FormatException('Нет потока.');
    }
    final index = entry['index'];
    if (index is! int || index < 0 || !indexes.add(index)) {
      throw const FormatException('Некорректный индекс.');
    }
    if (entry['codec_type'] == 'audio' && audio == null) {
      audio = entry;
    } else if (entry['codec_type'] == 'video' && coverIndex == null) {
      final disposition = entry['disposition'];
      final width = entry['width'], height = entry['height'];
      if (disposition is! Map ||
          disposition['attached_pic'] != 1 ||
          !['mjpeg', 'png'].contains(entry['codec_name']) ||
          width is! int ||
          height is! int ||
          width <= 0 ||
          height <= 0 ||
          width > 4096 ||
          height > 4096) {
        throw const FormatException('Некорректная встроенная обложка.');
      }
      coverIndex = index;
    } else {
      throw const FormatException('Неожиданный поток.');
    }
  }
  if (audio == null) throw const FormatException('Нет аудио.');
  final codec = switch (audio['codec_name']) {
    'mp3' => DownloadedAudioCodec.mp3,
    'aac' => DownloadedAudioCodec.aac,
    'flac' => DownloadedAudioCodec.flac,
    _ => throw const FormatException('Неподдерживаемый кодек.'),
  };
  final durationValue = audio['duration'] ?? format['duration'];
  final seconds =
      durationValue is String ? double.tryParse(durationValue) : null;
  if (seconds == null || !seconds.isFinite || seconds <= 0 || seconds > 43200) {
    throw const FormatException('Нет длительности.');
  }
  final tags = <String, String>{};
  for (final rawTags in [format['tags'], audio['tags']]) {
    if (rawTags == null) continue;
    if (rawTags is! Map) throw const FormatException('Нет тегов.');
    for (final entry in rawTags.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Некорректный тег.');
      }
      final key = (entry.key as String).toLowerCase();
      final canonical = key == 'albumartist' ? 'album_artist' : key;
      if (!audioValidationTagKeys.contains(canonical)) continue;
      final previous = tags[canonical];
      if (previous != null && previous != entry.value) {
        throw const FormatException('Конфликтующие теги.');
      }
      tags[canonical] = entry.value as String;
    }
  }
  return DownloadedAudioInspection(
      container: container,
      codec: codec,
      duration: Duration(microseconds: (seconds * 1000000).round()),
      sizeBytes: _integer(format['size'])!,
      audioStreamIndex: audio['index'] as int,
      sampleRate: _integer(audio['sample_rate'])!,
      channels: _integer(audio['channels'])!,
      bitRate: _integer(audio['bit_rate'], optional: true),
      bitDepth: _integer(audio['bits_per_raw_sample'], optional: true),
      coverStreamIndex: coverIndex,
      tags: tags);
}

int? _integer(Object? value, {bool optional = false}) {
  if (optional &&
      (value == null || value == 'N/A' || value == '0' || value == 0)) {
    return null;
  }
  final int? parsed = value is int
      ? value
      : value is String && RegExp(r'^[0-9]+$').stringMatch(value) == value
          ? int.tryParse(value)
          : null;
  if (parsed == null || parsed <= 0) {
    throw const FormatException('Некорректное число.');
  }
  return parsed;
}
