import 'dart:async';

import '../domain/models/models.dart';
import '../library/library_scan_control.dart';
import '../library_sync/download_lease_owner.dart';
import '../library_sync/native_publication_files.dart';
import '../library_sync/publication_intent.dart';
import '../library_sync/source_fingerprint_probe.dart';
import 'android_audio_publication_backend.dart';
import 'android_download_folders.dart';
import 'android_publication_journal.dart';
import 'android_publication_receipt.dart';
import 'android_publication_verifier.dart';

enum AndroidPublicationRecoveryStatus { requiresDownload, published, retained }

final class AndroidPublicationRecoveryResult {
  const AndroidPublicationRecoveryResult._(this.status,
      {this.receipt, this.reason});
  final AndroidPublicationRecoveryStatus status;
  final AndroidPublicationReceipt? receipt;
  final AudioPublicationStatus? reason;
}

/// Publishes an already validated app-private file. No downloading, metadata
/// rewriting, queue claims or automatic startup work. Caller owns journal/lease.
final class AndroidAudioPublisher {
  AndroidAudioPublisher(
      {required this.journal,
      AudioPublicationBackend? backend,
      PublicationDocumentVerifier? verifier,
      this.files = const NativePublicationFiles(),
      DateTime Function()? clock})
      : _backend = backend ?? AndroidAudioPublicationBackend(),
        _verifier = verifier ?? AndroidPublicationVerifier(),
        _clock = clock ?? DateTime.now;
  final AndroidPublicationJournal journal;
  final AudioPublicationBackend _backend;
  final PublicationDocumentVerifier _verifier;
  final PublicationFiles files;
  final DateTime Function() _clock;
  static final _owners = <AndroidPublicationJournal>{};
  bool _closed = false;
  Completer<void>? _active;
  LibraryScanControl? _control;
  Future<void>? _closing;

  Future<T> _run<T>(DownloadLeaseOwner owner, LibraryScanControl? control,
      Future<T> Function(LibraryScanControl) action) async {
    if (_closed || _active != null || !_owners.add(journal)) {
      throw StateError('Публикация уже выполняется.');
    }
    final done = _active = Completer<void>();
    final operation = _control = LibraryScanControl();
    void cancel() => operation.cancel();
    control?.addCancellationListener(cancel);
    owner.lossControl.addCancellationListener(cancel);
    try {
      operation.throwIfCancelled();
      return await action(operation);
    } finally {
      control?.removeCancellationListener(cancel);
      owner.lossControl.removeCancellationListener(cancel);
      _owners.remove(journal);
      _control = null;
      _active = null;
      done.complete();
    }
  }

  void _context(DownloadLeaseOwner owner, PublicationIntent intent) {
    final job = owner.current;
    if (!job.isExecuting ||
        job.id != intent.jobId ||
        job.key != intent.key ||
        job.stage.index < DownloadJobStage.publication.index) {
      throw ArgumentError('Другой контекст публикации.');
    }
  }

  Future<AudioPublicationRequest> _request(
      DownloadLeaseOwner owner, PublicationIntent intent) async {
    _context(owner, intent);
    final request = await owner.withOwnedDestination(owner.current,
        clock: _clock,
        action: (raw) async => AudioPublicationRequest(
            intent: intent,
            tree: AndroidDownloadFolders.parseTree(raw),
            owner: owner.current.attemptToken!));
    if (request == null) {
      throw const PublicationException(PublicationFailure.ownershipLost);
    }
    return request;
  }

  Future<List<PublicationIntent>> pending(DownloadLeaseOwner owner,
          {LibraryScanControl? control}) =>
      _run(owner, control, (operation) => _pending(owner, operation));

