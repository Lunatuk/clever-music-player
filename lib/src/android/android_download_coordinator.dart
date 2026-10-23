import 'dart:async';
import 'dart:math';

import '../core/async_lifecycle.dart';
import '../diagnostics/diagnostics_service.dart';
import '../domain/models/models.dart';
import '../domain/repositories/download_import_repository.dart';
import '../domain/repositories/download_job_repository.dart';
import '../domain/repositories/publication_retention_repository.dart';
import '../library/artwork_cache_service.dart';
import '../library/library_scan_control.dart';
import '../library_sync/download_coordination.dart';
import '../library_sync/download_lease_owner.dart';
import '../library_sync/download_workspace.dart';
import '../library_sync/downloaded_audio_metadata.dart';
import '../library_sync/downloaded_audio_metadata_preparer.dart';
import '../library_sync/downloaded_audio_validation.dart';
import '../library_sync/native_publication_files.dart';
import '../library_sync/publication_intent.dart';
import '../library_sync/source_fingerprint_probe.dart';
import 'android_audio_publication_backend.dart';
import 'android_audio_publisher.dart';
import 'android_download_folders.dart';
import 'android_publication_importer.dart';
import 'android_publication_journal.dart';
import 'android_publication_receipt.dart';
import 'android_publication_verifier.dart';
import 'android_published_track_reader.dart';
import 'audio_documents.dart';

/// One explicitly owned pipeline. Owns preparer and per-job platform adapters;
/// borrows the journal/workspace, repositories and artwork cache from its caller.
/// Does not claim jobs, access credentials, download or run at application boot.
final class AndroidDownloadCoordinator {
  AndroidDownloadCoordinator(
      {required DownloadJobRepository jobs,
      required DownloadImportRepository imports,
      required PublicationRetentionRepository retention,
      required DownloadedAudioMetadataPreparer preparer,
      required this.journal,
      required ArtworkCacheService artworkCache,
      this.diagnostics = const NoopDiagnosticsService(),
      this.workspace,
      AudioPublicationBackend Function()? backendFactory,
      PublicationDocumentVerifier Function()? verifierFactory,
      Future<AudioDocumentMetadata> Function(ContentUriAudioSource)?
          readDocument,
      this.files = const NativePublicationFiles(),
      DateTime Function()? clock,
      String Function()? publicationId,
      this.leaseFor = const Duration(seconds: 60),
      this.heartbeatEvery = const Duration(seconds: 20)})
      : _jobs = jobs,
        _imports = imports,
        _retention = retention,
        _preparer = preparer,
        _backend = backendFactory ?? AndroidAudioPublicationBackend.new,
        _verifier = verifierFactory ?? AndroidPublicationVerifier.new,
        _reader = AndroidPublishedTrackReader(
            artworkCache: artworkCache, readDocument: readDocument),
        _clock = clock ?? DateTime.now,
        _id = publicationId ?? _randomId {
    if (preparer.workspace != workspace ||
        leaseFor < const Duration(seconds: 1) ||
        leaseFor > const Duration(minutes: 10) ||
        heartbeatEvery <= Duration.zero ||
        heartbeatEvery * 2 > leaseFor) {
      throw ArgumentError('Некорректные границы координатора.');
    }
  }
  final DownloadJobRepository _jobs;
  final DownloadImportRepository _imports;
  final PublicationRetentionRepository _retention;
  final DownloadedAudioMetadataPreparer _preparer;
  final AndroidPublicationJournal journal;
  final DownloadWorkspace? workspace;
  final PublicationFiles files;
  final DiagnosticsService diagnostics;
  final AudioPublicationBackend Function() _backend;
  final PublicationDocumentVerifier Function() _verifier;
  final AndroidPublishedTrackReader _reader;
  final DateTime Function() _clock;
  final String Function() _id;
  final Duration leaseFor, heartbeatEvery;
  Completer<void>? _active;
  LibraryScanControl? _control;
  bool _closed = false;
  Future<void>? _closing;

  Future<DownloadCoordinationResult> processDownloadedFile(DownloadJob job,
      FileAudioSource source, DownloadedAudioExpectation expected,
      {EmbeddedCover? cover, LibraryScanControl? control}) {
    if (job.state != DownloadJobState.running ||
        job.stage != DownloadJobStage.download ||
        expected.quality != job.key.quality ||
        expected.tags['title'] == null) {
      return Future.error(
          ArgumentError('Нужен скачанный файл текущего задания.'));
    }
    return _run(job,
        source: source, expected: expected, cover: cover, control: control);
  }

