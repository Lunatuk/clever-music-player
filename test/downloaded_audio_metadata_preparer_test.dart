import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clever_music_player/src/domain/models/audio_source_reference.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/desktop_publication_store.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata_preparer.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/publication_fixture.dart';

void main() {
  late Directory root;
  late File source, sentinel;
  late _Backend backend;
  late DownloadedAudioMetadataPreparer preparer;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cmp_metadata_test_');
    source = await File(p.join(root.path, 'raw.part')).writeAsString('abc');
    sentinel = await File(p.join(root.path, 'other.mp3')).writeAsString('keep');
    backend = _Backend(source);
    preparer = DownloadedAudioMetadataPreparer(
        backend: backend, temporaryParent: root, clock: () => publicationNow);
  });
  tearDown(() async {
    await preparer.close();
    final allowed = await Directory.systemTemp.resolveSymbolicLinks();
    final target = await root.resolveSymbolicLinks();
    expect(p.isWithin(allowed, target), isTrue);
    await Directory(target).delete(recursive: true);
  });
  Matcher failure(AudioValidationOutcome outcome) =>
      throwsA(isA<AudioValidationException>()
          .having((error) => error.outcome, 'outcome', outcome));
  Future<List<Directory>> scratch() async =>
      (await root.list().toList()).whereType<Directory>().toList();

  test('prepared private output is verified; source and siblings are unchanged',
      () async {
    final result =
        await preparer.prepare(FileAudioSource(source.path), _expected());
    expect(await source.readAsString(), 'abc');
    expect(await sentinel.readAsString(), 'keep');
    expect(await result.file.readAsString(), 'tagged');
    expect(result.verification.contentHash,
        sha256.convert('tagged'.codeUnits).toString());
    expect(result.verification.fileSizeBytes, 6);
    expect(result.verification.checkedAt, publicationNow);
    expect(result.inspection.tags, {'title': 'Трек'});
    await preparer.close();
    expect(await result.file.exists(), isTrue);
    await result.close();
    await result.close();
    expect(await result.file.parent.exists(), isFalse);
    expect(await sentinel.readAsString(), 'keep');
    expect(backend.closeCalls, 1);
  });
  test('cover is snapshotted, embedded and checked against its exact bytes',
      () async {
    final bytes = [137, 80, 78, 71, 13, 10, 26, 10, 42];
    final cover = EmbeddedCover(bytes, EmbeddedCoverFormat.png);
    bytes[8] = 0;
    expect(() => cover.bytes[8] = 0, throwsUnsupportedError);
    final result = await preparer.prepare(
        FileAudioSource(source.path), _expected(cover: true),
        cover: cover);
    expect(backend.coverBytes!.last, 42);
    expect(result.inspection.coverStreamIndex, 1);
    await result.close();
  });
  test('existing cover is retained when a replacement is absent', () async {
    backend.sourceCover = true;
    final result = await preparer.prepare(
        FileAudioSource(source.path), _expected(cover: true));
    expect(result.inspection.coverStreamIndex, 1);
    expect(backend.coverBytes, isNull);
    await result.close();
  });
  test('missing required cover fails before creating an output', () async {
    await expectLater(
        preparer.prepare(FileAudioSource(source.path), _expected(cover: true)),
        failure(AudioValidationOutcome.coverMissing));
    expect(await scratch(), isEmpty);
    expect(backend.writes, 0);
  });
  test('source size mismatch does not invoke the backend', () async {
    await expectLater(
        preparer.prepare(FileAudioSource(source.path), _expected(size: 4)),
        failure(AudioValidationOutcome.changed));
    expect(backend.inspections, 0);
    expect(await scratch(), isEmpty);
  });
  test('unsupported URI does not start a file operation', () async {
    await expectLater(
        preparer.prepare(
            ContentUriAudioSource('content://test/song'), _expected()),
        failure(AudioValidationOutcome.unsupportedSource));
    expect(backend.inspections, 0);
  });
  test('total tag argv is bounded without truncating individual values',
      () async {
    await expectLater(
        preparer.prepare(
            FileAudioSource(source.path),
            _expected(tags: {
              'title': 'a' * 3000,
              'artist': 'b' * 3000,
              'album': 'c' * 3000
            })),
        failure(AudioValidationOutcome.metadataMismatch));
    expect(backend.inspections, 0);
  });
  test('pre-cancelled work does not read source or create output', () async {
    final control = LibraryScanControl()..cancel();
    await expectLater(
        preparer.prepare(FileAudioSource(source.path), _expected(),
            control: control),
        failure(AudioValidationOutcome.cancelled));
    expect(backend.inspections, 0);
    expect(await scratch(), isEmpty);
  });
  for (final mutation in [
    'packets',
    'pcm',
    'rate',
    'channels',
    'metadata',
    'late output',
    'source'
  ]) {
    test('reject $mutation change and clean only generated files', () async {
      backend.mutation = mutation;
      await expectLater(
          preparer.prepare(FileAudioSource(source.path), _expected()),
          failure(mutation == 'metadata'
              ? AudioValidationOutcome.metadataMismatch
              : AudioValidationOutcome.changed));
      expect(await scratch(), isEmpty);
      expect(await sentinel.readAsString(), 'keep');
      if (mutation != 'source') expect(await source.readAsString(), 'abc');
    });
  }
  for (final mutation in ['cover', 'extra cover', 'cover decode']) {
    test('reject $mutation without returning proof', () async {
      backend.mutation = mutation;
      backend.sourceCover = mutation != 'extra cover';
      await expectLater(
          preparer.prepare(FileAudioSource(source.path), _expected()),
          failure(AudioValidationOutcome.invalidCover));
      expect(await scratch(), isEmpty);
    });
  }
  test('failed writer is drained before its reserved output is removed',
      () async {
    backend.onWrite = (_, __) async {
      throw const AudioValidationException(
          AudioValidationOutcome.backendUnavailable);
    };
    await expectLater(
        preparer.prepare(FileAudioSource(source.path), _expected()),
        failure(AudioValidationOutcome.backendUnavailable));
    expect(await scratch(), isEmpty);
    expect(await source.readAsString(), 'abc');
  });
  test('close cancels, drains an accepted write and rejects new work',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    backend.onWrite = (_, __) async {
      entered.complete();
      await release.future;
    };
    final preparing =
        preparer.prepare(FileAudioSource(source.path), _expected());
    final rejected =
        expectLater(preparing, failure(AudioValidationOutcome.cancelled));
    await entered.future;
    await expectLater(
        preparer.prepare(FileAudioSource(source.path), _expected()),
        throwsStateError);
    var closed = false;
    final closing = preparer.close().then((_) => closed = true);
    expect(await scratch(), hasLength(1));
    expect(closed, isFalse);
    expect(backend.closeCalls, 0);
    await expectLater(
        preparer.prepare(FileAudioSource(source.path), _expected()),
        throwsStateError);
    release.complete();
    await rejected;
    await closing;
    expect(await scratch(), isEmpty);
    expect(backend.closeCalls, 1);
  });
  test('timeout cancels cooperatively and returns a distinct failure',
      () async {
    await preparer.close();
    backend = _Backend(source);
    backend.onWrite = (_, control) async {
      final cancelled = Completer<void>();
      control.addCancellationListener(cancelled.complete);
      await cancelled.future;
    };
    preparer = DownloadedAudioMetadataPreparer(
        backend: backend,
        temporaryParent: root,
        timeout: const Duration(seconds: 1));
    await expectLater(
        preparer.prepare(FileAudioSource(source.path), _expected()),
        failure(AudioValidationOutcome.timedOut));
    expect(await scratch(), isEmpty);
  });
  test('close drains an accepted prepare even if its caller forgot await',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    backend.onWrite = (_, __) async {
      entered.complete();
      await release.future;
    };
    unawaited(preparer.prepare(FileAudioSource(source.path), _expected()));
    await entered.future;
    final closing = preparer.close();
    expect(await scratch(), hasLength(1));
    release.complete();
    await closing;
    expect(await scratch(), isEmpty);
    expect(backend.closeCalls, 1);
  });
  test('validated output streams through publication with the same proof',
      () async {
    final result =
        await preparer.prepare(FileAudioSource(source.path), _expected());
    final library = await Directory(p.join(root.path, 'library')).create();
    final store = DesktopPublicationStore(
        jobs: PublicationTestJobs(library.path), clock: () => publicationNow);
    try {
      final receipt = await store.run(publicationJob(), (workspace) async {
        await workspace.writeAudio(result.file.openRead(),
            expectedSize: result.verification.fileSizeBytes);
        return workspace.publish(publicationJob(), result.verification);
      });
      await result.close();
      expect(await File(receipt.filePath).readAsString(), 'tagged');
      expect(receipt.verification.contentHash, result.verification.contentHash);
      expect(await source.readAsString(), 'abc');
    } finally {
      await store.close();
      await result.close();
    }
  });
  test('result cleanup refuses to recursively delete unknown content',
      () async {
    final result =
        await preparer.prepare(FileAudioSource(source.path), _expected());
    final other = await File(p.join(result.file.parent.path, 'unknown'))
        .writeAsString('keep this');
    await expectLater(
        result.close(), failure(AudioValidationOutcome.unreadable));
    expect(await other.readAsString(), 'keep this');
  });
  test('cover header, byte range and size are bounded before copying', () {
    for (final bytes in [
      <int>[],
      [1, 2, 3],
      [255, 216, 255, -1],
      Uint8List(8 * 1024 * 1024 + 1)
    ]) {
      expect(() => EmbeddedCover(bytes, EmbeddedCoverFormat.jpeg),
          throwsArgumentError);
    }
    expect(() => EmbeddedCover([255, 216, 255], EmbeddedCoverFormat.png),
        throwsArgumentError);
  });
}