  Future<List<PublicationIntent>> _pending(
      DownloadLeaseOwner owner, LibraryScanControl operation) async {
    final raw = await owner.withOwnedDestination(owner.current,
        clock: _clock, action: (value) async => value);
    if (raw == null) {
      throw const PublicationException(PublicationFailure.ownershipLost);
    }
    final native =
        await _backend.pending(AndroidDownloadFolders.parseTree(raw));
    final local = await journal.pending();
    operation.throwIfCancelled();
    await owner.withOwnedDestination(owner.current, clock: _clock,
        action: (current) async {
      if (current != raw) {
        throw const PublicationException(PublicationFailure.ownershipLost);
      }
      return true;
    });
    final result = <String, PublicationIntent>{};
    for (final intent in [
      ...native,
      ...local
          .where((r) => r.location.tree.storageValue == raw)
          .map((r) => r.intent)
    ]) {
      if (intent.jobId != owner.current.id || intent.key != owner.current.key) {
        continue;
      }
      final old = result[intent.publicationId];
      if (old != null && old.encode() != intent.encode()) {
        throw const PublicationException(PublicationFailure.invalidJournal);
      }
      result[intent.publicationId] = intent;
    }
    return List.unmodifiable(result.values);
  }

  Future<AndroidPublicationReceipt> publish(
          {required DownloadLeaseOwner owner,
          required PublicationIntent intent,
          required FileAudioSource prepared,
          LibraryScanControl? control}) =>
      _run(owner, control, (operation) async {
        _context(owner, intent);
        if (owner.current.stage != DownloadJobStage.publication) {
          throw ArgumentError('Нужен этап публикации.');
        }
        if ((await journal.pending()).any((r) =>
            r.intent.jobId == intent.jobId && r.intent.key == intent.key)) {
          throw const AudioPublicationException(
              AudioPublicationStatus.needsReconciliation);
        }
        final seal = await files.lock(prepared.path, seal: true);
        try {
          operation.throwIfCancelled();
          final request = await _request(owner, intent);
          // Native admission does not touch a provider. Streaming stays outside
          // this short SQLite/owner gate so heartbeat and revocation can run.
          await owner.withOwnedDestination(owner.current, clock: _clock,
              action: (raw) async {
            if (raw != request.tree.storageValue) {
              throw const PublicationException(
                  PublicationFailure.ownershipLost);
            }
            operation.throwIfCancelled();
            await _backend.prepare(request);
            return true;
          });
          operation.throwIfCancelled();
          final receipt = await _backend.publish(request, prepared, operation);
          // A published response wins over late cancellation: persist evidence
          // before releasing the source/returning to a cancelled caller.
          await _finalize(owner, request, receipt);
          return receipt;
        } finally {
          await seal.close();
        }
      });

  Future<AndroidPublicationReceipt> reconcile(
          {required DownloadLeaseOwner owner,
          required PublicationIntent intent,
          LibraryScanControl? control}) =>
      _run(owner, control, (operation) => _reconcile(owner, intent, operation));

  Future<AndroidPublicationReceipt> _reconcile(DownloadLeaseOwner owner,
      PublicationIntent intent, LibraryScanControl operation) async {
    final request = await _request(owner, intent);
    final native = await _backend.pending(request.tree);
    final exists =
        native.where((i) => i.publicationId == intent.publicationId).toList();
    if (exists.isNotEmpty) {
      if (exists.single.encode() != intent.encode()) {
        throw const PublicationException(PublicationFailure.invalidJournal);
      }
      final receipt = await _backend.reconcile(request, operation);
      await _finalize(owner, request, receipt);
      return receipt;
    }
    final matches = (await journal.pending())
        .where((r) =>
            r.intent.encode() == intent.encode() &&
            r.location.tree == request.tree)
        .toList();
    if (matches.length != 1) {
      throw const PublicationException(PublicationFailure.needsReconciliation);
    }
    final receipt = matches.single;
    final bytes = await _verifier.verify(receipt, operation);
    operation.throwIfCancelled();
    if (bytes.status != SourceFingerprintStatus.fingerprinted ||
        bytes.sizeBytes != intent.verification.fileSizeBytes ||
        bytes.digest != intent.verification.contentHash) {
      throw const PublicationException(PublicationFailure.changed);
    }
    await _request(
        owner, intent); // fresh owner/destination proof, no provider IO inside
    return receipt;
  }

  /// Permits a fresh download only when the native ledger proves that create
  /// was never admitted. No document lookup/write/delete inside this DB fence.
  /// CREATING, partial data, lost grants and missing documents remain unresolved.
  Future<void> releaseUncreated(
          {required DownloadLeaseOwner owner,
          required PublicationIntent intent,
          LibraryScanControl? control}) =>
      _run(owner, control,
          (operation) => _releaseUncreated(owner, intent, operation));

