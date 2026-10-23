import 'dart:async';

import 'package:flutter/foundation.dart';

import '../diagnostics/diagnostics_service.dart';
import '../library/library_scan_control.dart';
import '../library_sync/downloaded_audio_validation.dart';
import 'android_media_qualification.dart';

final class AndroidMediaCheckController extends ChangeNotifier {
  AndroidMediaCheckController(
      {required DiagnosticsService diagnostics,
      Future<String> Function(LibraryScanControl, void Function(int))? check})
      : _diagnostics = diagnostics,
        _check = check ??
            ((control, onCase) =>
                AndroidMediaQualification().check(control, onCase: onCase));
  final DiagnosticsService _diagnostics;
  final Future<String> Function(LibraryScanControl, void Function(int)) _check;
  bool _closed = false;
  LibraryScanControl? _control;
  Completer<void>? _active;
  Future<void>? _closing;
  String? message;
  bool get busy => _active != null;

  Future<void> check() async {
    if (_closed || busy) return;
    final control = _control = LibraryScanControl();
    final done = _active = Completer<void>();
    final watch = Stopwatch()..start();
    var caseIndex = -1;
    message = 'Проверяются MP3, M4A и FLAC…';
    notifyListeners();
    _diagnostics.record(DiagnosticEvent.androidMediaCheckStarted);
    try {
      await _check(control, (value) => caseIndex = value);
      control.throwIfCancelled();
      message = 'Медиаподготовка проверена: MP3, M4A, FLAC, теги и обложки. '
          'Звук сохранён без перекодирования. Тестовые файлы удалены.';
      _diagnostics.record(DiagnosticEvent.androidMediaCheckFinished,
          fields: {DiagnosticField.elapsedMs: watch.elapsedMilliseconds});
    } on Object catch (error) {
      final outcome =
          control.isCancellationRequested || error is LibraryScanCancelled
              ? AudioValidationOutcome.cancelled
              : error is AudioValidationException
                  ? error.outcome
                  : AudioValidationOutcome.unreadable;
      message = outcome == AudioValidationOutcome.cancelled
          ? 'Проверка остановлена.'
          : 'Не удалось проверить медиаподготовку. Создай диагностический '
              'отчёт в настройках и передай его для проверки.';
      _diagnostics.record(DiagnosticEvent.androidMediaCheckFailed, fields: {
        DiagnosticField.mediaCheckCase: caseIndex,
        DiagnosticField.mediaCheckOutcome: outcome.index,
        DiagnosticField.elapsedMs: watch.elapsedMilliseconds,
      });
    } finally {
      _control = null;
      _active = null;
      done.complete();
      if (!_closed) notifyListeners();
    }
  }

  void cancel() => _control?.cancel();
  Future<void> close() {
    _closed = true;
    cancel();
    return _closing ??= _drain(_active?.future);
  }

  Future<void> _drain(Future<void>? active) async => await active;
}
