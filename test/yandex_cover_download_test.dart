import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/binary_download.dart';
import 'package:clever_music_player/src/library_sync/binary_http_download_transport.dart';
import 'package:clever_music_player/src/library_sync/download_workspace.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global =
      null; // Real loopback integration, no widget HTTP stub.
  late DownloadFixture f;
  late YandexDownloadTestServer server;
  late DownloadWorkspace workspace;
  late RawDownloadPool pool;
  late YandexTrackDownloader downloader;
  late DownloadJob job;
  YandexDownloadedTrack? result;
  final gates = <Completer<void>>[];
  Future<void> configure(
      {int budget = maximumDownloadedCoverBytes + 3,
      Duration timeout = const Duration(seconds: 3)}) async {
    f = await DownloadFixture.open();
    f.account =
        await f.repositories.remoteLibrary.activateAccount(yandexAccount);
    workspace =
        await DownloadWorkspace.open(parent: f.root, maxReservedBytes: budget);
    server = await YandexDownloadTestServer.open(f.raw);
    (server.metadata.single as Map)['coverUri'] = yandexCoverTemplate;
    server.cover = File('test/fixtures/media_helper/cover.png');
    pool = RawDownloadPool(
        parent: f.root,
        workspace: workspace,
        maxReservedBytes: maximumDownloadedCoverBytes + 3);
    final reader = YandexLibraryClient(
        token: YandexAccessToken('synthetic-secret'),
        transport: YandexHttpTransport.loopbackForTesting(server.origin),
        downloadParser: YandexDownloadParser.loopbackForTesting(server.origin),
        clock: f.clock);
    await reader.verifyAccount();
    downloader = YandexTrackDownloader(
        reader: reader,
        transport: BinaryHttpDownloadTransport.loopbackForTesting(server.origin,
            pool: pool, timeout: timeout, idleTimeout: timeout),
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
    addTearDown(() async {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      gates.clear();
      await downloader.close();
      await result?.close();
      result = null;
      expect(pool.reservedBytes, 0);
      expect(workspace.reservedBytes, 0);
      await workspace.close();
      await server.close();
      await f.close();
    });
  }

  Future<YandexDownloadedTrack> download({LibraryScanControl? control}) =>
      downloader.download(job, f.account, yandexFlacSelection,
          maxBytes: 3, control: control);
  Completer<void> gate() {
    final value = Completer<void>();
    gates.add(value);
    return value;
  }

  Future<void> failed(DownloadFailure failure) async {
    final stored = (await f.repositories.downloadJobs.findByKey(job.key))!;
    expect(stored.state, DownloadJobState.failed);
    expect(stored.failure, failure);
    expect(await f.count('tracks'), 0);
    expect(await f.count('downloaded_assets'), 0);
  }

  Matcher binary(BinaryDownloadFailure failure) =>
      throwsA(isA<BinaryDownloadException>()
          .having((e) => e.failure, 'failure', failure));

  for (final (extension, format) in [
    ('png', EmbeddedCoverFormat.png),
    ('jpg', EmbeddedCoverFormat.jpeg)
  ]) {
    test(
        'anonymous $extension fetch -> immutable cover -> shared quota released before handoff',
        () async {
      await configure();
      server.cover = File('test/fixtures/media_helper/cover.$extension');
      result = await download();
      expect(result!.cover!.format, format);
      expect(result!.cover!.bytes, await server.cover!.readAsBytes());
      expect(result!.expectation.requireCover, isTrue);
      expect(workspace.reservedBytes, 3);
      expect(pool.reservedBytes, 3);
      final cover = server.requests
          .singleWhere((r) => r.path.startsWith('/get-music-content/'));
      expect(cover.path, '/get-music-content/28589/synthetic.album-1/600x600');
      expect(cover.method, 'GET');
      expect(cover.body, isEmpty);
      expect(cover.authorization, isNull);
      expect(cover.client, isNull);
      expect(cover.uri.hasQuery, isFalse);
      await downloader.close();
      expect(await File(result!.raw.source.path).readAsString(), 'abc');
      expect(result!.cover!.bytes, isNotEmpty);
      expect((await f.repositories.downloadJobs.findByKey(job.key))!.state,
          DownloadJobState.running);
    });
  }
  test('missing provider cover is explicit and adds no image request',
      () async {
    await configure();
    (server.metadata.single as Map).remove('coverUri');
    result = await download();
    expect(result!.cover, isNull);
    expect(result!.expectation.requireCover, isFalse);
    expect(server.requests.any((r) => r.path.startsWith('/get-music-content/')),
        isFalse);
  });
  test('shared cover admission fails before image network and cleans audio',
      () async {
    await configure(budget: maximumDownloadedCoverBytes + 2);
    await expectLater(download(), binary(BinaryDownloadFailure.quotaExceeded));
    expect(server.requests.any((r) => r.path.startsWith('/get-music-content/')),
        isFalse);
    await failed(DownloadFailure.noSpace);
  });
  for (final (status, failure, jobFailure) in [
    (302, BinaryDownloadFailure.invalidResponse, DownloadFailure.network),
    (404, BinaryDownloadFailure.notFound, DownloadFailure.unavailable),
    (429, BinaryDownloadFailure.rateLimited, DownloadFailure.rateLimited),
    (503, BinaryDownloadFailure.network, DownloadFailure.network),
  ]) {
    test(
        'cover HTTP $status fails whole attempt, never silently drops art or follows redirect',
        () async {
      await configure();
      server.onCover = (request) async {
        request.response.statusCode = status;
        request.response.headers
            .set('location', '${server.origin}/secret-redirect');
        await request.response.close();
      };
      await expectLater(download(), binary(failure));
      expect(server.requests.any((r) => r.path == '/secret-redirect'), isFalse);
      await failed(jobFailure);
    });
  }
  for (final type in [
    'text/html',
    'application/json',
    'image/svg+xml',
    'image/gif',
    'image/webp',
    'audio/mpeg'
  ]) {
    test('cover rejects unexpected MIME $type', () async {
      await configure();
      server.onCover = (request) async {
        request.response.headers.contentType = ContentType.parse(type);
        request.response.add(await server.cover!.readAsBytes());
        await request.response.close();
      };
      await expectLater(
          download(), binary(BinaryDownloadFailure.invalidResponse));
      await failed(DownloadFailure.network);
    });
  }
  for (final declared in [true, false]) {
    test(
        'cover byte ceiling enforced for ${declared ? 'declared' : 'chunked'} length',
        () async {
      await configure();
      server.onCover = (request) async {
        request.response.headers.contentType = ContentType('image', 'png');
        if (declared) {
          request.response.contentLength = maximumDownloadedCoverBytes + 1;
        }
        request.response.add(List.filled(maximumDownloadedCoverBytes + 1, 0));
        await request.response.close();
      };
      await expectLater(download(), binary(BinaryDownloadFailure.tooLarge));
      await failed(DownloadFailure.network);
    });
  }
  test('damaged PNG fails as invalid media, audio never handed off/imported',
      () async {
    await configure();
    server.onCover = (request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add([137, 80, 78, 71, 13, 10, 26, 10]);
      await request.response.close();
    };
    await expectLater(
        download(),
        throwsA(isA<AudioValidationException>().having(
            (e) => e.outcome, 'outcome', AudioValidationOutcome.invalidCover)));
    await failed(DownloadFailure.invalidMedia);
  });
  for (final action in [
    'cancel',
    'close',
    'disconnect',
    'new session',
    'disable folder',
    'timeout'
  ]) {
    test('$action during cover drains image and audio, revokes handoff',
        () async {
      await configure(
          timeout: action == 'timeout'
              ? const Duration(milliseconds: 300)
              : const Duration(seconds: 3));
      final entered = Completer<void>();
      final release = gate();
      server.onCover = (request) async {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add([137, 80, 78, 71]);
        await request.response.flush();
        entered.complete();
        await release.future;
        await request.response.close();
      };
      final control = LibraryScanControl();
      final operation = download(control: control);
      final assertion = expectLater(
          operation,
          switch (action) {
            'cancel' || 'close' => throwsA(isA<YandexLibraryException>().having(
                (e) => e.failure, 'failure', YandexLibraryFailure.cancelled)),
            'timeout' => binary(BinaryDownloadFailure.timeout),
            _ => throwsA(isA<PublicationException>().having(
                (e) => e.reason, 'reason', PublicationFailure.ownershipLost)),
          });
      await entered.future;
      expect(workspace.reservedBytes, maximumDownloadedCoverBytes + 3);
      switch (action) {
        case 'cancel':
          control.cancel();
        case 'close':
          await downloader.close();
        case 'disconnect':
          await f.repositories.remoteLibrary.disconnectAccount(f.account);
        case 'new session':
          await f.repositories.remoteLibrary.activateAccount(yandexAccount);
        case 'disable folder':
          await f.repositories.libraryFolders
              .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now);
      }
      await assertion.timeout(const Duration(seconds: 5));
      expect(workspace.reservedBytes, 0);
      expect(pool.reservedBytes, 0);
      expect(await f.count('tracks'), 0);
    });
  }
  test('revocation at end of image caught even before next heartbeat',
      () async {
    await configure();
    server.onCover = (request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(await server.cover!.readAsBytes());
      await request.response.flush();
      await f.repositories.remoteLibrary.disconnectAccount(f.account);
      await request.response.close();
    };
    await expectLater(
        download(),
        throwsA(isA<PublicationException>().having(
            (e) => e.reason, 'reason', PublicationFailure.ownershipLost)));
  });
}
