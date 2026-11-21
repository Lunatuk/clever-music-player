import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/audio_comparison.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/library_track_variants.dart';
import 'package:clever_music_player/src/library_sync/bundled_media_helper.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:clever_music_player/src/ui/library/audio_comparison_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('matching PCM still requires the same sample rate and channel count',
      () async {
    final reader = _Reader(((source, _) async => (
          digest: 'a' * 64,
          sampleRate: source == first.source ? 48000 : 44100,
          channels: 2
        )));
    final service = AudioComparisonService((_) async => reader);
    expect(await service.compare(first, second, control: LibraryScanControl()),
        AudioComparisonResult.different);
    expect(reader.closed, isTrue);
  });

  test('cancellation stops the first read, closes it and skips the second',
      () async {
    final entered = Completer<void>();
    final control = LibraryScanControl();
    final reader = _Reader((_, operation) async {
      final stopped = Completer<void>();
      operation.addCancellationListener(stopped.complete);
      entered.complete();
      await stopped.future;
      operation.throwIfCancelled();
      return equalPcm;
    });
    final task = AudioComparisonService((_) async => reader)
        .compare(first, second, control: control);
    await entered.future;
    control.cancel();
    expect(await task, AudioComparisonResult.cancelled);
    expect(reader.reads, 1);
    expect(reader.closed, isTrue);
  });

  test('deadline cancels a slow reader and reports a timeout', () async {
    final reader = _Reader((_, operation) async {
      final stopped = Completer<void>();
      operation.addCancellationListener(stopped.complete);
      await stopped.future;
      operation.throwIfCancelled();
      return equalPcm;
    });
    expect(
        await AudioComparisonService((_) async => reader,
                timeout: const Duration(milliseconds: 20))
            .compare(first, second, control: LibraryScanControl()),
        AudioComparisonResult.timedOut);
    expect(reader.closed, isTrue);
  });

  test('a changed source during comparison cannot produce library proof',
      () async {
    var revision = 'a' * 64;
    final reader = _Reader((source, _) async {
      if (source == second.source) revision = 'b' * 64;
      return equalPcm;
    });
    final service = AudioComparisonService((_) async => reader,
        revisionReader: (source) async =>
            source == first.source ? revision : 'c' * 64);
    final comparison = await service.compareWithProof(
        first.copyWith(id: 1), second.copyWith(id: 2),
        control: LibraryScanControl());
    expect(comparison.result, AudioComparisonResult.unreadable);
    expect(comparison.proof, isNull);
  });

  testWidgets('dialog selects two independent files even with the same search',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reader = _Reader((_, __) async => equalPcm);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showAudioComparisonDialog(context,
                      tracks: [first, second],
                      comparison: AudioComparisonService((_) async => reader)),
                  child: const Text('Открыть сравнение'),
                ),
              )),
    ));
    await tester.tap(find.text('Открыть сравнение'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('audio-comparison-search'));
    await tester.enterText(search, 'Fir');
    await tester.pumpAndSettle();
    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    await tester.enterText(search, 'Sec');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();
    expect(find.text('Выбрано 2 из 2'), findsOneWidget);
    await tester.tap(find.text('Сравнить'));
    await tester.pumpAndSettle();
    expect(find.text('Звук совпадает'), findsOneWidget);
    expect(reader.reads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dialog saves only after a confirmed audio match',
      (tester) async {
    final matches = _Matches();
    final service = AudioComparisonService(
        (_) async => _Reader((_, __) async => equalPcm),
        revisionReader: (_) async => 'a' * 64);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                onPressed: () => showAudioComparisonDialog(context,
                    comparison: service,
                    tracks: [first.copyWith(id: 1), second.copyWith(id: 2)],
                    matches: matches),
                child: const Text('Открыть'),
              ))),
    ));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Сгруппировать версии'), findsNothing);
    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сравнить'));
    await tester.pumpAndSettle();
    expect(matches.proof, isNull);
    await tester.tap(find.text('Сгруппировать версии'));
    await tester.pumpAndSettle();
    expect(find.text('Совпадение сохранено в медиатеке'), findsOneWidget);
    expect(matches.proof?.key, '1:48000:2:${equalPcm.digest}');
  });

  final helperPath = Platform.environment['CMP_TEST_MEDIA_HELPER'];
  for (final extension in ['mp3', 'm4a', 'flac']) {
    test('real ${extension.toUpperCase()} ignores tags and embedded cover',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('cmp_audio_Музыка_');
      addTearDown(() => directory.delete(recursive: true));
      final helper = BundledMediaHelper(directory: Directory(helperPath!));
      addTearDown(helper.close);
      final qualified = await helper.qualify();
      final remux = qualified.createMetadataBackend();
      addTearDown(remux.close);
      final original = File('test/fixtures/media_helper/tone.$extension');
      final other = File(
          'test/fixtures/media_helper/tone.${extension == 'mp3' ? 'flac' : 'mp3'}');
      final prepared = File(p.join(directory.path, 'Копия.$extension'));
      final control = LibraryScanControl();
      final info = await remux.inspect(original, control);
      await remux.writeMetadata(
          original,
          prepared,
          info,
          DownloadedAudioExpectation(
            quality: 'test',
            container: info.container,
            codec: info.codec,
            fileSizeBytes: info.sizeBytes,
            duration: info.duration,
            minimumBitRate: extension == 'flac' ? null : 90000,
            tags: {'title': 'Другое название', 'album': 'Другой альбом'},
          ),
          control,
          cover: File('test/fixtures/media_helper/cover.png'),
          coverFormat: EmbeddedCoverFormat.png);
      expect(await prepared.readAsBytes(), isNot(await original.readAsBytes()));
      final service = AudioComparisonService(
          (_) async =>
              DesktopAudioComparisonReader(qualified.createMetadataBackend()),
          revisionReader: readDesktopAudioRevision);
      final match = await service.compareWithProof(
          track(original.absolute.path, 'Original').copyWith(id: 1),
          track(prepared.path, 'Remuxed').copyWith(id: 2),
          control: control);
      expect(match.result, AudioComparisonResult.equal);
      expect(match.proof, isNotNull);
      expect(
          await service.compare(track(original.absolute.path, 'Original'),
              track(other.absolute.path, 'Other encoding'),
              control: control),
          AudioComparisonResult.different);
    },
        skip: !Platform.isWindows || helperPath == null
            ? 'Requires the qualified Windows helper via CMP_TEST_MEDIA_HELPER.'
            : false);
  }
}

class _Matches implements AudioMatchRepository {
  AudioMatchProof? proof;

  @override
  Future<AudioMatchSaveResult> rememberAudioMatch(AudioMatchProof proof) async {
    this.proof = proof;
    return AudioMatchSaveResult.saved;
  }

  @override
  Future<void> forgetAudioMatches(Map<int, String> matches) async {}
}

final first = track('/music/first.flac', 'First');
final second = track('/music/second.flac', 'Second');
final equalPcm = (digest: 'a' * 64, sampleRate: 48000, channels: 2);

Track track(String path, String title) => Track(
    filePath: path,
    title: title,
    addedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026));

final class _Reader implements AudioComparisonReader {
  _Reader(this._read);
  final Future<AudioPcmSignature> Function(
      AudioSourceReference, LibraryScanControl) _read;
  bool closed = false;
  int reads = 0;

  @override
  Future<AudioPcmSignature> read(
      AudioSourceReference source, LibraryScanControl control) {
    reads++;
    return _read(source, control);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