  Future<void> _releaseUncreated(DownloadLeaseOwner owner,
      PublicationIntent intent, LibraryScanControl operation) async {
    final request = await _request(owner, intent);
    if ((await journal.pending()).any(
        (r) => r.intent.jobId == intent.jobId && r.intent.key == intent.key)) {
      throw const AudioPublicationException(
          AudioPublicationStatus.needsReconciliation);
    }
    final released = await owner.withOwnedDestination(owner.current,
        clock: _clock, action: (raw) async {
      if (raw != request.tree.storageValue) {
        throw const PublicationException(PublicationFailure.ownershipLost);
      }
      operation.throwIfCancelled();
      await _backend.releaseUncreated(request);
      return true;
    });
    if (released != true) {
      throw const PublicationException(PublicationFailure.ownershipLost);
    }
  }

  /// Source-free decision for a currently claimed reconciliation attempt.
  /// Never changes the queue checkpoint; the coordinator consumes this result.
  Future<AndroidPublicationRecoveryResult> recover(DownloadLeaseOwner owner,
          {LibraryScanControl? control}) =>
      _run(owner, control, (operation) async {
        if (owner.current.state != DownloadJobState.reconciling) {
          throw ArgumentError('Нужна текущая попытка восстановления.');
        }
        final intents = await _pending(owner, operation);
        if (intents.isEmpty) {
          return const AndroidPublicationRecoveryResult._(
              AndroidPublicationRecoveryStatus.requiresDownload);
        }
        if (owner.current.stage.index < DownloadJobStage.publication.index) {
          throw const PublicationException(PublicationFailure.invalidJournal);
        }
        if (intents.length != 1) {
          return const AndroidPublicationRecoveryResult._(
              AndroidPublicationRecoveryStatus.retained,
              reason: AudioPublicationStatus.needsReconciliation);
        }
        final intent = intents.single;
        try {
          await _releaseUncreated(owner, intent, operation);
          return const AndroidPublicationRecoveryResult._(
              AndroidPublicationRecoveryStatus.requiresDownload);
        } on AudioPublicationException catch (error) {
          if (error.status != AudioPublicationStatus.needsReconciliation) {
            rethrow;
          }
        }
        operation.throwIfCancelled();
        try {
          final receipt = await _reconcile(owner, intent, operation);
          return AndroidPublicationRecoveryResult._(
              AndroidPublicationRecoveryStatus.published,
              receipt: receipt);
        } on AudioPublicationException catch (error) {
          if (!const {
            AudioPublicationStatus.changed,
            AudioPublicationStatus.needsReconciliation,
            AudioPublicationStatus.collision,
            AudioPublicationStatus.accessDenied
          }.contains(error.status)) {
            rethrow;
          }
          return AndroidPublicationRecoveryResult._(
              AndroidPublicationRecoveryStatus.retained,
              reason: error.status);
        } on PublicationException catch (error) {
          if (error.reason != PublicationFailure.changed) rethrow;
          return const AndroidPublicationRecoveryResult._(
              AndroidPublicationRecoveryStatus.retained,
              reason: AudioPublicationStatus.changed);
        }
      });

  Future<void> _finalize(
      DownloadLeaseOwner owner,
      AudioPublicationRequest request,
      AndroidPublicationReceipt receipt) async {
    if (receipt.intent.encode() != request.intent.encode() ||
        receipt.location.tree != request.tree) {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
    await journal.record(receipt,
        job: owner.current,
        jobs: owner,
        clock: _clock,
        control: LibraryScanControl());
    final ack = await owner.withOwnedDestination(owner.current, clock: _clock,
        action: (raw) async {
      if (raw != request.tree.storageValue) {
        throw const PublicationException(PublicationFailure.ownershipLost);
      }
      await _backend.acknowledge(request, receipt.location.document);
      return true;
    });
    if (ack == null) {
      throw const PublicationException(PublicationFailure.ownershipLost);
    }
  }

  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _drain();
  }

  Future<void> _drain() async {
    await _active?.future;
    await _backend.close();
    await _verifier.close();
  }
}
