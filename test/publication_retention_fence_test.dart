import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/download_fixture.dart';

void main() {
  late DownloadFixture f;
  late AppDatabase other;
  late PublicationCleanupRequest request;
  setUp(() async {
    f = await DownloadFixture.open(persistent: true);
    final job = await f.claim();
    await f.repositories.downloadJobs.cancel(job, now: f.now);
    f.now = f.now.add(const Duration(days: 2));
    request = PublicationCleanupRequest(
        jobId: job.id,
        key: job.key,
        publicationId: 'a' * 64,
        kind: PublicationCleanupKind.abandoned);
    other = AppDatabase(NativeDatabase.createInBackground(
        File(p.join(f.root.path, 'state.sqlite'))));
    await other.customStatement('PRAGMA busy_timeout = 5000');
  });
  tearDown(() async {
    await other.close();
    await f.close();
  });
  test(
      'SQLite writer reservation fences folder revocation throughout delete action',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    final cleanup = f.repositories.publicationRetention.withCleanupAuthority(
        request,
        notUpdatedAfter: f.now.subtract(const Duration(days: 1)),
        clock: f.clock, action: (path) async {
      entered.complete();
      await release.future;
      return path;
    });
    await entered.future;
    var changed = false;
    final revoke = other
        .customStatement('UPDATE library_folders SET is_enabled = 0')
        .then((_) => changed = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(changed, isFalse);
    } finally {
      release.complete();
    }
    expect(await cleanup, f.destination.path);
    await revoke;
    var called = false;
    expect(
        await f.repositories.publicationRetention.withCleanupAuthority(request,
            notUpdatedAfter: f.now, clock: f.clock, action: (_) async {
          called = true;
          return true;
        }),
        isNull);
    expect(called, isFalse);
  });
  test('cleanup waiting behind a writer rechecks the committed folder state',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    final writer = other.transaction(() async {
      await other.customStatement('UPDATE library_folders SET is_enabled = 0');
      entered.complete();
      await release.future;
    });
    await entered.future;
    var called = false, finished = false;
    final cleanup = f.repositories.publicationRetention
        .withCleanupAuthority(request, notUpdatedAfter: f.now, clock: f.clock,
            action: (_) async {
      called = true;
      return true;
    }).whenComplete(() => finished = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(finished, isFalse);
    } finally {
      release.complete();
    }
    await writer;
    expect(await cleanup, isNull);
    expect(called, isFalse);
  });
}
