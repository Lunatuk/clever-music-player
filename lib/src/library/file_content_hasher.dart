import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'library_scan_control.dart';
import 'sha256_digest.dart';

part 'sha256_hash_session.dart';

/// Worker wall times include IO waits and scheduling, not physical disk/CPU time.
/// Only completed, verified hashes contribute these details to scan metrics.
final class FileHashTimings {
  const FileHashTimings(
      {this.workerUs = 0,
      this.ioUs = 0,
      this.digestUs = 0,
      this.roundTripUs = 0,
      this.startupUs = 0,
      this.workerStarts = 0});
  final int workerUs;
  final int ioUs;
  final int digestUs;
  final int roundTripUs;
  final int startupUs;
  final int workerStarts;

  FileHashTimings _withParent(int totalUs, int startupUs, int workerStarts) =>
      FileHashTimings(
          workerUs: workerUs,
          ioUs: ioUs,
          digestUs: digestUs,
          roundTripUs: totalUs > workerUs ? totalUs - workerUs : 0,
          startupUs: startupUs,
          workerStarts: workerStarts);
}

/// Full-file identity, including tags and embedded artwork. Never a tag hash.
final class FileContentFingerprint {
  const FileContentFingerprint({
    required this.digest,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.changedAt,
    this.backend = Sha256Backend.dart,
    this.timings = const FileHashTimings(),
  });

  final String digest;
  final int sizeBytes;
  final DateTime modifiedAt;
  final DateTime changedAt;
  final Sha256Backend backend;
  final FileHashTimings timings;

  FileContentFingerprint _withParentTiming(
          int totalUs, int startupUs, int starts) =>
      FileContentFingerprint(
          digest: digest,
          sizeBytes: sizeBytes,
          modifiedAt: modifiedAt,
          changedAt: changedAt,
          backend: backend,
          timings: timings._withParent(totalUs, startupUs, starts));

  String get storageKey => 'file-sha256-v1:$sizeBytes:$digest';

  Future<bool> matchesFile(File file) async {
    final stat = await file.stat();
    return stat.type == FileSystemEntityType.file &&
        stat.size == sizeBytes &&
        stat.modified == modifiedAt &&
        stat.changed == changedAt;
  }
}

abstract interface class FileContentHasher {
  Future<FileContentFingerprint> hashFile(File file);
}

final class FileHashProgress {
  const FileHashProgress(this.bytesRead, this.totalBytes);
  final int bytesRead;
  final int totalBytes;
}

abstract interface class ControlledFileContentHasher
    implements FileContentHasher {
  Future<FileContentFingerprint> hashFileWithControl(
    File file, {
    required LibraryScanControl control,
    void Function(FileHashProgress)? onProgress,
  });
}

abstract interface class FileContentHashSession
    implements ControlledFileContentHasher {
  Future<void> close();
}

abstract interface class SessionFileContentHasher {
  FileContentHashSession openSession();
}

final class Sha256FileContentHasher
    implements ControlledFileContentHasher, SessionFileContentHasher {
  const Sha256FileContentHasher({this.preferNative = true});
  final bool preferNative;

  @override
  FileContentHashSession openSession() =>
      Sha256HashSession(preferNative: preferNative);

  @override
  Future<FileContentFingerprint> hashFile(File file) async {
    final timer = Stopwatch()..start();
    final path = file.path;
    final native = preferNative;
    // Both hashing and streaming IO belong to the worker, with bounded memory.
    final result =
        await Isolate.run(() => _hashFile(path, preferNative: native));
    return result._withParentTiming(timer.elapsedMicroseconds, 0, 1);
  }

  @override
  Future<FileContentFingerprint> hashFileWithControl(
    File file, {
    required LibraryScanControl control,
    void Function(FileHashProgress)? onProgress,
  }) async {
    control.throwIfCancelled();
    final timer = Stopwatch()..start();
    var startupUs = 0;
    final port = ReceivePort();
    final result = Completer<FileContentFingerprint>();
    final exited = Completer<void>();
    // Messages can arrive before spawn's Future resumes in the parent.
    result.future.ignore();
    Isolate? worker;
    SendPort? commands;
    final subscription = port.listen((message) {
      if (message == null) {
        if (!exited.isCompleted) exited.complete();
        if (!result.isCompleted) {
          result.completeError(control.isCancellationRequested
              ? const LibraryScanCancelled()
              : StateError('Проверка файла завершилась без результата.'));
        }
      } else if (!result.isCompleted) {
        if (message is SendPort) {
          startupUs = timer.elapsedMicroseconds;
          commands = message;
          if (control.isCancellationRequested) commands!.send(true);
        } else if (message is FileContentFingerprint) {
          if (control.isCancellationRequested) {
            result.completeError(const LibraryScanCancelled());
          } else {
            result.complete(message);
          }
        } else if (message is FileHashProgress) {
          if (!control.isCancellationRequested) onProgress?.call(message);
        } else if (message is _HashFailure) {
          result.completeError(message.error, message.stack);
        } else if (message is List && message.length == 2) {
          result.completeError(RemoteError('${message[0]}', '${message[1]}'));
        }
      }
    });
    void stopWorker() => commands?.send(true);
    control.addCancellationListener(stopWorker);
    late FileContentFingerprint fingerprint;
    try {
      control.throwIfCancelled();
      worker = await Isolate.spawn(
        _hashWorker,
        (file.path, port.sendPort, preferNative),
        onExit: port.sendPort,
        onError: port.sendPort,
        errorsAreFatal: true,
      );
      if (control.isCancellationRequested) stopWorker();
      fingerprint = await result.future;
    } finally {
      control.removeCancellationListener(stopWorker);
      stopWorker();
      if (worker != null) await exited.future;
      await subscription.cancel();
      port.close();
    }
    return fingerprint._withParentTiming(
        timer.elapsedMicroseconds, startupUs, 1);
  }
}

