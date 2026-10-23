import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/models/audio_source_reference.dart';
import '../library/library_scan_control.dart';
import '../library_sync/downloaded_audio_metadata.dart';
import '../library_sync/downloaded_audio_metadata_preparer.dart';
import '../library_sync/downloaded_audio_validation.dart';
import 'android_audio_metadata_backend.dart';

/// Runs the real preparer on generated, shipped fixtures. Nothing is imported
/// or published; exclusively known files are removed after all native IO drains.
final class AndroidMediaQualification {
  AndroidMediaQualification(
      {AndroidMediaProcessingBackend Function()? backend,
      Future<Directory> Function()? privateDirectory,
      Future<Uint8List> Function(String)? asset})
      : _backend = backend ?? AndroidAudioMetadataBackend.new,
        _directory = privateDirectory ?? getApplicationSupportDirectory,
        _asset = asset ??
            ((name) async {
              final data = await rootBundle.load(name);
              return data.buffer
                  .asUint8List(data.offsetInBytes, data.lengthInBytes);
            });
  final AndroidMediaProcessingBackend Function() _backend;
  final Future<Directory> Function() _directory;
  final Future<Uint8List> Function(String) _asset;

  Future<String> check(LibraryScanControl control,
      {void Function(int)? onCase}) async {
    control.throwIfCancelled();
    final backend = _backend();
    Directory? directory;
    DownloadedAudioMetadataPreparer? preparer;
    final sources = <File>[];
    try {
      final version = await backend.capabilities(control);
      control.throwIfCancelled();
      final parent =
          Directory(await (await _directory()).resolveSymbolicLinks());
      directory = await parent.createTemp('cmp_media_check_');
      preparer = DownloadedAudioMetadataPreparer(
          backend: backend,
          temporaryParent: directory,
          timeout: const Duration(minutes: 2));
      final png = await _asset('assets/media_check/cover.png');
      final jpeg = await _asset('assets/media_check/cover.jpg');
      var index = 0;
      for (final format in DownloadedAudioContainer.values) {
        control.throwIfCancelled();
        final source =
            File(p.join(directory.path, 'исходник-${format.name}-😀.part'));
        sources.add(source);
        await source.create(exclusive: true);
        final bytes = await _asset('assets/media_check/tone.${format.name}');
        if (bytes.isEmpty || bytes.length > 65536) {
          throw const AudioValidationException(
              AudioValidationOutcome.invalidAudio);
        }
        await source.writeAsBytes(bytes, flush: true);
        for (final cover in [
          EmbeddedCover(png, EmbeddedCoverFormat.png),
          EmbeddedCover(jpeg, EmbeddedCoverFormat.jpeg),
        ]) {
          control.throwIfCancelled();
          onCase?.call(index++);
          final ready = await preparer.prepare(
              FileAudioSource(source.path),
              DownloadedAudioExpectation(
                  quality: 'qualification',
                  container: format,
                  codec: switch (format) {
                    DownloadedAudioContainer.mp3 => DownloadedAudioCodec.mp3,
                    DownloadedAudioContainer.m4a => DownloadedAudioCodec.aac,
                    DownloadedAudioContainer.flac => DownloadedAudioCodec.flac,
                  },
                  fileSizeBytes: bytes.length,
                  duration: const Duration(milliseconds: 600),
                  minimumBitRate:
                      format == DownloadedAudioContainer.flac ? null : 32000,
                  minimumBitDepth:
                      format == DownloadedAudioContainer.flac ? 16 : null,
                  requireCover: true,
                  tags: const {
                    'title': 'Проверка 😀',
                    'artist': 'Исполнитель трека',
                    'album': 'Медиапроверка',
                    'album_artist': 'Исполнитель альбома',
                    'genre': 'Electronic',
                    'track': '2',
                    'disc': '1',
                    'date': '2026',
                  }),
              cover: cover,
              control: control);
          await ready.close();
        }
      }
      control.throwIfCancelled();
      return version;
    } finally {
      // Native streams/process ownership must end before removing known files.
      if (preparer != null) {
        await preparer.close();
      } else {
        await backend.close();
      }
      for (final source in sources) {
        if (await source.exists()) await source.delete();
      }
      if (directory != null) await directory.delete();
    }
  }
}
