import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/models/models.dart';
import '../domain/repositories/publication_job_access.dart';
import '../domain/repositories/publication_retention_repository.dart';
import '../library/library_scan_control.dart';
import '../library_sync/native_publication_files.dart';
import '../library_sync/publication_intent.dart';
import '../library_sync/publication_journal.dart';
import 'android_publication_receipt.dart';

/// Explicit, app-private receipt journal. No SAF paths are passed to POSIX IO.
/// One OS owner, immutable no-replace records, no startup scan/deletion of music.
final class AndroidPublicationJournal {
  AndroidPublicationJournal._(
      this.root, this._lock, this._files, this.maxRecords);
  final Directory root;
  final PublicationFileLock _lock;
  final PublicationFiles _files;
  final int maxRecords;
  Completer<void>? _active;
  bool _closed = false;
  Future<void>? _closing;
  static const _owner =
      '{"kind":"cmp-android-publication-receipts","version":1}';

  static Future<AndroidPublicationJournal> open(
      {required Directory privateParent,
      PublicationFiles files = const NativePublicationFiles(),
      int maxRecords = 512}) async {
    if (maxRecords < 1 || maxRecords > 512) {
      throw ArgumentError.value(maxRecords);
    }
    await publicationDirectory(privateParent.absolute.path);
    final parent = await privateParent.resolveSymbolicLinks();
    final root = Directory(p.join(parent, 'publication-receipts-v1'));
    final created = await files.createDirectory(root.path);
    await publicationDirectory(root.path);
    final lockFile = File(p.join(root.path, 'owner.lock'));
    try {
      await lockFile.create(exclusive: true);
    } on FileSystemException {
      await publicationFile(lockFile.path);
    }
    final lock = await files.lock(lockFile.path);
    try {
      final owner = File(p.join(root.path, 'owner.json'));
      if (created) await atomicPublicationRecord(owner, _owner, files);
      if (await readPublicationRecord(owner) != _owner) {
        throw const PublicationException(PublicationFailure.invalidJournal);
      }
      final journal =
          AndroidPublicationJournal._(root, lock, files, maxRecords);
      await journal._records();
      return journal;
    } on Object {
      await lock.close();
      rethrow;
    }
  }

  Future<T> _one<T>(Future<T> Function() action) async {
    if (_closed || _active != null) throw StateError('Журнал недоступен.');
    final done = _active = Completer<void>();
    try {
      return await action();
    } finally {
      _active = null;
      done.complete();
    }
  }

  Future<void> _paths() async {
    await publicationDirectory(root.path);
    if (await root.resolveSymbolicLinks() != root.path ||
        await readPublicationRecord(File(p.join(root.path, 'owner.json'))) !=
            _owner) {
      throw const PublicationException(PublicationFailure.unsafePath);
    }
  }

  Future<List<File>> _records() async {
    await _paths();
    final records = <File>[];
    var entries = 0;
    await for (final entry in root.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (name == 'owner.json' || name == 'owner.lock') {
        await publicationFile(entry.path);
        continue;
      }
      if (++entries > maxRecords || entry is! File) {
        throw const PublicationException(PublicationFailure.quotaExceeded);
      }
      await publicationFile(entry.path);
      if (RegExp(r'^journal-[0-9a-f]{64}\.part$').stringMatch(name) == name) {
        // Interrupted writes remain bounded and cannot become receipts.
        if (await entry.length() > 65536) {
          throw const PublicationException(PublicationFailure.invalidJournal);
        }
        continue;
      }
      if (RegExp(r'^[0-9a-f]{64}-[0-9a-f]{64}\.json$').stringMatch(name) !=
          name) {
        throw const PublicationException(PublicationFailure.invalidJournal);
      }
      final receipt = AndroidPublicationReceipt.decode(
          await readPublicationRecord(entry, limit: 65536));
      if (receipt.recordName != name) {
        throw const PublicationException(PublicationFailure.invalidJournal);
      }
      records.add(entry);
    }
    records.sort((a, b) => a.path.compareTo(b.path));
    return records;
  }

  Future<List<AndroidPublicationReceipt>> pending() => _one(() async => [
        for (final file in await _records())
          AndroidPublicationReceipt.decode(
              await readPublicationRecord(file, limit: 65536))
      ]);

  Future<void> record(AndroidPublicationReceipt receipt,
          {required DownloadJob job,
          required PublicationJobAccess jobs,
          required DateTime Function() clock,
          required LibraryScanControl control}) =>
      _one(() async {
        if (receipt.intent.jobId != job.id ||
            receipt.intent.key != job.key ||
            job.stage.index < DownloadJobStage.publication.index) {
          throw const PublicationException(PublicationFailure.invalidJournal);
        }
        control.throwIfCancelled();
        final records = await _records();
        final target = File(p.join(root.path, receipt.recordName));
        if (records.any((file) => file.path == target.path)) {
          if (await readPublicationRecord(target, limit: 65536) !=
              receipt.encode()) {
            throw const PublicationException(PublicationFailure.collision);
          }
          return; // A read-only replay does not claim current job ownership.
        }
        // Include interrupted private writes in the admission bound.
        var count = 0;
        await for (final entry in root.list(followLinks: false)) {
          if (!const {'owner.json', 'owner.lock'}
              .contains(p.basename(entry.path))) {
            count++;
          }
        }
        if (count >= maxRecords) {
          throw const PublicationException(PublicationFailure.quotaExceeded);
        }
        final accepted = await jobs.withOwnedDestination(job, clock: clock,
            action: (destination) async {
          if (destination != receipt.location.tree.storageValue) {
            throw const PublicationException(PublicationFailure.ownershipLost);
          }
          control.throwIfCancelled();
          await _paths();
          await atomicPublicationRecord(target, receipt.encode(), _files);
          return true;
        });
        if (accepted == null) {
          throw const PublicationException(PublicationFailure.ownershipLost);
        }
      });

  /// Only private metadata is removed; a failed/lost acknowledgement preserves
  /// the receipt. This method never calls a document provider or deletes music.
  Future<bool> acknowledge(AndroidPublicationReceipt receipt,
          {required PublicationRetentionRepository retention,
          required DateTime notUpdatedAfter,
          required DateTime Function() clock}) =>
      _one(() async {
        await _records();
        final target = File(p.join(root.path, receipt.recordName));
        if (await FileSystemEntity.type(target.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          return true;
        }
        if (await readPublicationRecord(target, limit: 65536) !=
            receipt.encode()) {
          throw const PublicationException(PublicationFailure.invalidJournal);
        }
        return await retention.withCleanupAuthority(
                PublicationCleanupRequest(
                    jobId: receipt.intent.jobId,
                    key: receipt.intent.key,
                    publicationId: receipt.intent.publicationId,
                    kind: PublicationCleanupKind.imported,
                    verification: receipt.intent.verification,
                    documentLocation: receipt.location),
                notUpdatedAfter: notUpdatedAfter,
                clock: clock, action: (destination) async {
              if (destination != receipt.location.tree.storageValue) {
                return false;
              }
              await _paths();
              await target.delete();
              return true;
            }) ??
            false;
      });

  Future<void> close() {
    _closed = true;
    return _closing ??= _drain();
  }

  Future<void> _drain() async {
    await _active?.future;
    await _lock.close();
  }
}
