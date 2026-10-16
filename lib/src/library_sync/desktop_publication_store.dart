import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../domain/models/download_job.dart';
import '../domain/models/downloaded_asset.dart';
import '../domain/repositories/publication_job_access.dart';
import '../library/file_content_hasher.dart';
import '../library/library_scan_control.dart';
import 'native_publication_files.dart';
import 'publication_intent.dart';
import 'publication_journal.dart';

/// No automatic startup work. One workspace, OS resource lock, drained close.
final class DesktopPublicationStore {
  DesktopPublicationStore(
      {required PublicationJobAccess jobs,
      PublicationFiles files = const NativePublicationFiles(),
      PublicationRetentionPolicy? retentionPolicy,
      DateTime Function()? clock})
      : _jobs = jobs,
        _files = files,
        _retentionPolicy = retentionPolicy ?? PublicationRetentionPolicy(),
        _clock = clock ?? DateTime.now;
  final PublicationJobAccess _jobs;
  final PublicationFiles _files;
  final PublicationRetentionPolicy _retentionPolicy;
  final DateTime Function() _clock;
  bool _closed = false;
  LibraryScanControl? _control;
  Completer<void>? _active;
  Future<void>? _closing;

  Future<T> run<T>(
      DownloadJob job, Future<T> Function(PublicationWorkspace) action,
      {LibraryScanControl? control}) async {
    if (_closed) throw StateError('Публикация закрыта.');
    if (_active != null) throw StateError('Публикация уже выполняется.');
    if (!job.isExecuting ||
        job.attemptToken == null ||
        job.leaseUntil == null) {
      throw const PublicationException(PublicationFailure.ownershipLost);
    }
    final done = Completer<void>();
    _active = done;
    final operation = LibraryScanControl();
    _control = operation;
    void cancel() => operation.cancel();
    control?.addCancellationListener(cancel);
    PublicationWorkspace? workspace;
    try {
      operation.throwIfCancelled();
      workspace = await _jobs.withOwnedDestination(job, clock: _clock,
          action: (path) async {
        operation.throwIfCancelled();
        final root = await Directory(path).resolveSymbolicLinks();
        await _directory(root);
        final state = p.join(root, '.cmp-publications-v1');
        final created = await _files.createDirectory(state);
        await _directory(state);
        final owner = File(p.join(state, 'owner.json'));
        if (created) {
          await _atomic(owner,
              '{"kind":"clever-music-publications","version":1}', _files);
        }
        await _file(owner.path);
        if (await _readSmall(owner) !=
            '{"kind":"clever-music-publications","version":1}') {
          throw const PublicationException(PublicationFailure.unsafePath);
        }
        for (final child in ['locks', 'operations']) {
          final target = p.join(state, child);
          await _files.createDirectory(target);
          await _directory(target);
        }
        final lockFile = File(
            p.join(state, 'locks', '${publicationResourceKey(job.key)}.lock'));
        try {
          await lockFile.create(exclusive: true);
        } on FileSystemException {
          await _file(lockFile.path);
        }
        await _file(lockFile.path);
        final lock = await _files.lock(lockFile.path);
        return workspace = PublicationWorkspace._(root, job, _jobs, _files,
            _clock, operation, lock, _retentionPolicy);
      });
      final acquired = workspace;
      if (acquired == null) {
        throw const PublicationException(PublicationFailure.ownershipLost);
      }
      operation.throwIfCancelled();
      return await action(acquired);
    } on PublicationFileException catch (error) {
      throw PublicationException(_nativeFailure(error.reason));
    } on FileSystemException {
      throw const PublicationException(PublicationFailure.io);
    } finally {
      control?.removeCancellationListener(cancel);
      try {
        await workspace?._close();
      } finally {
        _control = null;
        _active = null;
        done.complete();
      }
    }
  }

  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _drain(_active?.future);
  }

  Future<void> _drain(Future<void>? active) async => await active;
}

final class PublicationWorkspace {
  PublicationWorkspace._(this.root, this.job, this._jobs, this._files,
      this._clock, this.control, this._lock, this._retentionPolicy);
  final String root;
  final DownloadJob job;
  final PublicationJobAccess _jobs;
  final PublicationFiles _files;
  final DateTime Function() _clock;
  final LibraryScanControl control;
  final PublicationFileLock _lock;
  final PublicationRetentionPolicy _retentionPolicy;
  final String publicationId = _randomId();
  final FileContentHashSession _hash =
      const Sha256FileContentHasher().openSession();
  bool _closed = false, _busy = false, _started = false, _sealed = false;
  Completer<void>? _operationDone;
  String get _operation => p.join(root, '.cmp-publications-v1', 'operations',
      '${publicationResourceKey(job.key)}-$publicationId');
  String get stagingPath => p.join(_operation, 'audio.part');

