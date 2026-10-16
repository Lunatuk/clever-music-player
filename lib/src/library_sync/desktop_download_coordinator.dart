import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/models/models.dart';
import '../domain/repositories/download_import_repository.dart';
import '../domain/repositories/download_job_repository.dart';
import '../domain/repositories/publication_retention_repository.dart';
import '../library/artwork_cache_service.dart';
import '../library/file_content_hasher.dart';
import '../library/library_scan_control.dart';
import '../library/metadata_reader_service.dart';
import '../library/stable_track_id.dart';
import 'desktop_publication_store.dart';
import 'desktop_publication_maintenance.dart';
import 'publication_journal.dart';
import 'download_lease_owner.dart';
import 'downloaded_audio_metadata.dart';
import 'downloaded_audio_metadata_preparer.dart';
import 'downloaded_audio_validation.dart';
import 'native_publication_files.dart';
import 'publication_intent.dart';

enum DownloadCoordinationOutcome {
  completed,
  requiresDownload,
  cancelled,
  ownershipLost,
  busy,
  failed,
  needsReconciliation,
}

final class DownloadCoordinationResult {
  const DownloadCoordinationResult(
      {required this.outcome,
      required this.job,
      this.imported,
      this.failure,
      this.cleanupFailed = false});
  final DownloadCoordinationOutcome outcome;
  final DownloadJob job;
  final DownloadImportResult? imported;
  final DownloadFailure? failure;
  final bool cleanupFailed;
}

