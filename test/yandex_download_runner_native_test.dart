import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/bundled_media_helper.dart';
import 'package:clever_music_player/src/library_sync/desktop_yandex_download_pipeline.dart';
import 'package:clever_music_player/src/library_sync/download_workspace.dart';
import 'package:clever_music_player/src/library_sync/yandex_audio_selection.dart';
import 'package:clever_music_player/src/library_sync/yandex_credential_store.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_protocol.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_runner.dart';
import 'package:clever_music_player/src/library_sync/yandex_http_transport.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_client.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/download_fixture.dart';
import 'support/yandex_connection_fixture.dart';
import 'support/yandex_download_fixture.dart';
import 'support/yandex_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // Native image binding, real loopback HTTP.
  final bundle = Platform.environment['CMP_TEST_MEDIA_HELPER'];
  final skip = !Platform.isWindows || bundle == null
      ? 'Requires qualified Windows helper via CMP_TEST_MEDIA_HELPER.'
      : false;
  late DownloadFixture f;
  late YandexDownloadTestServer server;
  late YandexDownloadRunner runner;
  late YandexAudioSelection selection;
  final events = <YandexDownloadRunProgress>[];
  var missingHelper = false;
  Future<void> configure(String format) async {
    events.clear();
    missingHelper = false;
    f = await DownloadFixture.open();
    f.account =
        await f.repositories.remoteLibrary.activateAccount(yandexAccount);
    await File('test/fixtures/media_helper/tone.$format').copy(f.raw.path);
    selection = format == 'flac'
        ? yandexFlacSelection
        : YandexAudioSelection.lossy(
            quality: YandexFileQuality.hq,
            encoding: format == 'mp3'
                ? YandexFileEncoding.mp3
                : YandexFileEncoding.aacMp4,
            minimumDeclaredKbps: 128,
            minimumMeasuredBitRate: 96000);
    server = await YandexDownloadTestServer.open(f.raw);
    server.selection = selection;
    server.metadata = yandexDownloadTrack(durationMs: 2000);
    (server.metadata.single as Map)['coverUri'] = yandexCoverTemplate;
    server.cover = File(
        'test/fixtures/media_helper/cover.${format == 'm4a' ? 'jpg' : 'png'}');
    final credentials = MemoryYandexCredentials()
      ..value = YandexSavedCredential(
          account: f.account,
          token: YandexAccessToken('SYNTHETIC_RUNNER_TOKEN'));
    runner = YandexDownloadRunner(
        sessions: f.repositories.yandexSessions,
        credentials: credentials,
        jobs: f.repositories.downloadJobs,
        clock: f.clock,
        sessionCheckEvery: const Duration(milliseconds: 20),
        readerFactory: (token) => YandexLibraryClient(
            token: token,
            transport: YandexHttpTransport.loopbackForTesting(server.origin),
            downloadParser:
                YandexDownloadParser.loopbackForTesting(server.origin),
            clock: f.clock),
        pipelineFactory: (reader, control) =>
            DesktopYandexDownloadPipeline.open(
                reader: reader,
                temporaryParent: f.root,
                jobs: f.repositories.downloadJobs,
                accounts: f.repositories.remoteLibrary,
                imports: f.repositories.downloadImports,
                retention: f.repositories.publicationRetention,
                artworkCache: AppSupportArtworkCacheService(
                    artworkDirectory: Directory('${f.root.path}/covers')),
                control: control,
                clock: f.clock,
                maxAudioBytes: 1024 * 1024,
                helperFactory: () => BundledMediaHelper(
                    directory: Directory(missingHelper
                        ? '${f.root.path}/missing-helper'
                        : bundle!)),
                loopbackForTesting: server.origin));
    await f.repositories.downloadJobs.enqueue(
        f.account,
        [
          DownloadJobKey(
              libraryFolderId: f.folderId,
              identity: yandexDownloadIdentity,
              quality: selection.resourceQuality)
        ],
        now: f.now);
  }

  Future<YandexDownloadRunResult> run({LibraryScanControl? control}) =>
      runner.run(
          account: f.account,
          libraryFolderId: f.folderId,
          selection: selection,
          maxJobs: 1,
          control: control,
          onProgress: events.add);
  Future<DownloadJob> job() async =>
      (await f.repositories.downloadJobs.listJobs()).single;
  Future<void> released() async {
    // A new owner proves the old owner and every raw reader have released the
    // actual native lock. Recovery must find no remaining raw/prepared charge.
    final workspace = await DownloadWorkspace.open(parent: f.root);
    expect(workspace.reservedBytes, 0);
    await workspace.close();
  }

  Future<void> close() async {
    await runner.close();
    await server.close();
    await f.close();
  }

  for (final format in ['mp3', 'm4a', 'flac']) {
    test(
        'session-bound runner -> real HTTP $format/cover -> qualified helper -> atomic import',
        () async {
      await configure(format);
      try {
        final result = await run();
        expect(result.outcome, YandexDownloadRunOutcome.limited);
        expect(result.started, 1);
        expect(result.completed, 1);
        expect(result.cleanupFailed, isFalse);
        expect((await job()).state, DownloadJobState.completed);
        expect(await f.count('tracks'), 1);
        expect(await f.count('downloaded_assets'), 1);
        expect(await f.count('external_track_refs'), 1);
        final row =
            (await f.database.customSelect('SELECT * FROM tracks').get())
                .single
                .data;
        expect(row['title'], 'Provider title');
        expect(row['artwork_hash'],
            sha256.convert(await server.cover!.readAsBytes()).toString());
        expect(await File(row['file_path'] as String).exists(), isTrue);
        expect(server.requests.where((r) => r.path == '/account/status'),
            hasLength(1));
        expect(server.requests.where((r) => r.path == '/tracks'), hasLength(1));
        expect(server.requests.where((r) => r.path.startsWith('/music-v2')),
            hasLength(1));
        expect(
            server.requests
                .where((r) => r.path.startsWith('/get-music-content/'))
                .single
                .authorization,
            isNull);
        expect(
            events.map((e) => e.stage),
            containsAllInOrder([
              YandexDownloadRunStage.authenticating,
              YandexDownloadRunStage.preparing,
              YandexDownloadRunStage.downloading,
              YandexDownloadRunStage.processing,
              YandexDownloadRunStage.finished
            ]));
        await released();
      } finally {
        await close();
      }
    }, skip: skip);
  }
  test('helper qualification fails before claim, then a fresh run succeeds',
      () async {
    await configure('mp3');
    try {
      missingHelper = true;
      final rejected = await run();
      expect(rejected.outcome, YandexDownloadRunOutcome.failed);
      expect(rejected.started, 0);
      expect((await job()).attemptCount, 0);
      expect(
          server.requests.any((r) => r.path.startsWith('/music-v2')), isFalse);
      expect(
          await Directory('${f.root.path}/.cmp-download-workspace-v1').exists(),
          isFalse);
      missingHelper = false;
      expect((await run()).completed, 1);
      await released();
    } finally {
      await close();
    }
  }, skip: skip);
  test(
      'cancel during real HTTP drains borrowed reader, raw file and native workspace',
      () async {
    await configure('flac');
    final entered = Completer<void>(), release = Completer<void>();
    try {
      server.onAudio = (request) async {
        request.response.headers.contentType = ContentType.binary;
        request.response.add([1]);
        await request.response.flush();
        entered.complete();
        await release.future;
        await request.response.close();
      };
      final control = LibraryScanControl();
      final operation = run(control: control);
      await entered.future.timeout(const Duration(seconds: 10));
      control.cancel();
      final result = await operation.timeout(const Duration(seconds: 5));
      expect(result.outcome, YandexDownloadRunOutcome.cancelled);
      expect(result.completed, 0);
      expect((await job()).state, DownloadJobState.cancelled);
      expect(await f.count('tracks'), 0);
      await released();
    } finally {
      if (!release.isCompleted) release.complete();
      await close();
    }
  }, skip: skip);
  test(
      'session replacement during real HTTP cancels before the long job heartbeat',
      () async {
    await configure('flac');
    final entered = Completer<void>(), release = Completer<void>();
    try {
      server.onAudio = (request) async {
        request.response.headers.contentType = ContentType.binary;
        request.response.add([1]);
        await request.response.flush();
        entered.complete();
        await release.future;
        await request.response.close();
      };
      final operation = run();
      await entered.future.timeout(const Duration(seconds: 10));
      await f.repositories.remoteLibrary.activateAccount(yandexAccount);
      final result = await operation.timeout(const Duration(seconds: 5));
      expect(result.outcome, YandexDownloadRunOutcome.staleSession);
      expect(result.completed, 0);
      expect((await job()).attemptCount, 1);
      expect(await f.count('tracks'), 0);
      await released();
    } finally {
      if (!release.isCompleted) release.complete();
      await close();
    }
  }, skip: skip);
  test('destination disabled at real HTTP EOF cannot publish or import',
      () async {
    await configure('mp3');
    try {
      server.onAudio = (request) async {
        request.response.headers.contentType = ContentType.binary;
        request.response.add(await f.raw.readAsBytes());
        await request.response.flush();
        await f.repositories.libraryFolders
            .setFolderEnabled(f.folderId, isEnabled: false, updatedAt: f.now);
        await request.response.close();
      };
      final result = await run();
      expect(result.completed, 0);
      expect(result.started, 1);
      expect(result.outcome, isNot(YandexDownloadRunOutcome.completed));
      expect(await f.count('tracks'), 0);
      expect(await f.count('downloaded_assets'), 0);
      await released();
    } finally {
      await close();
    }
  }, skip: skip);
  test(
      'interrupted unpublished checkpoint reconciles then downloads in the same claimed attempt',
      () async {
    await configure('mp3');
    try {
      var current =
          (await f.repositories.downloadJobs.claimNext(f.account, now: f.now))!;
      current = (await f.repositories.downloadJobs
          .advance(current, DownloadJobStage.metadata, now: f.now))!;
      await f.repositories.downloadJobs.interrupt(current, now: f.now);
      expect((await run()).completed, 1);
      expect((await job()).attemptCount, 2);
      expect(events.any((e) => e.stage == YandexDownloadRunStage.recovering),
          isTrue);
      expect(server.requests.where((r) => r.path.startsWith('/music-v2')),
          hasLength(1));
      await released();
    } finally {
      await close();
    }
  }, skip: skip);
  test(
      'published file after import rollback recovers with a new runtime, without redownloading',
      () async {
    await configure('m4a');
    try {
      await f.database.customStatement(
          "CREATE TRIGGER reject_runner_import BEFORE INSERT ON downloaded_assets BEGIN SELECT RAISE(ABORT, 'synthetic'); END");
      final failed = await run();
      expect(failed.completed, 0);
      expect((await job()).state, DownloadJobState.needsReconciliation);
      expect(await f.count('tracks'), 0);
      await f.database.customStatement('DROP TRIGGER reject_runner_import');
      final before = server.requests.length;
      final recovered = await run();
      expect(recovered.completed, 1);
      expect((await job()).state, DownloadJobState.completed);
      expect(await f.count('tracks'), 1);
      expect(await f.count('downloaded_assets'), 1);
      expect(server.requests.skip(before).map((r) => r.path).toList(),
          ['/account/status']);
      await released();
    } finally {
      await close();
    }
  }, skip: skip);
}
