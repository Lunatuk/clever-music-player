import 'dart:async';
import 'dart:io';

import '../domain/models/audio_source_reference.dart';
import '../domain/models/track.dart';
import '../library_sync/bundled_media_helper.dart';
import '../library_sync/downloaded_audio_metadata.dart';
import '../library_sync/downloaded_audio_validation.dart';
import '../library_sync/ffmpeg_audio_metadata_backend.dart';
import 'library_scan_control.dart';

const audioComparisonMaxBytes = 128 * 1024 * 1024;
const audioComparisonMaxDuration = Duration(minutes: 30);

typedef AudioPcmSignature = ({String digest, int sampleRate, int channels});

enum AudioComparisonResult { equal, different, unreadable, cancelled, timedOut }

abstract interface class AudioComparisonReader {
  Future<AudioPcmSignature> read(
      AudioSourceReference source, LibraryScanControl control);
  Future<void> close();
}

final class AudioComparisonService {
  const AudioComparisonService(this._open,
      {this.timeout = const Duration(seconds: 45)});

  final Future<AudioComparisonReader> Function(LibraryScanControl) _open;
  final Duration timeout;

  Future<AudioComparisonResult> compare(Track first, Track second,
      {required LibraryScanControl control}) async {
    final operation = LibraryScanControl();
    control.addCancellationListener(operation.cancel);
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      operation.cancel();
    });
    AudioComparisonReader? reader;
    try {
      operation.throwIfCancelled();
      if (first.isMissing ||
          second.isMissing ||
          first.filePath == second.filePath) {
        return AudioComparisonResult.unreadable;
      }
      reader = await _open(operation);
      operation.throwIfCancelled();
      final left = await reader.read(first.source, operation);
      operation.throwIfCancelled();
      final right = await reader.read(second.source, operation);
      operation.throwIfCancelled();
      return left == right
          ? AudioComparisonResult.equal
          : AudioComparisonResult.different;
    } on Object {
      if (control.isCancellationRequested) {
        return AudioComparisonResult.cancelled;
      }
      if (timedOut) return AudioComparisonResult.timedOut;
      return AudioComparisonResult.unreadable;
    } finally {
      timer.cancel();
      control.removeCancellationListener(operation.cancel);
      await reader?.close();
    }
  }
}

Future<AudioComparisonReader> openDesktopAudioComparison(
    LibraryScanControl control) async {
  final helper = BundledMediaHelper.forCurrentProcess();
  try {
    final qualified = await helper.qualify(control: control);
    return DesktopAudioComparisonReader(qualified.createMetadataBackend());
  } finally {
    await helper.close();
  }
}

final class DesktopAudioComparisonReader implements AudioComparisonReader {
  const DesktopAudioComparisonReader(this._backend);
  final FfmpegAudioMetadataBackend _backend;

  @override
  Future<AudioPcmSignature> read(
      AudioSourceReference source, LibraryScanControl control) async {
    if (source is! FileAudioSource) throw _invalidAudio;
    final file = File(source.path);
    final before = await file.stat();
    control.throwIfCancelled();
    if (before.type != FileSystemEntityType.file ||
        before.size <= 0 ||
        before.size > audioComparisonMaxBytes) {
      throw _invalidAudio;
    }
    final info = await _backend.inspectForComparison(file, control);
    final layout = info.channelLayout;
    if (info.sizeBytes != before.size ||
        info.duration > audioComparisonMaxDuration ||
        info.sampleRate > 192000 ||
        info.channels < 1 ||
        info.channels > 2 ||
        (layout != null &&
            layout != 'unknown' &&
            layout != (info.channels == 1 ? 'mono' : 'stereo'))) {
      throw _invalidAudio;
    }
    final digest =
        await _backend.digest(file, info, AudioCopyDigest.decodedPcm, control);
    final after = await file.stat();
    control.throwIfCancelled();
    if (after.type != before.type ||
        after.size != before.size ||
        after.modified != before.modified ||
        after.changed != before.changed) {
      throw _invalidAudio;
    }
    return (
      digest: digest,
      sampleRate: info.sampleRate,
      channels: info.channels
    );
  }

  @override
  Future<void> close() => _backend.close();
}

const _invalidAudio =
    AudioValidationException(AudioValidationOutcome.invalidAudio);
