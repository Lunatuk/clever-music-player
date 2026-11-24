import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/audio_comparison.dart';
import 'package:clever_music_player/src/library/audio_fingerprint.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/library_track_variants.dart';
import 'package:clever_music_player/src/library/recording_candidate_selection.dart';
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

  test('a whole-recording match is a hint and grants no exact proof', () async {
    final words = _words();
    final other = _fingerprint([0, 1, 2, 3, 4, ...words.take(475)]);
    final reader = _FingerprintReader(_fingerprint(words), other);
    final comparison = await AudioComparisonService((_) async => reader,
            revisionReader: (_) async => 'a' * 64)
        .compareWithProof(first.copyWith(id: 1), second.copyWith(id: 2),
            control: LibraryScanControl());
    expect(comparison.result, AudioComparisonResult.possiblySameRecording);
    expect(comparison.proof, isNull);
    expect(reader.closed, isTrue);
  });

  test('a change during fingerprinting discards the result', () async {
    final fingerprint = _fingerprint(_words());
    var revision = 'a' * 64;
    final reader = _FingerprintReader(fingerprint, fingerprint,
        onFingerprint: () => revision = 'b' * 64);
    final comparison = await AudioComparisonService((_) async => reader,
            revisionReader: (_) async => revision)
        .compareWithProof(first, second, control: LibraryScanControl());
    expect(comparison.result, AudioComparisonResult.unreadable);
    expect(comparison.proof, isNull);
    expect(reader.closed, isTrue);
  });

  test('a missing fingerprint preserves the exact result', () async {
    final reader = _FingerprintReader(null, _fingerprint(_words()));
    final comparison = await AudioComparisonService((_) async => reader,
            revisionReader: (_) async => 'a' * 64)
        .compareWithProof(first, second, control: LibraryScanControl());
    expect(comparison.result, AudioComparisonResult.different);
    expect(comparison.proof, isNull);
    expect(reader.fingerprintReads, 1);
  });

  test('a differing ending fails even when the full average is high', () async {
    final words = _words();
    final endedDifferently = [
      ...words.take(455),
      for (final word in words.skip(455)) word ^ 0xffff,
    ];
    expect(
        await compareRecordingFingerprints(
            _fingerprint(words), _fingerprint(endedDifferently)),
        RecordingSimilarity.belowThreshold);
    expect(
        await compareRecordingFingerprints(
            _fingerprint(words), _fingerprint(List.filled(480, 0))),
        RecordingSimilarity.inconclusive);
  });

  test('cancellation during the approximate pass discards the hint', () async {
    final control = LibraryScanControl();
    final fp = _fingerprint(_words());
    final reader = _FingerprintReader(fp, fp, onFingerprint: control.cancel);
    final result = await AudioComparisonService((_) async => reader,
            revisionReader: (_) async => 'a' * 64)
        .compare(first, second, control: control);
    expect(result, AudioComparisonResult.cancelled);
    expect(reader.fingerprintReads, 1);
    expect(reader.closed, isTrue);
  });

  test('fingerprint parsing rejects malformed and oversized responses', () {
    for (final invalid in ['G234ffff', '0123', '0' * (8 * 15001)]) {
      expect(
          AudioFingerprint.decode({
            'status': 'ok',
            'durationUs': 60000000,
            'fingerprint': invalid,
          }),
          isNull);
    }
  });

  test('candidate preselection uses title, artist, duration and known copies',
      () {
    const duration = Duration(seconds: 62);
    final reference = track('/music/one.flac', 'ANDROMEDA – 2019').copyWith(
        artist: 'LXST CXNTURY', duration: duration, album: 'Andromeda');
    final possible = track('/music/two.m4a', 'Andromeda (2019)').copyWith(
        artist: 'lxst   CXNTURY', duration: duration, album: 'Andromeda');
    final unknownArtist =
        track('/music/3.m4a', 'Andromeda 2019').copyWith(duration: duration);
    final sameTitleOtherArtist = track('/music/4.m4a', 'Andromeda 2019')
        .copyWith(artist: 'Another Artist', duration: duration);
    final longer = possible.copyWith(
        filePath: '/music/5.m4a', duration: const Duration(seconds: 65));
    final missing =
        possible.copyWith(filePath: '/music/6.m4a', isMissing: true);
    final known = possible.copyWith(filePath: '/music/7.m4a');
    expect(
        selectRecordingCandidates(
            reference,
            [
              reference,
              unknownArtist,
              sameTitleOtherArtist,
              longer,
              missing,
              known,
              possible
            ],
            alreadyKnown: (item) => identical(item, known)),
        [possible, unknownArtist]);
  });

  test('same SAF document across folder grants is not a candidate', () {
    final reference = first.copyWith(
        filePath:
            'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AMusic%2Ftrack.flac',
        artist: 'Artist');
    final alias = reference.copyWith(
        filePath:
            'content://com.android.externalstorage.documents/tree/primary%3A/document/primary%3AMusic%2Ftrack.flac');
    expect(selectRecordingCandidates(reference, [alias]), isEmpty);
  });

  test('candidate search reads the reference once and bounds audio work',
      () async {
    final reference = first.copyWith(artist: 'Composer');
    final candidates = List.generate(
        12,
        (i) => reference.copyWith(
            filePath: '/music/candidate-${i.toString().padLeft(2, '0')}.m4a'));
    final words = _words();
    final unrelated =
        _fingerprint(words.map((word) => word ^ 0xffffffff).toList());
    final reader = _CandidateReader((source, _) async =>
        source == candidates[1].source ? unrelated : _fingerprint(words));
    final search = AudioComparisonService((_) async => reader,
        revisionReader: (_) async => 'a' * 64);
    final result = await search.findSimilarRecordings(reference, candidates,
        control: LibraryScanControl());
    expect(result.outcome, AudioCandidateSearchOutcome.completed);
    expect(result.candidates, 12);
    expect(result.checked, recordingCandidateLimit);
    expect(result.matches, [candidates.first, ...candidates.skip(2).take(6)]);
    expect(reader.fingerprintSources, [
      reference.source,
      ...candidates.take(recordingCandidateLimit).map((t) => t.source)
    ]);
    expect(reader.reads, 0);
    expect(reader.closed, isTrue);
  });

  test('candidate search discards modified results and skips unreadable files',
      () async {
    final reference = first.copyWith(artist: 'Composer');
    final two = reference.copyWith(filePath: '/music/2.m4a');
    final three = reference.copyWith(filePath: '/music/3.m4a');
    final four = reference.copyWith(filePath: '/music/4.m4a');
    var revision = 'a' * 64;
    final fp = _fingerprint(_words());
    final reader = _CandidateReader((source, _) async {
      if (source == three.source) throw const FormatException();
      if (source == four.source) revision = 'b' * 64;
      return fp;
    });
    final result = await AudioComparisonService((_) async => reader,
        revisionReader: (source) async =>
            source == two.source ? revision : 'c' * 64).findSimilarRecordings(
        reference, [two, three, four],
        control: LibraryScanControl());
    expect(result.checked, 2);
    expect(result.matches, [four]);
  });

  test('candidate cancellation stops the queue and releases its reader',
      () async {
    final reference = first.copyWith(artist: 'Composer');
    final control = LibraryScanControl();
    final fp = _fingerprint(_words());
    final reader = _CandidateReader((_, __) async {
      control.cancel();
      return fp;
    });
    final result = await AudioComparisonService((_) async => reader,
            revisionReader: (_) async => 'a' * 64)
        .findSimilarRecordings(
            reference, [reference.copyWith(filePath: '/music/2.m4a')],
            control: control);
    expect(result.outcome, AudioCandidateSearchOutcome.cancelled);
    expect(result.matches, isEmpty);
    expect(reader.fingerprintSources, [reference.source]);
    expect(reader.closed, isTrue);
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

  testWidgets(
      'dialog finds a candidate outside the manual filter and selects it',
      (tester) async {
    final reference = first.copyWith(title: 'Original!', artist: 'Composer');
    final candidate = second.copyWith(title: 'ORIGINAL', artist: 'COMPOSER');
    final fp = _fingerprint(_words());
    final reader = _CandidateReader((_, __) async => fp);
    final service = AudioComparisonService((_) async => reader,
        revisionReader: (_) async => 'a' * 64);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                    body: TextButton(
                  onPressed: () => showAudioComparisonDialog(context,
                      tracks: [reference, candidate],
                      comparison: service,
                      searchQuery: 'Original!'),
                  child: const Text('Открыть'),
                )))));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(ListTile), matching: find.text('Original!')));
    await tester.pumpAndSettle();
    expect(find.text('ORIGINAL'), findsNothing);
    await tester.tap(find.text('Найти похожие'));
    for (var tick = 0; !reader.finished.isCompleted && tick < 20; tick++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(reader.finished.isCompleted, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Возможные версии: 1. Проверено 1 из 1.'), findsOneWidget);
    await tester.tap(find.text('ORIGINAL'));
    await tester.pumpAndSettle();
    expect(find.text('Выбрано 2 из 2'), findsOneWidget);
    expect(find.text('Сравнить'), findsOneWidget);
    expect(find.text('Сгруппировать версии'), findsNothing);
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

List<int> _words() {
  final random = Random(42);
  return List.generate(480, (_) => random.nextInt(1 << 32));
}

AudioFingerprint _fingerprint(List<int> words) => AudioFingerprint.decode({
      'status': 'ok',
      'durationUs': 62000000,
      'fingerprint':
          words.map((word) => word.toRadixString(16).padLeft(8, '0')).join(),
    })!;

final class _FingerprintReader extends _Reader
    implements AudioFingerprintReader {
  _FingerprintReader(this.left, this.right, {this.onFingerprint})
      : super((source, _) async => (
              digest: (source == first.source ? 'a' : 'b') * 64,
              sampleRate: 48000,
              channels: 2,
            ));

  final AudioFingerprint? left, right;
  final void Function()? onFingerprint;
  int fingerprintReads = 0;

  @override
  Future<AudioFingerprint?> readFingerprint(
      AudioSourceReference source, LibraryScanControl control) async {
    fingerprintReads++;
    onFingerprint?.call();
    return source == first.source ? left : right;
  }
}

final class _CandidateReader extends _Reader implements AudioFingerprintReader {
  _CandidateReader(this._fingerprint) : super((_, __) async => equalPcm);

  final Future<AudioFingerprint?> Function(
      AudioSourceReference, LibraryScanControl) _fingerprint;
  final fingerprintSources = <AudioSourceReference>[];
  final finished = Completer<void>();

  @override
  Future<AudioFingerprint?> readFingerprint(
      AudioSourceReference source, LibraryScanControl control) {
    fingerprintSources.add(source);
    return _fingerprint(source, control);
  }

  @override
  Future<void> close() async {
    await super.close();
    finished.complete();
  }
}

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