  Future<DownloadCoordinationResult> recover(DownloadJob job,
      {LibraryScanControl? control}) {
    if (job.state != DownloadJobState.reconciling) {
      return Future.error(
          ArgumentError('Нужна текущая попытка восстановления.'));
    }
    return _run(job, control: control);
  }

  Future<DownloadCoordinationResult> _run(DownloadJob job,
      {FileAudioSource? source,
      DownloadedAudioExpectation? expected,
      EmbeddedCover? cover,
      LibraryScanControl? control}) {
    if (_closed || _active != null) {
      return Future.error(StateError('Координатор недоступен.'));
    }
    final done = _active = Completer<void>();
    final current = _control = LibraryScanControl();
    control?.addCancellationListener(current.cancel);
    final result =
        _execute(job, current, source: source, expected: expected, cover: cover)
            .whenComplete(() {
      control?.removeCancellationListener(current.cancel);
      _active = null;
      _control = null;
      done.complete();
    });
    result.ignore();
    return result;
  }

  Future<AndroidAudioPublisher> _openPublisher() async {
    final backend = _backend();
    try {
      return AndroidAudioPublisher(
          journal: journal,
          backend: backend,
          verifier: _verifier(),
          files: files,
          clock: _clock);
    } on Object {
      try {
        await backend.close();
      } on Object {/* Preserve factory failure. */}
      rethrow;
    }
  }

