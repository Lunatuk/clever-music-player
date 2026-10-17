import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/binary_download.dart';
import 'package:clever_music_player/src/library_sync/raw_download_pool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late RawDownloadPool pool;
  final slots = <RawDownloadReservation>[];
  setUp(() async {
    slots.clear();
    root = await Directory.systemTemp.createTemp('cmp_raw_pool_');
    pool = RawDownloadPool(parent: root, maxReservedBytes: 16, maxFiles: 2);
  });
  tearDown(() async {
    for (final slot in slots) {
      await slot.close();
    }
    await root.delete(recursive: true); // Exclusively this test's root.
  });
  RawDownloadReservation reserve([int limit = 8]) {
    final slot = pool.reserve(limit);
    slots.add(slot);
    return slot;
  }

  test('reservation is synchronous and performs no filesystem IO', () async {
    reserve();
    reserve();
    expect(pool.reservedBytes, 16);
    expect(pool.reservedFiles, 2);
    expect(await root.list().toList(), isEmpty);
    expect(() => pool.reserve(1), _throws(BinaryDownloadFailure.quotaExceeded));
  });
  test('byte ceiling is shared independently of file count', () {
    reserve(12);
    expect(() => pool.reserve(5), _throws(BinaryDownloadFailure.quotaExceeded));
    reserve(4);
    expect(pool.reservedBytes, 16);
  });
  for (final limit in [0, -1, maximumRawDownloadBytes + 1]) {
    test('invalid reservation $limit creates no owned resource', () {
      expect(() => pool.reserve(limit), throwsArgumentError);
      expect(pool.reservedBytes, 0);
    });
  }
  test('delivered bytes retain their reservation until the reader closes',
      () async {
    final raw = await reserve().write(
        Stream.fromIterable([
          [0, 255],
          [128]
        ]),
        expectedBytes: 3);
    final source = raw.source;
    expect(await File(source.path).readAsBytes(), [0, 255, 128]);
    expect(raw.sizeBytes, 3);
    expect(pool.reservedBytes, 8);
    expect(raw.toString(), isNot(contains(root.path)));
    final closing = raw.close();
    expect(identical(closing, raw.close()), isTrue);
    await closing;
    expect(pool.reservedBytes, 0);
    expect(await File(source.path).exists(), isFalse);
    expect(() => raw.source, _throws(BinaryDownloadFailure.closed));
    expect(await root.list().toList(), isEmpty);
  });
  test('unknown-length stream is bounded and empty EOF is rejected', () async {
    final raw = await reserve(3).write(Stream.value([1, 2, 3]));
    expect(raw.sizeBytes, 3);
    await raw.close();
    final slot = reserve();
    await expectLater(slot.write(const Stream.empty()),
        _throws(BinaryDownloadFailure.incomplete));
    await slot.close();
    expect(pool.reservedBytes, 0);
  });
  for (final expected in [null, 3]) {
    test('overflow is rejected before writing its offending chunk ($expected)',
        () async {
      final slot = reserve(expected == null ? 3 : 8);
      await expectLater(
          slot.write(
              Stream.fromIterable([
                [1, 2],
                [3, 4]
              ]),
              expectedBytes: expected),
          _throws(expected == null
              ? BinaryDownloadFailure.tooLarge
              : BinaryDownloadFailure.incomplete));
      expect(slot.bytesWritten, 2);
      await slot.close();
      expect(await root.list().toList(), isEmpty);
    });
  }
  test('short EOF never produces a delivered source', () async {
    final slot = reserve();
    await expectLater(slot.write(Stream.value([1]), expectedBytes: 2),
        _throws(BinaryDownloadFailure.incomplete));
    await slot.close();
    expect(pool.reservedBytes, 0);
  });
  test('a reservation cannot be written twice', () async {
    final slot = reserve();
    final raw = await slot.write(Stream.value([1]));
    await expectLater(
        slot.write(Stream.value([2])), _throws(BinaryDownloadFailure.busy));
    expect(await File(raw.source.path).readAsBytes(), [1]);
  });
  test('cancellation before IO does not create files', () async {
    final slot = reserve();
    await expectLater(
        slot.write(Stream.value([1]), control: LibraryScanControl()..cancel()),
        _throws(BinaryDownloadFailure.cancelled));
    expect(await root.list().toList(), isEmpty);
  });
  test('cancellation interrupts a stalled stream and drains its subscription',
      () async {
    final slot = reserve();
    final input = StreamController<List<int>>();
    final cancelled = Completer<void>();
    input.onCancel = cancelled.complete;
    final control = LibraryScanControl();
    final writing = slot.write(input.stream, control: control);
    input.add([1]);
    await _until(() => slot.bytesWritten == 1);
    control.cancel();
    await expectLater(writing, _throws(BinaryDownloadFailure.cancelled));
    await cancelled.future;
    await slot.close();
    await input.close();
    expect(pool.reservedBytes, 0);
  });
  test('close cancels an accepted write before freeing its capacity', () async {
    final slot = reserve();
    final input = StreamController<List<int>>();
    final writing = slot.write(input.stream);
    input.add([1]);
    await _until(() => slot.bytesWritten == 1);
    final closing = slot.close();
    await expectLater(writing, _throws(BinaryDownloadFailure.cancelled));
    await closing;
    await input.close();
    expect(pool.reservedBytes, 0);
    expect(await root.list().toList(), isEmpty);
  });
  test('cancel at flush never delivers a completed source', () async {
    final control = LibraryScanControl();
    final slot = reserve();
    await expectLater(
        slot.write(Stream.value([1]),
            control: control, onFlushing: control.cancel),
        _throws(BinaryDownloadFailure.cancelled));
  });
  test('observer errors do not break output; progress is numeric and final',
      () async {
    final seen = <BinaryDownloadProgress>[];
    final raw = await reserve().write(
        Stream.fromIterable([
          [1],
          [2],
          [3]
        ]),
        expectedBytes: 3, onProgress: (value) {
      seen.add(value);
      throw StateError('PRIVATE observer message');
    });
    expect(seen.first.receivedBytes, 0);
    expect(seen.last.receivedBytes, raw.sizeBytes);
    expect(seen.last.totalBytes, 3);
  });
  test('unknown file prevents cleanup and capacity remains charged for retry',
      () async {
    final raw = await reserve(16).write(Stream.value([1]));
    final unknown = File(p.join(p.dirname(raw.source.path), 'keep.txt'));
    await unknown.writeAsString('preserve');
    await expectLater(raw.close(), _throws(BinaryDownloadFailure.storage));
    expect(await unknown.readAsString(), 'preserve');
    expect(pool.reservedBytes, 16);
    expect(() => pool.reserve(1), _throws(BinaryDownloadFailure.quotaExceeded));
    await unknown.delete(); // Test-created file, never removed by the pool.
    await pool.retryFailedCleanup();
    expect(pool.reservedBytes, 0);
  });
  test('pool admission close and retry never delete a delivered reader',
      () async {
    final raw = await reserve().write(Stream.value([1]));
    pool.closeAdmission();
    await pool.retryFailedCleanup();
    expect(() => pool.reserve(1), _throws(BinaryDownloadFailure.closed));
    expect(await File(raw.source.path).readAsBytes(), [1]);
    expect(pool.reservedBytes, 8);
  });
  test('filesystem errors do not expose paths or raw exception text', () async {
    final missing = Directory(p.join(root.path, 'PRIVATE_missing'));
    final other = RawDownloadPool(parent: missing);
    final slot = other.reserve(3);
    try {
      await expectLater(slot.write(Stream.value([1])),
          _throws(BinaryDownloadFailure.storage));
    } finally {
      await slot.close();
    }
    expect(await missing.exists(), isFalse);
    expect(other.reservedBytes, 0);
  });
  test('stream and timeout errors retain only a typed safe reason', () async {
    for (final error in [
      StateError('https://PRIVATE/token=SECRET'),
      TimeoutException('PRIVATE')
    ]) {
      final slot = reserve();
      await expectLater(
          slot.write(Stream.error(error)),
          _throws(error is TimeoutException
              ? BinaryDownloadFailure.timeout
              : BinaryDownloadFailure.network));
      await slot.close();
    }
  });
}

Matcher _throws(BinaryDownloadFailure value) => throwsA(
    isA<BinaryDownloadException>().having((e) => e.failure, 'failure', value));

Future<void> _until(bool Function() predicate) async {
  final watch = Stopwatch()..start();
  while (!predicate()) {
    if (watch.elapsed > const Duration(seconds: 3)) {
      fail('No transfer progress');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