  Future<T> _one<T>(Future<T> Function() action) {
    if (_closed) return Future.error(StateError('Рабочая область закрыта.'));
    if (_busy) return Future.error(StateError('Операция уже выполняется.'));
    _busy = true;
    final done = Completer<void>();
    _operationDone = done;
    final operation = () async {
      try {
        return await action();
      } on PublicationFileException catch (error) {
        throw PublicationException(_nativeFailure(error.reason));
      } on FileSystemException {
        throw const PublicationException(PublicationFailure.io);
      } on FormatException {
        throw const PublicationException(PublicationFailure.invalidJournal);
      } finally {
        _busy = false;
        _operationDone = null;
        done.complete();
      }
    }();
    operation.ignore();
    return operation;
  }

  /// Own and close the writer; audio extensions appear only after publication.
  Future<File> writeAudio(Stream<List<int>> input,
          {required int expectedSize}) =>
      _one(() async {
        control.throwIfCancelled();
        if (_started ||
            expectedSize <= 0 ||
            expectedSize > 8 * 1024 * 1024 * 1024) {
          throw const PublicationException(PublicationFailure.invalidStaging);
        }
        await _paths();
        await reservePublication(
            root,
            PublicationReservation(
                jobId: job.id,
                key: job.key,
                publicationId: publicationId,
                sizeBytes: expectedSize,
                createdAt: _clock()),
            _retentionPolicy,
            _files,
            control);
        _started = true;
        final file = File(stagingPath);
        await file.create(exclusive: true);
        final output = await file.open(mode: FileMode.writeOnly);
        final iterator = StreamIterator(input);
        var written = 0, emptyChunks = 0;
        try {
          while (await _next(iterator, control)) {
            final chunk = iterator.current;
            if (chunk.isEmpty) {
              if (++emptyChunks >= 16) {
                throw const PublicationException(
                    PublicationFailure.invalidStaging);
              }
              continue;
            }
            emptyChunks = 0;
            if (chunk.length > expectedSize - written ||
                chunk.any((byte) => byte < 0 || byte > 255)) {
              throw const PublicationException(
                  PublicationFailure.invalidStaging);
            }
            for (var offset = 0; offset < chunk.length; offset += 256 * 1024) {
              control.throwIfCancelled();
              await output.writeFrom(
                  chunk, offset, min(offset + 256 * 1024, chunk.length));
            }
            written += chunk.length;
          }
          control.throwIfCancelled();
          if (written != expectedSize) {
            throw const PublicationException(PublicationFailure.invalidStaging);
          }
          await output.flush();
        } finally {
          try {
            await iterator.cancel();
          } finally {
            await output.close();
          }
        }
        return file;
      });

  Future<PublicationReceipt> publish(
          DownloadJob current, DownloadedAssetVerification proof) =>
      _one(() async {
        control.throwIfCancelled();
        if (!_started ||
            _sealed ||
            current.id != job.id ||
            current.key != job.key ||
            current.attemptToken != job.attemptToken ||
            current.accountId != job.accountId ||
            current.accountRevision != job.accountRevision ||
            current.state != DownloadJobState.running ||
            current.stage != DownloadJobStage.publication) {
          throw const PublicationException(PublicationFailure.invalidStaging);
        }
        final attempts = await _jobs.listAttempts(current.id, limit: 1);
        if (attempts.isEmpty ||
            attempts.single.token != current.attemptToken ||
            proof.checkedAt.isBefore(attempts.single.startedAt) ||
            proof.checkedAt.isAfter(_clock())) {
          throw const PublicationException(PublicationFailure.ownershipLost);
        }
        final intent = PublicationIntent(
            publicationId: publicationId,
            jobId: current.id,
            key: current.key,
            verification: proof);
        await _paths();
        await _directory(_operation);
        await _file(stagingPath);
        final seal = await _files.lock(stagingPath, seal: true);
        var accepted = false;
        try {
          await _matches(File(stagingPath), proof, control);
          control.throwIfCancelled();
          _sealed = true;
          await _atomic(
              File(p.join(_operation, 'intent.json')), intent.encode(), _files);
          control.throwIfCancelled();
          final applied = await _jobs.withOwnedDestination(current,
              clock: _clock, action: (path) async {
            await _boundDestination(path);
            control.throwIfCancelled();
            final target = File(p.join(root, intent.fileName));
            if (await FileSystemEntity.type(target.path, followLinks: false) !=
                FileSystemEntityType.notFound) {
              throw const PublicationException(PublicationFailure.collision);
            }
            control.throwIfCancelled();
            accepted = true; // A failure may now have left a physical effect.
            await _files.moveNoReplace(stagingPath, target.path);
            return true;
          });
          if (applied == null) {
            throw const PublicationException(PublicationFailure.ownershipLost);
          }
          // Cancellation after the accepted effect drains proof/receipt; report the
          // real publication, not a misleading 'cancelled without changes'.
          final target = File(p.join(root, intent.fileName));
          await _matches(target, proof, LibraryScanControl());
          await _atomic(File(p.join(_operation, 'published.json')),
              intent.encode(), _files);
          return PublicationReceipt(
              intent: intent,
              filePath: target.path,
              verification: proof,
              recovered: false);
        } on Object {
          if (accepted) {
            throw const PublicationException(
                PublicationFailure.needsReconciliation);
          }
          rethrow;
        } finally {
          await seal.close();
        }
      });

