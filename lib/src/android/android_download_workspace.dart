import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/async_lifecycle.dart';
import '../library/library_scan_control.dart';
import '../library_sync/download_workspace.dart';
import '../library_sync/native_publication_files.dart';

/// App-owned internal files, not cache and never the selected SAF destination.
Future<Directory> androidDownloadWorkspaceParent() async => Directory(p.join(
        (await getApplicationSupportDirectory()).path, 'android-downloads'))
    .create(recursive: true);

/// Small, explicit on-device qualification of the actual packaged native asset.
/// Each run owns a fresh child; it never opens or cleans a production workspace.
Future<void> checkAndroidDownloadWorkspace(
    {required Directory parent,
    required LibraryScanControl control,
    PublicationFiles files = const NativePublicationFiles()}) async {
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
    workspace = await DownloadWorkspace.open(
        parent: scratch,
        maxReservedBytes: 4096,
        maxEntries: 2,
        preparedGrowthBytes: 0,
        files: files,
        control: control);
    // A second owner must fail while the first owns its OS lock.
    try {
      final other = await DownloadWorkspace.open(parent: scratch, files: files);
      await other.close();
      throw StateError('Workspace lock did not exclude a second owner.');
    } on DownloadWorkspaceException catch (error) {
      if (error.failure != DownloadWorkspaceFailure.busy) rethrow;
    }
    control.throwIfCancelled();
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
    await audio.writeAsBytes(bytes, flush: true);
    control.throwIfCancelled();
    final actual = await audio.readAsBytes();
    if (actual.length != bytes.length ||
        List.generate(bytes.length, (i) => actual[i] == bytes[i])
            .contains(false)) {
      throw StateError('Workspace byte verification failed.');
    }
    await lease.close();
    lease = null;
    if (workspace.reservedBytes != 0 || workspace.reservedEntries != 0) {
      throw StateError('Workspace reservation was not released.');
    }
    // No-replace is required even when a target already exists.
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
    await files.moveNoReplace(source.path, target.path);
    if (await source.exists() || await target.readAsString() != 'new') {
      throw StateError('Workspace move did not preserve bytes.');
    }
    control.throwIfCancelled();
  } finally {
    // Drain handles before deleting only this invocation's fresh private child.
    // Always attempt both closes: a damaged reservation must not leak the
    // workspace's OS lock. Retain the child if either cleanup step fails.
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
  }
}
