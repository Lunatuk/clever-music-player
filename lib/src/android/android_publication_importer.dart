import 'dart:async';

import '../domain/models/models.dart';
import '../domain/repositories/download_import_repository.dart';
import '../domain/repositories/publication_retention_repository.dart';
import '../library/library_scan_control.dart';
import '../library_sync/download_lease_owner.dart';
import '../library_sync/source_fingerprint_probe.dart';
import 'android_publication_journal.dart';
import 'android_publication_receipt.dart';
import 'android_publication_verifier.dart';

final class AndroidPublicationVerificationException implements Exception {
  const AndroidPublicationVerificationException(this.status);
  final SourceFingerprintStatus status;
}

final class AndroidPublicationImportResult {
  const AndroidPublicationImportResult(this.imported,
      {required this.cleanupFailed});
  final DownloadImportResult imported;
  final bool cleanupFailed;
}

/// Imports an already prepared/published document. It does not create files,
/// prepare tags or start downloads. Caller owns journal, lease and repositories.
final class AndroidPublicationImporter {
  AndroidPublicationImporter(
      {required this.journal,
      required this.imports,
      required this.retention,
      PublicationDocumentVerifier? verifier,
      DateTime Function()? clock})
      : _verifier = verifier ?? AndroidPublicationVerifier(),
        _clock = clock ?? DateTime.now;
  final AndroidPublicationJournal journal;
  final DownloadImportRepository imports;
  final PublicationRetentionRepository retention;
  final PublicationDocumentVerifier _verifier;
  final DateTime Function() _clock;
  bool _closed = false;
  Completer<void>? _active;
  LibraryScanControl? _control;
  Future<void>? _closing;

  Future<AndroidPublicationImportResult> importReceipt({
    required DownloadLeaseOwner owner,
    required AndroidPublicationReceipt receipt,
    required Track preparedTrack,
    LibraryScanControl? control,
  }) async {
    if (_closed || _active != null) throw StateError('Импорт недоступен.');
    final job = owner.current;
    if (job.stage != DownloadJobStage.importing ||
        !job.isExecuting ||
        job.id != receipt.intent.jobId ||
        job.key != receipt.intent.key) {
      throw ArgumentError('Другой контекст публикации.');
    }
    // Validate metadata and the exact URI before admitting any IO.
    receipt.importTrack(preparedTrack, receipt.intent.verification);
    final done = _active = Completer<void>();
    final operation = _control = LibraryScanControl();
    void cancel() => operation.cancel();
    control?.addCancellationListener(cancel);
    owner.lossControl.addCancellationListener(cancel);
    try {
      operation.throwIfCancelled();
      await journal.record(receipt,
          job: job, jobs: owner, clock: _clock, control: operation);
      operation.throwIfCancelled();
      // No SQLite reservation/owner serial gate during provider IO. Heartbeat
      // can renew this same attempt while the full readback is in progress.
      final bytes = await _verifier.verify(receipt, operation);
      operation.throwIfCancelled();
      if (bytes.status == SourceFingerprintStatus.cancelled) {
        throw const LibraryScanCancelled();
      }
      if (bytes.status != SourceFingerprintStatus.fingerprinted) {
        throw AndroidPublicationVerificationException(bytes.status);
      }
      final old = receipt.intent.verification;
      if (bytes.sizeBytes != old.fileSizeBytes ||
          bytes.digest != old.contentHash) {
        throw const AndroidPublicationVerificationException(
            SourceFingerprintStatus.changed);
      }
      final checked = DownloadedAssetVerification(
          actualQuality: old.actualQuality,
          container: old.container,
          codec: old.codec,
          fileSizeBytes: old.fileSizeBytes,
          duration: old.duration,
          contentHash: old.contentHash,
          checkedAt: _clock());
      if (checked.checkedAt.isBefore(old.checkedAt)) {
        throw StateError('Время проверки изменилось.');
      }
      final command = receipt.importTrack(preparedTrack, checked);
      operation.throwIfCancelled();
      final imported =
          await owner.finish<DownloadImportResult>((current) async {
        operation.throwIfCancelled();
        final result = await imports.commit(current, command, clock: _clock);
        return result == null ? null : (result, result.job);
      });
      // Accepted DB completion wins over a late cancellation. Cleanup failures
      // leave a replayable receipt, never convert completed work into a retry.
      var cleanupFailed = false;
      try {
        cleanupFailed = !await journal.acknowledge(receipt,
            retention: retention,
            notUpdatedAfter: imported.job.updatedAt,
            clock: _clock);
      } on Object {
        cleanupFailed = true;
      }
      return AndroidPublicationImportResult(imported,
          cleanupFailed: cleanupFailed);
    } finally {
      control?.removeCancellationListener(cancel);
      owner.lossControl.removeCancellationListener(cancel);
      _control = null;
      _active = null;
      done.complete();
    }
  }

  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _drain();
  }

  Future<void> _drain() async {
    await _active?.future;
    await _verifier.close();
  }
}