  /// Explicit recovery only. Never guesses that an incomplete staging file is
  /// ready or overwrites a conflicting target. No Track/job completion here.
  Future<PublicationReceipt> reconcile(DownloadJob current, String id) =>
      _one(() async {
        control.throwIfCancelled();
        if (!isPublicationId(id) ||
            current.id != job.id ||
            current.key != job.key ||
            current.attemptToken != job.attemptToken ||
            current.accountId != job.accountId ||
            current.accountRevision != job.accountRevision ||
            !current.isExecuting ||
            current.stage.index < DownloadJobStage.publication.index) {
          throw const PublicationException(PublicationFailure.invalidJournal);
        }
        await _paths();
        final directory = p.join(root, '.cmp-publications-v1', 'operations',
            '${publicationResourceKey(job.key)}-$id');
        await _directory(directory);
        final intent =
            (await PublicationJournalEntry.read(Directory(directory))).intent;
        if (intent == null) {
          throw const PublicationException(PublicationFailure.invalidJournal);
        }
        if (intent.jobId != current.id ||
            intent.key != current.key ||
            intent.publicationId != id) {
          throw const PublicationException(PublicationFailure.invalidJournal);
        }
        final target = File(p.join(root, intent.fileName));
        await _file(target.path);
        final seal = await _files.lock(target.path, seal: true);
        try {
          await _matches(target, intent.verification, control);
          final original = File(p.join(directory, 'audio.part'));
          final originalType =
              await FileSystemEntity.type(original.path, followLinks: false);
          if (originalType != FileSystemEntityType.notFound &&
              (originalType != FileSystemEntityType.file ||
                  !await FileSystemEntity.identical(
                      original.path, target.path))) {
            throw const PublicationException(PublicationFailure.collision);
          }
          final marker = File(p.join(directory, 'published.json'));
          if (await marker.exists()) {
            await _file(marker.path);
            if (await _readSmall(marker) != intent.encode()) {
              throw const PublicationException(
                  PublicationFailure.invalidJournal);
            }
          }
          final applied = await _jobs.withOwnedDestination(current,
              clock: _clock, action: (path) async {
            await _boundDestination(path);
            control.throwIfCancelled();
            if (!await marker.exists()) {
              await _atomic(marker, intent.encode(), _files);
            }
            return true;
          });
          if (applied == null) {
            throw const PublicationException(PublicationFailure.ownershipLost);
          }
          final old = intent.verification;
          final checked = DownloadedAssetVerification(
              actualQuality: old.actualQuality,
              container: old.container,
              codec: old.codec,
              fileSizeBytes: old.fileSizeBytes,
              duration: old.duration,
              contentHash: old.contentHash,
              checkedAt: _clock());
          return PublicationReceipt(
              intent: intent,
              filePath: target.path,
              verification: checked,
              recovered: true);
        } finally {
          await seal.close();
        }
      });