final class _HashFailure {
  const _HashFailure(this.error, this.stack);
  final Object error;
  final StackTrace stack;
}

Future<void> _hashWorker((String, SendPort, bool) request) async {
  final (path, port, native) = request;
  final response = await _controlledHash(path, port, native, 64 * 1024);
  // Exit only after IO cleanup; never kill a worker during async file IO.
  Isolate.exit(port, response);
}

Future<Object> _controlledHash(
    String path, SendPort port, bool native, int bufferSize) async {
  final commands = ReceivePort();
  var cancelled = false;
  final subscription = commands.listen((_) => cancelled = true);
  port.send(commands.sendPort);
  Object response;
  try {
    response = await _hashFile(path,
        onProgress: port.send,
        isCancelled: () => cancelled,
        preferNative: native,
        bufferSize: bufferSize);
  } on Object catch (error, stack) {
    response = _HashFailure(error, stack);
  } finally {
    await subscription.cancel();
    commands.close();
  }
  return response;
}

Future<FileContentFingerprint> _hashFile(
  String path, {
  void Function(FileHashProgress)? onProgress,
  bool Function()? isCancelled,
  bool preferNative = true,
  int bufferSize = 64 * 1024,
}) async {
  final total = Stopwatch()..start();
  final io = Stopwatch();
  final compute = Stopwatch();
  void checkCancellation() {
    if (isCancelled?.call() ?? false) throw const LibraryScanCancelled();
  }

  checkCancellation();
  final file = File(path);
  io.start();
  final before = await file.stat();
  io.stop();
  if (before.type != FileSystemEntityType.file) {
    throw FileSystemException('Файл недоступен для проверки копий.', path);
  }
  var bytesRead = 0;
  final progressTimer = Stopwatch()..start();
  onProgress?.call(FileHashProgress(0, before.size));
  compute.start();
  final conversion = createSha256Digest(preferNative: preferNative);
  compute.stop();
  late final String digest;
  try {
    io.start();
    final input = await file.open();
    io.stop();
    try {
      final buffer = Uint8List(before.size <= 0
          ? 1
          : before.size < bufferSize
              ? before.size
              : bufferSize);
      while (true) {
        checkCancellation();
        io.start();
        final length = await input.readInto(buffer);
        io.stop();
        checkCancellation();
        if (length == 0) break;
        bytesRead += length;
        if (bytesRead > before.size) {
          throw FileSystemException(
              'Файл вырос во время проверки копий.', path);
        }
        if (progressTimer.elapsedMilliseconds >= 100) {
          onProgress?.call(FileHashProgress(bytesRead, before.size));
          progressTimer.reset();
        }
        compute.start();
        conversion.add(length == buffer.length
            ? buffer
            : Uint8List.sublistView(buffer, 0, length));
        compute.stop();
      }
    } finally {
      io.start();
      await input.close();
      io.stop();
    }
    checkCancellation();
    compute.start();
    digest = conversion.finish();
    compute.stop();
  } finally {
    compute.start();
    conversion.dispose();
    compute.stop();
  }
  checkCancellation();
  final fingerprint = FileContentFingerprint(
    digest: digest,
    backend: conversion.backend,
    sizeBytes: bytesRead,
    modifiedAt: before.modified,
    changedAt: before.changed,
  );
  io.start();
  final matches = await fingerprint.matchesFile(file);
  io.stop();
  if (bytesRead != before.size || !matches) {
    throw FileSystemException('Файл изменился во время проверки копий.', path);
  }
  onProgress?.call(FileHashProgress(bytesRead, before.size));
  checkCancellation();
  return FileContentFingerprint(
      digest: digest,
      backend: conversion.backend,
      sizeBytes: bytesRead,
      modifiedAt: before.modified,
      changedAt: before.changed,
      timings: FileHashTimings(
          workerUs: total.elapsedMicroseconds,
          ioUs: io.elapsedMicroseconds,
          digestUs: compute.elapsedMicroseconds));
}

final _verifiedFileHash =
    RegExp(r'^file-sha256-v1:(0|[1-9][0-9]*):[0-9a-f]{64}$');

/// Ignore legacy, imported or incomplete values whose identity is unknown.
String? verifiedFileContentKey(String? value) {
  return value != null && _verifiedFileHash.hasMatch(value) ? value : null;
}
