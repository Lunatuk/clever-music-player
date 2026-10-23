import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/android/android_audio_metadata_backend.dart';
import 'package:clever_music_player/src/android/android_publication_journal.dart';
import 'package:clever_music_player/src/android/android_yandex_download_pipeline.dart';
import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/exact_track_copies.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:clever_music_player/src/library_sync/bundled_media_helper.dart';
import 'package:clever_music_player/src/library_sync/download_workspace.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_protocol.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_runner.dart';
import 'package:clever_music_player/src/library_sync/yandex_http_transport.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_client.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_update_controller.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/android_download_provider.dart';
import 'support/android_publication_fixture.dart';
import 'support/library_update_fixture.dart';
import 'support/yandex_download_fixture.dart';
import 'support/yandex_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final bundle = Platform.environment['CMP_TEST_MEDIA_HELPER'];
  final skip = !Platform.isWindows || bundle == null
      ? 'Requires qualified Windows FFmpeg; SAF is a file-backed test adapter.'
      : false;
  late LibraryUpdateFixture x;
  late YandexDownloadTestServer server;
  late AndroidDownloadProvider provider;
  final media = <_HostMedia>[];
  var unavailable = false;
  Future<void> configure(String format) async {
    x = await LibraryUpdateFixture.open();
    await x.f.database.customStatement(
        'UPDATE library_folders SET path = ? WHERE id = ?',
        [androidPublicationTree.storageValue, x.f.folderId]);
    await x.ready();
    x.tracks = [yandexTrack('001')];
    await x.updates
        .configure(quality: YandexUpdateQuality.values.byName(format));
    await File('test/fixtures/media_helper/tone.$format').copy(x.f.raw.path);
    server = await YandexDownloadTestServer.open(x.f.raw);
    server.selection = x.updates.quality.selection;
    server.metadata = yandexDownloadTrack(durationMs: 2000);
    (server.metadata.single as Map)['coverUri'] = yandexCoverTemplate;
    server.cover = File('test/fixtures/media_helper/cover.png');
    provider = AndroidDownloadProvider(Directory('${x.f.root.path}/provider'));
    provider.metadata = (file, receipt) async {
      final m = await const EmbeddedAudioMetadataReaderService().read(file);
      expect(m.artwork, isNotNull);
      return AudioDocumentMetadata(
          name: receipt.intent.fileName,
          title: m.title,
          artist: m.artist,
          album: m.album,
          albumArtist: m.albumArtist,
          genre: m.genre,
          duration: m.duration,
          size: m.fileSizeBytes,
          trackNumber: m.trackNumber,
          discNumber: m.discNumber,
          year: m.year);
    };
    x.probeFactory = () => _ProviderProbe(provider);
    final helper = BundledMediaHelper(directory: Directory(bundle!));
    final qualified = await helper.qualify();
    await helper.close();
    media.clear();
    unavailable = false;
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
            AndroidYandexDownloadPipeline.open(
                reader: reader,
                temporaryParent: x.f.root,
                jobs: x.f.repositories.downloadJobs,
                accounts: x.f.repositories.remoteLibrary,
                imports: x.f.repositories.downloadImports,
                retention: x.f.repositories.publicationRetention,
                artworkCache: const NoopArtworkCacheService(),
                control: control,
                clock: x.f.clock,
                diagnostics: x.diagnostics,
                mediaFactory: () {
                  final m = _HostMedia(
                      qualified.createMetadataBackend(), unavailable);
                  media.add(m);
                  return m;
                },
                publicationFactory: provider.backend,
                verifierFactory: provider.verifier,
                readDocument: provider.read,
                maxAudioBytes: 1024 * 1024,
                loopbackForTesting: server.origin));
  }

  Future<void> close() async {
    await x.close();
    await server.close();
  }

  Future<void> released() async {
    expect(media.every((m) => m.closed), isTrue);
    final workspace = await DownloadWorkspace.open(parent: x.f.root);
    expect(workspace.reservedBytes, 0);
    await workspace.close();
    final journal =
        await AndroidPublicationJournal.open(privateParent: x.f.root);
    await journal.close();
  }

  for (final format in ['mp3', 'm4a', 'flac']) {
    test(
        'Android $format explicit update -> encrypted HTTP/cover -> real preparation -> URI import -> repeat',
        () async {
      await configure(format);
      server.encryptedKey = '000102030405060708090a0b0c0d0e0f';
      try {
        await x.updates.start();
        expect(x.updates.failure, isNull);
        expect(x.updates.result!.completed, 1);
        expect(provider.writes, 1);
        expect(await x.f.count('tracks'), 1);
        expect(await x.f.count('downloaded_assets'), 1);
        final published = (await x.f.repositories.tracks.listTracks()).single;
        final source = published.source as ContentUriAudioSource;
        final parent = await x.f.repositories.libraryFolders.upsertFolder(
            LibraryFolder(
                path: 'content://music.documents/tree/parent',
                createdAt: x.f.now,
                updatedAt: x.f.now));
        final alias = ContentUriAudioSource(source.uri.replace(pathSegments: [
          'tree',
          'parent',
          'document',
          source.uri.pathSegments.last
        ]).toString());
        await x.f.repositories.tracks.upsertTrack(Track.fromSource(
            source: alias,
            libraryFolderId: parent,
            title: published.title,
            addedAt: x.f.now,
            updatedAt: x.f.now));
        final rows = await x.f.repositories.tracks.listTracks();
        expect(rows, hasLength(2));
        expect(withoutExactTrackCopies(rows).single.id, published.id);
        final requests = server.requests.length;
        await x.updates.start();
        expect(x.updates.failure, isNull);
        expect(x.updates.checked, 1);
        expect(x.updates.planned, 0);
        expect(server.requests.length, requests);
        expect(provider.writes, 1);
        expect(await x.f.count('tracks'), 2);
        expect(await x.f.count('downloaded_assets'), 1);
        expect(
            await x.f.repositories.tracks.findById(published.id!), published);
        expect(
            x.diagnostics.entries
                .any((e) => e.fields.values.any((v) => v is String)),
            isFalse);
        await released();
      } finally {
        await close();
      }
    }, skip: skip);
  }
  test(
      'published receipt after SQL rollback recovers in a new pipeline without audio HTTP or duplicate',
      () async {
    await configure('m4a');
    try {
      await x.f.database.customStatement(
          "CREATE TRIGGER reject_import BEFORE INSERT ON downloaded_assets BEGIN SELECT RAISE(ABORT, 'test'); END");
      await x.updates.start();
      expect(x.updates.failure, YandexUpdateFailure.download);
      expect(x.updates.result!.needsReconciliation, isTrue);
      expect(await x.f.count('tracks'), 0);
      final requests = server.requests.length;
      await x.f.raw.delete(); // Recovery cannot rely on raw or its HTTP source.
      await x.f.database.customStatement('DROP TRIGGER reject_import');
      await x.updates.start(retryFailed: true);
      expect(x.updates.failure, isNull);
      expect(x.updates.result!.completed, 1);
      expect(provider.writes, 1);
      expect(server.requests.length, requests + 1); // account check only
      expect(await x.f.count('tracks'), 1);
      await released();
    } finally {
      await close();
    }
  }, skip: skip);
  test(
      'partial provider file stays quarantined across repeated updates without publishing another copy',
      () async {
    await configure('mp3');
    provider.partial = true;
    try {
      await x.updates.start();
      expect(x.updates.result!.needsReconciliation, isTrue);
      expect(await x.f.count('tracks'), 0);
      final requests = server.requests.length;
      await x.updates.start(retryFailed: true);
      expect(x.updates.result!.needsReconciliation, isTrue);
      expect(provider.writes, 1);
      expect(server.requests.length, requests + 1);
      expect(await x.f.count('downloaded_assets'), 0);
      expect(provider.files.length, 1);
      await released();
    } finally {
      await close();
    }
  }, skip: skip);
  test('cancel during HTTP releases raw/workspace and explicit retry completes',
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
      final running = x.updates.start();
      await entered.future.timeout(const Duration(seconds: 10));
      x.updates.cancel();
      await running.timeout(const Duration(seconds: 5));
      expect(x.updates.failure, YandexUpdateFailure.cancelled);
      expect(provider.writes, 0);
      await released();
      release.complete();
      server.onAudio = null;
      await x.updates.start(retryFailed: true);
      expect(x.updates.failure, isNull);
      expect(x.updates.result!.completed, 1);
      await released();
    } finally {
      if (!release.isCompleted) release.complete();
      await close();
    }
  }, skip: skip);
  test(
      'unavailable media backend closes before admission; retry opens fresh owners',
      () async {
    await configure('mp3');
    unavailable = true;
    try {
      await x.updates.start();
      expect(x.updates.failure, YandexUpdateFailure.download);
      expect(media.single.closed, isTrue);
      expect(provider.writes, 0);
      expect(
          server.requests.any((r) => r.path.startsWith('/music-v2/')), isFalse);
      unavailable = false;
      await x.updates.start();
      expect(x.updates.failure, isNull);
      expect(provider.writes, 1);
      await released();
    } finally {
      await close();
    }
  }, skip: skip);
  test('late stop after accepted publication drains one verified URI import',
      () async {
    await configure('m4a');
    provider.onWrite = (control) async => x.updates.cancel();
    try {
      await x.updates.start();
      expect(await x.f.count('tracks'), 1);
      expect(provider.writes, 1);
      expect((await x.f.repositories.downloadJobs.listJobs()).single.state,
          DownloadJobState.completed);
      await released();
    } finally {
      await close();
    }
  }, skip: skip);
}