/// Coordinates an already downloaded, exclusively owned local file. Transport,
/// account access, queue selection and retries are separate.
/// Never runs at startup; caller closes this owner before closing SQLite.
final class DesktopDownloadCoordinator {
  DesktopDownloadCoordinator(
      {required DownloadJobRepository jobs,
      required DownloadImportRepository imports,
      required PublicationRetentionRepository retention,
      required DownloadedAudioMetadataPreparer preparer,
      MetadataReaderService metadataReader =
          const EmbeddedAudioMetadataReaderService(),
      required ArtworkCacheService artworkCache,
      PublicationFiles files = const NativePublicationFiles(),
      PublicationRetentionPolicy? retentionPolicy,
      DateTime Function()? clock,
      this.leaseFor = const Duration(seconds: 60),
      this.heartbeatEvery = const Duration(seconds: 20)})
      : _jobs = jobs,
        _imports = imports,
        _retention = retention,
        _retentionPolicy = retentionPolicy ?? PublicationRetentionPolicy(),
        _preparer = preparer,
        _metadataReader = metadataReader,
        _artworkCache = artworkCache,
        _files = files,
        _clock = clock ?? DateTime.now;
  final DownloadJobRepository _jobs;
  final DownloadImportRepository _imports;
  final PublicationRetentionRepository _retention;
  final PublicationRetentionPolicy _retentionPolicy;
  final DownloadedAudioMetadataPreparer _preparer;
  final MetadataReaderService _metadataReader;
  final ArtworkCacheService _artworkCache;
  final PublicationFiles _files;
  final DateTime Function() _clock;
  final Duration leaseFor, heartbeatEvery;
  bool _closed = false;
  Completer<void>? _active;
  LibraryScanControl? _control;
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
    if (_closed) return Future.error(StateError('Координатор закрыт.'));
    if (_active != null) {
      return Future.error(StateError('Задание уже выполняется.'));
    }
    final done = Completer<void>();
    final current = LibraryScanControl();
    _active = done;
    _control = current;
    control?.addCancellationListener(current.cancel);
    final accepted = _execute(job, current,
        source: source, expected: expected, cover: cover);
    final result = accepted.whenComplete(() {
      control?.removeCancellationListener(current.cancel);
      _control = null;
      _active = null;
      done.complete();
    });
    result.ignore();
    return result;
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
    final publisher = DesktopPublicationStore(
        jobs: owner,
        files: _files,
        clock: _clock,
        retentionPolicy: _retentionPolicy);
    final maintenance = DesktopPublicationMaintenance(
        repository: _retention,
        files: _files,
        policy: _retentionPolicy,
        clock: _clock);
    final hash = const Sha256FileContentHasher().openSession();
    owner.lossControl.addCancellationListener(control.cancel);
    PreparedDownloadedAudio? prepared;
    DownloadImportResult? imported;
    var outcome = DownloadCoordinationOutcome.failed;
    DownloadFailure? failure;
    var possiblePublication = false, cleanupFailed = false;
    try {
      control.throwIfCancelled();
      await owner.start();
      final destination = await owner.withOwnedDestination(owner.current,
          clock: _clock, action: (path) async => path);
      if (destination == null) {
        throw const PublicationException(PublicationFailure.ownershipLost);
      }
      final cleaned = await maintenance.clean(
          destinationPath: destination,
          libraryFolderId: initial.key.libraryFolderId,
          control: control);
      cleanupFailed = cleaned.failed > 0;
      await publisher.run(owner.current, (workspace) async {
        final candidates = <String>[];
        for (final id in await workspace.pendingPublications()) {
          final intent = await workspace.readIntent(id);
          final kind = await FileSystemEntity.type(
              p.join(workspace.root, intent.fileName),
              followLinks: false);
          if (kind == FileSystemEntityType.file) {
            candidates.add(id);
          } else if (kind != FileSystemEntityType.notFound) {
            throw const PublicationException(PublicationFailure.unsafePath);
          }
        }
        control.throwIfCancelled();
        PublicationReceipt receipt;
        if (source == null) {
          if (candidates.isEmpty) {
            await owner.resolve(DownloadJobStage.download);
            outcome = DownloadCoordinationOutcome.requiresDownload;
            return;
          }
          possiblePublication = true;
          if (candidates.length != 1 ||
              owner.current.stage.index < DownloadJobStage.publication.index) {
            throw const PublicationException(
                PublicationFailure.needsReconciliation);
          }
          receipt = await workspace.reconcile(owner.current, candidates.single);
          await owner.resolve(owner.current.stage);
        } else {
          if (candidates.isNotEmpty) {
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
          await owner.advance(DownloadJobStage.publication);
          await workspace.writeAudio(prepared!.file.openRead(),
              expectedSize: prepared!.verification.fileSizeBytes);
          control.throwIfCancelled();
          possiblePublication = true;
          receipt =
              await workspace.publish(owner.current, prepared!.verification);
        }
        if (owner.current.stage == DownloadJobStage.publication) {
          await owner.advance(DownloadJobStage.importing);
        }
        // After accepted publication, late caller cancellation drains import.
        // Loss of lease/session remains fatal and cannot be ignored.
        final result = await _import(owner, receipt, hash);
        imported = result.$1;
        cleanupFailed = cleanupFailed || result.$2;
        outcome = DownloadCoordinationOutcome.completed;
      }, control: control);
    } on Object catch (error) {
      failure = _failure(error);
      if (imported != null) {
        // Workspace teardown may fail after the atomic completion. Report
        // cleanup, never try to interrupt an already completed attempt.
        cleanupFailed = true;
        outcome = DownloadCoordinationOutcome.completed;
      } else if (owner.lost ||
          (error is PublicationException &&
              error.reason == PublicationFailure.ownershipLost)) {
        outcome = DownloadCoordinationOutcome.ownershipLost;
      } else if (error is PublicationException &&
          error.reason == PublicationFailure.busy &&
          owner.current.stage == DownloadJobStage.download &&
          !possiblePublication) {
        outcome = DownloadCoordinationOutcome.busy;
      } else {
        // Admission may contend after advancing to publication. That snapshot
        // must reconcile/rewind before accepting another raw download.
        if (error is PublicationException &&
            error.reason == PublicationFailure.busy) {
          possiblePublication = true;
        }
        final cancelled = error is LibraryScanCancelled ||
            (error is AudioValidationException &&
                error.outcome == AudioValidationOutcome.cancelled);
        failure = cancelled ? DownloadFailure.cancelled : failure;
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
          // A DB failure is not a successful release; expiry recovery retains
          // the current checkpoint. Never claim that the job was completed.
        }
      }
    } finally {
      for (final close in [
        () async => await prepared?.close(),
        publisher.close,
        maintenance.close,
        hash.close,
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
    if (imported != null) outcome = DownloadCoordinationOutcome.completed;
    return DownloadCoordinationResult(
        outcome: outcome,
        job: owner.current,
        imported: imported,
        failure: failure,
        cleanupFailed: cleanupFailed);
  }

  Future<(DownloadImportResult, bool)> _import(DownloadLeaseOwner owner,
      PublicationReceipt receipt, FileContentHashSession hash) async {
    final file = File(receipt.filePath);
    final seal = await _files.lock(file.path, seal: true);
    DownloadImportResult? committed;
    var cleanupFailed = false;
    try {
      final metadata = await _metadataReader.read(file);
      owner.lossControl.throwIfCancelled();
      if (metadata.metadataSource != MetadataSource.embeddedTags ||
          metadata.fileSizeBytes != receipt.verification.fileSizeBytes ||
          p.normalize(metadata.filePath) != p.normalize(file.path)) {
        throw const PublicationException(PublicationFailure.changed);
      }
      final art = await _artworkCache.saveEmbeddedArtwork(metadata.artwork);
      owner.lossControl.throwIfCancelled();
      final checked =
          await hash.hashFileWithControl(file, control: owner.lossControl);
      if (checked.sizeBytes != receipt.verification.fileSizeBytes ||
          checked.digest != receipt.verification.contentHash) {
        throw const PublicationException(PublicationFailure.changed);
      }
      final destination = await owner.withOwnedDestination(owner.current,
          clock: _clock, action: (path) async => path);
      final sourcePath = p
          .normalize(p.absolute(p.join(destination!, receipt.intent.fileName)));
      final old = receipt.verification;
      final now = _clock();
      final proof = DownloadedAssetVerification(
          actualQuality: old.actualQuality,
          container: old.container,
          codec: old.codec,
          fileSizeBytes: old.fileSizeBytes,
          duration: old.duration,
          contentHash: old.contentHash,
          checkedAt: now);
      final track = Track(
          filePath: sourcePath,
          libraryFolderId: owner.current.key.libraryFolderId,
          stableId: generateStableTrackId(
              filePath: sourcePath,
              title: metadata.title,
              artist: metadata.artist,
              album: metadata.album,
              fileSizeBytes: proof.fileSizeBytes,
              durationMs: proof.duration.inMilliseconds),
          contentHash: proof.contentHash,
          fileSizeBytes: proof.fileSizeBytes,
          codec: proof.container,
          duration: proof.duration,
          title: metadata.title,
          artist: metadata.artist,
          album: metadata.album,
          albumArtist: metadata.albumArtist,
          genre: metadata.genre,
          trackNumber: metadata.trackNumber,
          discNumber: metadata.discNumber,
          year: metadata.year,
          artworkPath: art?.path,
          artworkHash: art?.hash,
          artworkMimeType: art?.mimeType,
          metadataSource: metadata.metadataSource,
          metadataConfidence: metadata.metadataConfidence,
          modifiedAt: metadata.modifiedAt,
          addedAt: now,
          updatedAt: now,
          lastSeenAt: now);
      committed = await owner.finish((job) async {
        final committed = await _imports.commit(
            job,
            DownloadedTrackImport(
                jobId: job.id,
                key: job.key,
                publicationId: receipt.intent.publicationId,
                track: track,
                verification: proof),
            clock: _clock);
        return committed == null ? null : (committed, committed.job);
      });
    } finally {
      try {
        await seal.close();
      } on Object {
        if (committed == null) rethrow;
        cleanupFailed = true;
      }
    }
    return (committed, cleanupFailed);
  }

  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _close(_active?.future);
  }

  Future<void> _close(Future<void>? active) async {
    await active;
    await _preparer.close();
  }
}

DownloadFailure _failure(Object error) => switch (error) {
      PublicationException(reason: PublicationFailure.quotaExceeded) =>
        DownloadFailure.noSpace,
      AudioValidationException() => DownloadFailure.invalidMedia,
      PublicationFileException(reason: PublicationFileFailure.noSpace) =>
        DownloadFailure.noSpace,
      PublicationFileException(reason: PublicationFileFailure.accessDenied) =>
        DownloadFailure.accessDenied,
      _ => DownloadFailure.internalError,
    };
