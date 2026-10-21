import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/async_lifecycle.dart';
import '../diagnostics/diagnostics_service.dart';
import '../library/library_scan_control.dart';
import '../library_sync/download_workspace.dart';
import '../library_sync/native_publication_files.dart';

/// App-owned internal files, not cache and never the selected SAF destination.
Future<Directory> androidDownloadWorkspaceParent() async => Directory(p.join(
        (await getApplicationSupportDirectory()).path, 'android-downloads'))
    .create(recursive: true);

enum AndroidWorkspaceCheckStage {
  parent,
  open,
  exclusiveOwner,
  reservation,
  write,
  read,
  release,
  collision,
  move,
  cleanup
}

/// Explicit qualification of the packaged native asset in a fresh child only.
Future<void> checkAndroidDownloadWorkspace(
    {required Directory parent,
    required LibraryScanControl control,
    PublicationFiles files = const NativePublicationFiles(),
    DiagnosticsService diagnostics = const NoopDiagnosticsService()}) async {
  var stage = AndroidWorkspaceCheckStage.parent;
  diagnostics.record(DiagnosticEvent.androidWorkspaceCheckStarted);
  try {
    await _checkAndroidDownloadWorkspace(
        parent: parent,
        control: control,
        files: _ProbeFiles(files, diagnostics, () => stage),
        onStage: (value) => stage = value);
    diagnostics.record(DiagnosticEvent.androidWorkspaceCheckCompleted);
  } on LibraryScanCancelled {
    diagnostics.record(DiagnosticEvent.androidWorkspaceCheckCancelled,
        fields: {DiagnosticField.workspaceStage: stage.index});
    rethrow;
  } on Object catch (error) {
    diagnostics.record(DiagnosticEvent.androidWorkspaceCheckFailed,
        error: error,
        fields: {
          DiagnosticField.workspaceStage: stage.index,
          if (error is PublicationFileException && error.osCode != null)
            DiagnosticField.nativeCode: error.osCode,
          if (error is FileSystemException && error.osError != null)
            DiagnosticField.nativeCode: error.osError!.errorCode,
        });
    rethrow;
  }
}

