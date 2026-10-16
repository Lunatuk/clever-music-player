import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/publication_retention_repository.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/desktop_publication_maintenance.dart';
import 'package:clever_music_player/src/library_sync/desktop_publication_store.dart';
import 'package:clever_music_player/src/library_sync/native_publication_files.dart';
import 'package:clever_music_player/src/library_sync/publication_intent.dart';
import 'package:clever_music_player/src/library_sync/publication_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/download_fixture.dart';

void main() {
  late DownloadFixture f;
  late DownloadJob job;
  late DesktopPublicationStore store;
  late DesktopPublicationMaintenance maintenance;
  late _Files files;
  setUp(() async {
    f = await DownloadFixture.open();
    job = await f.claim(stage: DownloadJobStage.publication);
    files = _Files();
    store = DesktopPublicationStore(
        jobs: f.repositories.downloadJobs, files: files, clock: f.clock);
    maintenance = DesktopPublicationMaintenance(
        repository: f.repositories.publicationRetention,
        files: files,
        clock: f.clock);
  });
  tearDown(() async {
    await maintenance.close();
    await store.close();
    await f.close();
  });
  Directory operation(String id) => Directory(p.join(
      f.destination.path,
      '.cmp-publications-v1',
      'operations',
      '${publicationResourceKey(job.key)}-$id'));
  File resourceLock() => File(p.join(f.destination.path, '.cmp-publications-v1',
      'locks', '${publicationResourceKey(job.key)}.lock'));
  Future<PublicationMaintenanceResult> clean({LibraryScanControl? control}) =>
      maintenance.clean(
          destinationPath: f.destination.path,
          libraryFolderId: f.folderId,
          control: control);
  Future<Directory> stage() => store.run(job, (w) async {
        await w.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3);
        return operation(w.publicationId);
      });
  Future<PublicationReceipt> publish({bool commit = true}) async {
    final receipt = await store.run(job, (w) async {
      await w.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3);
      return w.publish(job, f.proof());
    });
    if (commit) {
      job = (await f.repositories.downloadJobs
          .advance(job, DownloadJobStage.importing, now: f.now))!;
      job = (await f.repositories.downloadImports.commit(
              job, f.publication(job, id: receipt.intent.publicationId),
              clock: f.clock))!
          .job;
    }
    return receipt;
  }

  Future<void> cancelAndAge() async {
    job = (await f.repositories.downloadJobs.cancel(job, now: f.now))!;
    f.now = f.now.add(const Duration(days: 2));
  }

  test('finished journal removed immediately, final music and DB state survive',
      () async {
    final receipt = await publish();
    final before = await f.repositories.tracks.findById(job.completedTrackId!);
    final result = await clean();
    expect(result.removedOperations, 1);
    expect(result.failed, 0);
    expect(await operation(receipt.intent.publicationId).exists(), isFalse);
    expect(await File(receipt.filePath).readAsString(), 'abc');
    expect(await f.repositories.tracks.findById(job.completedTrackId!), before);
    expect(await f.count('downloaded_assets'), 1);
    expect(await f.count('download_attempts'), 1);
    expect(await resourceLock().exists(), isTrue);
    expect((await clean()).removedOperations, 0);
  });
  test(
      'abandoned owned staging removed only after terminal job and grace period',
      () async {
    final directory = await stage();
    job = (await f.repositories.downloadJobs.cancel(job, now: f.now))!;
    expect((await clean()).preserved, 1);
    f.now = f.now.add(const Duration(days: 1));
    expect((await clean()).removedOperations, 1);
    expect(await directory.exists(), isFalse);
    expect(await f.count('tracks'), 0);
  });
  test('old reservation cannot bypass a recently finished job grace period',
      () async {
    final directory = await stage();
    f.now = f.now.add(const Duration(days: 2));
    job = (await f.repositories.downloadJobs.cancel(job, now: f.now))!;
    expect((await clean()).preserved, 1);
    expect(await directory.exists(), isTrue);
  });
  test('expired running attempt is preserved, age is not ownership evidence',
      () async {
    final directory = await stage();
    f.now = f.now.add(const Duration(days: 30));
    expect((await clean()).preserved, 1);
    expect(await directory.exists(), isTrue);
  });
  test('needsReconciliation publication survives arbitrarily old journal',
      () async {
    final receipt = await publish(commit: false);
    await f.repositories.downloadJobs.interrupt(job, now: f.now);
    f.now = f.now.add(const Duration(days: 30));
    expect((await clean()).preserved, 1);
    expect(await operation(receipt.intent.publicationId).exists(), isTrue);
    expect(await File(receipt.filePath).readAsString(), 'abc');
  });
  test('cancelled job with a physical publication keeps its evidence',
      () async {
    final receipt = await publish(commit: false);
    await cancelAndAge();
    expect((await clean()).preserved, 1);
    expect(await operation(receipt.intent.publicationId).exists(), isTrue);
  });
  test('old intent with absent target and terminal failure can be removed',
      () async {
    final receipt = await publish(commit: false);
    await File(receipt.filePath).delete();
    await cancelAndAge();
    expect((await clean()).removedOperations, 1);
  });
  test('legacy committed intent without reservation remains cleanable',
      () async {
    final receipt = await publish();
    await File(p.join(
            operation(receipt.intent.publicationId).path, 'reservation.json'))
        .delete();
    expect((await clean()).removedOperations, 1);
    expect(await File(receipt.filePath).exists(), isTrue);
  });
  test('legacy pre-intent staging without attribution is preserved', () async {
    final directory = await stage();
    await File(p.join(directory.path, 'reservation.json')).delete();
    await cancelAndAge();
    expect((await clean()).preserved, 1);
    expect(
        await File(p.join(directory.path, 'audio.part')).readAsString(), 'abc');
  });
  test('unknown files preserve the entire operation', () async {
    final directory = await stage();
    await File(p.join(directory.path, 'my-recording.mp3'))
        .writeAsString('mine');
    await cancelAndAge();
    expect((await clean()).preserved, 1);
    expect(await File(p.join(directory.path, 'audio.part')).exists(), isTrue);
    expect(
        await File(p.join(directory.path, 'my-recording.mp3')).readAsString(),
        'mine');
  });
  test('nested directory is never recursively deleted', () async {
    final directory = await stage();
    await Directory(p.join(directory.path, 'nested')).create();
    await cancelAndAge();
    expect((await clean()).preserved, 1);
    expect(await Directory(p.join(directory.path, 'nested')).exists(), isTrue);
  });
  test('changed final bytes preserve journal even with matching DB asset',
      () async {
    final receipt = await publish();
    await File(receipt.filePath).writeAsString('xyz');
    expect((await clean()).preserved, 1);
    expect(await operation(receipt.intent.publicationId).exists(), isTrue);
  });
  test('missing final after completion preserves journal', () async {
    final receipt = await publish();
    await File(receipt.filePath).delete();
    f.now = f.now.add(const Duration(days: 2));
    expect((await clean()).preserved, 1);
  });
  test('invalidated asset preserves journal', () async {
    await publish();
    await f.database
        .customStatement("UPDATE downloaded_assets SET state = 'invalid'");
    expect((await clean()).preserved, 1);
  });
  test('disabled destination preserves journal', () async {
    await publish();
    await f.database
        .customStatement('UPDATE library_folders SET is_enabled = 0');
    expect((await clean()).preserved, 1);
  });
  test('saved destination moved to another root revokes cleanup authority',
      () async {
    await publish();
    final elsewhere =
        await Directory(p.join(f.root.path, 'elsewhere')).create();
    await f.database.customStatement(
        'UPDATE library_folders SET path = ?', [elsewhere.path]);
    expect((await clean()).preserved, 1);
  });
  test('folder aliases do not authorize another folder id', () async {
    await publish();
    expect(
        (await maintenance.clean(
                destinationPath: f.destination.path,
                libraryFolderId: f.folderId + 1))
            .preserved,
        1);
  });
  test('bad owner marker aborts without touching staging', () async {
    final directory = await stage();
    await cancelAndAge();
    await File(p.join(f.destination.path, '.cmp-publications-v1', 'owner.json'))
        .writeAsString('{}');
    await expectLater(clean(), throwsA(isA<PublicationException>()));
    expect(await File(p.join(directory.path, 'audio.part')).exists(), isTrue);
  });
  test('busy OS resource lock skips, same persistent lock object remains',
      () async {
    await publish();
    final held = await const NativePublicationFiles().lock(resourceLock().path);
    try {
      expect((await clean()).busy, 1);
    } finally {
      await held.close();
    }
    expect((await clean()).removedOperations, 1);
    expect(await resourceLock().exists(), isTrue);
  });
  test('same-byte separate staging file is not treated as final hard link',
      () async {
    final receipt = await publish();
    final directory = operation(receipt.intent.publicationId);
    await File(p.join(directory.path, 'audio.part')).writeAsString('abc');
    expect((await clean()).preserved, 1);
    expect(await File(p.join(directory.path, 'audio.part')).exists(), isTrue);
  });
  test('retirement record resumes after all original metadata was deleted',
      () async {
    final receipt = await publish();
    final directory = operation(receipt.intent.publicationId);
    final entry = await PublicationJournalEntry.read(directory);
    await File(p.join(directory.path, 'retention.json'))
        .writeAsString(entry.retirementRecord, flush: true);
    for (final file in entry.files.values) {
      await file.delete();
    }
    expect((await clean()).removedOperations, 1);
    expect(await File(receipt.filePath).readAsString(), 'abc');
  });
  test(
      'retirement record resumes abandoned staging without original reservation',
      () async {
    final directory = await stage();
    await cancelAndAge();
    final entry = await PublicationJournalEntry.read(directory);
    await File(p.join(directory.path, 'retention.json'))
        .writeAsString(entry.retirementRecord, flush: true);
    await File(p.join(directory.path, 'reservation.json')).delete();
    expect((await clean()).removedOperations, 1);
  });
  test('cancel after durable retirement record leaves resumable evidence',
      () async {
    final directory = await stage();
    await cancelAndAge();
    final control = LibraryScanControl();
    files.afterMove = (target) {
      if (p.basename(target) == 'retention.json') control.cancel();
    };
    await expectLater(
        clean(control: control), throwsA(isA<LibraryScanCancelled>()));
    expect(
        await File(p.join(directory.path, 'retention.json')).exists(), isTrue);
    files.afterMove = null;
    expect((await clean()).removedOperations, 1);
  });
  test(
      'empty directory after last-marker crash can be removed without DB inference',
      () async {
    final directory = await stage();
    await for (final file in directory.list()) {
      await file.delete();
    }
    expect((await clean()).removedOperations, 1);
  });
  test('reservation size mismatch with intent preserves data', () async {
    final receipt = await publish();
    final file = File(p.join(
        operation(receipt.intent.publicationId).path, 'reservation.json'));
    final reservation =
        PublicationReservation.decode(await file.readAsString());
    await file.writeAsString(PublicationReservation(
            jobId: reservation.jobId,
            key: reservation.key,
            publicationId: reservation.publicationId,
            sizeBytes: 4,
            createdAt: reservation.createdAt)
        .encode());
    expect((await clean()).preserved, 1);
  });
  test('cleaner close cancels and drains a pending authority read', () async {
    final directory = await stage();
    await cancelAndAge();
    await maintenance.close();
    final gate = _Gate(f.repositories.publicationRetention);
    maintenance =
        DesktopPublicationMaintenance(repository: gate, clock: f.clock);
    final result = clean();
    await gate.entered.future;
    var closed = false;
    final closing = maintenance.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    gate.release.complete();
    await expectLater(result, throwsA(isA<LibraryScanCancelled>()));
    await closing;
    expect(await directory.exists(), isTrue);
    final lock = await const NativePublicationFiles().lock(resourceLock().path);
    await lock.close();
  });
  test('authority is checked again after preflight; terminal row may change',
      () async {
    final directory = await stage();
    await cancelAndAge();
    await maintenance.close();
    final changing = _ChangeAfterPreflight(
        f.repositories.publicationRetention,
        () => f.database.customStatement(
            "UPDATE download_jobs SET state = 'needsReconciliation', revision = revision + 1"));
    maintenance =
        DesktopPublicationMaintenance(repository: changing, clock: f.clock);
    expect((await clean()).preserved, 1);
    expect(await directory.exists(), isTrue);
  });
  test('staging-only reservation cannot delete an unexpected final extension',
      () async {
    final directory = await stage();
    await cancelAndAge();
    final id = p.basename(directory.path).substring(65);
    final finalFile = File(p.join(
        f.destination.path, 'cmp-${publicationResourceKey(job.key)}-$id.flac'));
    await finalFile.writeAsString('unexpected');
    expect((await clean()).preserved, 1);
    expect(await finalFile.readAsString(), 'unexpected');
  });
  test('missing state is a no-op and creates no files', () async {
    expect((await clean()).removedOperations, 0);
    expect(
        await Directory(p.join(f.destination.path, '.cmp-publications-v1'))
            .exists(),
        isFalse);
  });
  for (final text in [
    '[]',
    '{"version":1,"reservation":7,"intent":null}',
    '{broken'
  ]) {
    test('malformed retirement record is preserved: $text', () async {
      final directory = await stage();
      await cancelAndAge();
      await File(p.join(directory.path, 'retention.json')).writeAsString(text);
      expect((await clean()).preserved, 1);
      expect(await File(p.join(directory.path, 'audio.part')).exists(), isTrue);
    });
  }
  test('partial cleanup resumes after closing and reopening persistent SQLite',
      () async {
    await maintenance.close();
    await store.close();
    await f.close();
    f = await DownloadFixture.open(persistent: true);
    job = await f.claim(stage: DownloadJobStage.publication);
    store = DesktopPublicationStore(
        jobs: f.repositories.downloadJobs, clock: f.clock);
    final directory = await stage();
    await cancelAndAge();
    final entry = await PublicationJournalEntry.read(directory);
    await File(p.join(directory.path, 'retention.json'))
        .writeAsString(entry.retirementRecord, flush: true);
    await File(p.join(directory.path, 'reservation.json')).delete();
    await store.close();
    f = await f.reopen();
    maintenance = DesktopPublicationMaintenance(
        repository: f.repositories.publicationRetention, clock: f.clock);
    expect((await clean()).removedOperations, 1);
    expect(await directory.exists(), isFalse);
  });
  test('Windows denied staging deletion preserves retirement record for retry',
      () async {
    final directory = await stage();
    await cancelAndAge();
    final held = await const NativePublicationFiles()
        .lock(p.join(directory.path, 'audio.part'));
    try {
      expect((await clean()).failed, 1);
      expect(await File(p.join(directory.path, 'retention.json')).exists(),
          isTrue);
    } finally {
      await held.close();
    }
    expect((await clean()).removedOperations, 1);
  }, skip: Platform.isWindows ? false : 'Windows share-delete contract');
  test('recovery reads immutable intent from a partially retired journal',
      () async {
    final receipt = await publish(commit: false);
    final directory = operation(receipt.intent.publicationId);
    final entry = await PublicationJournalEntry.read(directory);
    await File(p.join(directory.path, 'retention.json'))
        .writeAsString(entry.retirementRecord, flush: true);
    for (final file in entry.files.values) {
      await file.delete();
    }
    await f.repositories.downloadJobs.interrupt(job, now: f.now);
    job = (await f.repositories.downloadJobs.claimNext(f.account, now: f.now))!;
    expect((await clean()).preserved, 1);
    await store.run(job, (workspace) async {
      expect(await workspace.pendingPublications(),
          [receipt.intent.publicationId]);
      expect(
          (await workspace.readIntent(receipt.intent.publicationId)).encode(),
          receipt.intent.encode());
      final recovered =
          await workspace.reconcile(job, receipt.intent.publicationId);
      expect(recovered.recovered, isTrue);
      expect(await File(recovered.filePath).readAsString(), 'abc');
    });
  });
}

