import 'dart:io';
import 'dart:typed_data';

import '../domain/models/downloaded_asset.dart';
import '../library/library_scan_control.dart';
import 'downloaded_audio_validation.dart';
import 'downloaded_audio_validator.dart';
import 'download_workspace.dart';

enum EmbeddedCoverFormat { png, jpeg }

/// Snapshot of provider artwork. No remote URL or caller-controlled filename.
final class EmbeddedCover {
  factory EmbeddedCover(List<int> bytes, EmbeddedCoverFormat format) {
    if (bytes.isEmpty ||
        bytes.length > 8 * 1024 * 1024 ||
        bytes.any((byte) => byte < 0 || byte > 255) ||
        !_headerMatches(bytes, format)) {
      throw ArgumentError('Некорректная обложка.');
    }
    return EmbeddedCover._(
        Uint8List.fromList(bytes).asUnmodifiableView(), format);
  }
  EmbeddedCover._(this.bytes, this.format);
  final Uint8List bytes;
  final EmbeddedCoverFormat format;

  static bool _headerMatches(List<int> bytes, EmbeddedCoverFormat format) {
    final signature = format == EmbeddedCoverFormat.png
        ? const [137, 80, 78, 71, 13, 10, 26, 10]
        : const [255, 216, 255];
    return bytes.length >= signature.length &&
        List.generate(signature.length, (i) => bytes[i] == signature[i])
            .every((value) => value);
  }
}

enum AudioCopyDigest { packets, decodedPcm, cover }

abstract interface class AudioMetadataBackend
    implements AudioValidationBackend {
  Future<String> digest(File file, DownloadedAudioInspection info,
      AudioCopyDigest mode, LibraryScanControl control);

  /// Output is a newly reserved file owned by the preparer, never the source.
  Future<void> writeMetadata(
      File source,
      File output,
      DownloadedAudioInspection info,
      DownloadedAudioExpectation expected,
      LibraryScanControl control,
      {File? cover,
      EmbeddedCoverFormat? coverFormat,
      int? maxOutputBytes});
}

/// A validated private temporary file. The caller closes it after all reads /
/// publication finish. Closing the preparer does not delete delivered results.
final class PreparedDownloadedAudio {
  PreparedDownloadedAudio._(
      this.file, this.verification, this.inspection, this._temporary);
  final File file;
  final DownloadedAssetVerification verification;
  final DownloadedAudioInspection inspection;
  final AudioPreparationTemporary _temporary;
  Future<void> close() => _temporary.close();

  static PreparedDownloadedAudio fromValidation(
      AudioPreparationTemporary temporary, AudioValidationResult result) {
    if (result.verification == null || result.inspection == null) {
      throw StateError('Подготовленный файл не проверен.');
    }
    return PreparedDownloadedAudio._(
        temporary.audio, result.verification!, result.inspection!, temporary);
  }
}

/// Only removes its two known generated files and the empty owned directory.
/// No recursive deletion, scanning or cleanup of other temporary directories.
final class AudioPreparationTemporary {
  AudioPreparationTemporary._(this.directory, [this._managed]);
  final Directory directory;
  final DownloadWorkspaceReservation? _managed;
  File get audio =>
      File('${directory.path}${Platform.pathSeparator}audio.part');
  File get cover =>
      File('${directory.path}${Platform.pathSeparator}cover.part');
  Future<void>? _closing;

  static Future<AudioPreparationTemporary> create(Directory parent,
      {DownloadWorkspace? workspace,
      int? maxAudioBytes,
      int maxCoverBytes = 0}) async {
    if (workspace == null) {
      return AudioPreparationTemporary._(
          await parent.absolute.createTemp('cmp_audio_metadata_'));
    }
    final managed = workspace.reserve(DownloadWorkspaceStage.prepared,
        maxAudioBytes: maxAudioBytes!, maxCoverBytes: maxCoverBytes);
    try {
      return AudioPreparationTemporary._(await managed.materialize(), managed);
    } on Object {
      await managed.close();
      rethrow;
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    try {
      if (_managed != null) {
        await _managed.close();
        return;
      }
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const AudioValidationException(AudioValidationOutcome.unreadable);
      }
      for (final file in [audio, cover]) {
        final type = await FileSystemEntity.type(file.path, followLinks: false);
        if (type == FileSystemEntityType.file ||
            type == FileSystemEntityType.link) {
          await file.delete();
        } else if (type != FileSystemEntityType.notFound) {
          throw const AudioValidationException(
              AudioValidationOutcome.unreadable);
        }
      }
      await directory.delete();
    } on FileSystemException {
      _closing = null;
      throw const AudioValidationException(AudioValidationOutcome.unreadable);
    } on Object {
      _closing = null;
      rethrow;
    }
  }
}
