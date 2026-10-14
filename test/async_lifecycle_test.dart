import 'dart:async';

import 'package:clever_music_player/src/core/async_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracker starts immediately and drains all accepted concurrent work',
      () async {
    final tracker = AsyncOperationTracker();
    final first = Completer<void>();
    final second = Completer<void>();
    var started = 0;
    final a = tracker.run(() {
      started++;
      return first.future;
    });
    final b = tracker.run(() {
      started++;
      return second.future;
    });
    expect(started, 2);
    tracker.closeAdmission();
    var drained = false;
    final closing = tracker.drain().then((_) => drained = true);
    try {
      first.complete();
      await a;
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      await tracker.run(() async {
        fail('Closed admission must not run work');
      });
      second.complete();
      await Future.wait([b, closing]);
      expect(drained, isTrue);
      await tracker.drain();
    } finally {
      if (!first.isCompleted) first.complete();
      if (!second.isCompleted) second.complete();
      await closing;
    }
  });

  test(
      'drain called synchronously from accepted work still waits for that work',
      () async {
    final tracker = AsyncOperationTracker();
    final gate = Completer<void>();
    late Future<void> closing;
    var drained = false;
    final running = tracker.run(() {
      tracker.closeAdmission();
      closing = tracker.drain().then((_) => drained = true);
      return gate.future;
    });
    try {
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      gate.complete();
      await Future.wait([running, closing]);
      expect(drained, isTrue);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await closing;
    }
  });

  for (final sync in [true, false]) {
    test(
        'tracker preserves ${sync ? 'sync' : 'async'} errors without failing drain',
        () async {
      final tracker = AsyncOperationTracker();
      final error = StateError('operation');
      final result = tracker.run(() {
        if (sync) throw error;
        return Future.error(error);
      });
      tracker.closeAdmission();
      await expectLater(result, throwsA(same(error)));
      await tracker.drain();
    });
  }

  test('cleanup attempts every step and preserves first error and stack',
      () async {
    final primary = StateError('first');
    final stack = StackTrace.fromString('first cleanup stack');
    var lastClosed = false;
    try {
      await finishCleanup([
        () => Error.throwWithStackTrace(primary, stack),
        () async {
          throw StateError('later');
        },
        () async {
          lastClosed = true;
        },
      ]);
      fail('Expected first cleanup failure');
    } catch (error, actualStack) {
      expect(error, same(primary));
      expect(actualStack.toString(), contains('first cleanup stack'));
    }
    expect(lastClosed, isTrue);
  });
}
