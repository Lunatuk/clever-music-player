import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/download_fixture.dart';

void main() {
  late DownloadFixture f;
  late int otherFolder;
  setUp(() async {
    f = await DownloadFixture.open();
    otherFolder = await f.repositories.libraryFolders.upsertFolder(
        LibraryFolder(
            path: '${f.root.path}/other', createdAt: f.now, updatedAt: f.now));
  });
  tearDown(() async {
    await f.close();
  });
  DownloadJobKey key(int folder, String quality, {String id = '123'}) =>
      DownloadJobKey(
          libraryFolderId: folder,
          identity:
              ExternalTrackIdentity(provider: 'yandex_music', externalId: id),
          quality: quality);
  for (final filter in ['folder', 'quality', 'both']) {
    test('$filter filter skips older unrelated jobs without claiming them',
        () async {
      final keys = [
        key(otherFolder, 'lossless'),
        key(otherFolder, 'high'),
        key(f.folderId, 'lossless'),
        key(f.folderId, 'high')
      ];
      await f.repositories.downloadJobs.enqueue(f.account, keys, now: f.now);
      final chosen = (await f.repositories.downloadJobs.claimNext(f.account,
          now: f.now,
          libraryFolderId: filter == 'quality' ? null : f.folderId,
          quality: filter == 'folder' ? null : 'high'))!;
      expect(
          chosen.key,
          switch (filter) {
            'folder' => keys[2],
            'quality' => keys[1],
            _ => keys[3],
          });
      for (final unchosen in keys.where((k) => k != chosen.key)) {
        final job = (await f.repositories.downloadJobs.findByKey(unchosen))!;
        expect(job.state, DownloadJobState.queued);
        expect(await f.repositories.downloadJobs.listAttempts(job.id), isEmpty);
      }
    });
  }
  test('no match returns null without falling back to a different destination',
      () async {
    await f.repositories.downloadJobs
        .enqueue(f.account, [key(otherFolder, 'high')], now: f.now);
    expect(
        await f.repositories.downloadJobs.claimNext(f.account,
            now: f.now, libraryFolderId: f.folderId, quality: 'high'),
        isNull);
    expect(
        (await f.repositories.downloadJobs.listJobs()).single.attemptCount, 0);
  });
  test('unfiltered existing callers keep FIFO behaviour', () async {
    final first = key(otherFolder, 'lossless');
    await f.repositories.downloadJobs
        .enqueue(f.account, [first, key(f.folderId, 'high')], now: f.now);
    expect(
        (await f.repositories.downloadJobs.claimNext(f.account, now: f.now))!
            .key,
        first);
  });
  test('scope is exact, including quality casing', () async {
    await f.repositories.downloadJobs.enqueue(
        f.account, [key(f.folderId, 'high'), key(f.folderId, 'High')],
        now: f.now);
    expect(
        (await f.repositories.downloadJobs.claimNext(f.account,
                now: f.now, libraryFolderId: f.folderId, quality: 'High'))!
            .key
            .quality,
        'High');
  });
  test('disabled destination cannot be claimed with an explicit scope',
      () async {
    await f.repositories.downloadJobs
        .enqueue(f.account, [key(f.folderId, 'high')], now: f.now);
    await f.repositories.libraryFolders
        .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now);
    expect(
        await f.repositories.downloadJobs.claimNext(f.account,
            now: f.now, libraryFolderId: f.folderId, quality: 'high'),
        isNull);
  });
  test('reconciliation uses the same scope and preserves its checkpoint',
      () async {
    await f.repositories.downloadJobs.enqueue(
        f.account, [key(otherFolder, 'high'), key(f.folderId, 'high')],
        now: f.now);
    var job = (await f.repositories.downloadJobs.claimNext(f.account,
        now: f.now, libraryFolderId: f.folderId, quality: 'high'))!;
    job = (await f.repositories.downloadJobs
        .advance(job, DownloadJobStage.metadata, now: f.now))!;
    await f.repositories.downloadJobs.interrupt(job, now: f.now);
    final again = (await f.repositories.downloadJobs.claimNext(f.account,
        now: f.now, libraryFolderId: f.folderId, quality: 'high'))!;
    expect(again.state, DownloadJobState.reconciling);
    expect(again.stage, DownloadJobStage.metadata);
    expect(again.attemptToken, isNot(job.attemptToken));
    expect(
        (await f.repositories.downloadJobs.findByKey(key(otherFolder, 'high')))!
            .attemptCount,
        0);
  });
  for (final folder in [0, -1]) {
    test('invalid folder $folder rejected before any attempt', () async {
      await expectLater(
          Future.sync(() => f.repositories.downloadJobs
              .claimNext(f.account, now: f.now, libraryFolderId: folder)),
          throwsArgumentError);
    });
  }
  test('malformed quality rejected before database work', () async {
    await expectLater(
        Future.sync(() => f.repositories.downloadJobs
            .claimNext(f.account, now: f.now, quality: 'bad\nquality')),
        throwsFormatException);
  });
}