final class _Files implements PublicationFiles {
  final native = const NativePublicationFiles();
  void Function(String)? afterMove;
  @override
  Future<bool> createDirectory(String path) => native.createDirectory(path);
  @override
  Future<PublicationFileLock> lock(String path, {bool seal = false}) =>
      native.lock(path, seal: seal);
  @override
  Future<void> moveNoReplace(String source, String target) async {
    await native.moveNoReplace(source, target);
    afterMove?.call(target);
  }
}

final class _Gate implements PublicationRetentionRepository {
  _Gate(this.delegate);
  final PublicationRetentionRepository delegate;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<T?> withCleanupAuthority<T extends Object>(
      PublicationCleanupRequest request,
      {required DateTime notUpdatedAfter,
      required DateTime Function() clock,
      required Future<T> Function(String) action}) async {
    entered.complete();
    await release.future;
    return delegate.withCleanupAuthority(request,
        notUpdatedAfter: notUpdatedAfter, clock: clock, action: action);
  }
}

final class _ChangeAfterPreflight implements PublicationRetentionRepository {
  _ChangeAfterPreflight(this.delegate, this.change);
  final PublicationRetentionRepository delegate;
  final Future<void> Function() change;
  var calls = 0;
  @override
  Future<T?> withCleanupAuthority<T extends Object>(
      PublicationCleanupRequest request,
      {required DateTime notUpdatedAfter,
      required DateTime Function() clock,
      required Future<T> Function(String) action}) async {
    final result = await delegate.withCleanupAuthority(request,
        notUpdatedAfter: notUpdatedAfter, clock: clock, action: action);
    if (++calls == 1) await change();
    return result;
  }
}
