import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../library/library_scan_control.dart';

enum MediaProcessFailureKind { unavailable, outputLimit, io }

final class MediaProcessFailure implements Exception {
  const MediaProcessFailure(this.kind);
  final MediaProcessFailureKind kind;
}

final class MediaProcessOutput {
  const MediaProcessOutput(this.exitCode, this.stdout,
      {this.hadStderr = false});
  final int exitCode;
  final String stdout;
  final bool hadStderr;
}

abstract interface class MediaProcessRunner {
  Future<MediaProcessOutput> run(
      String executable, List<String> arguments, LibraryScanControl control);
  Future<void> close();
}

/// No shell, one child at a time, bounded output, drain both pipes after kill.
/// Logs/error text are deliberately not exposed in typed failures.
final class BoundedMediaProcessRunner implements MediaProcessRunner {
  BoundedMediaProcessRunner(
      {this.maxStdoutBytes = 256 * 1024, this.maxStderrBytes = 64 * 1024}) {
    if (maxStdoutBytes <= 0 ||
        maxStderrBytes <= 0 ||
        maxStdoutBytes > 1024 * 1024 ||
        maxStderrBytes > 1024 * 1024) {
      throw ArgumentError('Некорректный предел вывода процесса.');
    }
  }
  final int maxStdoutBytes, maxStderrBytes;
  bool _closed = false;
  Completer<void>? _active;
  LibraryScanControl? _control;
  Future<void>? _closing;

  @override
  Future<MediaProcessOutput> run(String executable, List<String> arguments,
      LibraryScanControl control) async {
    if (_closed) throw StateError('Процессы проверки закрыты.');
    if (_active != null) throw StateError('Процесс проверки уже запущен.');
    control.throwIfCancelled();
    final done = Completer<void>();
    _active = done;
    _control = control;
    Process? child;
    var childExited = false;
    void stop() {
      try {
        if (!childExited) child?.kill(ProcessSignal.sigkill);
      } on Object {/* Still drain. */}
    }

    control.addCancellationListener(stop);
    try {
      try {
        child = await Process.start(executable, List.of(arguments),
            runInShell: false, environment: {'AV_LOG_FORCE_NOCOLOR': '1'});
      } on ProcessException {
        control.throwIfCancelled();
        throw const MediaProcessFailure(MediaProcessFailureKind.unavailable);
      }
      final process = child;
      final stdinClosing = process.stdin.close().catchError((Object _) {});
      final stdout = BytesBuilder(copy: false);
      var stdoutBytes = 0;
      var stderrBytes = 0;
      var overflow = false;
      var ioFailure = false;
      Future<void> drain(Stream<List<int>> stream, bool isStdout) {
        final finished = Completer<void>();
        stream.listen((chunk) {
          if (isStdout) {
            stdoutBytes += chunk.length;
            if (stdoutBytes <= maxStdoutBytes && !overflow) stdout.add(chunk);
          } else {
            stderrBytes += chunk.length;
          }
          if (stdoutBytes > maxStdoutBytes || stderrBytes > maxStderrBytes) {
            overflow = true;
            stop();
          }
        }, onError: (Object _) {
          ioFailure = true;
          stop();
        }, onDone: finished.complete);
        return finished.future;
      }

      final outDone = drain(process.stdout, true);
      final errDone = drain(process.stderr, false);
      if (control.isCancellationRequested) stop();
      final int exitCode;
      try {
        exitCode = await process.exitCode;
        childExited = true;
      } finally {
        stop();
        await Future.wait([outDone, errDone, stdinClosing]);
      }
      control.throwIfCancelled();
      if (overflow) {
        throw const MediaProcessFailure(MediaProcessFailureKind.outputLimit);
      }
      if (ioFailure) {
        throw const MediaProcessFailure(MediaProcessFailureKind.io);
      }
      return MediaProcessOutput(exitCode, utf8.decode(stdout.takeBytes()),
          hadStderr: stderrBytes > 0);
    } finally {
      control.removeCancellationListener(stop);
      _control = null;
      _active = null;
      done.complete();
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _drain(_active?.future);
  }

  Future<void> _drain(Future<void>? active) async => await active;
}
