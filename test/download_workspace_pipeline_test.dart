import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library_sync/binary_download.dart';
import 'package:clever_music_player/src/library_sync/binary_http_download_transport.dart';
import 'package:clever_music_player/src/library_sync/desktop_download_coordinator.dart';
import 'package:clever_music_player/src/library_sync/desktop_publication_maintenance.dart';
import 'package:clever_music_player/src/library_sync/desktop_publication_store.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata_preparer.dart';
import 'package:clever_music_player/src/library_sync/download_workspace.dart';
import 'package:clever_music_player/src/library_sync/publication_journal.dart';
import 'package:clever_music_player/src/library_sync/publication_intent.dart';
import 'package:clever_music_player/src/library_sync/native_publication_files.dart';
import 'package:clever_music_player/src/library_sync/raw_download_pool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/binary_download_fixture.dart';
import 'support/download_fixture.dart';

void main() {
  late DownloadFixture f;
  late DownloadWorkspace workspace;
  final rawResults = <RawDownloadedAudio>[];
  final stores = <DesktopPublicationStore>[];
  setUp(() async {
    f = await DownloadFixture.open();
    workspace = await DownloadWorkspace.open(
        parent: f.root, maxReservedBytes: 9, preparedGrowthBytes: 0);
  });
  tearDown(() async {
    for (final store in stores) {
      await store.close();
    }
    stores.clear();
    for (final raw in rawResults) {
      await raw.close();
    }
    rawResults.clear();
    await workspace.close();
    await f.close();
  });
  RawDownloadPool pool() => RawDownloadPool(
      parent: f.root, workspace: workspace, maxReservedBytes: 6);
  Future<RawDownloadedAudio> raw() async {
    final result = await pool().reserve(3).write(Stream.value([97, 98, 99]));
    rawResults.add(result);
    return result;
  }

  DesktopPublicationStore publisher() {
    final store = DesktopPublicationStore(
        jobs: f.repositories.downloadJobs,
        workspace: workspace,
        clock: f.clock);
    stores.add(store);
    return store;
  }

  test('different raw pools share budget before opening binary HTTP', () async {
    final held =
        workspace.reserve(DownloadWorkspaceStage.prepared, maxAudioBytes: 8);
    final server = await TestBinaryDownloadServer.open(f.raw);
    final transport = BinaryHttpDownloadTransport.loopbackForTesting(
        server.origin,
        pool: pool());
    try {
      await expectLater(
          transport.download(server.address, maxBytes: 3),
          throwsA(isA<BinaryDownloadException>().having((e) => e.failure,
              'failure', BinaryDownloadFailure.quotaExceeded)));
      expect(workspace.reservedBytes, 8);
    } finally {
      await held.close();
      await transport.close();
      await server.close();
    }
  });
  test(
      'raw/prepared/publication overlap shares budget, final music outlives raw',
      () async {
    final input = await raw();
    final backend = DownloadTestBackend();
    backend.onWrite = (_) async {
      expect(workspace.reservedBytes, 6);
      expect(workspace.reservedEntries, 2);
    };
    final coordinator = DesktopDownloadCoordinator(
        jobs: f.repositories.downloadJobs,
        imports: f.repositories.downloadImports,
        retention: f.repositories.publicationRetention,
        workspace: workspace,
        preparer: DownloadedAudioMetadataPreparer(
            backend: backend,
            workspace: workspace,
            temporaryParent: f.root,
            clock: f.clock),
        metadataReader: DownloadTestMetadataReader(),
        clock: f.clock,
        artworkCache: AppSupportArtworkCacheService(
            artworkDirectory: Directory(p.join(f.root.path, 'covers'))));
    try {
      final job = await f.claim();
      final result = await coordinator.processDownloadedFile(
          job, input.source, downloadExpectation());
      expect(result.outcome, DownloadCoordinationOutcome.completed);
      expect(result.cleanupFailed, isFalse);
      expect(workspace.reservedBytes, 3);
      expect(await f.count('tracks'), 1);
      await input.close();
      expect(workspace.reservedBytes, 0);
      expect(await File(result.imported!.track.filePath).readAsString(), 'abc');
    } finally {
      await coordinator.close();
    }
  });
  test(
      'preparation quota fails before backend and leaves the raw reader intact',
      () async {
    final input = await raw();
    final other =
        workspace.reserve(DownloadWorkspaceStage.raw, maxAudioBytes: 4);
    final backend = DownloadTestBackend();
    final preparer = DownloadedAudioMetadataPreparer(
        backend: backend, workspace: workspace, temporaryParent: f.root);
    try {
      await expectLater(
          preparer.prepare(input.source, downloadExpectation()),
          throwsA(isA<DownloadWorkspaceException>().having((e) => e.failure,
              'failure', DownloadWorkspaceFailure.quotaExceeded)));
      expect(backend.writes, 0);
      expect(workspace.reservedBytes, 7);
      expect(await File(input.source.path).readAsString(), 'abc');
    } finally {
      await preparer.close();
      await other.close();
    }
  });
  test('publication quota includes raw/prepared held by independent readers',
      () async {
    await raw();
    final prepared =
        workspace.reserve(DownloadWorkspaceStage.prepared, maxAudioBytes: 4);
    final job = await f.claim(stage: DownloadJobStage.publication);
    try {
      await expectLater(
          publisher().run(job,
              (w) => w.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3)),
          throwsA(isA<DownloadWorkspaceException>().having((e) => e.failure,
              'failure', DownloadWorkspaceFailure.quotaExceeded)));
      expect(workspace.reservedBytes, 7);
      expect(await f.count('tracks'), 0);
    } finally {
      await prepared.close();
    }
  });
  test('output exceeding prepared cap is rejected and owned bytes cleaned',
      () async {
    final input = await raw();
    final backend = _OversizedBackend();
    final preparer = DownloadedAudioMetadataPreparer(
        backend: backend, workspace: workspace, temporaryParent: f.root);
    try {
      await expectLater(
          preparer.prepare(input.source, downloadExpectation()),
          throwsA(isA<DownloadWorkspaceException>().having((e) => e.failure,
              'failure', DownloadWorkspaceFailure.quotaExceeded)));
      expect(backend.limit, 3);
      expect(workspace.reservedBytes, 3);
    } finally {
      await preparer.close();
    }
  });
  test(
      'failed copy remains charged across reopen until publication retention proves cleanup',
      () async {
    final job = await f.claim(stage: DownloadJobStage.publication);
    await expectLater(
        publisher()
            .run(job, (w) => w.writeAudio(Stream.value([97]), expectedSize: 3)),
        throwsA(isA<PublicationException>().having(
            (e) => e.reason, 'reason', PublicationFailure.invalidStaging)));
    expect(workspace.reservedBytes, 3);
    final failed = await f.repositories.downloadJobs
        .fail(job, DownloadFailure.invalidMedia, now: f.now);
    expect(failed, isNotNull);
    await workspace.close();
    workspace =
        await DownloadWorkspace.open(parent: f.root, maxReservedBytes: 3);
    expect(workspace.reservedBytes, 3);
    expect(() => pool().reserve(1), throwsA(isA<BinaryDownloadException>()));
    final maintenance = DesktopPublicationMaintenance(
        repository: f.repositories.publicationRetention,
        policy: PublicationRetentionPolicy(abandonedAge: Duration.zero),
        clock: f.clock);
    try {
      final result = await maintenance.clean(
          destinationPath: f.destination.path, libraryFolderId: f.folderId);
      expect(result.removedOperations, 1);
      await workspace.recover();
      expect(workspace.reservedBytes, 0);
      expect(await f.count('tracks'), 0);
    } finally {
      await maintenance.close();
    }
  });
  test('incomplete publication retains charge while physical staging exists',
      () async {
    final job = await f.claim(stage: DownloadJobStage.publication);
    await publisher().run(job, (w) async {
      await w.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3);
    });
    expect(workspace.reservedBytes, 3);
    // Incomplete staging must be retained even without an active writer.
    final result = await workspace.recover();
    expect(result.retained, 1);
    expect(workspace.reservedBytes, 3);
  });
  test('preparer and coordinator cannot use different working budgets', () {
    final preparer = DownloadedAudioMetadataPreparer(
        backend: DownloadTestBackend(), workspace: workspace);
    addTearDown(preparer.close);
    expect(
        () => DesktopDownloadCoordinator(
            jobs: f.repositories.downloadJobs,
            imports: f.repositories.downloadImports,
            retention: f.repositories.publicationRetention,
            preparer: preparer,
            artworkCache: AppSupportArtworkCacheService(
                artworkDirectory: Directory(p.join(f.root.path, 'covers')))),
        throwsArgumentError);
  });
  test(
      'published music is preserved even before import and is not temporary data',
      () async {
    final job = await f.claim(stage: DownloadJobStage.publication);
    final receipt = await publisher().run(job, (w) async {
      await w.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3);
      return w.publish(job, f.proof());
    });
    expect(workspace.reservedBytes, 0);
    expect(await f.count('tracks'), 0);
    await workspace.recover();
    expect(await File(receipt.filePath).readAsString(), 'abc');
  });
  test('busy external OS lock prevents releasing a publication reservation',
      () async {
    final job = await f.claim(stage: DownloadJobStage.publication);
    late String operation;
    final receipt = await publisher().run(job, (w) async {
      await w.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3);
      operation = '${publicationResourceKey(job.key)}-${w.publicationId}';
      return w.publish(job, f.proof());
    });
    final held = workspace.reserve(DownloadWorkspaceStage.publication,
        maxAudioBytes: 3,
        publication: DownloadPublicationReference(
            destinationRoot: f.destination.path, operation: operation));
    await held.materialize();
    final lock = await const NativePublicationFiles().lock(p.join(
        f.destination.path,
        '.cmp-publications-v1',
        'locks',
        '${publicationResourceKey(job.key)}.lock'));
    try {
      await held.close();
      expect(workspace.reservedBytes, 3);
      await workspace.recover();
      expect(workspace.reservedBytes, 3);
    } finally {
      await lock.close();
    }
    await workspace.recover();
    expect(workspace.reservedBytes, 0);
    expect(await File(receipt.filePath).readAsString(), 'abc');
  });
  test('missing destination preserves publication charge across reopen',
      () async {
    final job = await f.claim(stage: DownloadJobStage.publication);
    await publisher().run(
        job, (w) => w.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3));
    final moved = Directory(p.join(f.root.path, 'renamed-music'));
    // Both resolved paths stay within this fixture; restore before teardown.
    expect(p.isWithin(f.root.path, moved.path), isTrue);
    expect(p.isWithin(f.root.path, f.destination.path), isTrue);
    await f.destination.rename(moved.path);
    try {
      await workspace.close();
      workspace = await DownloadWorkspace.open(parent: f.root);
      expect(workspace.reservedBytes, 3);
      expect(workspace.admissionBlocked, isFalse);
    } finally {
      await moved.rename(f.destination.path);
    }
  });
}

// A trusted backend contract violation is still caught before verification/import.
final class _OversizedBackend extends DownloadTestBackend {
  int? limit;
  @override
  Future<void> writeMetadata(File source, File output, info, expected, control,
      {File? cover,
      EmbeddedCoverFormat? coverFormat,
      int? maxOutputBytes}) async {
    limit = maxOutputBytes;
    await output.writeAsString('abcd');
  }
}
