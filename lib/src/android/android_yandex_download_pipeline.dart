import 'dart:async';
import 'dart:io';

import '../diagnostics/diagnostics_service.dart';
import '../domain/models/models.dart';
import '../domain/repositories/download_import_repository.dart';
import '../domain/repositories/download_job_repository.dart';
import '../domain/repositories/publication_retention_repository.dart';
import '../domain/repositories/remote_library_repository.dart';
import '../library/artwork_cache_service.dart';
import '../library/library_scan_control.dart';
import '../library_sync/binary_download.dart';
import '../library_sync/binary_http_download_transport.dart';
import 'android_audio_metadata_backend.dart';
import 'android_audio_publication_backend.dart';
import 'android_publication_journal.dart';
import 'android_publication_verifier.dart';
import 'audio_documents.dart';
import 'android_download_coordinator.dart';
import '../library_sync/download_coordination.dart';
import '../library_sync/download_workspace.dart';
import '../library_sync/downloaded_audio_metadata_preparer.dart';
import '../library_sync/downloaded_audio_validation.dart';
import '../library_sync/raw_download_pool.dart';
import '../library_sync/yandex_audio_selection.dart';
import '../library_sync/yandex_download_protocol.dart';
import '../library_sync/yandex_download_runner.dart';
import '../library_sync/yandex_track_downloader.dart';

/// Android composition, owned by ONE explicit runner invocation.
/// Owns media backend, receipt journal, workspace, transport and all issued temporary readers;
/// the credential reader remains borrowed from the runner.
final class AndroidYandexDownloadPipeline implements YandexDownloadPipeline {
  AndroidYandexDownloadPipeline._(this._workspace, this._pool, this._downloader,
      this._coordinator, this._journal, this.maxAudioBytes);

  static Future<AndroidYandexDownloadPipeline> open({
    required YandexDownloadSessionReader reader,
    required Directory temporaryParent,
    required DownloadJobRepository jobs,
    required RemoteLibraryRepository accounts,
    required DownloadImportRepository imports,
    required PublicationRetentionRepository retention,
    required ArtworkCacheService artworkCache,
    required LibraryScanControl control,
    DiagnosticsService diagnostics = const NoopDiagnosticsService(),
    AndroidMediaProcessingBackend Function()? mediaFactory,
    AudioPublicationBackend Function()? publicationFactory,
    PublicationDocumentVerifier Function()? verifierFactory,
    Future<AudioDocumentMetadata> Function(ContentUriAudioSource)? readDocument,
    DateTime Function()? clock,
    int maxAudioBytes = 256 * 1024 * 1024,
    Uri? loopbackForTesting,
  }) async {
    if (maxAudioBytes <= 0 || maxAudioBytes > maximumRawDownloadBytes) {
      throw ArgumentError('Некорректный предел аудио.');
    }
    control.throwIfCancelled();
    final media = (mediaFactory ?? AndroidAudioMetadataBackend.new)();
    DownloadWorkspace? workspace;
    AndroidPublicationJournal? journal;
    RawDownloadPool? pool;
    YandexTrackDownloader? downloader;
    DownloadedAudioMetadataPreparer? preparer;
    AndroidDownloadCoordinator? coordinator;
    try {
      await media.capabilities(control);
      control.throwIfCancelled();
      temporaryParent = Directory(await temporaryParent.resolveSymbolicLinks());
      workspace = await DownloadWorkspace.open(
          parent: temporaryParent, control: control);
      journal =
          await AndroidPublicationJournal.open(privateParent: temporaryParent);
      // Metadata-only cleanup with current completed-asset authority. Pending
      // receipts stay intact; no provider access or music deletion here.
      final notUpdatedAfter = (clock ?? DateTime.now)();
      for (final receipt in await journal.pending()) {
        control.throwIfCancelled();
        await journal.acknowledge(receipt,
            retention: retention,
            notUpdatedAfter: notUpdatedAfter,
            clock: clock ?? DateTime.now);
      }
      control.throwIfCancelled();
      pool = RawDownloadPool(
          parent: temporaryParent,
          workspace: workspace,
          maxReservedBytes: maxAudioBytes + maximumDownloadedCoverBytes);
      preparer = DownloadedAudioMetadataPreparer(
          backend: media,
          workspace: workspace,
          temporaryParent: temporaryParent,
          clock: clock);
      coordinator = AndroidDownloadCoordinator(
          jobs: jobs,
          journal: journal,
          backendFactory: publicationFactory,
          verifierFactory: verifierFactory,
          readDocument: readDocument,
          imports: imports,
          retention: retention,
          preparer: preparer,
          workspace: workspace,
          artworkCache: artworkCache,
          diagnostics: diagnostics,
          clock: clock);
      final transport = loopbackForTesting == null
          ? BinaryHttpDownloadTransport(pool: pool, diagnostics: diagnostics)
          : BinaryHttpDownloadTransport.loopbackForTesting(loopbackForTesting,
              pool: pool, diagnostics: diagnostics);
      downloader = YandexTrackDownloader(
          reader: reader,
          ownsReader: false,
          transport: transport,
          jobs: jobs,
          accounts: accounts,
          clock: clock);
      control.throwIfCancelled();
      return AndroidYandexDownloadPipeline._(
          workspace, pool, downloader, coordinator, journal, maxAudioBytes);
    } on Object catch (error) {
      try {
        diagnostics.record(DiagnosticEvent.androidDownloadOpenFailed, fields: {
          if (error is AudioValidationException)
            DiagnosticField.audioValidationOutcome: error.outcome.index,
          if (error is DownloadWorkspaceException)
            DiagnosticField.workspaceFailure: error.failure.index,
        });
      } on Object {/* Observers cannot interrupt cleanup. */}
      // No work has been admitted. Still close every constructed owner.
      for (final close in <Future<void> Function()>[
        if (downloader != null) downloader.close,
        if (coordinator != null)
          coordinator.close
        else if (preparer != null)
          preparer.close
        else
          media.close,
        if (journal != null) journal.close,
        if (workspace != null) workspace.close,
      ]) {
        try {
          await close();
        } on Object {/* Preserve original error. */}
      }
      pool?.closeAdmission();
      rethrow;
    }
  }