Future<void> _checkAndroidDownloadWorkspace(
    {required Directory parent,
    required LibraryScanControl control,
    required PublicationFiles files,
    required void Function(AndroidWorkspaceCheckStage) onStage}) async {
  control.throwIfCancelled();
  final canonicalParent = await parent.resolveSymbolicLinks();
  final scratch = await Directory(canonicalParent).createTemp('probe-');
  final canonicalScratch = await scratch.resolveSymbolicLinks();
  if (!p.isWithin(canonicalParent, canonicalScratch)) {
    throw const DownloadWorkspaceException(DownloadWorkspaceFailure.unsafePath);
  }
  DownloadWorkspace? workspace;
  DownloadWorkspaceReservation? lease;
  try {
    control.throwIfCancelled();
    onStage(AndroidWorkspaceCheckStage.open);
    workspace = await DownloadWorkspace.open(
        parent: scratch,
        maxReservedBytes: 4096,
        maxEntries: 2,
        preparedGrowthBytes: 0,
        files: files,
        control: control);
    // A second owner must fail while the first owns its OS lock.
    onStage(AndroidWorkspaceCheckStage.exclusiveOwner);
    try {
      final other = await DownloadWorkspace.open(parent: scratch, files: files);
      await other.close();
      throw StateError('Workspace lock did not exclude a second owner.');
    } on DownloadWorkspaceException catch (error) {
      if (error.failure != DownloadWorkspaceFailure.busy) rethrow;
    }
    control.throwIfCancelled();
    onStage(AndroidWorkspaceCheckStage.reservation);
    lease = workspace.reserve(DownloadWorkspaceStage.raw, maxAudioBytes: 4096);
    try {
      final unexpected =
          workspace.reserve(DownloadWorkspaceStage.raw, maxAudioBytes: 1);
      await unexpected.close();
      throw StateError('Workspace admitted data over its budget.');
    } on DownloadWorkspaceException catch (error) {
      if (error.failure != DownloadWorkspaceFailure.quotaExceeded) rethrow;
    }
    control.throwIfCancelled();
    final operation = await lease.materialize();
    final audio = File(p.join(operation.path, 'audio.part'));
    final bytes = List<int>.generate(4096, (i) => i % 251);
    onStage(AndroidWorkspaceCheckStage.write);
    await audio.writeAsBytes(bytes, flush: true);
    control.throwIfCancelled();
    onStage(AndroidWorkspaceCheckStage.read);
    final actual = await audio.readAsBytes();
    if (actual.length != bytes.length ||
        List.generate(bytes.length, (i) => actual[i] == bytes[i])
            .contains(false)) {
      throw StateError('Workspace byte verification failed.');
    }
    onStage(AndroidWorkspaceCheckStage.release);
    await lease.close();
    lease = null;
    if (workspace.reservedBytes != 0 || workspace.reservedEntries != 0) {
      throw StateError('Workspace reservation was not released.');
    }
    // No-replace is required even when a target already exists.
    onStage(AndroidWorkspaceCheckStage.collision);
    final source =
        await File(p.join(scratch.path, 'source')).writeAsString('new');
    final target =
        await File(p.join(scratch.path, 'target')).writeAsString('old');
    try {
      await files.moveNoReplace(source.path, target.path);
      throw StateError('Workspace overwrote an existing target.');
    } on PublicationFileException catch (error) {
      if (error.reason != PublicationFileFailure.collision) rethrow;
    }
    if (await source.readAsString() != 'new' ||
        await target.readAsString() != 'old') {
      throw StateError('Workspace changed a colliding file.');
    }
    await target.delete();
    onStage(AndroidWorkspaceCheckStage.move);
    await files.moveNoReplace(source.path, target.path);
    if (await source.exists() || await target.readAsString() != 'new') {
      throw StateError('Workspace move did not preserve bytes.');
    }
    control.throwIfCancelled();
  } finally {
    // Drain handles before deleting only this invocation's fresh private child.
    // Always attempt both closes: a damaged reservation must not leak the
    // workspace's OS lock. Retain the child if either cleanup step fails.
    try {
      await finishCleanup([
        () async => lease?.close(),
        () async => workspace?.close(),
      ]);
      if (await FileSystemEntity.type(scratch.path, followLinks: false) ==
              FileSystemEntityType.directory &&
          await scratch.resolveSymbolicLinks() == canonicalScratch &&
          p.isWithin(canonicalParent, canonicalScratch)) {
        await scratch.delete(recursive: true);
      }
    } on Object {
      onStage(AndroidWorkspaceCheckStage.cleanup);
      rethrow;
    }
  }
}

/// Capture native errno before workspace errors deliberately hide their cause.
/// The two expected refusal checks are not reported as unexpected failures.
final class _ProbeFiles implements PublicationFiles {
  _ProbeFiles(this.delegate, this.diagnostics, this.stage);
  final PublicationFiles delegate;
  final DiagnosticsService diagnostics;
  final AndroidWorkspaceCheckStage Function() stage;
  Future<T> _call<T>(int operation, Future<T> Function() action) async {
    try {
      return await action();
    } on PublicationFileException catch (error) {
      final current = stage();
      final expected = current == AndroidWorkspaceCheckStage.exclusiveOwner &&
              error.reason == PublicationFileFailure.busy ||
          current == AndroidWorkspaceCheckStage.collision &&
              error.reason == PublicationFileFailure.collision;
      if (!expected) {
        diagnostics.record(DiagnosticEvent.androidWorkspaceFileOperationFailed,
            error: error,
            fields: {
              DiagnosticField.workspaceStage: current.index,
              DiagnosticField.workspaceFileOperation: operation,
              DiagnosticField.workspaceFailure: error.reason.index,
              if (error.osCode != null)
                DiagnosticField.nativeCode: error.osCode,
            });
      }
      rethrow;
    }
  }

  @override
  Future<bool> createDirectory(String path) =>
      _call(0, () => delegate.createDirectory(path));
  @override
  Future<PublicationFileLock> lock(String path, {bool seal = false}) =>
      _call(1, () => delegate.lock(path, seal: seal));
  @override
  Future<void> moveNoReplace(String source, String target) =>
      _call(2, () => delegate.moveNoReplace(source, target));
}
