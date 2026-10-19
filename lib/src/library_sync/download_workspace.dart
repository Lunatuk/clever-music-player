import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../library/library_scan_control.dart';
import 'binary_download.dart';
import 'native_publication_files.dart';
import 'publication_journal.dart';

enum DownloadWorkspaceFailure {
  closed,
  busy,
  quotaExceeded,
  unsafePath,
  invalidJournal,
  storage
}

final class DownloadWorkspaceException implements Exception {
  const DownloadWorkspaceException(this.failure);
  final DownloadWorkspaceFailure failure;
  @override
  String toString() => 'DownloadWorkspaceException(${failure.name})';
}

enum DownloadWorkspaceStage { raw, prepared, publication }

final class DownloadWorkspaceRecovery {
  const DownloadWorkspaceRecovery(this.removed, this.retained, this.unknown);
  final int removed, retained, unknown;
}

/// Private reference to a publication operation, never an arbitrary delete path.
/// Recovery only observes this directory under its existing OS resource lock.
final class DownloadPublicationReference {
  DownloadPublicationReference(
      {required String destinationRoot, required this.operation})
      : destinationRoot = p.normalize(p.absolute(destinationRoot)) {
    if (destinationRoot.length > 8192 ||
        RegExp(r'^[0-9a-f]{64}-[0-9a-f]{64}$').stringMatch(operation) !=
            operation) {
      throw const DownloadWorkspaceException(
          DownloadWorkspaceFailure.invalidJournal);
    }
  }
  final String destinationRoot, operation;
  @override
  String toString() => 'DownloadPublicationReference(<redacted>)';
}

/// One explicitly opened app-private workspace. Exclusive OS ownership outlives
/// every accepted reader; no age/PID guesses and no automatic startup IO.
/// Data admission is shared by raw/prepared/publication; journal count is bounded
/// separately. This is a reservation budget, not an OS disk quota.
final class DownloadWorkspace {
  DownloadWorkspace._(this.directory, this._lock, this._files,
      this.maxReservedBytes, this.maxEntries, this.preparedGrowthBytes);
  final Directory directory;
  final PublicationFileLock _lock;
  final PublicationFiles _files;
  final int maxReservedBytes, maxEntries, preparedGrowthBytes;
  static const _owner =
      '{"kind":"clever-music-download-workspace","version":1}';
  static const _name = '.cmp-download-workspace-v1';
  static const maxRecordBytes = 32768;
  final _records = <String, _Record>{};
  final _live = <String, DownloadWorkspaceReservation>{};
  Future<void> _tail = Future.value();
  bool _admissionClosed = false,
      _released = false,
      _recovering = false,
      _blocked = false;
  Future<void>? _closing;
  Completer<void>? _drained;
  DownloadWorkspaceRecovery lastRecovery =
      const DownloadWorkspaceRecovery(0, 0, 0);
  int get reservedBytes =>
      _records.values.fold(0, (n, record) => n + record.bytes);
  int get reservedEntries => _records.length;
  bool get admissionBlocked => _blocked;