/// Real host FFmpeg exercises the common contracts, not Android JNI/SAF.
final class _HostMedia implements AndroidMediaProcessingBackend {
  _HostMedia(this.inner, this.unavailable);
  final AudioMetadataBackend inner;
  final bool unavailable;
  bool closed = false;
  @override
  Future<String> capabilities(LibraryScanControl control) async {
    control.throwIfCancelled();
    if (unavailable) {
      throw const AudioValidationException(
          AudioValidationOutcome.backendUnavailable);
    }
    return '7.1.5';
  }

  @override
  Future<DownloadedAudioInspection> inspect(File f, LibraryScanControl c) =>
      inner.inspect(f, c);
  @override
  Future<String> digest(File f, DownloadedAudioInspection i, AudioCopyDigest m,
          LibraryScanControl c) =>
      inner.digest(f, i, m, c);
  @override
  Future<Duration> decodeAudio(
          File f, DownloadedAudioInspection i, LibraryScanControl c) =>
      inner.decodeAudio(f, i, c);
  @override
  Future<void> decodeCover(
          File f, DownloadedAudioInspection i, LibraryScanControl c) =>
      inner.decodeCover(f, i, c);
  @override
  Future<void> writeMetadata(
          File source,
          File output,
          DownloadedAudioInspection info,
          DownloadedAudioExpectation expected,
          LibraryScanControl control,
          {File? cover,
          EmbeddedCoverFormat? coverFormat,
          int? maxOutputBytes}) =>
      inner.writeMetadata(source, output, info, expected, control,
          cover: cover,
          coverFormat: coverFormat,
          maxOutputBytes: maxOutputBytes);
  @override
  Future<void> close() async {
    closed = true;
    await inner.close();
  }
}

final class _ProviderProbe implements SourceFingerprintProbe {
  _ProviderProbe(this.provider);
  final AndroidDownloadProvider provider;
  @override
  Future<SourceFingerprintResult> fingerprint(AudioSourceReference source,
      {required int expectedSize, required LibraryScanControl control}) async {
    control.throwIfCancelled();
    final file = provider.files[source.storageValue];
    if (file == null) {
      return SourceFingerprintResult.failure(SourceFingerprintStatus.missing);
    }
    final bytes = await file.readAsBytes();
    return bytes.length == expectedSize
        ? SourceFingerprintResult.fingerprinted(
            bytes.length, sha256.convert(bytes).toString())
        : SourceFingerprintResult.failure(SourceFingerprintStatus.changed);
  }

  @override
  Future<void> close() async {}
}