DownloadedAudioExpectation _expected(
        {bool cover = false,
        int size = 3,
        Map<String, String> tags = const {'title': 'Трек'}}) =>
    DownloadedAudioExpectation(
        quality: 'high',
        container: DownloadedAudioContainer.mp3,
        codec: DownloadedAudioCodec.mp3,
        fileSizeBytes: size,
        duration: const Duration(seconds: 3),
        minimumBitRate: 300000,
        requireCover: cover,
        tags: tags);

final class _Backend implements AudioMetadataBackend {
  _Backend(this.source);
  final File source;
  String? mutation;
  bool sourceCover = false;
  List<int>? coverBytes;
  int closeCalls = 0, inspections = 0, writes = 0;
  Future<void> Function(File, LibraryScanControl)? onWrite;
  Map<String, String> tags = const {};
  String coverDigest = '3' * 64;
  @override
  Future<DownloadedAudioInspection> inspect(
      File file, LibraryScanControl control) async {
    inspections++;
    final original = file.path == source.path;
    return DownloadedAudioInspection(
        container: DownloadedAudioContainer.mp3,
        codec: DownloadedAudioCodec.mp3,
        duration: const Duration(seconds: 3),
        sizeBytes: await file.length(),
        audioStreamIndex: 0,
        sampleRate: !original && mutation == 'rate' ? 96000 : 48000,
        channels: !original && mutation == 'channels' ? 1 : 2,
        bitRate: 320000,
        coverStreamIndex: (original
                ? sourceCover
                : sourceCover ||
                    coverBytes != null ||
                    mutation == 'extra cover')
            ? 1
            : null,
        tags: original
            ? {}
            : mutation == 'metadata'
                ? {'title': 'Other'}
                : tags);
  }