  final DownloadWorkspace _workspace;
  final AndroidPublicationJournal _journal;
  final RawDownloadPool _pool;
  final YandexTrackDownloader _downloader;
  final AndroidDownloadCoordinator _coordinator;
  final int maxAudioBytes;
  bool _closed = false;
  LibraryScanControl? _control;
  Completer<void>? _active;
  Future<void>? _closing;

  @override
  Future<DownloadCoordinationResult> execute(DownloadJob job,
      RemoteLibraryAccount account, YandexAudioSelection selection,
      {required LibraryScanControl control,
      required void Function(YandexDownloadRunStage, BinaryDownloadProgress?)
          onProgress}) async {
    if (_closed || _active != null) {
      throw const YandexDownloadRunException(YandexDownloadRunFailure.pipeline);
    }
    final done = Completer<void>();
    _active = done;
    final current = LibraryScanControl();
    _control = current;
    control.addCancellationListener(current.cancel);
    YandexDownloadedTrack? raw;
    DownloadCoordinationResult? result;
    var cleanupFailed = false;
    void progress(YandexDownloadRunStage stage,
        [BinaryDownloadProgress? bytes]) {
      try {
        onProgress(stage, bytes);
      } on Object {/* UI observer only. */}
    }

    try {
      current.throwIfCancelled();
      var next = job;
      if (next.state == DownloadJobState.reconciling) {
        progress(YandexDownloadRunStage.recovering);
        final recovered = await _coordinator.recover(next, control: current);
        if (recovered.outcome != DownloadCoordinationOutcome.requiresDownload ||
            recovered.cleanupFailed) {
          result = recovered;
        } else {
          next = recovered.job;
        }
      }
      if (result == null) {
        current.throwIfCancelled();
        progress(YandexDownloadRunStage.downloading);
        raw = await _downloader.download(next, account, selection,
            maxBytes: maxAudioBytes,
            control: current,
            onProgress: (bytes) =>
                progress(YandexDownloadRunStage.downloading, bytes));
        current.throwIfCancelled();
        progress(YandexDownloadRunStage.processing);
        result = await _coordinator.processDownloadedFile(
            raw.job, raw.raw.source, raw.expectation,
            cover: raw.cover, control: current);
      }
    } finally {
      try {
        await raw?.close();
      } on Object {
        cleanupFailed = true;
      }
      control.removeCancellationListener(current.cancel);
      _control = null;
      _active = null;
      done.complete();
    }
    return DownloadCoordinationResult(
        outcome: result.outcome,
        job: result.job,
        imported: result.imported,
        failure: result.failure,
        cleanupFailed: cleanupFailed || result.cleanupFailed);
  }

  @override
  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _close();
  }

  Future<void> _close() async {
    final downloading = _downloader.close();
    final processing = _coordinator.close();
    downloading.ignore();
    processing.ignore();
    _pool.closeAdmission();
    await _active?.future;
    var failed = false;
    for (final close in <Future<void> Function()>[
      () => downloading,
      () => processing,
      _pool.retryFailedCleanup,
      _journal.close,
      _workspace.close,
    ]) {
      try {
        await close();
      } on Object {
        failed = true;
      }
    }
    if (failed) {
      throw const YandexDownloadRunException(YandexDownloadRunFailure.storage);
    }
  }
}