  /// Caller supplies an app-private existing parent, never the music directory.
  /// Android uses ordinary private paths here, never a SAF content URI.
  static Future<DownloadWorkspace> open(
      {required Directory parent,
      int maxReservedBytes = 2 * 1024 * 1024 * 1024,
      int maxEntries = 128,
      int preparedGrowthBytes = 32 * 1024 * 1024,
      PublicationFiles files = const NativePublicationFiles(),
      LibraryScanControl? control}) async {
    if (maxReservedBytes <= 0 ||
        maxReservedBytes > 64 * 1024 * 1024 * 1024 ||
        maxEntries <= 0 ||
        maxEntries > 512 ||
        preparedGrowthBytes < 0 ||
        preparedGrowthBytes > 256 * 1024 * 1024) {
      throw ArgumentError('Некорректный рабочий бюджет.');
    }
    PublicationFileLock? lock;
    DownloadWorkspace? workspace;
    var returned = false;
    try {
      control?.throwIfCancelled();
      final parentPath = await parent.absolute.resolveSymbolicLinks();
      await _directory(parentPath);
      final root = Directory(p.join(parentPath, _name));
      final created = await files.createDirectory(root.path);
      await _directory(root.path);
      final lockFile = File(p.join(root.path, 'owner.lock'));
      if (await FileSystemEntity.type(lockFile.path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        try {
          await lockFile.create(exclusive: true);
        } on FileSystemException {
          await _file(lockFile.path);
        }
      }
      await _file(lockFile.path);
      lock = await files.lock(lockFile.path);
      final owner = File(p.join(root.path, 'owner.json'));
      if (created) {
        await owner.create(exclusive: true);
        await owner.writeAsString(_owner, flush: true);
      }
      if (await _read(owner) != _owner) {
        _fail(DownloadWorkspaceFailure.unsafePath);
      }
      final operations = Directory(p.join(root.path, 'operations'));
      if (created) await files.createDirectory(operations.path);
      await _directory(operations.path);
      // Drain first-time namespace initialization before observing a late
      // cancellation, so retry never finds an owner-less half-created root.
      control?.throwIfCancelled();
      workspace = DownloadWorkspace._(
          root, lock, files, maxReservedBytes, maxEntries, preparedGrowthBytes);
      await workspace.recover(control: control);
      control?.throwIfCancelled();
      returned = true;
      return workspace;
    } on LibraryScanCancelled {
      rethrow;
    } on DownloadWorkspaceException {
      rethrow;
    } on PublicationFileException catch (error) {
      _fail(error.reason == PublicationFileFailure.busy
          ? DownloadWorkspaceFailure.busy
          : DownloadWorkspaceFailure.storage);
    } on Object {
      _fail(DownloadWorkspaceFailure.storage);
    } finally {
      if (workspace == null) await lock?.close();
      // A failed initial recovery must release ownership, too.
      if (workspace != null && !returned) await workspace.close();
    }
  }

  DownloadWorkspaceReservation reserve(DownloadWorkspaceStage stage,
      {required int maxAudioBytes,
      int maxCoverBytes = 0,
      DownloadPublicationReference? publication}) {
    if (_admissionClosed || _released) _fail(DownloadWorkspaceFailure.closed);
    if (_recovering) _fail(DownloadWorkspaceFailure.busy);
    if (_blocked) _fail(DownloadWorkspaceFailure.invalidJournal);
    final record =
        _Record(_id(), stage, maxAudioBytes, maxCoverBytes, publication);
    if (utf8.encode(record.encode()).length > maxRecordBytes) {
      _fail(DownloadWorkspaceFailure.invalidJournal);
    }
    if (reservedEntries >= maxEntries ||
        record.bytes > maxReservedBytes - reservedBytes) {
      _fail(DownloadWorkspaceFailure.quotaExceeded);
    }
    final lease = DownloadWorkspaceReservation._(this, record);
    _records[record.id] = record;
    _live[record.id] = lease;
    return lease;
  }

  int preparedLimit(int sourceBytes) =>
      min(maximumRawDownloadBytes, sourceBytes + preparedGrowthBytes);

  Future<T> _serial<T>(Future<T> Function() action) {
    if (_released) {
      return Future.error(
          const DownloadWorkspaceException(DownloadWorkspaceFailure.closed));
    }
    final accepted = _tail.then((_) async {
      try {
        if (_released) {
          _fail(DownloadWorkspaceFailure.closed);
        }
        return await action();
      } on DownloadWorkspaceException {
        rethrow;
      } on LibraryScanCancelled {
        rethrow;
      } on Object {
        _fail(DownloadWorkspaceFailure.storage);
      }
    });
    _tail = accepted.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    accepted.ignore();
    return accepted;
  }

  Future<void> _paths() async {
    await _directory(directory.path);
    if (!p.equals(await directory.resolveSymbolicLinks(), directory.path) ||
        await _read(File(p.join(directory.path, 'owner.json'))) != _owner) {
      _fail(DownloadWorkspaceFailure.unsafePath);
    }
    await _directory(p.join(directory.path, 'operations'));
    await _file(p.join(directory.path, 'owner.lock'));
  }

  Future<Directory> _materialize(_Record record) => _serial(() async {
        await _paths();
        final target = _entry(record.id);
        if (!await _files.createDirectory(target.path)) {
          _fail(DownloadWorkspaceFailure.unsafePath);
        }
        final pending = File(p.join(target.path, 'reservation.part'));
        await pending.create(exclusive: true);
        await pending.writeAsString(record.encode(), flush: true);
        await _files.moveNoReplace(
            pending.path, p.join(target.path, 'reservation.json'));
        return target;
      });
  Directory _entry(String id) =>
      Directory(p.join(directory.path, 'operations', id));

  Future<DownloadWorkspaceRecovery> recover({LibraryScanControl? control}) {
    if (_admissionClosed || _released) {
      return Future.error(
          const DownloadWorkspaceException(DownloadWorkspaceFailure.closed));
    }
    if (_recovering) {
      return Future.error(
          const DownloadWorkspaceException(DownloadWorkspaceFailure.busy));
    }
    _recovering = true;
    _blocked =
        true; // A failed/partial scan must never permit undercounted admission.
    final accepted = _serial(() async {
      control?.throwIfCancelled();
      await _paths();
      var removed = 0, retained = 0, unknown = 0, visited = 0;
      await for (final item in directory.list(followLinks: false)) {
        if (!{'owner.json', 'owner.lock', 'operations'}
            .contains(p.basename(item.path))) {
          unknown++;
        }
      }
      await for (final item in Directory(p.join(directory.path, 'operations'))
          .list(followLinks: false)) {
        control?.throwIfCancelled();
        if (++visited > 4096) _fail(DownloadWorkspaceFailure.invalidJournal);
        final id = p.basename(item.path);
        if (_live.containsKey(id)) {
          retained++;
          continue;
        }
        if (item is! Directory || !_validId(id)) {
          unknown++;
          continue;
        }
        try {
          final record = await _record(item);
          if (record == null) {
            await item.delete(); // Already empty; never recursive.
            _records.remove(id);
            removed++;
            continue;
          }
          _records[id] = record;
          if (await _clean(record)) {
            removed++;
          } else {
            retained++;
          }
        } on DownloadWorkspaceException catch (error) {
          if (_records.containsKey(id) &&
              error.failure == DownloadWorkspaceFailure.storage) {
            retained++;
          } else {
            unknown++;
          }
        }
      }
      control?.throwIfCancelled();
      _blocked = unknown > 0;
      return lastRecovery =
          DownloadWorkspaceRecovery(removed, retained, unknown);
    }).whenComplete(() => _recovering = false);
    accepted.ignore();
    return accepted;
  }

  Future<_Record?> _record(Directory target) async {
    await _directory(target.path);
    final children = await _children(target);
    if (children.isEmpty) return null;
    final manifest =
        children['reservation.json'] ?? children['reservation.part'];
    if (manifest == null ||
        (children.containsKey('reservation.json') &&
            children.containsKey('reservation.part'))) {
      _fail(DownloadWorkspaceFailure.invalidJournal);
    }
    final record = _Record.decode(await _read(manifest));
    if (record.id != p.basename(target.path)) {
      _fail(DownloadWorkspaceFailure.invalidJournal);
    }
    if (record.stage == DownloadWorkspaceStage.publication &&
        (children.containsKey('audio.part') ||
            children.containsKey('cover.part'))) {
      _fail(DownloadWorkspaceFailure.invalidJournal);
    }
    if (record.maxCoverBytes == 0 && children.containsKey('cover.part')) {
      _fail(DownloadWorkspaceFailure.invalidJournal);
    }
    return record;
  }

  Future<bool> _clean(_Record record) async {
    await _paths();
    final target = _entry(record.id);
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      final stored = await _record(target);
      if (stored != null && stored.encode() != record.encode()) {
        _fail(DownloadWorkspaceFailure.invalidJournal);
      }
    }
    if (record.publication case final publication?) {
      if (!await _publicationGone(publication)) return false;
    }
    if (type != FileSystemEntityType.notFound) {
      final children =
          await _children(target); // Validate ALL names before deleting any.
      for (final name in [
        'audio.part',
        'cover.part',
        'reservation.part',
        'reservation.json'
      ]) {
        await children[name]?.delete();
      }
      await target.delete();
    }
    _records.remove(record.id);
    return true;
  }