  Future<DownloadCoordinationResult> _execute(
      DownloadJob initial, LibraryScanControl control,
      {FileAudioSource? source,
      DownloadedAudioExpectation? expected,
      EmbeddedCover? cover}) async {
    final owner = DownloadLeaseOwner(
        job: initial,
        jobs: _jobs,
        clock: _clock,
        leaseFor: leaseFor,
        heartbeatEvery: heartbeatEvery);
    owner.lossControl.addCancellationListener(control.cancel);
    AndroidAudioPublisher? publisher;
    AndroidPublicationImporter? importer;
    PreparedDownloadedAudio? prepared;
    DownloadImportResult? imported;
    var possiblePublication = source == null;
    var cleanupFailed = false;
    var outcome = DownloadCoordinationOutcome.failed;
    DownloadFailure? failure;
    try {
      control.throwIfCancelled();
      await owner.start();
      await owner.withOwnedDestination(owner.current, clock: _clock,
          action: (raw) async {
        AndroidDownloadFolders.parseTree(raw);
        return true;
      });
      publisher = await _openPublisher();
      importer = AndroidPublicationImporter(
          journal: journal,
          imports: _imports,
          retention: _retention,
          verifier: _verifier(),
          clock: _clock);
      AndroidPublicationReceipt? receipt;
      if (source == null) {
        final recovery = await publisher.recover(owner, control: control);
        if (recovery.status ==
            AndroidPublicationRecoveryStatus.requiresDownload) {
          control.throwIfCancelled();
          await owner.resolve(DownloadJobStage.download);
          outcome = DownloadCoordinationOutcome.requiresDownload;
          possiblePublication = false;
        } else if (recovery.status ==
            AndroidPublicationRecoveryStatus.retained) {
          throw AudioPublicationException(recovery.reason!);
        } else {
          receipt = recovery.receipt!;
          await owner.resolve(owner.current.stage);
        }
      } else {
        if ((await publisher.pending(owner, control: control)).isNotEmpty) {
          possiblePublication = true;
          throw const PublicationException(
              PublicationFailure.needsReconciliation);
        }
        await owner.advance(DownloadJobStage.metadata);
        control.throwIfCancelled();
        prepared = await _preparer.prepare(source, expected!,
            cover: cover, control: control);
        await owner.advance(DownloadJobStage.verification);
        control.throwIfCancelled();
        final intent = PublicationIntent(
            publicationId: _id(),
            jobId: initial.id,
            key: initial.key,
            verification: prepared.verification);
        await owner.advance(DownloadJobStage.publication);
        possiblePublication = true;
        control.throwIfCancelled();
        receipt = await publisher.publish(
            owner: owner,
            intent: intent,
            prepared: FileAudioSource(prepared.file.path),
            control: control);
      }
      // A durably accepted publication drains import even after caller cancel.
      // Session, folder and owner loss still revoke completion through the lease.
      if (receipt != null) {
        if (owner.current.stage == DownloadJobStage.publication) {
          await owner.advance(DownloadJobStage.importing);
        }
        final track = await _reader.read(receipt, _clock(), owner.lossControl);
        final result = await importer.importReceipt(
            owner: owner, receipt: receipt, preparedTrack: track);
        imported = result.imported;
        cleanupFailed = result.cleanupFailed;
        outcome = DownloadCoordinationOutcome.completed;
      }
    } on Object catch (error) {
      try {
        diagnostics.record(DiagnosticEvent.androidDownloadCoordinated, fields: {
          DiagnosticField.coordinationStage: owner.current.stage.index,
          if (error is AudioPublicationException)
            DiagnosticField.publicationStatus: error.status.index,
          if (error is AudioValidationException)
            DiagnosticField.audioValidationOutcome: error.outcome.index,
          if (error is AndroidPublicationVerificationException)
            DiagnosticField.fingerprintStatus: error.status.index,
        });
      } on Object {/* Observers cannot interrupt ownership or cleanup. */}
      failure = _failure(error);
      if (owner.lost ||
          error is PublicationException &&
              error.reason == PublicationFailure.ownershipLost ||
          error is AudioPublicationException &&
              error.status == AudioPublicationStatus.ownershipLost) {
        outcome = DownloadCoordinationOutcome.ownershipLost;
      } else {
        final cancelled = error is LibraryScanCancelled ||
            error is AudioValidationException &&
                error.outcome == AudioValidationOutcome.cancelled ||
            error is AudioPublicationException &&
                error.status == AudioPublicationStatus.cancelled;
        if (cancelled) failure = DownloadFailure.cancelled;
        outcome = possiblePublication
            ? DownloadCoordinationOutcome.needsReconciliation
            : cancelled
                ? DownloadCoordinationOutcome.cancelled
                : DownloadCoordinationOutcome.failed;
        try {
          if (possiblePublication) {
            await owner.interrupt(failure);
          } else {
            await owner.fail(failure, cancelled: cancelled);
          }
        } on Object {
          if (owner.lost) outcome = DownloadCoordinationOutcome.ownershipLost;
        }
      }
    } finally {
      for (final close in <Future<void> Function()>[
        if (publisher != null) publisher.close,
        if (importer != null) importer.close,
        if (prepared != null) prepared.close,
        owner.close,
      ]) {
        try {
          await close();
        } on Object {
          cleanupFailed = true;
        }
      }
      owner.lossControl.removeCancellationListener(control.cancel);
    }
    try {
      diagnostics.record(DiagnosticEvent.androidDownloadCoordinated, fields: {
        DiagnosticField.coordinationStage: owner.current.stage.index,
        DiagnosticField.coordinationOutcome: outcome.index,
        DiagnosticField.needsReconciliation:
            outcome == DownloadCoordinationOutcome.needsReconciliation,
      });
    } on Object {/* Observers cannot interrupt ownership or cleanup. */}
    return DownloadCoordinationResult(
        outcome: outcome,
        job: owner.current,
        imported: imported,
        failure: failure,
        cleanupFailed: cleanupFailed);
  }

  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??=
        finishCleanup([() async => await _active?.future, _preparer.close]);
  }
}

String _randomId() {
  final random = Random.secure();
  return List.generate(
      32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

DownloadFailure _failure(Object error) => switch (error) {
      DownloadWorkspaceException(
        failure: DownloadWorkspaceFailure.quotaExceeded
      ) ||
      PublicationException(reason: PublicationFailure.quotaExceeded) ||
      AudioPublicationException(
        status: AudioPublicationStatus.quotaExceeded ||
            AudioPublicationStatus.noSpace
      ) ||
      PublicationFileException(reason: PublicationFileFailure.noSpace) =>
        DownloadFailure.noSpace,
      AudioPublicationException(status: AudioPublicationStatus.accessDenied) ||
      AndroidPublicationVerificationException(
        status: SourceFingerprintStatus.accessDenied
      ) ||
      PublicationFileException(reason: PublicationFileFailure.accessDenied) =>
        DownloadFailure.accessDenied,
      AudioValidationException() ||
      PublicationException(reason: PublicationFailure.changed) ||
      AudioPublicationException(status: AudioPublicationStatus.changed) ||
      AndroidPublicationVerificationException() =>
        DownloadFailure.invalidMedia,
      PublicationException(reason: PublicationFailure.needsReconciliation) ||
      AudioPublicationException(
        status: AudioPublicationStatus.needsReconciliation
      ) =>
        DownloadFailure.interrupted,
      _ => DownloadFailure.internalError,
    };
