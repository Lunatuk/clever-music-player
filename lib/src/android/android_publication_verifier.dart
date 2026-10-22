import 'dart:async';

import 'package:flutter/services.dart';

import '../library/library_scan_control.dart';
import '../library_sync/source_fingerprint_probe.dart';
import 'android_publication_receipt.dart';

abstract interface class PublicationDocumentVerifier {
  Future<SourceFingerprintResult> verify(
      AndroidPublicationReceipt receipt, LibraryScanControl control);
  Future<void> close();
}

/// Read-only: checks the provider's direct parent/name before and after hashing.
final class AndroidPublicationVerifier implements PublicationDocumentVerifier {
  AndroidPublicationVerifier({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
                'dev.lunatuk.clever_music_player/publication_verifier');
  final MethodChannel _channel;
  int _sequence = 0;
  bool _closed = false;
  Completer<void>? _active;
  LibraryScanControl? _control;
  Future<void>? _closing;
  @override
  Future<SourceFingerprintResult> verify(
      AndroidPublicationReceipt receipt, LibraryScanControl control) async {
    if (_closed || _active != null) throw StateError('Проверка недоступна.');
    if (control.isCancellationRequested) {
      return SourceFingerprintResult.failure(SourceFingerprintStatus.cancelled);
    }
    final done = _active = Completer<void>();
    _control = control;
    final id = _sequence = _sequence == 0x7fffffff ? 1 : _sequence + 1;
    final expected = receipt.intent.verification;
    final read =
        _channel.invokeMapMethod<String, dynamic>('verifyPublishedAudio', {
      'requestId': id,
      'tree': receipt.location.tree.storageValue,
      'document': receipt.location.document.storageValue,
      'displayName': receipt.location.displayName,
      'expectedSize': expected.fileSizeBytes,
      'digest': expected.contentHash,
    });
    void cancel() {
      _channel.invokeMethod<void>('cancelPublishedAudioVerification',
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
        throw const FormatException('Некорректный ответ проверки публикации.');
      }
      final status = SourceFingerprintStatus.values.firstWhere(
          (s) => s.name == result['status'],
          orElse: () =>
              throw const FormatException('Неизвестный результат проверки.'));
      if (status != SourceFingerprintStatus.fingerprinted) {
        return SourceFingerprintResult.failure(status);
      }
      if (result['sizeBytes'] is! int ||
          result['sizeBytes'] != expected.fileSizeBytes ||
          result['digest'] != expected.contentHash) {
        throw const FormatException(
            'Проверка не соответствует ожидаемым байтам.');
      }
      return SourceFingerprintResult.fingerprinted(
          expected.fileSizeBytes, expected.contentHash);
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
