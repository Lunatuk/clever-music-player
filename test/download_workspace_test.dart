import 'dart:convert';
import 'dart:io';

import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/download_workspace.dart';
import 'package:clever_music_player/src/library_sync/native_publication_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late DownloadWorkspace workspace;
  final leases = <DownloadWorkspaceReservation>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cmp_workspace_');
    workspace = await DownloadWorkspace.open(
        parent: root,
        maxReservedBytes: 16,
        maxEntries: 4,
        preparedGrowthBytes: 0);
  });
  tearDown(() async {
    for (final lease in leases) {
      try {
        await lease.close();
      } on DownloadWorkspaceException {
        /* Explicit corruption/cleanup fixtures. */
      }
    }
    leases.clear();
    await workspace.close();
    await root.delete(recursive: true); // Exclusively this fixture's root.
  });
  DownloadWorkspaceReservation reserve(DownloadWorkspaceStage stage, int bytes,
      {int cover = 0}) {
    final result =
        workspace.reserve(stage, maxAudioBytes: bytes, maxCoverBytes: cover);
    leases.add(result);
    return result;
  }

  Matcher failure(DownloadWorkspaceFailure value) =>
      throwsA(isA<DownloadWorkspaceException>()
          .having((e) => e.failure, 'failure', value));
  Future<Directory> orphan(String id,
      {String stage = 'raw',
      int bytes = 8,
      int cover = 0,
      bool pending = false}) async {
    final directory =
        await Directory(p.join(workspace.directory.path, 'operations', id))
            .create();
    await File(p.join(
            directory.path, pending ? 'reservation.part' : 'reservation.json'))
        .writeAsString(
            jsonEncode({
              'version': 1,
              'id': id,
              'stage': stage,
              'audioBytes': bytes,
              'coverBytes': cover,
              'publication': null
            }),
            flush: true);
    return directory;
  }

  test('raw and prepared share synchronous byte admission before payload IO',
      () async {
    reserve(DownloadWorkspaceStage.raw, 8);
    reserve(DownloadWorkspaceStage.prepared, 6, cover: 2);
    expect(workspace.reservedBytes, 16);
    expect(workspace.reservedEntries, 2);
    expect(() => reserve(DownloadWorkspaceStage.raw, 1),
        failure(DownloadWorkspaceFailure.quotaExceeded));
    expect(
        await Directory(p.join(workspace.directory.path, 'operations'))
            .list()
            .toList(),
        isEmpty);
  });
  test(
      'count and byte limits are independent and unmaterialized close releases',
      () async {
    final local = <DownloadWorkspaceReservation>[];
    for (var i = 0; i < 4; i++) {
      local.add(reserve(DownloadWorkspaceStage.raw, 1));
    }
    expect(() => reserve(DownloadWorkspaceStage.raw, 1),
        failure(DownloadWorkspaceFailure.quotaExceeded));
    await local.first.close();
    reserve(DownloadWorkspaceStage.raw, 2);
    expect(workspace.reservedBytes, 5);
  });
  test(
      'manifest precedes data, is bounded and contains no credential or server fields',
      () async {
    final lease = reserve(DownloadWorkspaceStage.prepared, 8, cover: 2);
    final directory = await lease.materialize();
    final json =
        await File(p.join(directory.path, 'reservation.json')).readAsString();
    expect(jsonDecode(json).keys,
        ['version', 'id', 'stage', 'audioBytes', 'coverBytes', 'publication']);
    expect(json, isNot(contains(root.path)));
    expect(json, isNot(contains('token')));
    await File(p.join(directory.path, 'audio.part')).writeAsString('a');
    await File(p.join(directory.path, 'cover.part')).writeAsString('b');
    await lease.close();
    expect(await directory.exists(), isFalse);
    expect(workspace.reservedBytes, 0);
    expect(lease.toString(), isNot(contains(root.path)));
  });
  test('recover never touches a live writer or issued reader', () async {
    final lease = reserve(DownloadWorkspaceStage.raw, 8);
    final directory = await lease.materialize();
    final audio = await File(p.join(directory.path, 'audio.part'))
        .writeAsString('reading');
    final result = await workspace.recover();
    expect(result.retained, 1);
    expect(await audio.readAsString(), 'reading');
    expect(workspace.reservedBytes, 8);
  });
  test(
      'close stops admission and waits for issued resources before releasing OS lock',
      () async {
    final lease = reserve(DownloadWorkspaceStage.raw, 8);
    final directory = await lease.materialize();
    var ended = false;
    final closing = workspace.close().then((_) => ended = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(ended, isFalse);
    expect(await directory.exists(), isTrue);
    expect(() => reserve(DownloadWorkspaceStage.raw, 1),
        failure(DownloadWorkspaceFailure.closed));
    await expectLater(DownloadWorkspace.open(parent: root),
        failure(DownloadWorkspaceFailure.busy));
    await lease.close();
    await closing;
    expect(ended, isTrue);
    final next = await DownloadWorkspace.open(parent: root);
    await next.close();
  });
  test('second owner and parent alias cannot acquire the same physical root',
      () async {
    await expectLater(
        DownloadWorkspace.open(parent: Directory(p.join(root.path, '.', ''))),
        failure(DownloadWorkspaceFailure.busy));
    expect(workspace.reservedBytes, 0);
  });
  test(
      'explicit reopen cleans abandoned raw/prepared but leaves legacy temp and music',
      () async {
    await workspace.close();
    final raw = await orphan('a' * 64);
    final prepared = await orphan('b' * 64, stage: 'prepared', cover: 2);
    await File(p.join(raw.path, 'audio.part')).writeAsString('partial');
    await File(p.join(prepared.path, 'audio.part')).writeAsString('ready');
    await File(p.join(prepared.path, 'cover.part')).writeAsString('c');
    final old =
        await Directory(p.join(root.path, 'cmp_raw_download_legacy')).create();
    final music =
        await File(p.join(root.path, 'song.mp3')).writeAsString('my music');
    workspace = await DownloadWorkspace.open(parent: root);
    expect(workspace.lastRecovery.removed, 2);
    expect(workspace.reservedBytes, 0);
    expect(await raw.exists(), isFalse);
    expect(await prepared.exists(), isFalse);
    expect(await old.exists(), isTrue);
    expect(await music.readAsString(), 'my music');
  });
  test(
      'crash after complete pending record or final marker removal is recoverable',
      () async {
    await workspace.close();
    final pending = await orphan('c' * 64, pending: true);
    final empty = await Directory(
            p.join(workspace.directory.path, 'operations', 'd' * 64))
        .create();
    workspace = await DownloadWorkspace.open(parent: root);
    expect(workspace.lastRecovery.removed, 2);
    expect(await pending.exists(), isFalse);
    expect(await empty.exists(), isFalse);
  });
  for (final kind in [
    'extra file',
    'nested directory',
    'bad json',
    'partial marker',
    'wrong identity',
    'oversized marker',
    'wrong version',
    'invalid limits',
    'payload directory',
    'extra root file'
  ]) {
    test('$kind is preserved and blocks admission until explicitly resolved',
        () async {
      await workspace.close();
      final directory = await orphan('e' * 64);
      final data = await File(p.join(directory.path, 'audio.part'))
          .writeAsString('retain');
      switch (kind) {
        case 'extra file':
          await File(p.join(directory.path, 'foreign.mp3'))
              .writeAsString('foreign');
        case 'nested directory':
          await Directory(p.join(directory.path, 'nested')).create();
        case 'bad json':
          await File(p.join(directory.path, 'reservation.json'))
              .writeAsString('{broken');
        case 'partial marker':
          await File(p.join(directory.path, 'reservation.json')).delete();
          await File(p.join(directory.path, 'reservation.part'))
              .writeAsString('{partial');
        case 'wrong identity':
          final manifest = File(p.join(directory.path, 'reservation.json'));
          await manifest.writeAsString(
              (await manifest.readAsString()).replaceAll('e' * 64, 'f' * 64));
        case 'oversized marker':
          await File(p.join(directory.path, 'reservation.json'))
              .writeAsString('x' * (DownloadWorkspace.maxRecordBytes + 1));
        case 'wrong version':
          final manifest = File(p.join(directory.path, 'reservation.json'));
          await manifest.writeAsString((await manifest.readAsString())
              .replaceFirst('"version":1', '"version":2'));
        case 'invalid limits':
          final manifest = File(p.join(directory.path, 'reservation.json'));
          await manifest.writeAsString((await manifest.readAsString())
              .replaceFirst('"audioBytes":8', '"audioBytes":-1'));
        case 'payload directory':
          await data.delete();
          await Directory(data.path).create();
        case 'extra root file':
          await File(p.join(workspace.directory.path, 'foreign'))
              .writeAsString('foreign');
      }
      workspace = await DownloadWorkspace.open(parent: root);
      expect(workspace.admissionBlocked, isTrue);
      expect(workspace.lastRecovery.unknown, greaterThan(0));
      expect(() => reserve(DownloadWorkspaceStage.raw, 1),
          failure(DownloadWorkspaceFailure.invalidJournal));
      if (kind != 'extra root file' && kind != 'payload directory') {
        expect(await data.readAsString(), 'retain');
      }
    });
  }
  test('failed owned cleanup retains charge and allows explicit retry',
      () async {
    final lease = reserve(DownloadWorkspaceStage.raw, 8);
    final directory = await lease.materialize();
    final extra =
        await File(p.join(directory.path, 'foreign')).writeAsString('keep');
    await expectLater(
        lease.close(), failure(DownloadWorkspaceFailure.unsafePath));
    expect(workspace.reservedBytes, 8);
    await extra.delete();
    await lease.close();
    expect(workspace.reservedBytes, 0);
  });
  test(
      'root ownership mismatch is never adopted and failed open releases the lock',
      () async {
    await workspace.close();
    final owner = File(p.join(workspace.directory.path, 'owner.json'));
    final valid = await owner.readAsString();
    await owner.writeAsString('foreign');
    await expectLater(DownloadWorkspace.open(parent: root),
        failure(DownloadWorkspaceFailure.unsafePath));
    await owner.writeAsString(valid);
    workspace = await DownloadWorkspace.open(parent: root);
    expect(workspace.admissionBlocked, isFalse);
  });
  test('cancelled open releases ownership and does not erase content',
      () async {
    await workspace.close();
    await orphan('f' * 64);
    await expectLater(
        DownloadWorkspace.open(
            parent: root, control: LibraryScanControl()..cancel()),
        throwsA(isA<LibraryScanCancelled>()));
    workspace = await DownloadWorkspace.open(parent: root);
    expect(workspace.lastRecovery.removed, 1);
  });
  test(
      'native denied delete retains quota and recovery retries after handle release',
      () async {
    if (!Platform.isWindows) return;
    final lease = reserve(DownloadWorkspaceStage.raw, 8);
    final directory = await lease.materialize();
    final audio =
        await File(p.join(directory.path, 'audio.part')).writeAsString('abc');
    final handle = await audio.open();
    try {
      await expectLater(
          lease.close(), failure(DownloadWorkspaceFailure.storage));
      expect(workspace.reservedBytes, 8);
      expect(await audio.readAsString(), 'abc');
    } finally {
      await handle.close();
    }
    final result = await workspace.recover();
    expect(result.removed, 1);
    expect(workspace.reservedBytes, 0);
  });
  test('cancelled recovery blocks fresh admission until a complete retry',
      () async {
    await expectLater(
        workspace.recover(control: LibraryScanControl()..cancel()),
        throwsA(isA<LibraryScanCancelled>()));
    expect(workspace.admissionBlocked, isTrue);
    expect(() => reserve(DownloadWorkspaceStage.raw, 1),
        failure(DownloadWorkspaceFailure.invalidJournal));
    await workspace.recover();
    reserve(DownloadWorkspaceStage.raw, 1);
  });
  test('maintenance rejects simultaneous recovery and admission', () async {
    final operation = workspace.recover();
    await expectLater(
        workspace.recover(), failure(DownloadWorkspaceFailure.busy));
    expect(() => reserve(DownloadWorkspaceStage.raw, 1),
        failure(DownloadWorkspaceFailure.busy));
    await operation;
    reserve(DownloadWorkspaceStage.raw, 1);
  });
  test('failed marker install cleans the owned complete pending record',
      () async {
    await workspace.close();
    workspace =
        await DownloadWorkspace.open(parent: root, files: _FailMoveFiles());
    final lease = reserve(DownloadWorkspaceStage.raw, 8);
    await expectLater(
        lease.materialize(), failure(DownloadWorkspaceFailure.storage));
    expect(workspace.reservedBytes, 8);
    await lease.close();
    expect(workspace.reservedBytes, 0);
    expect((await workspace.recover()).unknown, 0);
  });
  test('stale cleanup cannot act after another owner reopens the root',
      () async {
    final lease = reserve(DownloadWorkspaceStage.raw, 8);
    final directory = await lease.materialize();
    final extra =
        await File(p.join(directory.path, 'foreign')).writeAsString('keep');
    await expectLater(
        lease.close(), failure(DownloadWorkspaceFailure.unsafePath));
    await workspace.close();
    workspace = await DownloadWorkspace.open(parent: root);
    await expectLater(lease.close(), failure(DownloadWorkspaceFailure.closed));
    expect(await extra.readAsString(), 'keep');
    await extra.delete();
    await workspace.recover();
    expect(workspace.reservedBytes, 0);
  });
  test('creation and close are idempotent and closed entries cannot reopen',
      () async {
    final lease = reserve(DownloadWorkspaceStage.raw, 1);
    final opening = lease.materialize();
    expect(identical(opening, lease.materialize()), isTrue);
    await opening;
    final closing = lease.close();
    expect(identical(closing, lease.close()), isTrue);
    await closing;
    await expectLater(
        lease.materialize(), failure(DownloadWorkspaceFailure.closed));
  });
  test('cleanup retry is rejected as soon as workspace shutdown begins',
      () async {
    final lease = reserve(DownloadWorkspaceStage.raw, 8);
    final directory = await lease.materialize();
    final extra =
        await File(p.join(directory.path, 'foreign')).writeAsString('keep');
    await expectLater(
        lease.close(), failure(DownloadWorkspaceFailure.unsafePath));
    final closing = workspace.close();
    await expectLater(lease.close(), failure(DownloadWorkspaceFailure.closed));
    await closing;
    expect(await extra.readAsString(), 'keep');
    await extra.delete();
    workspace = await DownloadWorkspace.open(parent: root);
    expect(workspace.reservedBytes, 0);
  });
  test(
      'real process death releases workspace ownership and recovers serialized journals',
      () async {
    final templates = <Map<String, Object?>>[];
    for (final (stage, bytes, cover) in [
      (DownloadWorkspaceStage.raw, 8, 0),
      (DownloadWorkspaceStage.prepared, 4, 2)
    ]) {
      final lease = reserve(stage, bytes, cover: cover);
      final directory = await lease.materialize();
      templates.add({
        'directory': directory.path,
        'record': await File(p.join(directory.path, 'reservation.json'))
            .readAsString(),
        'cover': cover > 0
      });
      await lease.close();
    }
    await workspace.close();
    final specification = await File(p.join(root.path, 'writer.json'))
        .writeAsString(jsonEncode(templates));
    final marker = File(p.join(root.path, 'ready'));
    final music =
        await File(p.join(root.path, 'song.mp3')).writeAsString('preserve');
    final metadata = jsonDecode(await File(p.join('build', 'native_assets',
            Platform.operatingSystem, 'native_assets.json'))
        .readAsString()) as Map;
    final library = ((metadata['native-assets'] as Map).values.first
        as Map)['package:cmp_file_ops/cmp_file_ops.dart'][1] as String;
    final dart = p.join(Platform.environment['FLUTTER_ROOT']!, 'bin', 'cache',
        'dart-sdk', 'bin', Platform.isWindows ? 'dart.exe' : 'dart');
    final process = await Process.start(dart, [
      '--packages=${File('.dart_tool/package_config.json').absolute.path}',
      File('test/support/download_workspace_process_child.dart').absolute.path,
      p.join(workspace.directory.path, 'owner.lock'),
      marker.path,
      library,
      specification.path
    ]);
    final out = process.stdout.drain<void>(),
        err = process.stderr.drain<void>();
    var exited = false;
    final exitCode = process.exitCode.then((code) {
      exited = true;
      return code;
    });
    try {
      final deadline = Stopwatch()..start();
      while (!await marker.exists() &&
          !exited &&
          deadline.elapsed < const Duration(seconds: 30)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await marker.readAsString(), 'held');
      await expectLater(DownloadWorkspace.open(parent: root),
          failure(DownloadWorkspaceFailure.busy));
      process.stdin.writeln('exit-without-cleanup');
      await process.stdin.close();
      expect(await exitCode, 73);
      workspace = await DownloadWorkspace.open(parent: root);
      expect(workspace.lastRecovery.removed, 2);
      expect(workspace.reservedBytes, 0);
      expect(await music.readAsString(), 'preserve');
      for (final entry in templates) {
        expect(await Directory(entry['directory'] as String).exists(), isFalse);
      }
    } finally {
      if (!exited) process.kill(ProcessSignal.sigkill);
      await exitCode;
      await Future.wait([out, err]);
    }
  });
  test('late cancellation drains first initialization and allows a clean retry',
      () async {
    final fresh = await Directory(p.join(root.path, 'cancelled-open')).create();
    final control = LibraryScanControl();
    await expectLater(
        DownloadWorkspace.open(
            parent: fresh,
            control: control,
            files: _CancelAfterLockFiles(control)),
        throwsA(isA<LibraryScanCancelled>()));
    final retry = await DownloadWorkspace.open(parent: fresh);
    expect(retry.admissionBlocked, isFalse);
    expect(retry.reservedBytes, 0);
    await retry.close();
  });
}

final class _FailMoveFiles implements PublicationFiles {
  final delegate = const NativePublicationFiles();
  @override
  Future<bool> createDirectory(String path) => delegate.createDirectory(path);
  @override
  Future<PublicationFileLock> lock(String path, {bool seal = false}) =>
      delegate.lock(path, seal: seal);
  @override
  Future<void> moveNoReplace(String source, String target) =>
      Future.error(const PublicationFileException(PublicationFileFailure.io));
}

final class _CancelAfterLockFiles implements PublicationFiles {
  _CancelAfterLockFiles(this.control);
  final LibraryScanControl control;
  final delegate = const NativePublicationFiles();
  @override
  Future<bool> createDirectory(String path) => delegate.createDirectory(path);
  @override
  Future<PublicationFileLock> lock(String path, {bool seal = false}) async {
    final result = await delegate.lock(path, seal: seal);
    control.cancel();
    return result;
  }

  @override
  Future<void> moveNoReplace(String source, String target) =>
      delegate.moveNoReplace(source, target);
}
