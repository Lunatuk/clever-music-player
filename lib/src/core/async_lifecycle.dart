import 'dart:async';

/// Tracks accepted work without serializing it or delaying foreground commands.
/// Owners close admission synchronously, stop their event sources, then drain.
final class AsyncOperationTracker {
  final Set<Future<void>> _pending = {};
  bool _closed = false;

  Future<void> run(Future<void> Function() action) {
    if (_closed) return Future<void>.value();
    // Register before invoking user code: it can synchronously request shutdown.
    final settled = Completer<void>();
    _pending.add(settled.future);
    final result = Future<void>.sync(action);
    void finish() {
      _pending.remove(settled.future);
      settled.complete();
    }

    unawaited(result.then<void>((_) => finish(),
        onError: (Object _, StackTrace __) => finish()));
    // Callers still receive the original result/error. Drain waits for settled
    // operations so one failure cannot skip waiting for the others.
    return result;
  }

  void closeAdmission() => _closed = true;

  Future<void> drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList(growable: false));
    }
  }
}

/// Attempt every cleanup step, retaining the first error and its stack.
Future<void> finishCleanup(Iterable<Future<void> Function()> actions) async {
  Object? firstError;
  StackTrace? firstStack;
  for (final action in actions) {
    try {
      await Future<void>.sync(action);
    } on Object catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
  }
  if (firstError != null) {
    Error.throwWithStackTrace(firstError, firstStack!);
  }
}
