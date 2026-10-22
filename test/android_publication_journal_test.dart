import 'dart:io';

import 'package:clever_music_player/src/android/android_publication_journal.dart';
import 'package:clever_music_player/src/android/android_publication_receipt.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/native_publication_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/android_publication_fixture.dart';
import 'support/download_fixture.dart';

void main() {
  late DownloadFixture f;
  late AndroidPublicationJournal journal;
  late DownloadJob job;
  late AndroidPublicationReceipt receipt;
  setUp(() async {
    f = await androidPublicationFixture();
    job = await f.claim(stage: DownloadJobStage.importing);
    receipt = androidReceipt(f, job);
    journal = await AndroidPublicationJournal.open(privateParent: f.root);
  });
  tearDown(() async {
    await journal.close();
    await f.close();
  });
  Future<void> record(
          [AndroidPublicationReceipt? value, DownloadJob? current]) =>
      journal.record(value ?? receipt,
          job: current ?? job,
          jobs: f.repositories.downloadJobs,
          clock: f.clock,
          control: LibraryScanControl());
  test(
      'durable immutable receipt survives close/reopen and repeats idempotently',
      () async {
    await record();
    await record();
    expect((await journal.pending()).single.encode(), receipt.encode());
    await journal.close();
    journal = await AndroidPublicationJournal.open(privateParent: f.root);
    expect((await journal.pending()).single.encode(), receipt.encode());
    expect(await f.raw.readAsString(), 'abc');
  });
  test('OS lock rejects another journal owner without losing records',
      () async {
    await record();
    await expectLater(AndroidPublicationJournal.open(privateParent: f.root),
        throwsA(isA<PublicationFileException>()));
    expect((await journal.pending()).length, 1);
  });
  test('same publication ID cannot be rebound to a different document',
      () async {
    await record();
    await expectLater(record(androidReceipt(f, job, documentId: 'different')),
        throwsA(anything));
    expect((await journal.pending()).single.encode(), receipt.encode());
  });
  for (final revoked in ['lease', 'account', 'folder', 'address']) {
    test('$revoked loss prevents a new durable receipt', () async {
      if (revoked == 'lease') f.now = job.leaseUntil!;
      if (revoked == 'account') {
        await f.repositories.remoteLibrary.activateAccount(f.account.identity);
      }
      if (revoked == 'folder') {
        await f.repositories.libraryFolders
            .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now);
      }
      if (revoked == 'address') {
        await f.database.customStatement(
            'UPDATE library_folders SET path = ? WHERE id = ?',
            ['content://music.documents/tree/new', f.folderId]);
      }
      await expectLater(record(), throwsA(anything));
      expect(await journal.pending(), isEmpty);
    });
  }
  test('quota includes interrupted private writes and preserves them',
      () async {
    await journal.close();
    journal = await AndroidPublicationJournal.open(
        privateParent: f.root, maxRecords: 1);
    final interrupted =
        File(p.join(journal.root.path, 'journal-${'b' * 64}.part'));
    await interrupted.writeAsString('{');
    expect(await journal.pending(), isEmpty);
    await expectLater(record(), throwsA(anything));
    expect(await interrupted.readAsString(), '{');
  });
  test('unknown and corrupt files block mutation and remain unchanged',
      () async {
    final foreign = File(p.join(journal.root.path, 'unrelated.txt'));
    await foreign.writeAsString('keep');
    await expectLater(record(), throwsA(anything));
    expect(await foreign.readAsString(), 'keep');
    await foreign.delete();
    final corrupt = File(p.join(journal.root.path, receipt.recordName));
    await corrupt.writeAsString('broken');
    await expectLater(record(), throwsA(anything));
    expect(await corrupt.readAsString(), 'broken');
  });
  test('receipt cleanup waits for atomic import and never deletes audio',
      () async {
    await record();
    Future<bool> acknowledge() => journal.acknowledge(receipt,
        retention: f.repositories.publicationRetention,
        notUpdatedAfter: f.now,
        clock: f.clock);
    expect(await acknowledge(), isFalse);
    final result = await f.repositories.downloadImports.commit(job,
        receipt.importTrack(androidPreparedTrack(f, job, receipt), f.proof()),
        clock: f.clock);
    expect(result, isNotNull);
    expect(await acknowledge(), isTrue);
    expect(await acknowledge(), isTrue);
    expect(await journal.pending(), isEmpty);
    expect(await f.raw.readAsString(), 'abc');
    expect(await f.count('tracks'), 1);
  });
  test('lost cleanup authority preserves receipt after completed import',
      () async {
    await record();
    await f.repositories.downloadImports.commit(job,
        receipt.importTrack(androidPreparedTrack(f, job, receipt), f.proof()),
        clock: f.clock);
    await f.repositories.libraryFolders
        .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now);
    expect(
        await journal.acknowledge(receipt,
            retention: f.repositories.publicationRetention,
            notUpdatedAfter: f.now,
            clock: f.clock),
        isFalse);
    expect((await journal.pending()).length, 1);
  });
  test('failed no-replace move leaves only a bounded non-receipt private write',
      () async {
    await journal.close();
    final files = _FailingFiles();
    journal = await AndroidPublicationJournal.open(
        privateParent: f.root, files: files);
    files.fail = true;
    await expectLater(record(), throwsA(anything));
    expect(await journal.pending(), isEmpty);
    expect(
        (await journal.root.list().toList())
            .where((e) => e.path.endsWith('.part'))
            .length,
        1);
    files.fail = false;
    await record();
    expect((await journal.pending()).single.encode(), receipt.encode());
  });
  test('close drains accepted receipt persistence and rejects new work',
      () async {
    await journal.close();
    await expectLater(journal.pending(), throwsStateError);
    await journal.close();
    journal = await AndroidPublicationJournal.open(privateParent: f.root);
    final writing = record();
    final closing = journal.close();
    await writing;
    await closing;
    journal = await AndroidPublicationJournal.open(privateParent: f.root);
    expect((await journal.pending()).single.encode(), receipt.encode());
  });
}

final class _FailingFiles implements PublicationFiles {
  final _native = const NativePublicationFiles();
  bool fail = false;
  @override
  Future<bool> createDirectory(String path) => _native.createDirectory(path);
  @override
  Future<PublicationFileLock> lock(String path, {bool seal = false}) =>
      _native.lock(path, seal: seal);
  @override
  Future<void> moveNoReplace(String source, String target) async {
    if (fail) {
      throw const PublicationFileException(PublicationFileFailure.noSpace);
    }
    await _native.moveNoReplace(source, target);
  }
}
