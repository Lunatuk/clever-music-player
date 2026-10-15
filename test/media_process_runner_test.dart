import 'dart:io';

import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/media_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late File script;
  late BoundedMediaProcessRunner runner;
  late String dart;
  setUp(() async {
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root == null) {
      throw StateError(
          'FLUTTER_ROOT is required for native child-process tests.');
    }
    dart = p.join(root, 'bin', 'cache', 'dart-sdk', 'bin',
        Platform.isWindows ? 'dart.exe' : 'dart');
    expect(File(dart).existsSync(), isTrue);
    temp = await Directory.systemTemp.createTemp('cmp_process_');
    script = File(p.join(temp.path, 'child.dart'));
    runner = BoundedMediaProcessRunner();
  });
  tearDown(() async {
    await runner.close();
    await temp.delete(recursive: true);
  });
  Future<MediaProcessOutput> run(
          {LibraryScanControl? control, List<String> args = const []}) =>
      runner.run(dart, [script.path, ...args], control ?? LibraryScanControl());
  test('literal arguments survive quotes, Unicode and shell syntax', () async {
    await script.writeAsString(
        "import 'dart:io'; void main(List<String> args){stdout.write(args.single);}");
    const value = 'a "quote" Кириллица \$() & ; space';
    final result = await run(args: [value]);
    expect(result.exitCode, 0);
    expect(result.stdout, value);
    expect(result.hadStderr, isFalse);
  });
  test('stdout and stderr both drain without exposing private error text',
      () async {
    await script.writeAsString(
        "import 'dart:io'; void main(){stdout.write('ok');stderr.write('private');exitCode=7;}");
    final result = await run();
    expect(result.exitCode, 7);
    expect(result.stdout, 'ok');
    expect(result.hadStderr, isTrue);
  });
  for (final stream in ['stdout', 'stderr']) {
    test('$stream output overflow kills and drains the child', () async {
      await runner.close();
      runner =
          BoundedMediaProcessRunner(maxStdoutBytes: 1024, maxStderrBytes: 1024);
      await script.writeAsString(
          "import 'dart:io'; void main(){while(true){$stream.write('x'*4096);}}");
      await expectLater(
          run().timeout(const Duration(seconds: 10)),
          throwsA(isA<MediaProcessFailure>().having(
              (e) => e.kind, 'kind', MediaProcessFailureKind.outputLimit)));
    });
  }
  test('missing executable is typed, no raw exception retained', () async {
    await expectLater(
        runner.run(
            p.join(temp.path, 'missing-executable'), [], LibraryScanControl()),
        throwsA(isA<MediaProcessFailure>().having(
            (e) => e.kind, 'kind', MediaProcessFailureKind.unavailable)));
  });
  test('pre-cancelled read does not spawn the child', () async {
    await expectLater(run(control: LibraryScanControl()..cancel()),
        throwsA(isA<LibraryScanCancelled>()));
    expect(script.existsSync(), isFalse);
  });
  test('close kills a live child, waits for pipe cleanup and rejects new work',
      () async {
    final marker = File(p.join(temp.path, 'started'));
    await script.writeAsString(
        "import 'dart:io'; import 'dart:async'; void main(List<String> args){File(args.single).writeAsStringSync('ready');Timer.periodic(const Duration(seconds:1),(_){});}");
    final reading = run(args: [marker.path]);
    final expectation =
        expectLater(reading, throwsA(isA<LibraryScanCancelled>()));
    final watch = Stopwatch()..start();
    while (
        !marker.existsSync() && watch.elapsed < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(marker.existsSync(), isTrue);
    await expectLater(run(), throwsStateError);
    final closing = runner.close();
    expect(identical(closing, runner.close()), isTrue);
    await closing.timeout(const Duration(seconds: 10));
    await expectation;
    await expectLater(run(), throwsStateError);
  });
}