  @override
  Future<void> writeMetadata(
      File source,
      File output,
      DownloadedAudioInspection info,
      DownloadedAudioExpectation expected,
      LibraryScanControl control,
      {File? cover,
      EmbeddedCoverFormat? coverFormat}) async {
    writes++;
    await onWrite?.call(output, control);
    control.throwIfCancelled();
    tags = expected.tags;
    if (cover != null) {
      coverBytes = await cover.readAsBytes();
      coverDigest = sha256.convert(coverBytes!).toString();
    }
    await output.writeAsString('tagged');
    if (mutation == 'source') await source.writeAsString('xyz');
  }

  @override
  Future<String> digest(File file, DownloadedAudioInspection info,
      AudioCopyDigest mode, LibraryScanControl control) async {
    final original = file.path == source.path;
    if (!original &&
        mode == AudioCopyDigest.decodedPcm &&
        mutation == 'late output') {
      await file.writeAsString('edited');
    }
    return switch (mode) {
      AudioCopyDigest.packets =>
        !original && mutation == 'packets' ? '9' * 64 : '1' * 64,
      AudioCopyDigest.decodedPcm =>
        !original && mutation == 'pcm' ? '8' * 64 : '2' * 64,
      AudioCopyDigest.cover =>
        !original && mutation == 'cover' ? '4' * 64 : coverDigest,
    };
  }

  @override
  Future<Duration> decodeAudio(File file, DownloadedAudioInspection info,
          LibraryScanControl control) async =>
      const Duration(seconds: 3);
  @override
  Future<void> decodeCover(File file, DownloadedAudioInspection info,
      LibraryScanControl control) async {
    if (mutation == 'cover decode') {
      throw const AudioValidationException(AudioValidationOutcome.invalidCover);
    }
  }

  @override
  Future<void> close() async => closeCalls++;
}
