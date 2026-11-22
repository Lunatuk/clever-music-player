import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../diagnostics/diagnostics_service.dart';
import '../domain/models/audio_document_identity.dart';
import '../domain/models/audio_source_reference.dart';
import '../domain/models/track.dart';
import '../library_sync/bundled_media_helper.dart';
import '../library_sync/downloaded_audio_metadata.dart';
import '../library_sync/downloaded_audio_validation.dart';
import '../library_sync/ffmpeg_audio_metadata_backend.dart';
import '../library_sync/media_process_runner.dart';
import 'audio_fingerprint.dart';
import 'library_scan_control.dart';

const audioComparisonMaxBytes = 128 * 1024 * 1024;
const audioComparisonMaxDuration = Duration(minutes: 30);

typedef AudioPcmSignature = ({String digest, int sampleRate, int channels});
typedef AudioRevisionReader = Future<String?> Function(AudioSourceReference);
typedef AudioComparison = ({
  AudioComparisonResult result,
  AudioMatchProof? proof
});

enum AudioComparisonResult {
  equal,
  different,
  possiblySameRecording,
  unreadable,
  cancelled,
  timedOut
}

final class AudioMatchProof {
  const AudioMatchProof._(this.first, this.second, this.key, this.firstRevision,
      this.secondRevision);

  final Track first, second;
  final String key, firstRevision, secondRevision;
}

String audioRevisionKey(List<Object> fields) =>
    sha256.convert(utf8.encode(jsonEncode(fields))).toString();

final _revisionPattern = RegExp(r'^[0-9a-f]{64}$');
bool isAudioRevisionKey(String key) => _revisionPattern.stringMatch(key) == key;

final _pcmKeyPattern = RegExp(r'^1:[0-9]{4,6}:[12]:[0-9a-f]{64}$');
bool isAudioMatchKey(String key) => _pcmKeyPattern.stringMatch(key) == key;

Future<String?> readDesktopAudioRevision(AudioSourceReference source) async {
  if (source is! FileAudioSource) return null;
  final stat = await File(source.path).stat();
  if (stat.type != FileSystemEntityType.file ||
      stat.size <= 0 ||
      stat.size > audioComparisonMaxBytes) {
    return null;
  }
  return audioRevisionKey([
    'desktop',
    source.storageValue,
    stat.size,
    stat.modified.microsecondsSinceEpoch,
    stat.changed.microsecondsSinceEpoch
  ]);
}

Future<String?> tryAudioRevision(
    AudioRevisionReader? reader, AudioSourceReference source) async {
  try {
    final revision =
        await reader?.call(source).timeout(const Duration(seconds: 4));
    return revision != null && isAudioRevisionKey(revision) ? revision : null;
  } on Object {
    return null;
  }
}

abstract interface class AudioComparisonReader {
  Future<AudioPcmSignature> read(
      AudioSourceReference source, LibraryScanControl control);
  Future<void> close();
}

final class AudioComparisonService {
  const AudioComparisonService(this._open,
      {this.timeout = const Duration(seconds: 45),
      this.revisionReader,
      this.diagnostics = const NoopDiagnosticsService()});

  final Future<AudioComparisonReader> Function(LibraryScanControl) _open;
  final Duration timeout;
  final AudioRevisionReader? revisionReader;
  final DiagnosticsService diagnostics;

  Future<AudioComparisonResult> compare(Track first, Track second,
          {required LibraryScanControl control}) async =>
      (await compareWithProof(first, second, control: control)).result;

