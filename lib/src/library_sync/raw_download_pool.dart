import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../domain/models/audio_source_reference.dart';
import '../library/library_scan_control.dart';
import 'binary_download.dart';
import 'download_workspace.dart';

/// Shared admission for raw downloads, including delivered files still in use.
/// No startup IO/recursive deletion. This is not the prepared/publication quota
/// or an OS disk quota; callers must share one pool and release each result.
final class RawDownloadPool {
  RawDownloadPool(
      {required Directory parent,
      this.workspace,
      this.maxReservedBytes = 512 * 1024 * 1024,
      this.maxFiles = 2})
      : _parent = parent.absolute {
    if (maxReservedBytes <= 0 ||
        maxReservedBytes > 32 * 1024 * 1024 * 1024 ||
        maxFiles <= 0 ||
        maxFiles > 32) {
      throw ArgumentError('Некорректный бюджет загрузки.');
    }
  }
  final Directory _parent;
  final DownloadWorkspace? workspace;
  final int maxReservedBytes, maxFiles;
  int _reservedBytes = 0;
  final _reservations = <RawDownloadReservation>{};
  bool _closed = false;
  int get reservedBytes => _reservedBytes;
  int get reservedFiles => _reservations.length;

  /// Synchronous reservation before opening a connection or creating a file.
  RawDownloadReservation reserve(int maxBytes) {
    if (_closed) {
      throw const BinaryDownloadException(BinaryDownloadFailure.closed);
    }
    if (maxBytes <= 0 || maxBytes > maximumRawDownloadBytes) {
      throw ArgumentError('Некорректный предел файла.');
    }
    if (_reservations.length >= maxFiles ||
        maxBytes > maxReservedBytes - _reservedBytes) {
      throw const BinaryDownloadException(BinaryDownloadFailure.quotaExceeded);
    }
    final DownloadWorkspaceReservation? managed;
    try {
      managed = workspace?.reserve(DownloadWorkspaceStage.raw,
          maxAudioBytes: maxBytes);
    } on DownloadWorkspaceException catch (error) {
      throw BinaryDownloadException(switch (error.failure) {
        DownloadWorkspaceFailure.quotaExceeded =>
          BinaryDownloadFailure.quotaExceeded,
        DownloadWorkspaceFailure.closed => BinaryDownloadFailure.closed,
        DownloadWorkspaceFailure.busy => BinaryDownloadFailure.busy,
        _ => BinaryDownloadFailure.unsafePath,
      });
    }
    final slot = RawDownloadReservation._(this, maxBytes, managed);
    _reservations.add(slot);
    _reservedBytes += maxBytes;
    return slot;
  }

  /// Stops admission. A delivered result belongs to its reader, not the pool:
  /// deleting it during metadata processing would break an accepted operation.
  void closeAdmission() => _closed = true;

  /// Retry only failed cleanups. Delivered/actively written files are retained.
  Future<void> retryFailedCleanup() async {
    BinaryDownloadException? first;
    for (final slot in _reservations.toList(growable: false)) {
      if (!slot._closed) continue;
      try {
        await slot.close();
      } on BinaryDownloadException catch (error) {
        first ??= error;
      }
    }
    if (first != null) throw first;
  }

  void _release(RawDownloadReservation slot) {
    if (_reservations.remove(slot)) _reservedBytes -= slot.maxBytes;
  }
}

/// A single generated file. The lease remains charged until cleanup succeeds.
final class RawDownloadReservation {
  RawDownloadReservation._(this._pool, this.maxBytes, this._managed);
  final RawDownloadPool _pool;
  final int maxBytes;
  final DownloadWorkspaceReservation? _managed;
  final _control = LibraryScanControl();
  Directory? _directory;
  File? _file;
  Future<RawDownloadedAudio>? _active;
  Future<void>? _closing;
  bool _started = false, _closed = false, _ownsFile = false;
  int _written = 0;
  int get bytesWritten => _written;

  Future<RawDownloadedAudio> write(Stream<List<int>> bytes,
      {int? expectedBytes,
      LibraryScanControl? control,
      void Function(BinaryDownloadProgress)? onProgress,
      void Function()? onFlushing}) {
    if (_closed) {
      return Future.error(
          const BinaryDownloadException(BinaryDownloadFailure.closed));
    }
    if (_started) {
      return Future.error(
          const BinaryDownloadException(BinaryDownloadFailure.busy));
    }
    if (expectedBytes != null &&
        (expectedBytes <= 0 || expectedBytes > maxBytes)) {
      return Future.error(
          const BinaryDownloadException(BinaryDownloadFailure.invalidResponse));
    }
    _started = true;
    final result =
        _write(bytes, expectedBytes, control, onProgress, onFlushing);
    result.ignore();
    return _active = result;
  }

