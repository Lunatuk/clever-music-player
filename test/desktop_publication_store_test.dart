import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library_sync/desktop_publication_store.dart';
import 'package:clever_music_player/src/library_sync/native_publication_files.dart';
import 'package:clever_music_player/src/library_sync/publication_intent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/publication_fixture.dart';

void main() {
  late Directory temp;
  late PublicationTestJobs jobs;
  late _Files files;
  late DesktopPublicationStore store;
  final job = publicationJob();
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cmp_publication_');
    jobs = PublicationTestJobs(temp.path);
    files = _Files();
    store = DesktopPublicationStore(
        jobs: jobs, files: files, clock: () => publicationNow);
  });
  test('repeated empty input chunks stop after a bounded count', () async {
    var emitted = 0;
    Iterable<List<int>> empty() sync* {
      for (var i = 0; i < 100; i++) {
        emitted++;
        yield [];
      }
    }

    await expectLater(
        store.run(
            job,
            (workspace) => workspace.writeAudio(Stream.fromIterable(empty()),
                expectedSize: 3)),
        throwsA(isA<PublicationException>().having(
            (e) => e.reason, 'reason', PublicationFailure.invalidStaging)));
    expect(emitted, lessThan(30));
  });
  tearDown(() async {
    await store.close();
    await temp.delete(recursive: true);
  });
  Future<PublicationReceipt> publish() => store.run(job, (workspace) async {
        await workspace.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3);
        return workspace.publish(job, publicationProof());
      });
  Matcher failure(PublicationFailure reason) => throwsA(
      isA<PublicationException>().having((e) => e.reason, 'reason', reason));

  test(
      'publish complete bytes and durable intent/receipt, staging never scanned',
      () async {
    final receipt = await store.run(job, (workspace) async {
      final staged = await workspace.writeAudio(Stream.value([97, 98, 99]),
          expectedSize: 3);
      expect(isSupportedAudioFilePath(staged.path), isFalse);
      expect(staged.parent.path.startsWith(temp.path), isTrue);
      expect(await staged.readAsString(), 'abc');
      return workspace.publish(job, publicationProof());
    });
    expect(await File(receipt.filePath).readAsString(), 'abc');
    expect(isSupportedAudioFilePath(receipt.filePath), isTrue);
    expect(receipt.recovered, isFalse);
    final operation = p.join(temp.path, '.cmp-publications-v1', 'operations',
        receipt.intent.operationName);
    expect(await File(p.join(operation, 'intent.json')).readAsString(),
        receipt.intent.encode());
    expect(await File(p.join(operation, 'published.json')).readAsString(),
        receipt.intent.encode());
    expect(File(p.join(operation, 'audio.part')).existsSync(), isFalse);
  });
  test('reopen explicitly recovers same publication and confirms current bytes',
      () async {
    final receipt = await publish();
    await store.close();
    store = DesktopPublicationStore(
        jobs: jobs,
        clock: () => publicationNow.add(const Duration(seconds: 1)));
    final recovered = await store.run(job, (workspace) async {
      expect(await workspace.pendingPublications(),
          [receipt.intent.publicationId]);
      return workspace.reconcile(job, receipt.intent.publicationId);
    });
    expect(recovered.filePath, receipt.filePath);
    expect(recovered.recovered, isTrue);
    expect(
        recovered.verification.checkedAt
            .isAfter(receipt.verification.checkedAt),
        isTrue);
    expect(await File(recovered.filePath).readAsString(), 'abc');
  });
  for (final phase in ['before-move', 'after-move', 'receipt']) {
    test(
        'failure $phase never overwrites and recovery distinguishes the physical effect',
        () async {
      String? id;
      files.move = (source, target) async {
        if (source.endsWith('audio.part')) {
          if (phase == 'before-move') {
            throw const PublicationFileException(PublicationFileFailure.io);
          }
          await files.native.moveNoReplace(source, target);
          if (phase == 'after-move') {
            throw const PublicationFileException(PublicationFileFailure.io);
          }
          return;
        }
        if (phase == 'receipt' && target.endsWith('published.json')) {
          throw const PublicationFileException(PublicationFileFailure.io);
        }
        await files.native.moveNoReplace(source, target);
      };
      await expectLater(
          store.run(job, (workspace) async {
            id = workspace.publicationId;
            await workspace.writeAudio(Stream.value([97, 98, 99]),
                expectedSize: 3);
            return workspace.publish(job, publicationProof());
          }),
          failure(PublicationFailure.needsReconciliation));
      files.move = null;
      if (phase == 'before-move') {
        await expectLater(
            store.run(job, (workspace) => workspace.reconcile(job, id!)),
            failure(PublicationFailure.unsafePath));
      } else {
        final recovered =
            await store.run(job, (workspace) => workspace.reconcile(job, id!));
        expect(await File(recovered.filePath).readAsString(), 'abc');
        expect(recovered.recovered, isTrue);
      }
    });
  }
  test('existing destination preserved even when bytes happen to match',
      () async {
    await expectLater(
        store.run(job, (workspace) async {
          await workspace.writeAudio(Stream.value([97, 98, 99]),
              expectedSize: 3);
          final intent = PublicationIntent(
              publicationId: workspace.publicationId,
              jobId: job.id,
              key: job.key,
              verification: publicationProof());
          final target = await File(p.join(temp.path, intent.fileName))
              .writeAsString('abc');
          try {
            return await workspace.publish(job, publicationProof());
          } finally {
            expect(await target.readAsString(), 'abc');
          }
        }),
        failure(PublicationFailure.collision));
  });
  test('concurrent collision after precheck is still rejected atomically',
      () async {
    File? target;
    files.move = (source, destination) async {
      if (source.endsWith('audio.part')) {
        target = await File(destination).writeAsString('foreign');
      }
      await files.native.moveNoReplace(source, destination);
    };
    await expectLater(
        publish(), failure(PublicationFailure.needsReconciliation));
    expect(await target!.readAsString(), 'foreign');
  });
  test('changed bytes after validation never become a published track',
      () async {
    await expectLater(
        store.run(job, (workspace) async {
          await workspace.writeAudio(Stream.value([120, 121, 122]),
              expectedSize: 3);
          return workspace.publish(job, publicationProof());
        }),
        failure(PublicationFailure.changed));
    expect(
        temp
            .listSync()
            .whereType<File>()
            .where((f) => isSupportedAudioFilePath(f.path)),
        isEmpty);
  });
  test('old workspace cannot rebind itself to another attempt token', () async {
    await expectLater(
        store.run(job, (workspace) async {
          await workspace.writeAudio(Stream.value([97, 98, 99]),
              expectedSize: 3);
          return workspace.publish(
              publicationJob(token: 'b' * 64), publicationProof());
        }),
        failure(PublicationFailure.invalidStaging));
  });
  for (final data in [
    [97, 98],
    [97, 98, 99, 100],
    [97, 98, 256]
  ]) {
    test('incorrect stream size/bytes $data rejected', () async {
      await expectLater(
          store.run(
              job,
              (workspace) =>
                  workspace.writeAudio(Stream.value(data), expectedSize: 3)),
          failure(PublicationFailure.invalidStaging));
    });
  }
  test('stage cannot be written twice or after an immutable intent', () async {
    await store.run(job, (workspace) async {
      await workspace.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3);
      await expectLater(
          workspace.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3),
          failure(PublicationFailure.invalidStaging));
      await workspace.publish(job, publicationProof());
      await expectLater(workspace.publish(job, publicationProof()),
          failure(PublicationFailure.invalidStaging));
    });
  });
  test('lost ownership before admission does no filesystem work', () async {
    jobs.owned = false;
    await expectLater(publish(), failure(PublicationFailure.ownershipLost));
    expect(temp.listSync(), isEmpty);
  });
  test('lost ownership after intent never publishes', () async {
    jobs.beforeFence = (n) async {
      if (n == 2) jobs.owned = false;
    };
    await expectLater(publish(), failure(PublicationFailure.ownershipLost));
    expect(
        temp
            .listSync()
            .whereType<File>()
            .where((f) => isSupportedAudioFilePath(f.path)),
        isEmpty);
  });
  test('native lock released if admission transaction fails after acquisition',
      () async {
    jobs.afterFence = (n) async {
      if (n == 1) throw StateError('commit failed');
    };
    await expectLater(publish(), throwsStateError);
    jobs.afterFence = null;
    expect((await publish()).recovered, isFalse);
  });
  test(
      'same destination identity serializes different qualities and folder aliases',
      () async {
    final other =
        DesktopPublicationStore(jobs: jobs, clock: () => publicationNow);
    try {
      await store.run(job, (workspace) async {
        await expectLater(
            other.run(publicationJob(quality: 'lossless', folder: 2),
                (_) => Future.value(true)),
            failure(PublicationFailure.busy));
        expect(
            await other.run(
                publicationJob(variant: 'live'), (_) => Future.value(true)),
            isTrue);
      });
    } finally {
      await other.close();
    }
  });
  test('callback failure closes workspace and releases lock', () async {
    PublicationWorkspace? retained;
    await expectLater(
        store.run(job, (workspace) async {
          retained = workspace;
          throw StateError('failed');
        }),
        throwsStateError);
    await expectLater(retained!.pendingPublications(), throwsStateError);
    expect((await publish()).recovered, isFalse);
  });
  test(
      'close cancels a stalled input and drains its stream before releasing lock',
      () async {
    final input = StreamController<List<int>>();
    final entered = Completer<void>();
    var streamClosed = false;
    input.onListen = entered.complete;
    input.onCancel = () {
      streamClosed = true;
    };
    final writing = store.run(job,
        (workspace) => workspace.writeAudio(input.stream, expectedSize: 3));
    final assertion =
        expectLater(writing, throwsA(isA<LibraryScanCancelled>()));
    await entered.future;
    final closing = store.close();
    expect(identical(closing, store.close()), isTrue);
    await closing.timeout(const Duration(seconds: 5));
    await assertion;
    expect(streamClosed, isTrue);
    await input.close();
    await expectLater(publish(), throwsStateError);
  });
  test('forgotten workspace operation is cancelled and drained on scope exit',
      () async {
    final input = StreamController<List<int>>();
    final entered = Completer<void>();
    var cancelled = false;
    input.onListen = entered.complete;
    input.onCancel = () {
      cancelled = true;
    };
    await store.run(job, (workspace) async {
      workspace.writeAudio(input.stream, expectedSize: 3);
      await entered.future;
    });
    expect(cancelled, isTrue);
    await input.close();
    expect((await publish()).recovered, isFalse);
  });
  test(
      'cancel after accepted publication reports and journals the actual effect',
      () async {
    final control = LibraryScanControl();
    files.move = (source, target) async {
      await files.native.moveNoReplace(source, target);
      if (source.endsWith('audio.part')) control.cancel();
    };
    final receipt = await store.run(job, (workspace) async {
      await workspace.writeAudio(Stream.value([97, 98, 99]), expectedSize: 3);
      return workspace.publish(job, publicationProof());
    }, control: control);
    expect(await File(receipt.filePath).readAsString(), 'abc');
    expect(
        File(p.join(temp.path, '.cmp-publications-v1', 'operations',
                receipt.intent.operationName, 'published.json'))
            .existsSync(),
        isTrue);
  });
  test('recovery rejects changed target bytes and keeps them untouched',
      () async {
    final receipt = await publish();
    await File(receipt.filePath).writeAsString('xyz');
    await expectLater(
        store.run(
            job,
            (workspace) =>
                workspace.reconcile(job, receipt.intent.publicationId)),
        failure(PublicationFailure.changed));
    expect(await File(receipt.filePath).readAsString(), 'xyz');
  });
  test(
      'recovery rejects unrelated remaining staging file, even identical bytes',
      () async {
    final receipt = await publish();
    final original = File(p.join(temp.path, '.cmp-publications-v1',
        'operations', receipt.intent.operationName, 'audio.part'));
    await original.writeAsString('abc');
    await expectLater(
        store.run(
            job,
            (workspace) =>
                workspace.reconcile(job, receipt.intent.publicationId)),
        failure(PublicationFailure.collision));
    expect(await original.readAsString(), 'abc');
  });
  test('invalid or oversized journal never triggers a publication', () async {
    final receipt = await publish();
    final intent = File(p.join(temp.path, '.cmp-publications-v1', 'operations',
        receipt.intent.operationName, 'intent.json'));
    await intent.writeAsString('a' * 16385);
    await expectLater(
        store.run(
            job,
            (workspace) =>
                workspace.reconcile(job, receipt.intent.publicationId)),
        failure(PublicationFailure.invalidJournal));
    expect(await File(receipt.filePath).readAsString(), 'abc');
  });
  test('unrecognized managed directory is preserved rather than adopted',
      () async {
    final existing =
        await Directory(p.join(temp.path, '.cmp-publications-v1')).create();
    await File(p.join(existing.path, 'foreign.txt')).writeAsString('keep');
    await expectLater(publish(), failure(PublicationFailure.unsafePath));
    expect(await File(p.join(existing.path, 'foreign.txt')).readAsString(),
        'keep');
  });
  test('pre-cancelled scope and concurrent scope admission do no extra work',
      () async {
    await expectLater(
        store.run(job, (_) => Future.value(true),
            control: LibraryScanControl()..cancel()),
        throwsA(isA<LibraryScanCancelled>()));
    expect(temp.listSync(), isEmpty);
    await store.run(job, (_) async {
      await expectLater(publish(), throwsStateError);
    });
  });
  test('journal roundtrip preserves exact opaque identities and quality', () {
    final intent = PublicationIntent(
        publicationId: 'b' * 64,
        jobId: 1,
        key: job.key,
        verification: publicationProof());
    final decoded = PublicationIntent.decode(intent.encode());
    expect(decoded.key, job.key);
    expect(decoded.verification, publicationProof());
    final data = jsonDecode(intent.encode()) as Map<String, dynamic>;
    for (final mutation in [
      {'version': 2},
      {'jobId': 1.0},
      {'publicationId': '../file'},
      {'sha256': 'bad'},
      {'container': 'exe'},
      {'path': '/escape'}
    ]) {
      expect(() => PublicationIntent.decode(jsonEncode({...data, ...mutation})),
          failure(PublicationFailure.invalidJournal));
    }
  });
}

final class _Files implements PublicationFiles {
  final native = const NativePublicationFiles();
  Future<void> Function(String, String)? move;
  @override
  Future<bool> createDirectory(String path) => native.createDirectory(path);
  @override
  Future<PublicationFileLock> lock(String path, {bool seal = false}) =>
      native.lock(path, seal: seal);
  @override
  Future<void> moveNoReplace(String source, String target) =>
      move?.call(source, target) ?? native.moveNoReplace(source, target);
}
