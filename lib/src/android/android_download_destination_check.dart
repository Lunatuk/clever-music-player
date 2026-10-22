import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/models/audio_source_reference.dart';
import '../library/library_scan_control.dart';

enum DownloadDestinationStatus {
  ready,
  cancelled,
  accessDenied,
  unsupported,
  busy,
  retained,
  io,
}

final class DownloadDestinationResult {
  const DownloadDestinationResult(this.status,
      {this.stage = 0,
      this.verifiedBytes = 0,
      this.recovered = 0,
      this.retained = 0});
  final DownloadDestinationStatus status;
  final int stage, verifiedBytes, recovered, retained;
}

abstract interface class DownloadDestinationChecker {
  Future<DownloadDestinationResult> check(
      ContentUriAudioSource tree, LibraryScanControl control);
  Future<void> close();
}

/// Completion includes closing streams and attempted cleanup, even on cancel.
final class AndroidDownloadDestinationCheck
    implements DownloadDestinationChecker {
  AndroidDownloadDestinationCheck({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
                'dev.lunatuk.clever_music_player/download_publication'),
        _checkMethod = 'checkDownloadDestination',
        _treeArgument = 'uri',
        _cancelMethod = 'cancelDownloadDestinationCheck';
  AndroidDownloadDestinationCheck.audioPublication({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
                'dev.lunatuk.clever_music_player/audio_publication'),
        _checkMethod = 'checkAudioPublication',
        _treeArgument = 'tree',
        _cancelMethod = 'cancelAudioPublicationCheck';
  final MethodChannel _channel;
  final String _checkMethod, _cancelMethod, _treeArgument;
  int _sequence = 0;
  bool _closed = false;
  Completer<void>? _active;
  LibraryScanControl? _control;
  Future<void>? _closing;

  @override
  Future<DownloadDestinationResult> check(
      ContentUriAudioSource tree, LibraryScanControl control) async {
    if (_closed || _active != null) throw StateError('Проверка недоступна.');
    if (control.isCancellationRequested) {
      return const DownloadDestinationResult(
          DownloadDestinationStatus.cancelled);
    }
    final done = _active = Completer<void>();
    _control = control;
    final id = _sequence = _sequence == 0x7fffffff ? 1 : _sequence + 1;
    final response = _channel.invokeMapMethod<String, dynamic>(
        _checkMethod, {'requestId': id, _treeArgument: tree.storageValue});
    void cancel() {
      _channel.invokeMethod<void>(
          _cancelMethod, {'requestId': id}).catchError((Object _) {});
    }

    control.addCancellationListener(cancel);
    try {
      final result = await response;
      if (result == null ||
          result['requestId'] is! int ||
          result['requestId'] != id) {
        throw const FormatException('Некорректный ответ проверки папки.');
      }
      final status = DownloadDestinationStatus.values.firstWhere(
          (value) => value.name == result['status'],
          orElse: () => throw const FormatException('Неизвестный результат.'));
      int field(String key, int max) {
        final value = result[key];
        if (value is! int || value < 0 || value > max) {
          throw const FormatException('Некорректный результат проверки.');
        }
        return value;
      }

      final stage = field('stage', 6);
      final bytes = field('verifiedBytes', 4096);
      final recovered = field('recovered', 64);
      final retained = field('retained', 64);
      if ((bytes != 0 && bytes != 4096) ||
          (status == DownloadDestinationStatus.ready &&
              (stage != 6 || bytes != 4096 || retained != 0)) ||
          (status == DownloadDestinationStatus.retained && retained == 0)) {
        throw const FormatException('Противоречивый результат проверки.');
      }
      // A late cancellation must not hide retained files or provider errors.
      return DownloadDestinationResult(
          status == DownloadDestinationStatus.ready &&
                  control.isCancellationRequested
              ? DownloadDestinationStatus.cancelled
              : status,
          stage: stage,
          verifiedBytes: bytes,
          recovered: recovered,
          retained: retained);
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
