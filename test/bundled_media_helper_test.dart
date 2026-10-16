import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/bundled_media_helper.dart';
import 'package:clever_music_player/src/library_sync/media_process_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Map<String, dynamic> manifest;
  late _Runner runner;
  late BundledMediaHelper helper;
  Future<void> save() => File(p.join(root.path, 'manifest.json'))
      .writeAsString(jsonEncode(manifest));
  Matcher failure(MediaHelperFailure value) =>
      throwsA(isA<MediaHelperException>()
          .having((error) => error.failure, 'failure', value));
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cmp_helper_музыка_');
    final files = <String, dynamic>{};
    for (final name in BundledMediaHelper.binaries) {
      final bytes = utf8.encode('synthetic binary $name');
      await File(p.join(root.path, name)).writeAsBytes(bytes);
      files[name] = {
        'bytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      };
    }
    manifest = {
      'schema': 1,
      'profile': 'cmp-audio-1',
      'target': 'windows-x64',
      'ffmpegVersion': '7.1.5',
      'files': files,
    };
    await save();
    runner = _Runner();
    helper = BundledMediaHelper(directory: root, runner: runner);
  });
  tearDown(() async {
    await helper.close();
    await root.delete(recursive: true); // Only our test-created synthetic root.
  });

  test('lazy until explicit check; absolute paths and backend use own bundle',
      () async {
    expect(runner.calls, isEmpty);
    final result = await helper.qualify();
    expect(result.version, '7.1.5');
    expect(result.ffprobePath, p.join(root.path, 'ffprobe.exe'));
    expect(result.ffmpegPath, p.join(root.path, 'ffmpeg.exe'));
    expect(runner.calls, hasLength(8));
    expect(
        runner.calls.every((call) => p.dirname(call.$1) == root.path), isTrue);
    final backend = result.createMetadataBackend();
    await backend.close();
    // A repeated check must really check again, not reuse a stale result.
    await helper.qualify();
    expect(runner.calls, hasLength(16));
  });
  for (final field in ['schema', 'profile', 'target', 'ffmpegVersion']) {
    test('rejects wrong manifest $field before any executable', () async {
      manifest[field] = 'unknown';
      await save();
      await expectLater(
          helper.qualify(), failure(MediaHelperFailure.invalidBundle));
      expect(runner.calls, isEmpty);
    });
  }
  test('missing bundle is distinct from a damaged bundle', () async {
    await helper.close();
    helper = BundledMediaHelper(
        directory: Directory(p.join(root.path, 'missing')), runner: runner);
    await expectLater(helper.qualify(), failure(MediaHelperFailure.missing));
    expect(runner.calls, isEmpty);
  });
  for (final change in ['missing', 'size', 'hash', 'directory']) {
    test('rejects $change DLL before launching either exe', () async {
      final file = File(p.join(root.path, 'avcodec-61.dll'));
      final bytes = List<int>.of(await file.readAsBytes());
      if (change == 'missing' || change == 'directory') {
        await file.delete();
        if (change == 'directory') await Directory(file.path).create();
      } else {
        if (change == 'size') {
          bytes.add(1);
        } else {
          bytes[0] ^= 1;
        }
        await file.writeAsBytes(bytes);
      }
      await expectLater(
          helper.qualify(), failure(MediaHelperFailure.invalidBundle));
      expect(runner.calls, isEmpty);
    });
  }
  test('manifest cannot select an executable outside the fixed bundle',
      () async {
    final files = manifest['files'] as Map<String, dynamic>;
    files['../ffmpeg.exe'] = files.remove('ffmpeg.exe');
    await save();
    await expectLater(
        helper.qualify(), failure(MediaHelperFailure.invalidBundle));
    expect(runner.calls, isEmpty);
  });
  for (final content in ['{bad', '[]', ' ' * 8193]) {
    test('rejects malformed/oversized manifest ${content.length}', () async {
      await File(p.join(root.path, 'manifest.json')).writeAsString(content);
      await expectLater(
          helper.qualify(), failure(MediaHelperFailure.invalidBundle));
      expect(runner.calls, isEmpty);
    });
  }
  test('invalid numeric hash evidence is rejected', () async {
    (manifest['files'] as Map)['ffmpeg.exe'] = {'bytes': -1, 'sha256': 'bad'};
    await save();
    await expectLater(
        helper.qualify(), failure(MediaHelperFailure.invalidBundle));
  });
  for (final version in ['7.1.4', '7.1.50', '9.0.2']) {
    test('rejects different executable version $version', () async {
      runner.version = version;
      await expectLater(
          helper.qualify(), failure(MediaHelperFailure.incompatible));
    });
  }
  test('both executables must match', () async {
    runner.probeVersion = '7.1';
    await expectLater(
        helper.qualify(), failure(MediaHelperFailure.incompatible));
  });
  for (final flag in [
    '--enable-gpl',
    '--enable-nonfree',
    '--enable-version3'
  ]) {
    test('rejects unexpected license configuration $flag', () async {
      runner.extraFlag = flag;
      await expectLater(
          helper.qualify(), failure(MediaHelperFailure.incompatible));
    });
  }
  for (final table in [
    '-decoders',
    '-encoders',
    '-demuxers',
    '-muxers',
    '-filters'
  ]) {
    test('requires real table entries for $table, not a description', () async {
      runner.missingTable = table;
      await expectLater(
          helper.qualify(), failure(MediaHelperFailure.incompatible));
    });
  }
  test('network protocol is rejected even if file/pipe are present', () async {
    runner.network = true;
    await expectLater(
        helper.qualify(), failure(MediaHelperFailure.incompatible));
  });
  test('DLL replaced during process probes fails final verification', () async {
    runner.onCall = () async {
      final file = File(p.join(root.path, 'avcodec-61.dll'));
      final bytes = await file.readAsBytes();
      bytes[0] ^= 1;
      await file.writeAsBytes(bytes);
      runner.onCall = null;
    };
    await expectLater(
        helper.qualify(), failure(MediaHelperFailure.invalidBundle));
  });
  test('process launch failure is typed and does not expose command output',
      () async {
    runner.fail = true;
    await expectLater(
        helper.qualify(), failure(MediaHelperFailure.unavailable));
  });
  test('stderr / nonzero exit is incompatible', () async {
    runner.badExit = true;
    await expectLater(
        helper.qualify(), failure(MediaHelperFailure.incompatible));
  });
  test('pre-cancel never starts work', () async {
    await expectLater(helper.qualify(control: LibraryScanControl()..cancel()),
        throwsA(isA<LibraryScanCancelled>()));
    expect(runner.calls, isEmpty);
  });
  test('cancel drains pending probe; next explicit check succeeds', () async {
    runner.block = true;
    final control = LibraryScanControl();
    final checking = helper.qualify(control: control);
    final expected =
        expectLater(checking, throwsA(isA<LibraryScanCancelled>()));
    await runner.started.future;
    control.cancel();
    await expected;
    expect(runner.drained, isTrue);
    runner.block = false;
    await helper.qualify();
  });
  test('timeout cancels and drains, without cancelling caller control',
      () async {
    await helper.close();
    runner = _Runner()..block = true;
    helper = BundledMediaHelper(
        directory: root,
        runner: runner,
        timeout: const Duration(milliseconds: 100));
    final control = LibraryScanControl();
    await expectLater(
        helper.qualify(control: control), failure(MediaHelperFailure.timedOut));
    expect(control.isCancellationRequested, isFalse);
    expect(runner.drained, isTrue);
  });
  test('overlap rejected; close drains and is idempotent', () async {
    runner.block = true;
    final expected =
        expectLater(helper.qualify(), throwsA(isA<LibraryScanCancelled>()));
    await runner.started.future;
    await expectLater(helper.qualify(), throwsStateError);
    final closing = helper.close();
    expect(identical(closing, helper.close()), isTrue);
    await closing;
    await expected;
    expect(runner.closed, isTrue);
    expect(runner.drained, isTrue);
    await expectLater(helper.qualify(), throwsStateError);
  });
  test('unsupported target never launches a process', () async {
    await helper.close();
    helper = BundledMediaHelper(
        directory: root, runner: runner, target: 'android-arm64');
    await expectLater(
        helper.qualify(), failure(MediaHelperFailure.unsupportedPlatform));
    expect(runner.calls, isEmpty);
  });
}

