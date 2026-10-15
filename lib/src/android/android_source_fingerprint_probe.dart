import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/models/audio_source_reference.dart';
import '../library/library_scan_control.dart';
import '../library_sync/source_fingerprint_probe.dart';

/// SAF reads stay in the provider: no temporary copy or main-thread hashing.
final class AndroidSourceFingerprintProbe implements SourceFingerprintProbe {
  AndroidSourceFingerprintProbe({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
                'dev.lunatuk.clever_music_player/audio_fingerprint');
  final MethodChannel _channel;
  int _requestId = 0;
  bool _closed = false;
  Completer<void>? _active;
  LibraryScanControl? _control;
  Future<void>? _closing;

  @override
  Future<SourceFingerprintResult> fingerprint(AudioSourceReference source,
      {required int expectedSize, required LibraryScanControl control}) async {
    if (_closed) throw StateError('Проверка документов закрыта.');
    if (_active != null) throw StateError('Документ уже проверяется.');
    if (expectedSize <= 0) throw ArgumentError.value(expectedSize);
    if (control.isCancellationRequested) {
      return SourceFingerprintResult.failure(SourceFingerprintStatus.cancelled);
    }
    if (source is! ContentUriAudioSource) {
      return SourceFingerprintResult.failure(
          SourceFingerprintStatus.unreadable);
    }
    final done = Completer<void>();
    _active = done;
    _control = control;
    _requestId = _requestId == 0x7fffffff ? 1 : _requestId + 1;
    final id = _requestId;
    // Send the read first so a cancellation cannot arrive before admission.
    final read = _channel.invokeMapMethod<String, dynamic>('fingerprintAudio', {
      'requestId': id,
      'uri': source.storageValue,
      'expectedSize': expectedSize
    });
    void cancel() {
      _channel.invokeMethod<void>('cancelAudioFingerprint',
          {'requestId': id}).catchError((Object _) {});
    }

    control.addCancellationListener(cancel);
    try {
      final result = await read;
      if (control.isCancellationRequested) {
        return SourceFingerprintResult.failure(
            SourceFingerprintStatus.cancelled);
      }
      if (result == null ||
          result['requestId'] is! int ||
          result['requestId'] != id) {
        throw const FormatException('Ответ проверки не соответствует запросу.');
      }
      final status = SourceFingerprintStatus.values.firstWhere(
          (value) => value.name == result['status'],
          orElse: () =>
              throw const FormatException('Неизвестный ответ проверки.'));
      if (status == SourceFingerprintStatus.fingerprinted) {
        final size = result['sizeBytes'];
        final digest = result['digest'];
        if (size is! int || digest is! String || size != expectedSize) {
          throw const FormatException('Некорректный результат проверки.');
        }
        return SourceFingerprintResult.fingerprinted(size, digest);
      }
      return SourceFingerprintResult.failure(status);
    } finally {
      control.removeCancellationListener(cancel);
      _control = null;
      _active = null;
      done.complete();
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _drain(_active?.future);
  }

  Future<void> _drain(Future<void>? active) async => await active;
}
