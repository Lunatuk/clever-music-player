import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/binary_http_download_transport.dart';
import 'package:clever_music_player/src/library_sync/publication_intent.dart';
import 'package:clever_music_player/src/library_sync/raw_download_pool.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_protocol.dart';
import 'package:clever_music_player/src/library_sync/yandex_http_transport.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_client.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:clever_music_player/src/library_sync/yandex_track_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/download_fixture.dart';
import 'support/yandex_download_fixture.dart';
import 'support/yandex_fixture.dart';

void main() {
  late DownloadFixture f;
  late YandexDownloadTestServer server;
  late RawDownloadPool pool;
  late YandexTrackDownloader downloader;
  late DownloadJob job;
  setUp(() async {
    f = await DownloadFixture.open();
    f.account =
        await f.repositories.remoteLibrary.activateAccount(yandexAccount);
    server = await YandexDownloadTestServer.open(f.raw);
    pool = RawDownloadPool(parent: f.root, maxReservedBytes: 3);
    final reader = YandexLibraryClient(
        token: YandexAccessToken('synthetic-secret'),
        transport: YandexHttpTransport.loopbackForTesting(server.origin),
        downloadParser: YandexDownloadParser.loopbackForTesting(server.origin),
        clock: f.clock);
    await reader.verifyAccount();
    downloader = YandexTrackDownloader(
        reader: reader,
        transport: BinaryHttpDownloadTransport.loopbackForTesting(server.origin,
            pool: pool),
        jobs: f.repositories.downloadJobs,
        accounts: f.repositories.remoteLibrary,
        clock: f.clock,
        leaseFor: const Duration(seconds: 1),
        heartbeatEvery: const Duration(milliseconds: 20));
    await f.repositories.downloadJobs.enqueue(
        f.account,
        [
          DownloadJobKey(
              libraryFolderId: f.folderId,
              identity: yandexDownloadIdentity,
              quality: yandexFlacSelection.resourceQuality)
        ],
        now: f.now);
    job = (await f.repositories.downloadJobs.claimNext(f.account, now: f.now))!;
  });
  tearDown(() async {
    await downloader.close();
    await server.close();
    await f.close();
  });
  Future<YandexDownloadedTrack> download({LibraryScanControl? control}) =>
      downloader.download(job, f.account, yandexFlacSelection,
          maxBytes: 3, control: control);
  Matcher lost() => throwsA(isA<PublicationException>()
      .having((e) => e.reason, 'reason', PublicationFailure.ownershipLost));

  test('real API POST/signing -> anonymous raw HTTP -> fresh lease handoff',
      () async {
    server.onFileInfo =
        (_) async => Future<void>.delayed(const Duration(milliseconds: 75));
    final result = await download();
    try {
      expect(await File(result.raw.source.path).readAsString(), 'abc');
      expect(result.job.revision, greaterThan(job.revision + 1));
      expect(result.job.stage, DownloadJobStage.download);
      expect(result.job.attemptToken, job.attemptToken);
      expect(result.variant.expectedBytes, 3);
      expect(result.variant.expectation(result.raw.sizeBytes).tags['title'],
          'Provider title');
      expect(pool.reservedBytes, 3);
      expect(await f.count('tracks'), 0);
      final metadata = server.requests.singleWhere((r) => r.path == '/tracks');
      expect(metadata.method, 'POST');
      expect(Uri.splitQueryString(metadata.body),
          {'track-ids': '001:009', 'with-positions': 'True'});
      expect(metadata.contentType,
          startsWith('application/x-www-form-urlencoded'));
      final info =
          server.requests.singleWhere((r) => r.path == '/get-file-info');
      expect(info.method, 'GET');
      expect(info.client, 'YandexMusicDesktopAppWindows/5.95.0');
      expect(info.authorization, 'OAuth synthetic-secret');
      expect(info.uri.queryParameters['trackId'], '001');
      expect(info.uri.queryParameters['transports'], 'encraw');
      final audio = server.requests.last;
      expect(audio.path, '/music-v2/raw/synthetic/audio');
      expect(audio.authorization, isNull);
      expect(audio.client, isNull);
      expect(audio.body, isEmpty);
      // Closing the downloader must not remove a file handed to a consumer.
      await downloader.close();
      expect(await File(result.raw.source.path).exists(), isTrue);
    } finally {
      await result.close();
    }
    expect(pool.reservedBytes, 0);
  });
  test('quality fallback fails attempt without any binary request', () async {
    server.transformInfo = (value) {
      (value['downloadInfo'] as Map)['quality'] = 'hq';
      return value;
    };
    await expectLater(
        download(),
        throwsA(isA<YandexDownloadException>().having((e) => e.failure,
            'failure', YandexDownloadFailure.qualityMismatch)));
    expect(server.requests.any((r) => r.path.startsWith('/music-v2')), isFalse);
    expect(pool.reservedBytes, 0);
    final stored = await f.repositories.downloadJobs.findByKey(job.key);
    expect(stored!.state, DownloadJobState.failed);
    expect(stored.failure, DownloadFailure.unavailable);
    expect(await f.count('tracks'), 0);
  });
  for (final action in [
    'disconnect',
    'new session',
    'disable folder',
    'cancel',
    'close'
  ]) {
    test('$action during resolver cancels accepted HTTP and prevents download',
        () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      server.onFileInfo = (_) async {
        entered.complete();
        await release.future;
      };
      final control = LibraryScanControl();
      final operation = download(control: control);
      final rejected = expectLater(
          operation,
          action == 'cancel' || action == 'close'
              ? throwsA(isA<YandexLibraryException>().having(
                  (e) => e.failure, 'failure', YandexLibraryFailure.cancelled))
              : lost());
      try {
        await entered.future;
        switch (action) {
          case 'disconnect':
            await f.repositories.remoteLibrary.disconnectAccount(f.account);
          case 'new session':
            await f.repositories.remoteLibrary.activateAccount(yandexAccount);
          case 'disable folder':
            await f.repositories.libraryFolders.setFolderEnabled(f.folderId,
                isEnabled: false, updatedAt: f.now);
          case 'cancel':
            control.cancel();
          case 'close':
            await downloader.close();
        }
        await rejected.timeout(const Duration(seconds: 5));
        expect(server.requests.any((r) => r.path.startsWith('/music-v2')),
            isFalse);
        expect(pool.reservedBytes, 0);
        expect(await f.count('tracks'), 0);
      } finally {
        release.complete();
      }
    });
  }
  test(
      'revocation after final bytes but before EOF is caught by final writer fence',
      () async {
    server.onAudio = (request) async {
      request.response.headers.contentType = ContentType.binary;
      // Chunked body keeps EOF under server control, no heartbeat needed.
      request.response.add([97, 98, 99]);
      await request.response.flush();
      await f.repositories.remoteLibrary.disconnectAccount(f.account);
      await request.response.close();
    };
    await expectLater(download(), lost());
    expect(pool.reservedBytes, 0);
    expect(await f.count('tracks'), 0);
  });
  test('user cancellation during raw body deletes partial and marks cancelled',
      () async {
    final received = Completer<void>();
    final release = Completer<void>();
    server.onAudio = (request) async {
      request.response.headers.contentType = ContentType.binary;
      request.response.add([97]);
      await request.response.flush();
      received.complete();
      await release.future;
      await request.response.close();
    };
    final control = LibraryScanControl();
    final rejected = expectLater(
        download(control: control),
        throwsA(isA<YandexLibraryException>().having(
            (e) => e.failure, 'failure', YandexLibraryFailure.cancelled)));
    try {
      await received.future;
      control.cancel();
      await rejected;
      expect(pool.reservedBytes, 0);
      expect((await f.repositories.downloadJobs.findByKey(job.key))!.state,
          DownloadJobState.cancelled);
    } finally {
      release.complete();
    }
  });
  test('busy rejects concurrent job; close drains it and closes admission',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    server.onFileInfo = (_) async {
      entered.complete();
      await release.future;
    };
    final rejected =
        expectLater(download(), throwsA(isA<YandexLibraryException>()));
    try {
      await entered.future;
      await expectLater(
          download(),
          throwsA(isA<YandexLibraryException>()
              .having((e) => e.failure, 'failure', YandexLibraryFailure.busy)));
      await downloader.close();
      await rejected;
      await expectLater(
          download(),
          throwsA(isA<YandexLibraryException>().having(
              (e) => e.failure, 'failure', YandexLibraryFailure.closed)));
      expect(pool.reservedBytes, 0);
    } finally {
      release.complete();
    }
  });
  test('pre-cancelled operation does not start API/IO', () async {
    final before = server.requests.length;
    await expectLater(download(control: LibraryScanControl()..cancel()),
        throwsA(isA<YandexLibraryException>()));
    expect(server.requests, hasLength(before));
    expect(pool.reservedBytes, 0);
  });
}