  Future<AudioComparison> compareWithProof(Track first, Track second,
      {required LibraryScanControl control}) async {
    final operation = LibraryScanControl();
    control.addCancellationListener(operation.cancel);
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      operation.cancel();
    });
    AudioComparisonReader? reader;
    try {
      operation.throwIfCancelled();
      final firstSource = first.source;
      final secondSource = second.source;
      final document = audioDocumentIdentity(first.filePath);
      if (first.isMissing ||
          second.isMissing ||
          firstSource == secondSource ||
          (document != null &&
              document == audioDocumentIdentity(second.filePath))) {
        return (result: AudioComparisonResult.unreadable, proof: null);
      }
      final leftRevision = await tryAudioRevision(revisionReader, firstSource);
      final rightRevision =
          await tryAudioRevision(revisionReader, secondSource);
      operation.throwIfCancelled();
      reader = await _open(operation);
      operation.throwIfCancelled();
      final left = await reader.read(firstSource, operation);
      operation.throwIfCancelled();
      final right = await reader.read(secondSource, operation);
      final leftAfter = leftRevision == null
          ? null
          : await tryAudioRevision(revisionReader, firstSource);
      final rightAfter = rightRevision == null
          ? null
          : await tryAudioRevision(revisionReader, secondSource);
      operation.throwIfCancelled();
      if (leftRevision != leftAfter || rightRevision != rightAfter) {
        return (result: AudioComparisonResult.unreadable, proof: null);
      }
      if (left != right) {
        if (reader is AudioFingerprintReader &&
            leftRevision != null &&
            rightRevision != null) {
          final possiblySame = await _compareFingerprints(
              reader as AudioFingerprintReader,
              firstSource,
              secondSource,
              operation);
          operation.throwIfCancelled();
          if (leftRevision !=
                  await tryAudioRevision(revisionReader, firstSource) ||
              rightRevision !=
                  await tryAudioRevision(revisionReader, secondSource)) {
            operation.throwIfCancelled();
            return (result: AudioComparisonResult.unreadable, proof: null);
          }
          operation.throwIfCancelled();
          if (possiblySame) {
            return (
              result: AudioComparisonResult.possiblySameRecording,
              proof: null
            );
          }
        }
        return (result: AudioComparisonResult.different, proof: null);
      }
      final key = '1:${left.sampleRate}:${left.channels}:${left.digest}';
      final proof = leftRevision != null &&
              rightRevision != null &&
              first.id != null &&
              second.id != null &&
              first.id != second.id &&
              isAudioMatchKey(key)
          ? AudioMatchProof._(first, second, key, leftRevision, rightRevision)
          : null;
      return (result: AudioComparisonResult.equal, proof: proof);
    } on Object {
      if (control.isCancellationRequested) {
        return (result: AudioComparisonResult.cancelled, proof: null);
      }
      return (
        result: timedOut
            ? AudioComparisonResult.timedOut
            : AudioComparisonResult.unreadable,
        proof: null,
      );
    } finally {
      timer.cancel();
      control.removeCancellationListener(operation.cancel);
      await reader?.close();
    }
  }

  Future<bool> _compareFingerprints(
      AudioFingerprintReader reader,
      AudioSourceReference first,
      AudioSourceReference second,
      LibraryScanControl control) async {
    final clock = Stopwatch()..start();
    var similarity = RecordingSimilarity.inconclusive;
    try {
      final left = await reader.readFingerprint(first, control);
      control.throwIfCancelled();
      if (left == null) return false;
      final right = await reader.readFingerprint(second, control);
      control.throwIfCancelled();
      if (right == null) return false;
      similarity = await compareRecordingFingerprints(left, right);
      control.throwIfCancelled();
      return similarity == RecordingSimilarity.possible;
    } on LibraryScanCancelled {
      rethrow;
    } on Object {
      return false;
    } finally {
      diagnostics.record(DiagnosticEvent.audioFingerprintFinished, fields: {
        DiagnosticField.elapsedMs: clock.elapsedMilliseconds,
        DiagnosticField.recordingSimilarity:
            control.isCancellationRequested ? 3 : similarity.index,
      });
    }
  }
}

Future<AudioComparisonReader> openDesktopAudioComparison(
    LibraryScanControl control) async {
  final helper = BundledMediaHelper.forCurrentProcess();
  try {
    final qualified =
        await helper.qualify(control: control, includeFingerprint: true);
    return DesktopAudioComparisonReader(qualified.createMetadataBackend(),
        fingerprintPath: qualified.fingerprintPath);
  } finally {
    await helper.close();
  }
}

final class DesktopAudioComparisonReader
    implements AudioComparisonReader, AudioFingerprintReader {
  DesktopAudioComparisonReader(this._backend, {String? fingerprintPath})
      : _fingerprintPath = fingerprintPath;
  final FfmpegAudioMetadataBackend _backend;
  final String? _fingerprintPath;
  final _fingerprints = BoundedMediaProcessRunner(maxStdoutBytes: 128 * 1024);

  @override
  Future<AudioPcmSignature> read(
      AudioSourceReference source, LibraryScanControl control) async {
    if (source is! FileAudioSource) throw _invalidAudio;
    final file = File(source.path);
    final before = await file.stat();
    control.throwIfCancelled();
    if (before.type != FileSystemEntityType.file ||
        before.size <= 0 ||
        before.size > audioComparisonMaxBytes) {
      throw _invalidAudio;
    }
    final info = await _backend.inspectForComparison(file, control);
    final layout = info.channelLayout;
    if (info.sizeBytes != before.size ||
        info.duration > audioComparisonMaxDuration ||
        info.sampleRate > 192000 ||
        info.channels < 1 ||
        info.channels > 2 ||
        (layout != null &&
            layout != 'unknown' &&
            layout != (info.channels == 1 ? 'mono' : 'stereo'))) {
      throw _invalidAudio;
    }
    final digest =
        await _backend.digest(file, info, AudioCopyDigest.decodedPcm, control);
    final after = await file.stat();
    control.throwIfCancelled();
    if (after.type != before.type ||
        after.size != before.size ||
        after.modified != before.modified ||
        after.changed != before.changed) {
      throw _invalidAudio;
    }
    return (
      digest: digest,
      sampleRate: info.sampleRate,
      channels: info.channels
    );
  }

  @override
  Future<AudioFingerprint?> readFingerprint(
      AudioSourceReference source, LibraryScanControl control) async {
    final executable = _fingerprintPath;
    if (executable == null || source is! FileAudioSource) return null;
    final result = await _fingerprints.run(
        executable, [File(source.path).absolute.path], control);
    if (result.exitCode != 0 || result.hadStderr) return null;
    final value = jsonDecode(result.stdout);
    return value is Map<String, dynamic>
        ? AudioFingerprint.decode(value)
        : null;
  }

  @override
  Future<void> close() async {
    await Future.wait([_backend.close(), _fingerprints.close()]);
  }
}

const _invalidAudio =
    AudioValidationException(AudioValidationOutcome.invalidAudio);
