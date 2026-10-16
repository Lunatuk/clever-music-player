import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
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
  final stores = <DesktopPublicationStore>[];
  setUp(() async {
    f = await DownloadFixture.open();
    job = await f.claim(stage: DownloadJobStage.publication);
  });
  tearDown(() async {
    for (final store in stores) {
      await store.close();
    }
    stores.clear();
    await f.close();
  });
  DesktopPublicationStore store(
      {int bytes = 6,
      int operations = 2,
      PublicationFiles files = const NativePublicationFiles()}) {
    final result = DesktopPublicationStore(
        jobs: f.repositories.downloadJobs,
        files: files,
        clock: f.clock,
        retentionPolicy: PublicationRetentionPolicy(
            maxStagingBytes: bytes, maxOperations: operations));
    stores.add(result);
    return result;
  }

  Future<void> stage(DesktopPublicationStore store,
          {DownloadJob? current, Stream<List<int>>? input, int size = 3}) =>
      store.run(current ?? job, (w) async {
        await w.writeAudio(input ?? Stream.value([97, 98, 99]),
            expectedSize: size);
      });
  Directory getOperations() => Directory(
      p.join(f.destination.path, '.cmp-publications-v1', 'operations'));
  Matcher quota() => throwsA(isA<PublicationException>()
      .having((e) => e.reason, 'reason', PublicationFailure.quotaExceeded));

  test(
      'exact byte limit accepted, next operation rejected before input consumption',
      () async {
    await stage(store(bytes: 3));
    var consumed = false;
    Stream<List<int>> input() async* {
      consumed = true;
      yield [97, 98, 99];
    }

    await expectLater(stage(store(bytes: 3), input: input()), quota());
    expect(consumed, isFalse);
    expect(await getOperations().list().length, 1);
  });
  test('operation count limit includes committed journals with no staging',
      () async {
    await store(operations: 1).run(job, (w) async {
      await w.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3);
      await w.publish(job, f.proof());
    });
    await expectLater(stage(store(operations: 1)), quota());
  });
  test('single oversized reservation rejected without creating an operation',
      () async {
    await expectLater(stage(store(bytes: 2)), quota());
    expect(await getOperations().list().length, 0);
  });
  test('reserved size counts while first writer has not received any bytes',
      () async {
    final secondJob =
        await f.claim(externalId: '002', stage: DownloadJobStage.publication);
    final entered = Completer<void>();
    final input = StreamController<List<int>>(onListen: entered.complete);
    final first = stage(store(bytes: 5), input: input.stream);
    await entered.future;
    try {
      await expectLater(stage(store(bytes: 5), current: secondJob), quota());
    } finally {
      input.add([97, 98, 99]);
      await input.close();
      await first;
    }
    expect(await getOperations().list().length, 1);
  });
  test('folder OS quota lock prevents two resources reserving simultaneously',
      () async {
    final secondJob =
        await f.claim(externalId: '002', stage: DownloadJobStage.publication);
    final files = _GatedFiles();
    final first = stage(store(bytes: 3, files: files));
    await files.entered.future;
    try {
      await expectLater(
          stage(store(bytes: 3), current: secondJob),
          throwsA(isA<PublicationException>()
              .having((e) => e.reason, 'reason', PublicationFailure.busy)));
    } finally {
      files.release.complete();
      await first;
    }
    await expectLater(stage(store(bytes: 3), current: secondJob), quota());
    expect(await getOperations().list().length, 1);
  });
  test('published marker releases bytes, preserves final music', () async {
    final receipt = await store(bytes: 3).run(job, (w) async {
      await w.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3);
      return w.publish(job, f.proof());
    });
    await stage(store(bytes: 3));
    expect(await File(receipt.filePath).readAsString(), 'abc');
    expect(await getOperations().list().length, 2);
  });
  test('legacy staging without reservation counts actual bytes', () async {
    await stage(store());
    final directory = await getOperations().list().first;
    await File(p.join(directory.path, 'reservation.json')).delete();
    await expectLater(stage(store(bytes: 3)), quota());
  });
  test('unknown content cannot silently bypass accounting', () async {
    await stage(store());
    final directory = await getOperations().list().first;
    await File(p.join(directory.path, 'unknown.bin')).writeAsString('large');
    await expectLater(
        stage(store()),
        throwsA(isA<PublicationException>().having(
            (e) => e.reason, 'reason', PublicationFailure.invalidJournal)));
    expect(await File(p.join(directory.path, 'unknown.bin')).readAsString(),
        'large');
  });
  test('short input leaves attributed reservation counted against next attempt',
      () async {
    await expectLater(
        stage(store(bytes: 3), input: Stream.value([97])),
        throwsA(isA<PublicationException>().having(
            (e) => e.reason, 'reason', PublicationFailure.invalidStaging)));
    final directory = await getOperations().list().first;
    expect(await File(p.join(directory.path, 'reservation.json')).exists(),
        isTrue);
    await expectLater(stage(store(bytes: 3)), quota());
  });
  test('retention frees operation quota, next real job can publish', () async {
    final receipt = await store(operations: 1).run(job, (w) async {
      await w.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3);
      return w.publish(job, f.proof());
    });
    job = (await f.repositories.downloadJobs
        .advance(job, DownloadJobStage.importing, now: f.now))!;
    await f.repositories.downloadImports.commit(
        job, f.publication(job, id: receipt.intent.publicationId),
        clock: f.clock);
    final cleaner = DesktopPublicationMaintenance(
        repository: f.repositories.publicationRetention, clock: f.clock);
    try {
      expect(
          (await cleaner.clean(
                  destinationPath: f.destination.path,
                  libraryFolderId: f.folderId))
              .removedOperations,
          1);
    } finally {
      await cleaner.close();
    }
    final next =
        await f.claim(externalId: '002', stage: DownloadJobStage.publication);
    await stage(store(operations: 1), current: next);
    expect(await File(receipt.filePath).exists(), isTrue);
  });
}

final class _GatedFiles implements PublicationFiles {
  final native = const NativePublicationFiles();
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<bool> createDirectory(String path) => native.createDirectory(path);
  @override
  Future<PublicationFileLock> lock(String path, {bool seal = false}) =>
      native.lock(path, seal: seal);
  @override
  Future<void> moveNoReplace(String source, String target) async {
    if (p.basename(target) == 'reservation.json') {
      entered.complete();
      await release.future;
    }
    await native.moveNoReplace(source, target);
  }
}