  Future<RawDownloadedAudio> _write(
      Stream<List<int>> bytes,
      int? expected,
      LibraryScanControl? external,
      void Function(BinaryDownloadProgress)? onProgress,
      void Function()? onFlushing) async {
    external?.addCancellationListener(_control.cancel);
    RandomAccessFile? output;
    StreamIterator<List<int>>? input;
    Future<void>? cancelling;
    void cancelInput() {
      if (input != null) {
        cancelling ??= input.cancel();
        cancelling!.ignore();
      }
    }

    final progressClock = Stopwatch()..start();
    void progress({bool force = false}) {
      if (_control.isCancellationRequested ||
          (!force && progressClock.elapsedMilliseconds < 200)) {
        return;
      }
      progressClock.reset();
      try {
        onProgress?.call(BinaryDownloadProgress(_written, expected));
      } on Object {
        // A UI observer does not own the transfer or its cleanup.
      }
    }

    try {
      _control.throwIfCancelled();
      final Directory directory;
      if (_managed != null) {
        directory = await _managed.materialize();
      } else {
        final root = await _pool._parent.resolveSymbolicLinks();
        _control.throwIfCancelled();
        if (await FileSystemEntity.type(root, followLinks: false) !=
            FileSystemEntityType.directory) {
          throw const BinaryDownloadException(BinaryDownloadFailure.unsafePath);
        }
        directory = await Directory(root).createTemp('cmp_raw_download_');
      }
      _directory = directory;
      _control.throwIfCancelled();
      _file = File(p.join(directory.path, 'audio.part'));
      await _file!.create(exclusive: true);
      _ownsFile = true;
      _control.throwIfCancelled();
      output = await _file!.open(mode: FileMode.writeOnly);
      input = StreamIterator(bytes);
      _control.addCancellationListener(cancelInput);
      progress(force: true);
      while (await input.moveNext()) {
        _control.throwIfCancelled();
        final chunk = input.current;
        if (chunk.length > maxBytes - _written) {
          throw const BinaryDownloadException(BinaryDownloadFailure.tooLarge);
        }
        if (expected != null && chunk.length > expected - _written) {
          throw const BinaryDownloadException(BinaryDownloadFailure.incomplete);
        }
        for (var offset = 0; offset < chunk.length;) {
          _control.throwIfCancelled();
          final end = min(offset + 64 * 1024, chunk.length);
          await output.writeFrom(chunk, offset, end);
          _written += end - offset;
          offset = end;
          progress();
        }
      }
      _control.throwIfCancelled();
      if (_written == 0 || (expected != null && _written != expected)) {
        throw const BinaryDownloadException(BinaryDownloadFailure.incomplete);
      }
      onFlushing?.call();
      await output.flush();
      await output.close();
      output = null;
      _control.throwIfCancelled();
      if (await FileSystemEntity.type(_file!.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await _file!.length() != _written) {
        throw const BinaryDownloadException(BinaryDownloadFailure.unsafePath);
      }
      _control.throwIfCancelled();
      progress(force: true);
      _control.throwIfCancelled();
      return RawDownloadedAudio._(this, _written);
    } on BinaryDownloadException {
      rethrow;
    } on LibraryScanCancelled {
      throw const BinaryDownloadException(BinaryDownloadFailure.cancelled);
    } on DownloadWorkspaceException catch (error) {
      throw BinaryDownloadException(switch (error.failure) {
        DownloadWorkspaceFailure.quotaExceeded =>
          BinaryDownloadFailure.quotaExceeded,
        DownloadWorkspaceFailure.unsafePath ||
        DownloadWorkspaceFailure.invalidJournal =>
          BinaryDownloadFailure.unsafePath,
        _ => BinaryDownloadFailure.storage,
      });
    } on FileSystemException {
      throw const BinaryDownloadException(BinaryDownloadFailure.storage);
    } on TimeoutException {
      throw const BinaryDownloadException(BinaryDownloadFailure.timeout);
    } on HttpException {
      throw BinaryDownloadException(expected != null && _written < expected
          ? BinaryDownloadFailure.incomplete
          : BinaryDownloadFailure.network);
    } on Object {
      throw const BinaryDownloadException(BinaryDownloadFailure.network);
    } finally {
      external?.removeCancellationListener(_control.cancel);
      _control.removeCancellationListener(cancelInput);
      try {
        try {
          await (cancelling ?? input?.cancel());
        } finally {
          await output?.close();
        }
      } on Object {
        throw const BinaryDownloadException(BinaryDownloadFailure.storage);
      }
    }
  }

  Future<void> close() {
    _closed = true;
    _control.cancel();
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      try {
        await _active;
      } on Object {
        // A failed write still owns its partial file.
      }
      final directory = _directory;
      if (_managed != null) {
        await _managed.close();
      } else if (directory != null) {
        if (await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          throw const BinaryDownloadException(BinaryDownloadFailure.unsafePath);
        }
        final file = _file;
        if (file != null && _ownsFile) {
          final kind =
              await FileSystemEntity.type(file.path, followLinks: false);
          if (kind == FileSystemEntityType.file ||
              kind == FileSystemEntityType.link) {
            await file.delete();
          } else if (kind != FileSystemEntityType.notFound) {
            throw const BinaryDownloadException(
                BinaryDownloadFailure.unsafePath);
          }
        }
        await directory.delete(); // Only our empty directory; never recursive.
      }
      _pool._release(this);
    } on BinaryDownloadException {
      _closing = null; // Explicit retry, with capacity still charged.
      rethrow;
    } on Object {
      _closing = null;
      throw const BinaryDownloadException(BinaryDownloadFailure.storage);
    }
  }
}

/// Transport completion only, not audio/identity/quality verification.
final class RawDownloadedAudio {
  RawDownloadedAudio._(this._reservation, this.sizeBytes);
  final RawDownloadReservation _reservation;
  final int sizeBytes;
  FileAudioSource get source {
    if (_reservation._closed) {
      throw const BinaryDownloadException(BinaryDownloadFailure.closed);
    }
    return FileAudioSource(_reservation._file!.path);
  }

  Future<void> close() => _reservation.close();
  @override
  String toString() => 'RawDownloadedAudio($sizeBytes bytes)';
}