  Future<bool> _publicationGone(DownloadPublicationReference ref) async {
    PublicationFileLock? lock;
    try {
      await _directory(ref.destinationRoot);
      if (!p.equals(await Directory(ref.destinationRoot).resolveSymbolicLinks(),
          ref.destinationRoot)) {
        return false;
      }
      final state = p.join(ref.destinationRoot, '.cmp-publications-v1');
      if (await FileSystemEntity.type(state, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return true;
      }
      await _directory(state);
      if (await _read(File(p.join(state, 'owner.json'))) !=
          '{"kind":"clever-music-publications","version":1}') {
        return false;
      }
      await _directory(p.join(state, 'locks'));
      final lockPath =
          p.join(state, 'locks', '${ref.operation.substring(0, 64)}.lock');
      await _file(lockPath);
      lock = await _files.lock(lockPath);
      final operations = p.join(state, 'operations');
      await _directory(operations);
      final operation = Directory(p.join(operations, ref.operation));
      if (await FileSystemEntity.type(operation.path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return true;
      }
      final entry = await PublicationJournalEntry.read(operation);
      return !entry.files.containsKey('audio.part');
    } on Object {
      return false; // Busy, missing volume, unknown/modified journal: retain charge.
    } finally {
      await lock?.close();
    }
  }

  Future<void> _finish(DownloadWorkspaceReservation lease) {
    if (_admissionClosed && !_live.containsKey(lease._record.id)) {
      return Future.error(
          const DownloadWorkspaceException(DownloadWorkspaceFailure.closed));
    }
    return _serial(() async {
      try {
        if (lease._materializing == null) {
          _records.remove(lease._record.id);
        } else {
          await _clean(lease._record);
        }
      } on DownloadWorkspaceException catch (error) {
        if (error.failure == DownloadWorkspaceFailure.unsafePath ||
            error.failure == DownloadWorkspaceFailure.invalidJournal) {
          _blocked = true;
        }
        rethrow;
      } finally {
        _live.remove(lease._record.id);
        if (_live.isEmpty && _drained != null && !_drained!.isCompleted) {
          _drained!.complete();
        }
      }
    });
  }

  /// Stops admission and waits for readers, not just writers. Failed/retained
  /// cleanup stays journalled/charged and is inspected on the next explicit open.
  Future<void> close() {
    _admissionClosed = true;
    return _closing ??= () async {
      if (_live.isNotEmpty) {
        _drained = Completer<void>();
        await _drained!.future;
      }
      await _tail;
      _released = true;
      await _lock.close();
    }();
  }
}

final class DownloadWorkspaceReservation {
  DownloadWorkspaceReservation._(this._workspace, this._record);
  final DownloadWorkspace _workspace;
  final _Record _record;
  Future<Directory>? _materializing;
  Future<void>? _closing;
  bool _closed = false;
  int get maxAudioBytes => _record.maxAudioBytes;
  Future<Directory> materialize() {
    if (_closed) {
      return Future.error(
          const DownloadWorkspaceException(DownloadWorkspaceFailure.closed));
    }
    final accepted = _materializing ??= _workspace._materialize(_record);
    accepted.ignore();
    return accepted;
  }

  Future<void> close() {
    _closed = true;
    final accepted = _closing ??= () async {
      try {
        try {
          await _materializing;
        } on Object {/* Partial creation is still owned. */}
        await _workspace._finish(this);
      } on Object {
        _closing = null;
        rethrow;
      }
    }();
    accepted.ignore();
    return accepted;
  }

  @override
  String toString() =>
      'DownloadWorkspaceReservation(${_record.stage.name}, <redacted>)';
}

final class _Record {
  _Record(this.id, this.stage, this.maxAudioBytes, this.maxCoverBytes,
      this.publication) {
    if (!_validId(id) ||
        maxAudioBytes <= 0 ||
        maxAudioBytes > maximumRawDownloadBytes ||
        maxCoverBytes < 0 ||
        maxCoverBytes > 8 * 1024 * 1024 ||
        (stage != DownloadWorkspaceStage.prepared && maxCoverBytes != 0) ||
        ((stage == DownloadWorkspaceStage.publication) !=
            (publication != null))) {
      _fail(DownloadWorkspaceFailure.invalidJournal);
    }
  }
  final String id;
  final DownloadWorkspaceStage stage;
  final int maxAudioBytes, maxCoverBytes;
  final DownloadPublicationReference? publication;
  int get bytes => maxAudioBytes + maxCoverBytes;
  String encode() => jsonEncode({
        'version': 1,
        'id': id,
        'stage': stage.name,
        'audioBytes': maxAudioBytes,
        'coverBytes': maxCoverBytes,
        'publication': publication == null
            ? null
            : {
                'root': publication!.destinationRoot,
                'operation': publication!.operation
              }
      });
  static _Record decode(String value) {
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      final ref = data['publication'] as Map<String, dynamic>?;
      final result = _Record(
          data['id'] as String,
          DownloadWorkspaceStage.values.byName(data['stage'] as String),
          data['audioBytes'] as int,
          data['coverBytes'] as int,
          ref == null
              ? null
              : DownloadPublicationReference(
                  destinationRoot: ref['root'] as String,
                  operation: ref['operation'] as String));
      if (result.encode() != value) {
        _fail(DownloadWorkspaceFailure.invalidJournal);
      }
      return result;
    } on Object {
      _fail(DownloadWorkspaceFailure.invalidJournal);
    }
  }
}

Future<Map<String, File>> _children(Directory target) async {
  final result = <String, File>{};
  await for (final child in target.list(followLinks: false)) {
    final name = p.basename(child.path);
    if (!{'audio.part', 'cover.part', 'reservation.json', 'reservation.part'}
            .contains(name) ||
        child is! File ||
        await FileSystemEntity.type(child.path, followLinks: false) !=
            FileSystemEntityType.file) {
      _fail(DownloadWorkspaceFailure.unsafePath);
    }
    result[name] = child;
  }
  return result;
}

Future<String> _read(File file) async {
  await _file(file.path);
  final handle = await file.open();
  try {
    if (await handle.length() > DownloadWorkspace.maxRecordBytes) {
      _fail(DownloadWorkspaceFailure.invalidJournal);
    }
    final data = await handle.read(DownloadWorkspace.maxRecordBytes + 1);
    if (data.length > DownloadWorkspace.maxRecordBytes) {
      _fail(DownloadWorkspaceFailure.invalidJournal);
    }
    try {
      return utf8.decode(data);
    } on FormatException {
      _fail(DownloadWorkspaceFailure.invalidJournal);
    }
  } finally {
    await handle.close();
  }
}

Future<void> _directory(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.directory) {
    _fail(DownloadWorkspaceFailure.unsafePath);
  }
}

Future<void> _file(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) {
    _fail(DownloadWorkspaceFailure.unsafePath);
  }
}

bool _validId(String id) => RegExp(r'^[0-9a-f]{64}$').stringMatch(id) == id;
String _id() {
  final random = Random.secure();
  return List.generate(
      32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

Never _fail(DownloadWorkspaceFailure failure) =>
    throw DownloadWorkspaceException(failure);
