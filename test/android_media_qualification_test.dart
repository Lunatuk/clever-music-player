import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

import 'package:clever_music_player/src/android/android_audio_metadata_backend.dart';
import 'package:clever_music_player/src/android/android_media_qualification.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Backend backend;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cmp_media_qualification_');
    backend = _Backend();
  });
  tearDown(() async {
    expect(await root.list().toList(), isEmpty);
    await root.delete();
  });
  Future<Uint8List> asset(String name) async =>
      Uint8List.fromList(name.endsWith('.png')
          ? [137, 80, 78, 71, 13, 10, 26, 10, 1]
          : name.endsWith('.jpg')
              ? [255, 216, 255, 2]
              : name.codeUnits);
  AndroidMediaQualification service(
          {Future<Uint8List> Function(String)? loader}) =>
      AndroidMediaQualification(
          backend: () => backend,
          privateDirectory: () async => root,
          asset: loader ?? asset);
  test(
      'all six formats/covers pass the real preparer and remove only owned fixtures',
      () async {
    final cases = <int>[];
    expect(await service().check(LibraryScanControl(), onCase: cases.add),
        '7.1.5');
    expect(cases, [0, 1, 2, 3, 4, 5]);
    expect(backend.writes.length, 6);
    expect(backend.closed, true);
    expect(backend.writes.map((w) => w.$1), [
      DownloadedAudioContainer.mp3,
      DownloadedAudioContainer.mp3,
      DownloadedAudioContainer.m4a,
      DownloadedAudioContainer.m4a,
      DownloadedAudioContainer.flac,
      DownloadedAudioContainer.flac
    ]);
    expect(backend.writes.map((w) => w.$2), [
      EmbeddedCoverFormat.png,
      EmbeddedCoverFormat.jpeg,
      EmbeddedCoverFormat.png,
      EmbeddedCoverFormat.jpeg,
      EmbeddedCoverFormat.png,
      EmbeddedCoverFormat.jpeg
    ]);
  });
  test('capability failure closes backend without loading files', () async {
    backend.capabilityFailure = true;
    await expectLater(
        service(loader: (_) async => throw StateError('must not load'))
            .check(LibraryScanControl()),
        throwsA(isA<AudioValidationException>()));
    expect(backend.closed, true);
    expect(backend.writes, isEmpty);
  });
  test('oversized fixture is rejected and temporary empty source is removed',
      () async {
    await expectLater(
        service(
            loader: (name) => name.contains('tone.')
                ? Future.value(Uint8List(65537))
                : asset(name)).check(LibraryScanControl()),
        throwsA(isA<AudioValidationException>()));
    expect(backend.closed, true);
    expect(backend.writes, isEmpty);
  });
  test(
      'cancel waits for the accepted writer before deleting files or closing backend',
      () async {
    backend.entered = Completer<void>();
    backend.release = Completer<void>();
    final control = LibraryScanControl();
    var finished = false;
    final running = expectLater(
            service().check(control),
            throwsA(isA<AudioValidationException>().having(
                (e) => e.outcome, 'outcome', AudioValidationOutcome.cancelled)))
        .then((_) {
      finished = true;
    });
    await backend.entered!.future;
    control.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(finished, false);
    expect(backend.closed, false);
    expect(await root.list().toList(), isNotEmpty);
    backend.release!.complete();
    await running;
    expect(backend.closed, true);
  });
  test('pre-cancelled qualification creates no backend or directory', () async {
    var created = false;
    final check = AndroidMediaQualification(
        backend: () {
          created = true;
          return backend;
        },
        privateDirectory: () async => throw StateError('no IO'));
    await expectLater(check.check(LibraryScanControl()..cancel()),
        throwsA(isA<LibraryScanCancelled>()));
    expect(created, false);
  });
}

class _Prepared {
  _Prepared(this.expected, this.cover);
  final DownloadedAudioExpectation expected;
  final List<int> cover;
}

class _Backend implements AndroidMediaProcessingBackend {
  bool closed = false, capabilityFailure = false;
  Completer<void>? entered, release;
  final prepared = <String, _Prepared>{};
  final writes = <(DownloadedAudioContainer, EmbeddedCoverFormat?)>[];
  @override
  Future<String> capabilities(LibraryScanControl control) async {
    if (capabilityFailure) {
      throw const AudioValidationException(
          AudioValidationOutcome.backendUnavailable);
    }
    return '7.1.5';
  }

  @override
  Future<DownloadedAudioInspection> inspect(
      File file, LibraryScanControl control) async {
    final output = prepared[file.path];
    final format = output?.expected.container ??
        (file.path.contains('m4a')
            ? DownloadedAudioContainer.m4a
            : file.path.contains('flac')
                ? DownloadedAudioContainer.flac
                : DownloadedAudioContainer.mp3);
    return DownloadedAudioInspection(
        container: format,
        codec: switch (format) {
          DownloadedAudioContainer.mp3 => DownloadedAudioCodec.mp3,
          DownloadedAudioContainer.m4a => DownloadedAudioCodec.aac,
          DownloadedAudioContainer.flac => DownloadedAudioCodec.flac
        },
        duration: const Duration(milliseconds: 600),
        sizeBytes: await file.length(),
        audioStreamIndex: 0,
        sampleRate: 48000,
        channels: 1,
        bitRate: format == DownloadedAudioContainer.flac ? null : 128000,
        bitDepth: format == DownloadedAudioContainer.flac ? 16 : null,
        coverStreamIndex: output == null ? null : 1,
        tags: output?.expected.tags ?? {});
  }

  @override
  Future<Duration> decodeAudio(File file, DownloadedAudioInspection inspection,
          LibraryScanControl control) async =>
      const Duration(milliseconds: 600);
  @override
  Future<void> decodeCover(File file, DownloadedAudioInspection inspection,
      LibraryScanControl control) async {}
  @override
  Future<String> digest(File file, DownloadedAudioInspection info,
          AudioCopyDigest mode, LibraryScanControl control) async =>
      mode == AudioCopyDigest.cover
          ? crypto.sha256.convert(prepared[file.path]!.cover).toString()
          : (mode == AudioCopyDigest.packets ? 'a' : 'b') * 64;
  @override
  Future<void> writeMetadata(
      File source,
      File output,
      DownloadedAudioInspection info,
      DownloadedAudioExpectation expected,
      LibraryScanControl control,
      {File? cover,
      EmbeddedCoverFormat? coverFormat,
      int? maxOutputBytes}) async {
    entered?.complete();
    await release?.future;
    final before = await source.readAsBytes();
    final picture = await cover!.readAsBytes();
    prepared[output.path] = _Prepared(expected, picture);
    writes.add((expected.container, coverFormat));
    await output.writeAsBytes([...before, ...picture], flush: true);
    expect(await source.readAsBytes(), before);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
