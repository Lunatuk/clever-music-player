import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../library/library_scan_control.dart';
import '../library_sync/download_workspace.dart';
import '../library_sync/downloaded_audio_metadata.dart';
import '../library_sync/downloaded_audio_validation.dart';

/// In-process FFmpeg library, called on a native worker. Only completed private
/// staging files; no shell, executable, content URI or playback dependency.
abstract interface class AndroidMediaProcessingBackend
    implements AudioMetadataBackend {
  Future<String> capabilities(LibraryScanControl control);
}

final class AndroidAudioMetadataBackend
    implements AndroidMediaProcessingBackend {
  AndroidAudioMetadataBackend({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
                'dev.lunatuk.clever_music_player/media_backend');
  final MethodChannel _channel;
  static int _sequence = 0;
  bool _closed = false;
  Completer<void>? _active;
  LibraryScanControl? _control;
  Future<void>? _closing;

  Future<Map<String, dynamic>> _run(int op, LibraryScanControl control,
      [Map<String, Object> arguments = const {}]) async {
    if (_closed || _active != null) {
      throw StateError('Медиаподготовка недоступна.');
    }
    control.throwIfCancelled();
    final done = _active = Completer<void>();
    _control = control;
    final id = _sequence = _sequence == 0x7fffffff ? 1 : _sequence + 1;
    final call = _channel.invokeMapMethod<String, dynamic>(
        'runMediaOperation', {'requestId': id, 'op': op, ...arguments});
    void cancel() {
      _channel.invokeMethod<void>(
          'cancelMediaOperation', {'requestId': id}).catchError((Object _) {});
    }

    control.addCancellationListener(cancel);
    try {
      final result = await call;
      if (result == null ||
          result['requestId'] is! int ||
          result['requestId'] != id ||
          result['status'] is! String) {
        throw const AudioValidationException(AudioValidationOutcome.unreadable);
      }
      control.throwIfCancelled();
      if (result['status'] == 'quotaExceeded') {
        throw const DownloadWorkspaceException(
            DownloadWorkspaceFailure.quotaExceeded);
      }
      if (result['status'] != 'ok') {
        final failure = switch (result['status']) {
          'cancelled' => AudioValidationOutcome.cancelled,
          'timedOut' => AudioValidationOutcome.timedOut,
          'invalidAudio' => AudioValidationOutcome.invalidAudio,
          'invalidCover' => AudioValidationOutcome.invalidCover,
          'coverMissing' => AudioValidationOutcome.coverMissing,
          'backendUnavailable' ||
          'busy' =>
            AudioValidationOutcome.backendUnavailable,
          _ => AudioValidationOutcome.unreadable,
        };
        throw AudioValidationException(failure);
      }
      return result;
    } on MissingPluginException {
      throw const AudioValidationException(
          AudioValidationOutcome.backendUnavailable);
    } on PlatformException {
      throw const AudioValidationException(AudioValidationOutcome.unreadable);
    } finally {
      control.removeCancellationListener(cancel);
      _active = null;
      _control = null;
      done.complete();
    }
  }

  @override
  Future<String> capabilities(LibraryScanControl control) async {
    final result = await _run(0, control);
    if (result['profile'] != 'cmp-android-audio-1' ||
        result['version'] != '7.1.5' ||
        result['license'] != 'LGPL version 2.1 or later') {
      throw const AudioValidationException(
          AudioValidationOutcome.backendUnavailable);
    }
    return result['version'] as String;
  }

  @override
  Future<DownloadedAudioInspection> inspect(
      File file, LibraryScanControl control) async {
    final result = await _run(1, control, {'source': file.absolute.path});
    try {
      final raw = Map<String, dynamic>.from(result['inspection'] as Map);
      final tags = Map<String, String>.from(raw['tags'] as Map);
      return DownloadedAudioInspection(
          container: DownloadedAudioContainer.values.byName(raw['container']),
          codec: DownloadedAudioCodec.values.byName(raw['codec']),
          duration: Duration(microseconds: raw['durationUs'] as int),
          sizeBytes: raw['sizeBytes'] as int,
          audioStreamIndex: raw['audioStreamIndex'] as int,
          sampleRate: raw['sampleRate'] as int,
          channels: raw['channels'] as int,
          bitRate: raw['bitRate'] as int?,
          bitDepth: raw['bitDepth'] as int?,
          coverStreamIndex: raw['coverStreamIndex'] as int?,
          tags: tags);
    } on Object {
      throw const AudioValidationException(AudioValidationOutcome.invalidAudio);
    }
  }

  @override
  Future<Duration> decodeAudio(File file, DownloadedAudioInspection inspection,
      LibraryScanControl control) async {
    final result = await _run(2, control, {'source': file.absolute.path});
    final micros = result['durationUs'];
    if (micros is! int ||
        micros <= 0 ||
        micros > const Duration(hours: 12).inMicroseconds) {
      throw const AudioValidationException(AudioValidationOutcome.invalidAudio);
    }
    return Duration(microseconds: micros);
  }

  @override
  Future<void> decodeCover(File file, DownloadedAudioInspection inspection,
          LibraryScanControl control) async =>
      await _run(3, control, {'source': file.absolute.path});

  @override
  Future<String> digest(File file, DownloadedAudioInspection info,
      AudioCopyDigest mode, LibraryScanControl control) async {
    final result = await _run(
        4, control, {'source': file.absolute.path, 'mode': mode.index});
    final hash = result['digest'];
    if (hash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        hash ==
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') {
      throw const AudioValidationException(AudioValidationOutcome.invalidAudio);
    }
    return hash;
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
    if (source.absolute.path == output.absolute.path ||
        (cover == null) != (coverFormat == null) ||
        (maxOutputBytes != null &&
            (maxOutputBytes <= 0 || maxOutputBytes > 8589934592))) {
      throw ArgumentError('Некорректное назначение метаданных.');
    }
    await _run(5, control, {
      'source': source.absolute.path,
      'output': output.absolute.path,
      'tags': expected.tags,
      if (cover != null) 'cover': cover.absolute.path,
      'coverFormat': coverFormat == null
          ? 0
          : coverFormat == EmbeddedCoverFormat.png
              ? 1
              : 2,
      'maxOutputBytes': maxOutputBytes ?? 8589934592,
    });
  }

  @override
  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _drain(_active?.future);
  }

  Future<void> _drain(Future<void>? active) async => await active;
}
