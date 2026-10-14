import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:clever_music_player/src/library/file_content_hasher.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late File file;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cmp_hash_session_');
    file = await File(p.join(root.path, 'песня 💿.wav')).writeAsString('abc');
  });
  tearDown(() => root.delete(recursive: true));

  for (final native in [false, true]) {
    test('one worker preserves SHA-256 for all buffer edges (native=$native)',
        () async {
      final session = Sha256HashSession(preferNative: native);
      addTearDown(session.close);
      var starts = 0;
      for (final length in [
        0,
        1,
        55,
        63,
        64,
        65,
        65535,
        65536,
        65537,
        262143,
        262144,
        262145,
        1048583
      ]) {
        final bytes = Uint8List(length);
        for (var i = 0; i < bytes.length; i++) {
          bytes[i] = i % 251;
        }
        await file.writeAsBytes(bytes);
        final result = await session.hashFile(file);
        expect(result.digest, sha256.convert(bytes).toString());
        expect(result.storageKey,
            (await const Sha256FileContentHasher().hashFile(file)).storageKey);
        expect(result.sizeBytes, length);
        expect(await result.matchesFile(file), isTrue);
        starts += result.timings.workerStarts;
        expect(
            result.timings.workerUs,
            greaterThanOrEqualTo(
                result.timings.ioUs + result.timings.digestUs));
      }
      expect(starts, 1);
    });
  }

  test('pre-cancelled and unused sessions never start a worker', () async {
    final session = Sha256HashSession(workerEntry: _mustNotStart);
    await expectLater(
        session.hashFileWithControl(file,
            control: LibraryScanControl()..cancel()),
        throwsA(isA<LibraryScanCancelled>()));
    await session.close();
    await session.close();
  });

  test('concurrent requests fail immediately and cannot queue files', () async {
    final session = Sha256HashSession();
    addTearDown(session.close);
    final first = session.hashFile(file);
    final second = session.hashFile(file);
    await expectLater(second, throwsStateError);
    expect((await first).digest, sha256.convert('abc'.codeUnits).toString());
    expect((await session.hashFile(file)).timings.workerStarts, 0);
  });

  test('read errors do not poison the next request', () async {
    final session = Sha256HashSession();
    addTearDown(session.close);
    await expectLater(session.hashFile(File(p.join(root.path, 'gone.wav'))),
        throwsA(isA<FileSystemException>()));
    await expectLater(
        session.hashFile(File(root.path)), throwsA(isA<FileSystemException>()));
    final recovered = await session.hashFile(file);
    expect(recovered.digest, sha256.convert('abc'.codeUnits).toString());
    expect(recovered.timings.workerStarts, 1);
  });

  test('repeated cancellation releases the file and keeps the worker usable',
      () async {
    final session = Sha256HashSession();
    addTearDown(session.close);
    await file.writeAsBytes(Uint8List(8 * 1024 * 1024));
    for (var attempt = 0; attempt < 3; attempt++) {
      final control = LibraryScanControl();
      var callbacks = 0;
      await expectLater(
          session.hashFileWithControl(file, control: control, onProgress: (_) {
            callbacks++;
            control.cancel();
          }),
          throwsA(isA<LibraryScanCancelled>()));
      expect(callbacks, 1);
      // Windows deletion after the Future settles detects a leaked RAF handle.
      await file.delete();
      await file.writeAsBytes(Uint8List(8 * 1024 * 1024));
    }
    expect((await session.hashFile(file)).sizeBytes, 8 * 1024 * 1024);
  });

  test('progress callback failures drain IO before propagating', () async {
    final session = Sha256HashSession();
    addTearDown(session.close);
    await expectLater(
        session.hashFileWithControl(file,
            control: LibraryScanControl(),
            onProgress: (_) => throw StateError('callback failed')),
        throwsStateError);
    await file.delete();
    await file.writeAsString('recovered');
    expect((await session.hashFile(file)).sizeBytes, 9);
  });

  test('closing during progress cancels and drains before returning', () async {
    final session = Sha256HashSession();
    Future<void>? closing;
    await expectLater(
        session.hashFileWithControl(file, control: LibraryScanControl(),
            onProgress: (_) {
          closing ??= session.close();
        }),
        throwsA(isA<LibraryScanCancelled>()));
    await closing;
    await session.close();
    await file.delete();
    await expectLater(session.hashFile(file), throwsStateError);
  });

  test('close before startup completes does not dispatch a file', () async {
    final session = Sha256HashSession(workerEntry: _delayedReady);
    final hashing = session.hashFile(file);
    final closing = session.close();
    await expectLater(hashing, throwsA(isA<LibraryScanCancelled>()));
    await closing.timeout(const Duration(seconds: 5));
    await file.delete();
  });

  for (final entry in [
    _crashBeforeReady,
    _crashDuringRequest,
    _exitWithoutReply
  ]) {
    test('unexpected worker failure settles the request and close ($entry)',
        () async {
      final session = Sha256HashSession(workerEntry: entry);
      await expectLater(
          session.hashFile(file).timeout(const Duration(seconds: 5)),
          throwsA(anyOf(isA<RemoteError>(), isA<StateError>())));
      await session.close().timeout(const Duration(seconds: 5));
      await expectLater(session.hashFile(file), throwsStateError);
    });
  }

  test('normal close releases the worker and rejects later work', () async {
    final session = Sha256HashSession();
    await session.hashFile(file);
    await session.close();
    await session.close();
    await expectLater(session.hashFile(file), throwsStateError);
    final replacement = Sha256HashSession();
    try {
      expect((await replacement.hashFile(file)).timings.workerStarts, 1);
    } finally {
      await replacement.close();
    }
  });

  test('invalid buffer limits are rejected', () {
    for (final size in [-1, 0, 1024 * 1024 + 1]) {
      expect(() => Sha256HashSession(bufferSize: size), throwsArgumentError);
    }
  });
}

void _mustNotStart((SendPort, bool, int) _) =>
    throw StateError('Worker unexpectedly started');
void _crashBeforeReady((SendPort, bool, int) _) =>
    throw StateError('startup crash');
void _crashDuringRequest((SendPort, bool, int) bootstrap) {
  final requests = ReceivePort();
  bootstrap.$1.send(requests.sendPort);
  requests.listen((_) => throw StateError('request crash'));
}

void _exitWithoutReply((SendPort, bool, int) bootstrap) {
  final requests = ReceivePort();
  bootstrap.$1.send(requests.sendPort);
  requests.listen((_) => Isolate.exit());
}

Future<void> _delayedReady((SendPort, bool, int) bootstrap) async {
  final requests = ReceivePort();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  bootstrap.$1.send(requests.sendPort);
  await for (final request in requests) {
    if (request == null) break;
    throw StateError('Closed session dispatched work');
  }
  requests.close();
  Isolate.exit();
}
