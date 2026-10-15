import 'dart:async';

import '../domain/models/downloaded_asset.dart';
import '../domain/repositories/downloaded_asset_repository.dart';
import '../library/library_scan_control.dart';
import 'source_fingerprint_probe.dart';

enum AssetCheckOutcome {
  confirmed,
  changed,
  missing,
  accessDenied,
  unreadable,
  cancelled,
  stale,
}

/// Confirms previously verified audio properties only when ALL bytes match.
/// Admission is bounded to one read; closing drains any accepted database CAS.
final class DownloadedAssetChecker {
  DownloadedAssetChecker(
      {required DownloadedAssetRepository repository,
      required SourceFingerprintProbe probe,
      DateTime Function()? clock,
      Duration timeout = const Duration(minutes: 5)})
      : _repository = repository,
        _probe = probe,
        _clock = clock ?? DateTime.now,
        _timeout = timeout {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 30)) {
      throw ArgumentError.value(timeout);
    }
  }
  final DownloadedAssetRepository _repository;
  final SourceFingerprintProbe _probe;
  final DateTime Function() _clock;
  final Duration _timeout;
  bool _closed = false;
  LibraryScanControl? _activeControl;
  Completer<void>? _activeDone;
  Future<void>? _closing;

  Future<AssetCheckOutcome> check(DownloadedAsset expected,
      {LibraryScanControl? control}) async {
    if (_closed) throw StateError('Проверка файлов закрыта.');
    if (_activeDone != null) throw StateError('Файл уже проверяется.');
    final done = Completer<void>();
    _activeDone = done;
    final operation = LibraryScanControl();
    _activeControl = operation;
    void cancel() => operation.cancel();
    control?.addCancellationListener(cancel);
    var timedOut = false;
    final timer = Timer(_timeout, () {
      timedOut = true;
      operation.cancel();
    });
    try {
      if (operation.isCancellationRequested) return AssetCheckOutcome.cancelled;
      final SourceFingerprintResult result;
      try {
        result = await _probe.fingerprint(expected.publication.source,
            expectedSize: expected.verification.fileSizeBytes,
            control: operation);
      } on Object {
        // Unsupported providers, native protocol failures and transient IO are
        // not evidence that the registered bytes are missing or corrupt.
        return operation.isCancellationRequested && !timedOut
            ? AssetCheckOutcome.cancelled
            : AssetCheckOutcome.unreadable;
      }
      if (operation.isCancellationRequested) {
        return timedOut
            ? AssetCheckOutcome.unreadable
            : AssetCheckOutcome.cancelled;
      }
      final AssetCheckOutcome outcome;
      final DownloadedAssetState? state;
      switch (result.status) {
        case SourceFingerprintStatus.fingerprinted:
          final same =
              result.sizeBytes == expected.verification.fileSizeBytes &&
                  result.digest == expected.verification.contentHash;
          outcome =
              same ? AssetCheckOutcome.confirmed : AssetCheckOutcome.changed;
          state = same ? null : DownloadedAssetState.invalid;
        case SourceFingerprintStatus.changed:
          outcome = AssetCheckOutcome.changed;
          state = DownloadedAssetState.invalid;
        case SourceFingerprintStatus.missing:
          outcome = AssetCheckOutcome.missing;
          state = DownloadedAssetState.missing;
        case SourceFingerprintStatus.accessDenied:
          outcome = AssetCheckOutcome.accessDenied;
          state = DownloadedAssetState.accessDenied;
        case SourceFingerprintStatus.unreadable:
          return AssetCheckOutcome.unreadable;
        case SourceFingerprintStatus.cancelled:
          return AssetCheckOutcome.cancelled;
      }
      // After accepting the CAS, cancellation must drain it and report the
      // committed outcome, not pretend that a completed write was cancelled.
      timer.cancel();
      final bool applied;
      if (state != null) {
        applied = await _repository.invalidate(expected, state);
      } else {
        final old = expected.verification;
        applied = await _repository.confirm(
            expected,
            DownloadedAssetVerification(
                actualQuality: old.actualQuality,
                container: old.container,
                codec: old.codec,
                fileSizeBytes: old.fileSizeBytes,
                duration: old.duration,
                contentHash: old.contentHash,
                checkedAt: _clock()));
      }
      return applied ? outcome : AssetCheckOutcome.stale;
    } finally {
      timer.cancel();
      control?.removeCancellationListener(cancel);
      _activeControl = null;
      _activeDone = null;
      done.complete();
    }
  }

  Future<void> close() {
    _closed = true;
    _activeControl?.cancel();
    return _closing ??= _close(_activeDone?.future);
  }

  Future<void> _close(Future<void>? active) async {
    await active;
    await _probe.close();
  }
}
