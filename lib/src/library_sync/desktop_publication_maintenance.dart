import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/models/publication_cleanup.dart';
import '../domain/repositories/publication_retention_repository.dart';
import '../library/file_content_hasher.dart';
import '../library/library_scan_control.dart';
import 'native_publication_files.dart';
import 'publication_intent.dart';
import 'publication_journal.dart';

final class PublicationMaintenanceResult {
  const PublicationMaintenanceResult(
      {required this.removedOperations,
      required this.removedBytes,
      required this.preserved,
      required this.busy,
      required this.failed});
  final int removedOperations, removedBytes, preserved, busy, failed;
}

/// Explicit folder maintenance, never startup or recursive music deletion.
/// A future update runner invokes it before admitting more publications.
final class DesktopPublicationMaintenance {
  DesktopPublicationMaintenance(
      {required PublicationRetentionRepository repository,
      PublicationFiles files = const NativePublicationFiles(),
      PublicationRetentionPolicy? policy,
      DateTime Function()? clock})
      : _repository = repository,
        _files = files,
        _policy = policy ?? PublicationRetentionPolicy(),
        _clock = clock ?? DateTime.now;
  final PublicationRetentionRepository _repository;
  final PublicationFiles _files;
  final PublicationRetentionPolicy _policy;
  final DateTime Function() _clock;
  LibraryScanControl? _control;
  Future<PublicationMaintenanceResult>? _active;
  Future<void>? _closing;
  bool _closed = false;

  Future<PublicationMaintenanceResult> clean(
      {required String destinationPath,
      required int libraryFolderId,
      LibraryScanControl? control}) {
    if (_closed || _active != null) {
      return Future.error(StateError('Очистка недоступна.'));
    }
    if (libraryFolderId <= 0) {
      return Future.error(ArgumentError('Нужна папка.'));
    }
    final current = LibraryScanControl();
    _control = current;
    control?.addCancellationListener(current.cancel);
    final operation =
        _clean(destinationPath, libraryFolderId, current).whenComplete(() {
      control?.removeCancellationListener(current.cancel);
      _active = null;
      _control = null;
    });
    operation.ignore();
    return _active = operation;
  }

