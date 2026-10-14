part of 'file_content_hasher.dart';

/// Entry point override exists for worker lifecycle/error contract tests.
typedef HashSessionWorkerEntry = void Function((SendPort, bool, int) bootstrap);

/// One lazy worker for one scan. Requests are sequential; concurrent use fails
/// immediately instead of accumulating an unbounded queue. close drains IO.
final class Sha256HashSession implements FileContentHashSession {
  Sha256HashSession(
      {this.preferNative = true,
      this.bufferSize = 256 * 1024,
      HashSessionWorkerEntry workerEntry = _reusableHashWorker})
      : _workerEntry = workerEntry {
    if (bufferSize <= 0 || bufferSize > 1024 * 1024) {
      throw ArgumentError.value(bufferSize, 'bufferSize');
    }
  }
  final bool preferNative;
  final int bufferSize;
  final HashSessionWorkerEntry _workerEntry;
  bool _closed = false, _busy = false, _shutdownSent = false;
  Future<void>? _starting, _closing;
  final _ready = Completer<SendPort>();
  final _exited = Completer<void>();
  Completer<void>? _idle;
  ReceivePort? _events;
  StreamSubscription<dynamic>? _eventSubscription;
  Isolate? _worker;
  SendPort? _requests;
  Object? _failure;
  StackTrace? _failureStack;
  void Function(Object, StackTrace)? _failActive;
  void Function()? _cancelActive;
  int _unreportedStarts = 0, _unreportedStartupUs = 0;

  Future<void> _start() async {
    _ready.future.ignore();
    final events = _events = ReceivePort();
    void fail(Object error, StackTrace stack) {
      _failure ??= error;
      _failureStack ??= stack;
      if (!_ready.isCompleted) _ready.completeError(error, stack);
      _failActive?.call(error, stack);
    }

    _eventSubscription = events.listen((message) {
      if (message is SendPort) {
        if (!_ready.isCompleted) _ready.complete(message);
      } else if (message == null) {
        if (!_exited.isCompleted) _exited.complete();
        if (!_shutdownSent) {
          fail(StateError('Hash worker exited unexpectedly.'),
              StackTrace.current);
        }
      } else if (message is List && message.length == 2) {
        fail(RemoteError('${message[0]}', '${message[1]}'), StackTrace.current);
      }
    });
    try {
      _worker = await Isolate.spawn(
          _workerEntry, (events.sendPort, preferNative, bufferSize),
          onExit: events.sendPort,
          onError: events.sendPort,
          errorsAreFatal: true);
      _requests = await _ready.future;
      if (_failure != null) {
        Error.throwWithStackTrace(_failure!, _failureStack!);
      }
    } on Object catch (error, stack) {
      fail(error, stack);
      rethrow;
    }
  }

  @override
  Future<FileContentFingerprint> hashFile(File file) =>
      hashFileWithControl(file, control: LibraryScanControl());

  @override
  Future<FileContentFingerprint> hashFileWithControl(
    File file, {
    required LibraryScanControl control,
    void Function(FileHashProgress)? onProgress,
  }) async {
    if (_closed) throw StateError('Hash session is closed.');
    if (_busy) throw StateError('Hash session already has an active file.');
    control.throwIfCancelled();
    _busy = true;
    final idle = _idle = Completer<void>();
    final timer = Stopwatch()..start();
    var startupUs = 0, starts = 0;
    var cancelled = false;
    SendPort? commands;
    ReceivePort? replies;
    StreamSubscription<dynamic>? subscription;
    void stop() {
      cancelled = true;
      commands?.send(true);
    }

    _cancelActive = stop;
    control.addCancellationListener(stop);
    try {
      if (_starting == null) {
        starts = 1;
        _starting = _start();
      }
      await _starting;
      if (starts == 1) {
        startupUs = timer.elapsedMicroseconds;
        _unreportedStarts++;
        _unreportedStartupUs += startupUs;
      }
      if (_failure != null) {
        Error.throwWithStackTrace(_failure!, _failureStack!);
      }
      if (_closed || cancelled) throw const LibraryScanCancelled();
      control.throwIfCancelled();
      final result = Completer<FileContentFingerprint>();
      result.future.ignore();
      Object? progressError;
      StackTrace? progressStack;
      void fail(Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      }

      _failActive = fail;
      final port = replies = ReceivePort();
      subscription = port.listen((message) {
        if (message is SendPort) {
          commands = message;
          if (cancelled || _closed) commands!.send(true);
        } else if (!result.isCompleted) {
          if (message is FileHashProgress) {
            if (!cancelled && !_closed) {
              try {
                onProgress?.call(message);
              } on Object catch (error, stack) {
                progressError = error;
                progressStack = stack;
                stop();
              }
            }
          } else if (message is FileContentFingerprint ||
              message is _HashFailure) {
            // A reply is sent only after the file and cancellation port close.
            if (progressError != null) {
              fail(progressError!, progressStack!);
            } else if (_closed ||
                cancelled ||
                control.isCancellationRequested) {
              fail(const LibraryScanCancelled(), StackTrace.current);
            } else if (message is _HashFailure) {
              fail(message.error, message.stack);
            } else {
              result.complete(message as FileContentFingerprint);
            }
          }
        }
      });
      _requests!.send((file.path, port.sendPort));
      final fingerprint = await result.future;
      // A failed/cancelled first file must not hide a reused worker's startup
      // from the next successful hash. Details are aggregated per scan.
      final verified = fingerprint._withParentTiming(
          timer.elapsedMicroseconds, _unreportedStartupUs, _unreportedStarts);
      _unreportedStarts = 0;
      _unreportedStartupUs = 0;
      return verified;
    } finally {
      control.removeCancellationListener(stop);
      _failActive = null;
      _cancelActive = null;
      await subscription?.cancel();
      replies?.close();
      _busy = false;
      idle.complete();
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    _cancelActive?.call();
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      try {
        await _starting;
      } on Object {/* Failed workers still need cleanup. */}
      await _idle?.future;
      if (_worker != null) {
        if (!_exited.isCompleted) {
          _shutdownSent = true;
          _requests?.send(null);
        }
        await _exited.future;
      }
    } finally {
      await _eventSubscription?.cancel();
      _events?.close();
    }
  }
}

Future<void> _reusableHashWorker((SendPort, bool, int) bootstrap) async {
  final (parent, native, bufferSize) = bootstrap;
  final requests = ReceivePort();
  parent.send(requests.sendPort);
  try {
    await for (final message in requests) {
      if (message == null) break;
      final (path, reply) = message as (String, SendPort);
      // A separate command port remains listened to while this stream is
      // paused on file IO, so cancelling the active request cannot be queued.
      final response = await _controlledHash(path, reply, native, bufferSize);
      reply.send(response);
    }
  } finally {
    requests.close();
  }
  Isolate.exit();
}
