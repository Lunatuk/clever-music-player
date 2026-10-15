import 'dart:io';

import 'package:clever_music_player/src/domain/models/audio_source_reference.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validator.dart';
import 'package:clever_music_player/src/library_sync/ffmpeg_audio_validation_backend.dart';
import 'package:clever_music_player/src/library_sync/media_process_runner.dart';
import 'package:path/path.dart' as p;

/// Explicit developer integration check. Generates its own audio in systemTemp;
/// never opens the user's music, profile, database or account.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
        'Usage: dart run tool/check_downloaded_audio.dart <absolute-ffprobe> <absolute-ffmpeg>');
    exitCode = 64;
    return;
  }
  final probe = arguments[0], ffmpeg = arguments[1];
  final temp = await Directory.systemTemp.createTemp('cmp_media_validation_');
  final generation = BoundedMediaProcessRunner();
  final backend =
      FfmpegAudioValidationBackend(ffprobePath: probe, ffmpegPath: ffmpeg);
  final validator = DownloadedAudioValidator(backend: backend);
  var checks = 0;
  Future<void> generate(List<String> args) async {
    final output = await generation.run(
        ffmpeg,
        ['-hide_banner', '-nostdin', '-v', 'error', ...args],
        LibraryScanControl());
    if (output.exitCode != 0 || output.hadStderr) {
      throw StateError('Fixture generation failed.');
    }
  }

  Future<void> check(String name, File file,
      DownloadedAudioExpectation expected, AudioValidationOutcome outcome,
      {DownloadedAudioValidator? using}) async {
    final result = await (using ?? validator)
        .validate(FileAudioSource(file.path), expected);
    if (result.outcome != outcome) {
      throw StateError('$name: ${result.outcome}, expected $outcome');
    }
    if (outcome == AudioValidationOutcome.verified &&
        result.verification == null) {
      throw StateError('Missing verified evidence.');
    }
    checks++;
    stdout.writeln('PASS $name');
  }

  DownloadedAudioExpectation expected(File file,
          DownloadedAudioContainer container, DownloadedAudioCodec codec,
          {bool cover = true,
          String title = 'Тест "музыки"',
          int? minimumBitRate,
          Duration duration = const Duration(seconds: 2)}) =>
      DownloadedAudioExpectation(
          quality: 'synthetic-${codec.name}-profile',
          container: container,
          codec: codec,
          fileSizeBytes: file.lengthSync(),
          duration: duration,
          tags: {'title': title, 'artist': 'Артист', 'album': 'Album'},
          minimumBitRate: minimumBitRate ??
              (codec == DownloadedAudioCodec.flac ? null : 96000),
          minimumSampleRate: 48000,
          minimumBitDepth: codec == DownloadedAudioCodec.flac ? 16 : null,
          requireCover: cover);
  try {
    final cover = File(p.join(temp.path, 'cover.png'));
    await generate([
      '-f',
      'lavfi',
      '-i',
      'color=c=blue:s=16x16',
      '-frames:v',
      '1',
      '-threads',
      '1',
      cover.path
    ]);
    final files = <DownloadedAudioContainer, File>{};
    for (final entry in [
      (
        DownloadedAudioContainer.mp3,
        DownloadedAudioCodec.mp3,
        ['-c:a', 'libmp3lame', '-b:a', '320k']
      ),
      (
        DownloadedAudioContainer.m4a,
        DownloadedAudioCodec.aac,
        ['-c:a', 'aac', '-b:a', '256k']
      ),
      (
        DownloadedAudioContainer.flac,
        DownloadedAudioCodec.flac,
        ['-c:a', 'flac']
      ),
    ]) {
      final file = File(p.join(
          temp.path,
          'Кириллица quote " ${entry.$1.name}.${entry.$1.name}'
              .replaceAll('"', '')));
      await generate([
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:sample_rate=48000:duration=2',
        '-i',
        cover.path,
        '-map',
        '0:a',
        '-map',
        '1:v',
        '-ac',
        '2',
        ...entry.$3,
        '-c:v',
        'copy',
        '-disposition:v',
        'attached_pic',
        '-metadata',
        'title=Тест "музыки"',
        '-metadata',
        'artist=Артист',
        '-metadata',
        'album=Album',
        file.path
      ]);
      files[entry.$1] = file;
      await check(
          '${entry.$1.name} full audio and PNG cover decode',
          file,
          expected(file, entry.$1, entry.$2,
              minimumBitRate:
                  entry.$2 == DownloadedAudioCodec.mp3 ? 300000 : null),
          AudioValidationOutcome.verified);
    }
    final mp3 = files[DownloadedAudioContainer.mp3]!;
    await check(
        'wrong metadata rejected',
        mp3,
        expected(mp3, DownloadedAudioContainer.mp3, DownloadedAudioCodec.mp3,
            title: 'Other'),
        AudioValidationOutcome.metadataMismatch);
    await check(
        'lower encoding cannot satisfy higher policy',
        mp3,
        expected(mp3, DownloadedAudioContainer.mp3, DownloadedAudioCodec.mp3,
            minimumBitRate: 400000),
        AudioValidationOutcome.encodingMismatch);
    final renamed = await files[DownloadedAudioContainer.flac]!
        .copy(p.join(temp.path, 'renamed.mp3'));
    await check(
        'extension does not determine format',
        renamed,
        expected(
            renamed, DownloadedAudioContainer.flac, DownloadedAudioCodec.flac),
        AudioValidationOutcome.verified);
    final noCover = File(p.join(temp.path, 'no-cover.mp3'));
    final jpeg = File(p.join(temp.path, 'cover.jpg'));
    await generate(
        ['-i', cover.path, '-frames:v', '1', '-threads', '1', jpeg.path]);
    final jpegTrack = File(p.join(temp.path, 'jpeg-cover.mp3'));
    await generate([
      '-i',
      mp3.path,
      '-i',
      jpeg.path,
      '-map',
      '0:a:0',
      '-map',
      '1:v:0',
      '-c',
      'copy',
      '-disposition:v',
      'attached_pic',
      jpegTrack.path
    ]);
    await check(
        'JPEG embedded cover decode',
        jpegTrack,
        expected(
            jpegTrack, DownloadedAudioContainer.mp3, DownloadedAudioCodec.mp3),
        AudioValidationOutcome.verified);
    await generate(
        ['-i', mp3.path, '-map', '0:a:0', '-c:a', 'copy', noCover.path]);
    await check(
        'required embedded cover missing',
        noCover,
        expected(
            noCover, DownloadedAudioContainer.mp3, DownloadedAudioCodec.mp3),
        AudioValidationOutcome.coverMissing);
    await check(
        'provider without cover allowed explicitly',
        noCover,
        expected(
            noCover, DownloadedAudioContainer.mp3, DownloadedAudioCodec.mp3,
            cover: false),
        AudioValidationOutcome.verified);
    final fake = await File(p.join(temp.path, 'fake.mp3'))
        .writeAsString('<html>Not audio</html>');
    await check(
        'non-audio response rejected',
        fake,
        expected(fake, DownloadedAudioContainer.mp3, DownloadedAudioCodec.mp3),
        AudioValidationOutcome.invalidAudio);
    final bytes = await mp3.readAsBytes();
    final coverBytes = await cover.readAsBytes();
    final coverStart = _indexOf(bytes, coverBytes);
    final idat = _indexOf(coverBytes, [73, 68, 65, 84]);
    if (coverStart < 0 || idat < 0) {
      throw StateError('Missing PNG fixture payload.');
    }
    final damagedBytes = List<int>.of(bytes);
    damagedBytes[coverStart + idat + 4] ^= 255;
    final damaged = await File(p.join(temp.path, 'damaged-cover.mp3'))
        .writeAsBytes(damagedBytes);
    final damagedResult = await validator.validate(
        FileAudioSource(damaged.path),
        expected(
            damaged, DownloadedAudioContainer.mp3, DownloadedAudioCodec.mp3));
    if (![
          AudioValidationOutcome.invalidAudio,
          AudioValidationOutcome.invalidCover
        ].contains(damagedResult.outcome) ||
        damagedResult.verification != null) {
      throw StateError('Corrupt PNG was accepted.');
    }
    checks++;
    stdout.writeln('PASS corrupt embedded PNG rejected');
    final truncated = await File(p.join(temp.path, 'truncated.mp3'))
        .writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
    await check(
        'truncated MP3 rejected even with matching received size',
        truncated,
        expected(
            truncated, DownloadedAudioContainer.mp3, DownloadedAudioCodec.mp3),
        AudioValidationOutcome.invalidAudio);
    final gapped = File(p.join(temp.path, 'timestamp-gap.m4a'));
    await generate([
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=48000:duration=2',
      '-af',
      r'asetpts=PTS+if(gte(T\,1)\,3/TB\,0)',
      '-c:a',
      'aac',
      '-b:a',
      '256k',
      '-metadata',
      'title=Тест "музыки"',
      '-metadata',
      'artist=Артист',
      '-metadata',
      'album=Album',
      gapped.path
    ]);
    await check(
        'timestamp gap cannot substitute for decoded samples',
        gapped,
        expected(gapped, DownloadedAudioContainer.m4a, DownloadedAudioCodec.aac,
            cover: false,
            minimumBitRate: 1,
            duration: const Duration(seconds: 5)),
        AudioValidationOutcome.invalidAudio);
    final unavailable = DownloadedAudioValidator(
        backend: FfmpegAudioValidationBackend(
            ffprobePath: probe,
            ffmpegPath: p.join(temp.path, 'not-installed')));
    try {
      await check(
          'missing helper fails closed',
          mp3,
          expected(mp3, DownloadedAudioContainer.mp3, DownloadedAudioCodec.mp3),
          AudioValidationOutcome.backendUnavailable,
          using: unavailable);
    } finally {
      await unavailable.close();
    }
    stdout.writeln('$checks native media validation checks passed.');
  } finally {
    await validator.close();
    await generation.close();
    await temp.delete(recursive: true);
  }
}

int _indexOf(List<int> bytes, List<int> needle) {
  for (var index = 0; index <= bytes.length - needle.length; index++) {
    var matches = true;
    for (var part = 0; part < needle.length; part++) {
      if (bytes[index + part] != needle[part]) {
        matches = false;
        break;
      }
    }
    if (matches) return index;
  }
  return -1;
}