  Future<PublicationMaintenanceResult> _clean(
      String path, int folderId, LibraryScanControl control) async {
    control.throwIfCancelled();
    final root = await Directory(path).resolveSymbolicLinks();
    await publicationDirectory(root);
    final state = p.join(root, '.cmp-publications-v1');
    if (await FileSystemEntity.type(state, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return const PublicationMaintenanceResult(
          removedOperations: 0,
          removedBytes: 0,
          preserved: 0,
          busy: 0,
          failed: 0);
    }
    await _paths(root);
    final entries = await publicationOperations(root, control);
    final hash = const Sha256FileContentHasher().openSession();
    var removed = 0, bytes = 0, kept = 0, busy = 0, failed = 0;
    try {
      for (final directory in entries) {
        control.throwIfCancelled();
        PublicationFileLock? lock, seal;
        try {
          final name = p.basename(directory.path);
          if (RegExp(r'^[0-9a-f]{64}-[0-9a-f]{64}$').stringMatch(name) !=
              name) {
            kept++;
            continue;
          }
          final lockPath =
              p.join(state, 'locks', '${name.substring(0, 64)}.lock');
          await publicationFile(lockPath); // Never replace/delete lock objects.
          lock = await _files.lock(lockPath);
          await _paths(root);
          final entry = await PublicationJournalEntry.read(directory);
          if (entry.files.isEmpty) {
            // Crash after deleting the last marker: no remaining recovery data.
            await directory
                .delete(); // Nonrecursive, fails if anything appeared.
            removed++;
            continue;
          }
          final reservation = entry.reservation;
          final intent = entry.intent;
          final key = reservation?.key ?? intent?.key;
          final jobId = reservation?.jobId ?? intent?.jobId;
          if (key == null || jobId == null || key.libraryFolderId != folderId) {
            kept++;
            continue;
          }
          final finalPath =
              intent == null ? null : p.join(root, intent.fileName);
          final kind = finalPath == null
              ? FileSystemEntityType.notFound
              : await FileSystemEntity.type(finalPath, followLinks: false);
          final imported = kind == FileSystemEntityType.file;
          if (kind != FileSystemEntityType.file &&
              kind != FileSystemEntityType.notFound) {
            kept++;
            continue;
          }
          final now = _clock();
          final cutoff = now
              .subtract(imported ? _policy.importedAge : _policy.abandonedAge);
          if (entry.createdAt == null || entry.createdAt!.isAfter(cutoff)) {
            kept++;
            continue;
          }
          final request = PublicationCleanupRequest(
              jobId: jobId,
              key: key,
              publicationId: entry.publicationId,
              kind: imported
                  ? PublicationCleanupKind.imported
                  : PublicationCleanupKind.abandoned,
              verification: intent?.verification);
          // Avoid hashing unresolved publications on every update. Recheck the
          // authority after IO; this first transaction grants no delete rights.
          final destination = await _repository.withCleanupAuthority(request,
              notUpdatedAfter: cutoff,
              clock: _clock,
              action: (path) async => path);
          if (destination == null ||
              !p.equals(
                  await Directory(destination).resolveSymbolicLinks(), root)) {
            kept++;
            continue;
          }
          if (imported) {
            seal = await _files.lock(finalPath!, seal: true);
            final proof = intent!.verification;
            final checked = await hash.hashFileWithControl(File(finalPath),
                control: control);
            if (checked.sizeBytes != proof.fileSizeBytes ||
                checked.digest != proof.contentHash) {
              kept++;
              continue;
            }
            final staged = entry.files['audio.part'];
            if (staged != null &&
                !await FileSystemEntity.identical(staged.path, finalPath)) {
              kept++;
              continue;
            }
          } else if (!await _noFinal(root, entry)) {
            kept++;
            continue;
          }
          control.throwIfCancelled();
          final deleted = await _repository.withCleanupAuthority(request,
              notUpdatedAfter: cutoff,
              clock: _clock, action: (destination) async {
            control.throwIfCancelled();
            if (!p.equals(
                await Directory(destination).resolveSymbolicLinks(), root)) {
              return -1;
            }
            await _paths(root);
            final current = await PublicationJournalEntry.read(directory);
            if (current.retirementRecord != entry.retirementRecord ||
                (imported
                    ? await FileSystemEntity.type(finalPath!,
                            followLinks: false) !=
                        FileSystemEntityType.file
                    : !await _noFinal(root, current))) {
              return -1;
            }
            final staged = current.files['audio.part'];
            if (imported &&
                staged != null &&
                !await FileSystemEntity.identical(staged.path, finalPath!)) {
              return -1;
            }
            if (!current.retiring) {
              await atomicPublicationRecord(
                  File(p.join(directory.path, 'retention.json')),
                  current.retirementRecord,
                  _files);
            }
            // Durable attribution remains until every other known file is gone.
            var freed = 0;
            for (final file in current.files.entries) {
              if (file.key == 'retention.json') continue;
              control.throwIfCancelled();
              await publicationFile(file.value.path);
              freed += await file.value.length();
              await file.value.delete();
            }
            control.throwIfCancelled();
            await File(p.join(directory.path, 'retention.json')).delete();
            await directory.delete();
            return freed;
          });
          if (deleted == null || deleted < 0) {
            kept++;
          } else {
            removed++;
            bytes += deleted;
          }
        } on LibraryScanCancelled {
          rethrow;
        } on PublicationFileException catch (error) {
          if (error.reason == PublicationFileFailure.busy) {
            busy++;
          } else {
            failed++;
          }
        } on PublicationException {
          kept++;
        } on FormatException {
          kept++;
        } on TypeError {
          kept++;
        } on Object {
          failed++;
        } finally {
          // Attempt both releases even if the first one fails.
          await Future.wait(
              [if (seal != null) seal.close(), if (lock != null) lock.close()]);
        }
      }
    } finally {
      await hash.close();
    }
    return PublicationMaintenanceResult(
        removedOperations: removed,
        removedBytes: bytes,
        preserved: kept,
        busy: busy,
        failed: failed);
  }

  Future<bool> _noFinal(String root, PublicationJournalEntry entry) async {
    // Reservation-only staging has not yet selected an audio extension.
    for (final extension in ['mp3', 'm4a', 'flac']) {
      final name = 'cmp-${entry.resourceKey}-${entry.publicationId}.$extension';
      if (await FileSystemEntity.type(p.join(root, name), followLinks: false) !=
          FileSystemEntityType.notFound) {
        return false;
      }
    }
    return true;
  }

  Future<void> _paths(String root) async {
    if (!p.equals(await Directory(root).resolveSymbolicLinks(), root)) {
      throw const PublicationException(PublicationFailure.unsafePath);
    }
    final state = p.join(root, '.cmp-publications-v1');
    for (final path in [
      root,
      state,
      p.join(state, 'locks'),
      p.join(state, 'operations')
    ]) {
      await publicationDirectory(path);
    }
    if (await readPublicationRecord(File(p.join(state, 'owner.json'))) !=
        '{"kind":"clever-music-publications","version":1}') {
      throw const PublicationException(PublicationFailure.unsafePath);
    }
  }

  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _drain();
  }

  Future<void> _drain() async {
    try {
      await _active;
    } on Object {/* Reported by clean. */}
  }
}
