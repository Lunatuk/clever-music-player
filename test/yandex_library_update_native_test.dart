import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library_sync/bundled_media_helper.dart';
import 'package:clever_music_player/src/library_sync/desktop_yandex_download_pipeline.dart';
import 'package:clever_music_player/src/library_sync/download_workspace.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_protocol.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_runner.dart';
import 'package:clever_music_player/src/library_sync/yandex_http_transport.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_client.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_update_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/library_update_fixture.dart';
import 'support/yandex_download_fixture.dart';
import 'support/yandex_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final bundle = Platform.environment['CMP_TEST_MEDIA_HELPER'];
  final skip = !Platform.isWindows || bundle == null
      ? 'Requires qualified Windows helper via CMP_TEST_MEDIA_HELPER.'
      : false;
  late LibraryUpdateFixture x;
  late YandexDownloadTestServer server;
  Future<void> configure(String format) async {
    x = await LibraryUpdateFixture.open();
    await x.ready();
    x.tracks = [yandexTrack('001')];
    await x.updates.configure(
        quality: format == 'flac'
            ? YandexUpdateQuality.flac
            : YandexUpdateQuality.mp3);
    await File('test/fixtures/media_helper/tone.$format').copy(x.f.raw.path);
    server = await YandexDownloadTestServer.open(x.f.raw);
    server.selection = x.updates.quality.selection;
    server.metadata = yandexDownloadTrack(durationMs: 2000);
    (server.metadata.single as Map)['coverUri'] = yandexCoverTemplate;
    server.cover = File('test/fixtures/media_helper/cover.png');
    x.probeFactory = FileSourceFingerprintProbe.new;
    x.runner = YandexDownloadRunner(
        sessions: x.f.repositories.yandexSessions,
        credentials: x.credentials,
        jobs: x.f.repositories.downloadJobs,
        clock: x.f.clock,
        readerFactory: (token) => YandexLibraryClient(
            token: token,
            transport: YandexHttpTransport.loopbackForTesting(server.origin),
            downloadParser:
                YandexDownloadParser.loopbackForTesting(server.origin),
            clock: x.f.clock),
        pipelineFactory: (reader, control) =>
            DesktopYandexDownloadPipeline.open(
                reader: reader,
                temporaryParent: x.f.root,
                jobs: x.f.repositories.downloadJobs,
                accounts: x.f.repositories.remoteLibrary,
                imports: x.f.repositories.downloadImports,
                retention: x.f.repositories.publicationRetention,
                artworkCache: AppSupportArtworkCacheService(
                    artworkDirectory: Directory('${x.f.root.path}/covers')),
                control: control,
                clock: x.f.clock,
                maxAudioBytes: 1024 * 1024,
                helperFactory: () =>
                    BundledMediaHelper(directory: Directory(bundle!)),
                loopbackForTesting: server.origin));
  }

  Future<void> close() async {
    await x.close();
    await server.close();
  }

  Future<void> released() async {
    final workspace = await DownloadWorkspace.open(parent: x.f.root);
    expect(workspace.reservedBytes, 0);
    await workspace.close();
  }

  for (final format in ['mp3', 'flac']) {
    test(
        'fresh selection $format -> canonical plan -> real HTTP/helper/import -> repeat hash check skips download',
        () async {
      await configure(format);
      try {
        await x.updates.start();
        expect(x.updates.failure, isNull);
        expect(x.updates.result!.completed, 1);
        expect(await x.f.count('tracks'), 1);
        expect(await x.f.count('downloaded_assets'), 1);
        final before = server.requests.length;
        await x.updates.start();
        expect(x.updates.failure, isNull);
        expect(x.updates.checked, 1);
        expect(x.updates.planned, 0);
        expect(x.updates.result, isNull);
        expect(server.requests.length, before);
        expect(await x.f.count('tracks'), 1);
        expect(await x.f.count('downloaded_assets'), 1);
        expect(
            (await x.f.repositories.downloadJobs.listJobs())
                .single
                .attemptCount,
            1);
        await released();
      } finally {
        await close();
      }
    }, skip: skip);
  }
  test(
      'cancelled real download can be retried explicitly from the update action',
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
      final operation = x.updates.start();
      await entered.future.timeout(const Duration(seconds: 10));
      x.updates.cancel();
      await operation.timeout(const Duration(seconds: 5));
      expect(x.updates.failure, YandexUpdateFailure.cancelled);
      expect(await x.f.count('tracks'), 0);
      expect((await x.f.repositories.downloadJobs.listJobs()).single.state,
          DownloadJobState.cancelled);
      release.complete();
      server.onAudio = null;
      await x.updates.start(retryFailed: true);
      expect(x.updates.failure, isNull);
      expect(x.updates.result!.completed, 1);
      expect(await x.f.count('tracks'), 1);
      await released();
    } finally {
      if (!release.isCompleted) release.complete();
      await close();
    }
  }, skip: skip);
  test('HQ variant declared128 cannot silently satisfy the selected320 profile',
      () async {
    await configure('mp3');
    try {
      server.transformInfo = (value) {
        (value['downloadInfo'] as Map)['bitrate'] = 128;
        return value;
      };
      await x.updates.start();
      expect(x.updates.failure, YandexUpdateFailure.download);
      expect(x.updates.result!.jobFailure, DownloadFailure.unavailable);
      expect(
          server.requests.any((r) => r.path.startsWith('/music-v2/')), isFalse);
      expect(x.updates.result!.completed, 0);
      expect(await x.f.count('tracks'), 0);
      expect(await x.f.count('downloaded_assets'), 0);
      await released();
    } finally {
      await close();
    }
  }, skip: skip);
}
