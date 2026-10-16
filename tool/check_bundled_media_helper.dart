import 'dart:io';

import 'package:clever_music_player/src/domain/models/audio_source_reference.dart';
import 'package:clever_music_player/src/library_sync/bundled_media_helper.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata_preparer.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:path/path.dart' as p;

/// Offline qualification, no music/database/account access.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 && arguments.length != 2) {
    stderr.writeln('Usage: dart tool/check_bundled_media_helper.dart '
        '<absolute-bundle-directory> [synthetic-fixture-directory]');
    exitCode = 64;
    return;
  }
  final helper = BundledMediaHelper(directory: Directory(arguments.first));
  try {
    final qualified = await helper.qualify();
    stdout.writeln('PASS bundled FFmpeg ${qualified.version}: integrity, '
        'versions, codecs, containers, filters, file/pipe only.');
    if (arguments.length == 2) {
      await _smoke(qualified, Directory(arguments[1]));
    }
  } on MediaHelperException catch (error) {
    stderr.writeln('FAIL media helper: ${error.failure.name}');
    exitCode = 1;
  } finally {
    await helper.close();
  }
}

Future<void> _smoke(QualifiedMediaHelper helper, Directory fixtures) async {
  final root = await Directory.systemTemp.createTemp('cmp helper_музыка_');
  final preparer = DownloadedAudioMetadataPreparer(
      backend: helper.createMetadataBackend(), temporaryParent: root);
  final results = <PreparedDownloadedAudio>[];
  var checks = 0;
  try {
    final covers = [
      EmbeddedCover(
          await File(p.join(fixtures.path, 'cover.png')).readAsBytes(),
          EmbeddedCoverFormat.png),
      EmbeddedCover(
          await File(p.join(fixtures.path, 'cover.jpg')).readAsBytes(),
          EmbeddedCoverFormat.jpeg),
    ];
    for (final entry in [
      (DownloadedAudioContainer.mp3, DownloadedAudioCodec.mp3),
      (DownloadedAudioContainer.m4a, DownloadedAudioCodec.aac),
      (DownloadedAudioContainer.flac, DownloadedAudioCodec.flac),
    ]) {
      var input = await File(p.join(fixtures.path, 'tone.${entry.$1.name}'))
          .copy(p.join(root.path, 'Тест \$() ${entry.$1.name}.part'));
      for (final cover in <EmbeddedCover?>[...covers, null]) {
        final expected = DownloadedAudioExpectation(
            quality: 'synthetic-${entry.$2.name}',
            container: entry.$1,
            codec: entry.$2,
            fileSizeBytes: await input.length(),
            duration: const Duration(seconds: 2),
            minimumBitRate:
                entry.$2 == DownloadedAudioCodec.flac ? null : 96000,
            minimumSampleRate: 48000,
            requireCover: true,
            tags: {
              'title': 'Тест "\$()" = ; # 🎵',
              'artist': 'Артист / 漢字',
              'album': 'Альбом',
              'album_artist': 'Исполнитель альбома',
              'genre': 'Rock; Alternative',
              'track': '2/10',
              'disc': '1/2',
              'date': '2026-10-16',
            });
        final result = await preparer
            .prepare(FileAudioSource(input.path), expected, cover: cover);
        results.add(result);
        input = result.file;
        checks++;
        stdout.writeln('PASS ${entry.$1.name}: tags, '
            '${cover?.format.name ?? 'retained cover'}, packets + full PCM, decode + SHA.');
      }
    }
    stdout.writeln('$checks packaged-helper native audio checks passed.');
  } finally {
    await preparer.close();
    for (final result in results) {
      await result.close();
    }
    await root.delete(recursive: true); // Exclusively our synthetic test data.
  }
}
