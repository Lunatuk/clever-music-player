import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' as tags;

import 'package:clever_music_player/src/domain/models/audio_source_reference.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata_preparer.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:clever_music_player/src/library_sync/ffmpeg_audio_metadata_backend.dart';
import 'package:clever_music_player/src/library_sync/media_process_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Explicit, offline developer check. All audio/artwork is generated in our own
/// systemTemp directory; the user's library, database and account are not read.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('Usage: dart tool/check_downloaded_audio_metadata.dart '
        '<absolute-ffprobe> <absolute-ffmpeg>');
    exitCode = 64;
    return;
  }
  final root = await Directory.systemTemp.createTemp('cmp_metadata_check_');
  final runner = BoundedMediaProcessRunner();
  final preparer = DownloadedAudioMetadataPreparer(
      backend: FfmpegAudioMetadataBackend(
          ffprobePath: arguments[0], ffmpegPath: arguments[1]),
      temporaryParent: root);
  final delivered = <PreparedDownloadedAudio>[];
  var checks = 0;
  void pass(String name) {
    checks++;
    stdout.writeln('PASS $name');
  }

  Future<void> generate(List<String> args) async {
    final output = await runner.run(
        arguments[1],
        ['-hide_banner', '-nostdin', '-v', 'error', ...args],
        LibraryScanControl());
    if (output.exitCode != 0 || output.hadStderr) {
      throw StateError('Synthetic fixture generation failed.');
    }
  }

  DownloadedAudioExpectation expectation(File file,
          DownloadedAudioContainer container, DownloadedAudioCodec codec,
          {String title = 'Тест "музыки" \$() = ; # 🎵',
          bool requireCover = true}) =>
      DownloadedAudioExpectation(
          quality: 'synthetic-${codec.name}',
          container: container,
          codec: codec,
          fileSizeBytes: file.lengthSync(),
          duration: const Duration(seconds: 2),
          minimumBitRate: codec == DownloadedAudioCodec.flac ? null : 96000,
          minimumSampleRate: 48000,
          minimumBitDepth: codec == DownloadedAudioCodec.flac ? 16 : null,
          requireCover: requireCover,
          tags: {
            'title': title,
            'artist': 'Артист / 漢字',
            'album': 'Альбом',
            'album_artist': 'Исполнитель альбома',
            'genre': 'Rock; Alternative',
            'track': '2/10',
            'disc': '1/2',
            'date': '2026-10-16',
          });
  Future<PreparedDownloadedAudio> prepare(File file,
      DownloadedAudioExpectation expected, EmbeddedCover? cover) async {
    final PreparedDownloadedAudio result;
    try {
      result = await preparer.prepare(FileAudioSource(file.path), expected,
          cover: cover);
    } on AudioValidationException catch (error) {
      stderr.writeln('Preparation failed: ${error.outcome}');
      rethrow;
    }
    delivered.add(result);
    if (result.file.path == file.path ||
        result.verification.fileSizeBytes != await result.file.length() ||
        sha256.convert(await result.file.readAsBytes()).toString() !=
            result.verification.contentHash) {
      throw StateError('Prepared result has invalid file evidence.');
    }
    return result;
  }

  Future<void> reject(String name, Future<Object?> Function() operation,
      Set<AudioValidationOutcome> outcomes) async {
    try {
      await operation();
      throw StateError('Unexpected success: $name');
    } on AudioValidationException catch (error) {
      if (!outcomes.contains(error.outcome)) {
        throw StateError('$name: unexpected ${error.outcome}');
      }
      pass(name);
    }
  }

  try {
    final pngFile = File(p.join(root.path, 'cover.png'));
    final jpegFile = File(p.join(root.path, 'cover.jpg'));
    await generate([
      '-f',
      'lavfi',
      '-i',
      'color=c=blue:s=16x16',
      '-frames:v',
      '1',
      '-threads',
      '1',
      pngFile.path,
    ]);
    await generate([
      '-f',
      'lavfi',
      '-i',
      'color=c=red:s=16x16',
      '-frames:v',
      '1',
      '-threads',
      '1',
      jpegFile.path,
    ]);
    final png =
        EmbeddedCover(await pngFile.readAsBytes(), EmbeddedCoverFormat.png);
    final jpeg =
        EmbeddedCover(await jpegFile.readAsBytes(), EmbeddedCoverFormat.jpeg);
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
      final source =
          File(p.join(root.path, 'Музыка пробел ${entry.$1.name}.part'));
      await generate([
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:sample_rate=48000:duration=2',
        '-ac',
        '2',
        ...entry.$3,
        '-f',
        entry.$1 == DownloadedAudioContainer.m4a ? 'ipod' : entry.$1.name,
        source.path,
      ]);
      final raw = await source.readAsBytes();
      final expected = expectation(source, entry.$1, entry.$2);
      final withPng = await prepare(source, expected, png);
      pass('${entry.$1.name}: 8 Unicode tags + PNG, identical packets and PCM');
      final readerCopy = await withPng.file
          .copy(p.join(root.path, 'application-reader.${entry.$1.name}'));
      final read = await const AudioMetadataReaderService().read(readerCopy);
      if (read.title != expected.tags['title'] ||
          read.artist != expected.tags['artist'] ||
          read.albumArtist != expected.tags['album_artist'] ||
          read.album != expected.tags['album'] ||
          read.trackNumber != 2 ||
          read.discNumber != 1 ||
          read.year != 2026 ||
          read.artwork == null ||
          sha256.convert(read.artwork!.bytes).toString() !=
              sha256.convert(png.bytes).toString()) {
        throw StateError(
            'Application metadata reader mismatch: ${entry.$1.name}; '
            'artist=${read.artist}, albumArtist=${read.albumArtist}, '
            'year=${read.year}, track=${read.trackNumber}, disc=${read.discNumber}');
      }
      pass(
          '${entry.$1.name}: app reader keeps track and album artists distinct');
      if (entry.$1 == DownloadedAudioContainer.flac) {
        // Only a generated copy, not the metadata writer used by downloads.
        final legacyCopy =
            await withPng.file.copy(p.join(root.path, 'legacy-writer.flac'));
        final checking = FfmpegAudioMetadataBackend(
            ffprobePath: arguments[0], ffmpegPath: arguments[1]);
        final token = LibraryScanControl();
        try {
          final oldInfo = await checking.inspect(legacyCopy, token);
          final oldPcm = await checking.digest(
              legacyCopy, oldInfo, AudioCopyDigest.decodedPcm, token);
          final oldPackets = await checking.digest(
              legacyCopy, oldInfo, AudioCopyDigest.packets, token);
          final metadata =
              tags.readAllMetadata(legacyCopy) as tags.VorbisMetadata;
          metadata.title = ['Roundtrip fixture'];
          tags.FlacWriter().write(legacyCopy, metadata);
          final newInfo = await checking.inspect(legacyCopy, token);
          final readAgain = tags.readMetadata(legacyCopy);
          if (await checking.digest(
                      legacyCopy, newInfo, AudioCopyDigest.decodedPcm, token) !=
                  oldPcm ||
              await checking.digest(
                      legacyCopy, newInfo, AudioCopyDigest.packets, token) !=
                  oldPackets ||
              readAgain.artist != expected.tags['artist'] ||
              readAgain.albumArtist != expected.tags['album_artist']) {
            throw StateError(
                'Vendored FLAC serializer changed audio or artist roles.');
          }
          pass(
              'FLAC serializer retains artist roles, valid final block, packets and PCM');
        } finally {
          await checking.close();
        }
      }
      await prepare(source, expected, jpeg);
      pass('${entry.$1.name}: JPEG without audio transcoding');
      await prepare(
          withPng.file,
          expectation(withPng.file, entry.$1, entry.$2,
              title: 'Новое название'),
          null);
      pass('${entry.$1.name}: existing PNG retained while updating tags');
      await prepare(
          withPng.file, expectation(withPng.file, entry.$1, entry.$2), jpeg);
      pass('${entry.$1.name}: existing PNG replaced with exact JPEG');
      final withoutCover = await prepare(source,
          expectation(source, entry.$1, entry.$2, requireCover: false), null);
      if (withoutCover.inspection.coverStreamIndex != null) {
        throw StateError('Unexpected artwork added.');
      }
      pass('${entry.$1.name}: explicit coverless provider supported');
      if (sha256.convert(raw).toString() !=
          sha256.convert(await source.readAsBytes()).toString()) {
        throw StateError('Source bytes were changed.');
      }
      await reject(
          '${entry.$1.name}: required cover absent',
          () => prepare(source, expected, null),
          {AudioValidationOutcome.coverMissing});
    }
    final mp3 = File(p.join(root.path, 'Музыка пробел mp3.part'));
    final mp3Expected = expectation(
        mp3, DownloadedAudioContainer.mp3, DownloadedAudioCodec.mp3);
    await reject(
        'corrupt PNG never yields a prepared result',
        () => prepare(
            mp3,
            mp3Expected,
            EmbeddedCover([137, 80, 78, 71, 13, 10, 26, 10, 0, 1],
                EmbeddedCoverFormat.png)),
        {
          AudioValidationOutcome.invalidAudio,
          AudioValidationOutcome.invalidCover
        });
    await reject(
        'declared container cannot substitute for actual format',
        () => prepare(
            mp3,
            expectation(
                mp3, DownloadedAudioContainer.m4a, DownloadedAudioCodec.aac),
            png),
        {AudioValidationOutcome.encodingMismatch});
    final rawMp3 = await mp3.readAsBytes();
    final truncated = await File(p.join(root.path, 'truncated.part'))
        .writeAsBytes(rawMp3.sublist(0, rawMp3.length ~/ 2));
    await reject(
        'truncated source cannot be repaired by tagging',
        () => prepare(
            truncated,
            expectation(truncated, DownloadedAudioContainer.mp3,
                DownloadedAudioCodec.mp3),
            png),
        {AudioValidationOutcome.invalidAudio, AudioValidationOutcome.changed});
    await reject(
        'cancelled preparation does not start a helper',
        () => preparer.prepare(FileAudioSource(mp3.path), mp3Expected,
            control: LibraryScanControl()..cancel()),
        {AudioValidationOutcome.cancelled});
    await reject(
        'SAF URI requires the future Android metadata adapter',
        () => preparer.prepare(
            ContentUriAudioSource('content://synthetic/song'), mp3Expected),
        {AudioValidationOutcome.unsupportedSource});
    final absent = DownloadedAudioMetadataPreparer(
        backend: FfmpegAudioMetadataBackend(
            ffprobePath: p.join(root.path, 'absent-ffprobe.exe'),
            ffmpegPath: arguments[1]),
        temporaryParent: root);
    try {
      await reject(
          'missing helper cannot publish a metadata result',
          () => absent.prepare(FileAudioSource(mp3.path), mp3Expected),
          {AudioValidationOutcome.backendUnavailable});
    } finally {
      await absent.close();
    }
    final ogg = File(p.join(root.path, 'shared-vorbis-parser.ogg'));
    await generate([
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:duration=1',
      '-c:a',
      'libvorbis',
      '-metadata',
      'album_artist=Album Singer',
      '-metadata',
      'artist=Track Singer',
      '-metadata',
      'title=OGG fixture',
      ogg.path
    ]);
    final oggRead = await const AudioMetadataReaderService().read(ogg);
    if (oggRead.artist != 'Track Singer' ||
        oggRead.albumArtist != 'Album Singer') {
      throw StateError('Shared Vorbis parser lost artist roles in OGG.');
    }
    pass('shared Vorbis reader keeps OGG artist roles distinct');
    await preparer.close();
    if (!await delivered.first.file.exists()) {
      throw StateError('Closing the preparer removed a delivered result.');
    }
    pass(
        'preparer close preserves delivered files until explicit result close');
    for (final result in delivered) {
      await result.close();
      await result.close();
      if (await result.file.parent.exists()) {
        throw StateError('Prepared private directory was not removed.');
      }
    }
    pass('result close is idempotent and removes only its own generated files');
    stdout.writeln('$checks native metadata preparation checks passed.');
  } finally {
    await preparer.close();
    await runner.close();
    for (final result in delivered) {
      await result.close();
    }
    // All known files only; unknown content prevents removal of the directory.
    await for (final file in root.list(followLinks: false)) {
      if (file is! File) throw StateError('Unexpected fixture directory.');
      await file.delete();
    }
    await root.delete();
  }
}
