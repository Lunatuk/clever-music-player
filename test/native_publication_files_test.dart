import 'dart:io';
import 'dart:convert';

import 'package:clever_music_player/src/library_sync/native_publication_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  const files = NativePublicationFiles();
  setUp(() async =>
      temp = await Directory.systemTemp.createTemp('cmp_native_publish_'));
  tearDown(() async => temp.delete(recursive: true));
  test('directory creation is exclusive', () async {
    final path = p.join(temp.path, 'owned');
    expect(await files.createDirectory(path), isTrue);
    expect(await files.createDirectory(path), isFalse);
  });
  test('publish moves a complete file without replacing anything', () async {
    final source =
        await File(p.join(temp.path, 'source.part')).writeAsString('complete');
    final target = File(p.join(temp.path, 'result.mp3'));
    await files.moveNoReplace(source.path, target.path);
    expect(source.existsSync(), isFalse);
    expect(await target.readAsString(), 'complete');
  });
  test('collision preserves both files including their bytes', () async {
    final source = await File(p.join(temp.path, 'source')).writeAsString('new');
    final target =
        await File(p.join(temp.path, 'target')).writeAsString('foreign');
    await expectLater(
        files.moveNoReplace(source.path, target.path),
        throwsA(isA<PublicationFileException>().having(
            (e) => e.reason, 'reason', PublicationFileFailure.collision)));
    expect(await source.readAsString(), 'new');
    expect(await target.readAsString(), 'foreign');
  });
  test(
      'native locks exclude another handle in the same process and release once',
      () async {
    final file = await File(p.join(temp.path, 'resource.lock')).create();
    final first = await files.lock(file.path);
    try {
      await expectLater(
          files.lock(file.path),
          throwsA(isA<PublicationFileException>()
              .having((e) => e.reason, 'reason', PublicationFileFailure.busy)));
    } finally {
      final closing = first.close();
      expect(identical(closing, first.close()), isTrue);
      await closing;
    }
    await (await files.lock(file.path)).close();
  });
  test('sealed file remains readable and movable', () async {
    final file =
        await File(p.join(temp.path, 'sealed.part')).writeAsString('abc');
    final lock = await files.lock(file.path, seal: true);
    try {
      expect(await file.readAsString(), 'abc');
      if (Platform.isWindows) {
        await expectLater(file.open(mode: FileMode.writeOnly),
            throwsA(isA<FileSystemException>()));
      }
      final target = p.join(temp.path, 'published.mp3');
      await files.moveNoReplace(file.path, target);
      expect(await File(target).readAsString(), 'abc');
    } finally {
      await lock.close();
    }
  });
  test('concurrent native publication has exactly one winner', () async {
    final sources = [
      for (final name in ['a', 'b'])
        await File(p.join(temp.path, name)).writeAsString(name)
    ];
    final target = File(p.join(temp.path, 'winner'));
    final results = await Future.wait([
      for (final file in sources)
        files.moveNoReplace(file.path, target.path).then((_) => true,
            onError: (Object error) {
          expect(error, isA<PublicationFileException>());
          return false;
        })
    ]);
    expect(results.where((ok) => ok).length, 1);
    expect(await target.readAsString(), results.first ? 'a' : 'b');
    expect(sources.where((file) => file.existsSync()).length, 1);
  });
  test('Unicode and extended Windows paths survive native calls', () async {
    var parent = temp;
    for (var i = 0; i < 5; i++) {
      parent = await Directory(p.join(parent.path, 'кириллица_${'a' * 35}_$i'))
          .create();
    }
    final source =
        await File(p.join(parent.path, 'песня.part')).writeAsString('abc');
    final target = p.join(parent.path, 'музыка.mp3');
    await files.moveNoReplace(source.path, target);
    expect(await File(target).readAsString(), 'abc');
  });
  test('other process obeys the lock and process death releases it', () async {
    final dart = p.join(Platform.environment['FLUTTER_ROOT']!, 'bin', 'cache',
        'dart-sdk', 'bin', Platform.isWindows ? 'dart.exe' : 'dart');
    final script =
        File('test/support/publication_lock_child.dart').absolute.path;
    final file = await File(p.join(temp.path, 'process.lock')).create();
    final metadata = jsonDecode(await File(p.join('build', 'native_assets',
            Platform.operatingSystem, 'native_assets.json'))
        .readAsString()) as Map;
    final mappings = (metadata['native-assets'] as Map).values;
    final library = (mappings.first
        as Map)['package:cmp_file_ops/cmp_file_ops.dart'][1] as String;
    final packages = File('.dart_tool/package_config.json').absolute.path;
    Future<void> child(File marker, {required bool holding}) async {
      final process = await Process.start(dart,
          ['--packages=$packages', script, file.path, marker.path, library]);
      final out = process.stdout.drain<void>(),
          err = process.stderr.drain<void>();
      final watch = Stopwatch()..start();
      var exited = false;
      final exit = process.exitCode.then((code) {
        exited = true;
        return code;
      });
      var markerValue = '';
      try {
        while (watch.elapsed < const Duration(seconds: 30)) {
          if (marker.existsSync()) markerValue = await marker.readAsString();
          if (markerValue == (holding ? 'held' : 'busy') || exited) break;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(markerValue, holding ? 'held' : 'busy');
        if (holding) {
          await expectLater(
              files.lock(file.path),
              throwsA(isA<PublicationFileException>().having(
                  (e) => e.reason, 'reason', PublicationFileFailure.busy)));
          process.kill(ProcessSignal.sigkill);
        }
        await exit.timeout(const Duration(seconds: 10));
      } finally {
        if (!exited) process.kill(ProcessSignal.sigkill);
        await exit;
        await Future.wait([out, err]);
      }
    }

    final lock = await files.lock(file.path);
    try {
      await child(File(p.join(temp.path, 'blocked')), holding: false);
    } finally {
      await lock.close();
    }
    await child(File(p.join(temp.path, 'acquired')), holding: true);
    await (await files.lock(file.path)).close();
  }, timeout: const Timeout(Duration(seconds: 90)));
}