class _Runner implements MediaProcessRunner {
  final calls = <(String, List<String>)>[];
  final started = Completer<void>();
  String version = '7.1.5', extraFlag = '';
  String? probeVersion, missingTable;
  bool network = false, fail = false, badExit = false, block = false;
  bool drained = false, closed = false;
  Future<void> Function()? onCall;
  @override
  Future<MediaProcessOutput> run(String executable, List<String> arguments,
      LibraryScanControl control) async {
    calls.add((executable, arguments));
    if (!started.isCompleted) started.complete();
    if (fail) {
      throw const MediaProcessFailure(MediaProcessFailureKind.unavailable);
    }
    if (block) {
      final stop = Completer<void>();
      void cancel() => stop.complete();
      control.addCancellationListener(cancel);
      await stop.future;
      control.removeCancellationListener(cancel);
      drained = true;
      control.throwIfCancelled();
    }
    await onCall?.call();
    if (badExit) {
      return const MediaProcessOutput(1, 'private text', hadStderr: true);
    }
    final flag = arguments.last;
    if (flag == '-version') {
      final probe = p.basename(executable) == 'ffprobe.exe';
      return MediaProcessOutput(
          0,
          '${probe ? 'ffprobe' : 'ffmpeg'} version '
          '${probe ? probeVersion ?? version : version} Copyright developers\n'
          'configuration: --disable-network --enable-shared --disable-autodetect $extraFlag');
    }
    if (flag == '-protocols') {
      return MediaProcessOutput(
          0,
          'Supported file protocols:\nInput:\n file\n pipe\n'
          'Output:\n file\n pipe\n${network ? ' http\n' : ''}');
    }
    final names = {
      '-decoders': ['mp3float', 'aac', 'flac', 'png', 'mjpeg'],
      '-encoders': ['pcm_s16le', 'pcm_s32le', 'wrapped_avframe'],
      '-demuxers': [
        'mp3',
        'mov,mp4,m4a,3gp,3g2,mj2',
        'flac',
        'png_pipe',
        'jpeg_pipe'
      ],
      '-muxers': ['mp3', 'ipod', 'flac', 'null', 'hash'],
      '-filters': ['asetpts', 'aformat', 'aresample', 'null'],
    }[flag]!;
    return MediaProcessOutput(
        0,
        names
            .map((name) =>
                ' D ${missingTable == flag ? 'other' : name} description $name')
            .join('\n'));
  }

  @override
  Future<void> close() async => closed = true;
}
