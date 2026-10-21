import 'dart:io';

import 'package:clever_music_player/src/android/android_download_workspace.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/download_workspace.dart';
import 'package:clever_music_player/src/library_sync/native_publication_files.dart';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'support/recording_diagnostics.dart';

void main() {
  late Directory root;
  late File sentinel;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cmp_android_workspace_');
    sentinel = await File(p.join(root.path, 'keep')).writeAsString('user data');
  });
  tearDown(() async => root.delete(recursive: true));

  Future<void> expectClean() async {
    expect(await sentinel.readAsString(), 'user data');
    expect(
        (await root.list().toList()).map((e) => p.basename(e.path)), ['keep']);
  }

  test(
      'real native asset: exclusive owner, bounded IO, collision and successful move; repeat is clean',
      () async {
    for (var i = 0; i < 2; i++) {
      await checkAndroidDownloadWorkspace(
          parent: root, control: LibraryScanControl());
      await expectClean();
    }
  });
  test('pre-cancelled check performs no filesystem work', () async {
    await expectLater(
        checkAndroidDownloadWorkspace(
            parent: root, control: LibraryScanControl()..cancel()),
        throwsA(isA<LibraryScanCancelled>()));
    await expectClean();
  });
  test(
      'cancellation after native lock acquisition drains and deletes only probe',
      () async {
    final control = LibraryScanControl();
    final files = _Files(onLock: control.cancel);
    await expectLater(
        checkAndroidDownloadWorkspace(
            parent: root, control: control, files: files),
        throwsA(isA<LibraryScanCancelled>()));
    await expectClean();
    await checkAndroidDownloadWorkspace(
        parent: root, control: LibraryScanControl());
  });
  test('cancellation during final native move still drains cleanup', () async {
    final control = LibraryScanControl();
    await expectLater(
        checkAndroidDownloadWorkspace(
            parent: root,
            control: control,
            files: _Files(onMove: control.cancel)),
        throwsA(isA<LibraryScanCancelled>()));
    await expectClean();
  });
  test('unexpected native IO failure cannot be reported as success', () async {
    await expectLater(
        checkAndroidDownloadWorkspace(
            parent: root,
            control: LibraryScanControl(),
            files: _Files(failMove: true)),
        throwsA(isA<DownloadWorkspaceException>().having(
            (e) => e.failure, 'failure', DownloadWorkspaceFailure.storage)));
    await expectClean();
  });
  test('damaged journal retains probe but releases the OS owner lock',
      () async {
    final diagnostics = RecordingDiagnostics();
    await expectLater(
        checkAndroidDownloadWorkspace(
            parent: root,
            control: LibraryScanControl(),
            files: _Files(corruptOwner: true),
            diagnostics: diagnostics),
        throwsA(isA<DownloadWorkspaceException>().having(
            (e) => e.failure, 'failure', DownloadWorkspaceFailure.unsafePath)));
    expect(await sentinel.readAsString(), 'user data');
    final probe =
        (await root.list().where((e) => e is Directory).toList()).single;
    final lock = await const NativePublicationFiles()
        .lock(p.join(probe.path, '.cmp-download-workspace-v1', 'owner.lock'));
    await lock.close();
    expect(diagnostics.entries.last.event,
        DiagnosticEvent.androidWorkspaceCheckFailed);
    expect(diagnostics.entries.last.fields[DiagnosticField.workspaceStage],
        AndroidWorkspaceCheckStage.cleanup.index);
  });

  test('successful native check reports completion without expected refusals',
      () async {
    final diagnostics = RecordingDiagnostics();
    await checkAndroidDownloadWorkspace(
        parent: root, control: LibraryScanControl(), diagnostics: diagnostics);
    expect(diagnostics.entries.map((e) => e.event), [
      DiagnosticEvent.androidWorkspaceCheckStarted,
      DiagnosticEvent.androidWorkspaceCheckCompleted,
    ]);
    await expectClean();
  });
  test('native errno and failing stage survive workspace error masking',
      () async {
    final diagnostics = RecordingDiagnostics();
    await expectLater(
        checkAndroidDownloadWorkspace(
            parent: root,
            control: LibraryScanControl(),
            files: _Files(failMove: true),
            diagnostics: diagnostics),
        throwsA(isA<DownloadWorkspaceException>()));
    final native = diagnostics.entries.singleWhere(
        (e) => e.event == DiagnosticEvent.androidWorkspaceFileOperationFailed);
    expect(native.fields[DiagnosticField.nativeCode], 28);
    expect(native.fields[DiagnosticField.workspaceFileOperation], 2);
    expect(native.fields[DiagnosticField.workspaceStage],
        AndroidWorkspaceCheckStage.reservation.index);
    expect(diagnostics.entries.last.event,
        DiagnosticEvent.androidWorkspaceCheckFailed);
    expect(diagnostics.entries.last.fields[DiagnosticField.workspaceStage],
        AndroidWorkspaceCheckStage.reservation.index);
    await expectClean();
  });
  test('cancelled native check reports cancellation after draining cleanup',
      () async {
    final diagnostics = RecordingDiagnostics(), control = LibraryScanControl();
    await expectLater(
        checkAndroidDownloadWorkspace(
            parent: root,
            control: control,
            files: _Files(onMove: control.cancel),
            diagnostics: diagnostics),
        throwsA(isA<LibraryScanCancelled>()));
    expect(diagnostics.entries.map((e) => e.event), [
      DiagnosticEvent.androidWorkspaceCheckStarted,
      DiagnosticEvent.androidWorkspaceCheckCancelled,
    ]);
    await expectClean();
  });
  test(
      'exported failed-check diagnostics contain no private path or error text',
      () async {
    final log = await Directory.systemTemp.createTemp('cmp_probe_log_');
    addTearDown(() => log.delete(recursive: true));
    final diagnostics =
        LocalDiagnosticsService(directoryProvider: () async => log);
    final missing = Directory(p.join(root.path, 'PRIVATE_PATH_DO_NOT_EXPORT'));
    await expectLater(
        checkAndroidDownloadWorkspace(
            parent: missing,
            control: LibraryScanControl(),
            diagnostics: diagnostics),
        throwsA(isA<FileSystemException>()));
    final report = await (await diagnostics.exportReport()).readAsString();
    expect(report, contains('androidWorkspaceCheckFailed'));
    expect(report, contains('"workspaceStage": 0'));
    expect(report, isNot(contains('PRIVATE_PATH_DO_NOT_EXPORT')));
    expect(report, isNot(contains(root.path)));
    await expectClean();
  });
}

final class _Files implements PublicationFiles {
  _Files(
      {this.onLock,
      this.onMove,
      this.failMove = false,
      this.corruptOwner = false});
  final void Function()? onLock, onMove;
  final bool failMove;
  final bool corruptOwner;
  final _native = const NativePublicationFiles();
  @override
  Future<bool> createDirectory(String path) => _native.createDirectory(path);
  @override
  Future<PublicationFileLock> lock(String path, {bool seal = false}) async {
    final result = await _native.lock(path, seal: seal);
    onLock?.call();
    return result;
  }

  @override
  Future<void> moveNoReplace(String source, String target) async {
    if (failMove) {
      throw const PublicationFileException(PublicationFileFailure.noSpace,
          osCode: 28);
    }
    await _native.moveNoReplace(source, target);
    if (corruptOwner && p.basename(source) == 'reservation.part') {
      await File(p.join(p.dirname(p.dirname(p.dirname(target))), 'owner.json'))
          .writeAsString('damaged');
    }
    if (p.basename(source) == 'source') onMove?.call();
  }
}