  Future<List<String>> pendingPublications() => _one(() async {
        await _paths();
        control.throwIfCancelled();
        final ids = <String>[];
        final prefix = '${publicationResourceKey(job.key)}-';
        var visited = 0;
        await for (final entry
            in Directory(p.join(root, '.cmp-publications-v1', 'operations'))
                .list(followLinks: false)) {
          control.throwIfCancelled();
          if (++visited > 10000) {
            throw const PublicationException(PublicationFailure.invalidJournal);
          }
          final name = p.basename(entry.path);
          if (entry is Directory &&
              name.startsWith(prefix) &&
              isPublicationId(name.substring(prefix.length))) {
            final intent = (await PublicationJournalEntry.read(entry)).intent;
            if (intent != null) {
              if (intent.jobId == job.id && intent.key == job.key) {
                ids.add(intent.publicationId);
              }
              if (ids.length > 256) {
                throw const PublicationException(
                    PublicationFailure.invalidJournal);
              }
            }
          }
        }
        ids.sort();
        return List.unmodifiable(ids);
      });

  Future<PublicationIntent> readIntent(String id) => _one(() async {
        control.throwIfCancelled();
        if (!isPublicationId(id)) {
          throw const PublicationException(PublicationFailure.invalidJournal);
        }
        await _paths();
        final folder = p.join(root, '.cmp-publications-v1', 'operations',
            '${publicationResourceKey(job.key)}-$id');
        await _directory(folder);
        final intent =
            (await PublicationJournalEntry.read(Directory(folder))).intent;
        if (intent == null) {
          throw const PublicationException(PublicationFailure.invalidJournal);
        }
        if (intent.jobId != job.id ||
            intent.key != job.key ||
            intent.publicationId != id) {
          throw const PublicationException(PublicationFailure.invalidJournal);
        }
        return intent;
      });

  Future<void> _paths() async {
    if (!p.equals(await Directory(root).resolveSymbolicLinks(), root)) {
      throw const PublicationException(PublicationFailure.unsafePath);
    }
    for (final path in [
      root,
      p.join(root, '.cmp-publications-v1'),
      p.join(root, '.cmp-publications-v1', 'locks'),
      p.join(root, '.cmp-publications-v1', 'operations')
    ]) {
      await _directory(path);
    }
  }

  Future<void> _boundDestination(String path) async {
    if (!p.equals(await Directory(path).resolveSymbolicLinks(), root)) {
      throw const PublicationException(PublicationFailure.ownershipLost);
    }
    await _paths();
  }

  Future<void> _matches(File file, DownloadedAssetVerification proof,
      LibraryScanControl token) async {
    await _file(file.path);
    if (await file.length() != proof.fileSizeBytes) {
      throw const PublicationException(PublicationFailure.changed);
    }
    final hash = await _hash.hashFileWithControl(file, control: token);
    if (hash.sizeBytes != proof.fileSizeBytes ||
        hash.digest != proof.contentHash) {
      throw const PublicationException(PublicationFailure.changed);
    }
  }

  Future<void> _close() async {
    _closed = true;
    control.cancel();
    await _operationDone?.future;
    await Future.wait(
        [Future<void>.sync(_hash.close), Future<void>.sync(_lock.close)]);
  }
}

Future<void> _directory(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const PublicationException(PublicationFailure.unsafePath);
  }
}

Future<void> _file(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const PublicationException(PublicationFailure.unsafePath);
  }
}

Future<String> _readSmall(File file) async {
  await _file(file.path);
  final input = await file.open();
  try {
    if (await input.length() > 16384) {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
    final bytes = await input.read(16385);
    if (bytes.length > 16384 || (await input.read(1)).isNotEmpty) {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
    return utf8.decode(bytes);
  } finally {
    await input.close();
  }
}

Future<void> _atomic(File target, String value, PublicationFiles files) async {
  final temporary =
      File(p.join(target.parent.path, 'journal-${_randomId()}.part'));
  await temporary.create(exclusive: true);
  await temporary.writeAsString(value, flush: true);
  await files.moveNoReplace(temporary.path, target.path);
}

String _randomId() {
  final random = Random.secure();
  return List.generate(
      32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

PublicationFailure _nativeFailure(PublicationFileFailure reason) =>
    switch (reason) {
      PublicationFileFailure.busy => PublicationFailure.busy,
      PublicationFileFailure.collision => PublicationFailure.collision,
      PublicationFileFailure.unsupported => PublicationFailure.unsupported,
      _ => PublicationFailure.io,
    };
Future<bool> _next(
    StreamIterator<List<int>> iterator, LibraryScanControl control) async {
  control.throwIfCancelled();
  final cancelled = Completer<bool>();
  void stop() {
    if (!cancelled.isCompleted) cancelled.complete(false);
  }

  control.addCancellationListener(stop);
  try {
    final next = iterator.moveNext();
    next.ignore();
    final result = await Future.any([next, cancelled.future]);
    control.throwIfCancelled();
    return result;
  } finally {
    control.removeCancellationListener(stop);
  }
}
