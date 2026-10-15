import 'dart:async';
import 'dart:io';

import '../domain/models/audio_source_reference.dart';
import '../domain/models/downloaded_asset.dart';
import '../library/file_content_hasher.dart';
import '../library/library_scan_control.dart';
import 'downloaded_audio_validation.dart';

abstract interface class AudioValidationBackend {
  Future<DownloadedAudioInspection> inspect(
      File file, LibraryScanControl control);
  Future<Duration> decodeAudio(File file, DownloadedAudioInspection inspection,
      LibraryScanControl control);
  Future<void> decodeCover(File file, DownloadedAudioInspection inspection,
      LibraryScanControl control);
  Future<void> close();
}

/// Read-only validation of a completed staging file, after metadata/cover writes.
/// Does not register a track, publish a file, or turn a job into completed.
final class DownloadedAudioValidator {
  DownloadedAudioValidator(
      {required AudioValidationBackend backend,
      FileContentHashSession? hashSession,
      DateTime Function()? clock,
      Duration timeout = const Duration(minutes: 10)})
      : _backend = backend,
        _hashSession =
            hashSession ?? const Sha256FileContentHasher().openSession(),
        _clock = clock ?? DateTime.now,
        _timeout = timeout {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 30)) {
      throw ArgumentError.value(timeout);
    }
  }
  final AudioValidationBackend _backend;
  final FileContentHashSession _hashSession;
  final DateTime Function() _clock;
  final Duration _timeout;
  bool _closed = false;
  LibraryScanControl? _activeControl;
  Completer<void>? _activeDone;
  Future<void>? _closing;

  Future<AudioValidationResult> validate(
      AudioSourceReference source, DownloadedAudioExpectation expected,
      {LibraryScanControl? control}) async {
    if (_closed) throw StateError('Проверка аудио закрыта.');
    if (_activeDone != null) throw StateError('Аудиофайл уже проверяется.');
    if (source is! FileAudioSource) {
      return AudioValidationResult.failure(
          AudioValidationOutcome.unsupportedSource);
    }
    final done = Completer<void>();
    _activeDone = done;
    final operation = LibraryScanControl();
    _activeControl = operation;
    void cancel() => operation.cancel();
    control?.addCancellationListener(cancel);
    var timedOut = false;
    final timer = Timer(_timeout, () {
      timedOut = true;
      operation.cancel();
    });
    try {
      operation.throwIfCancelled();
      final file = File(source.path);
      final stat = await file.stat();
      operation.throwIfCancelled();
      if (stat.type != FileSystemEntityType.file) {
        return AudioValidationResult.failure(AudioValidationOutcome.unreadable);
      }
      if (stat.size != expected.fileSizeBytes) {
        return AudioValidationResult.failure(AudioValidationOutcome.changed);
      }
      final before =
          await _hashSession.hashFileWithControl(file, control: operation);
      operation.throwIfCancelled();
      if (before.sizeBytes != expected.fileSizeBytes) {
        return AudioValidationResult.failure(AudioValidationOutcome.changed);
      }
      final info = await _backend.inspect(file, operation);
      operation.throwIfCancelled();
      if (info.sizeBytes != before.sizeBytes) {
        return AudioValidationResult.failure(AudioValidationOutcome.changed);
      }
      if (info.container != expected.container ||
          info.codec != expected.codec ||
          !_minimum(info.bitRate, expected.minimumBitRate) ||
          !_minimum(info.sampleRate, expected.minimumSampleRate) ||
          !_minimum(info.bitDepth, expected.minimumBitDepth)) {
        return AudioValidationResult.failure(
            AudioValidationOutcome.encodingMismatch);
      }
      if (!_near(
          info.duration, expected.duration, expected.durationTolerance)) {
        return AudioValidationResult.failure(
            AudioValidationOutcome.invalidAudio);
      }
      if (expected.tags.entries
          .any((entry) => info.tags[entry.key] != entry.value)) {
        return AudioValidationResult.failure(
            AudioValidationOutcome.metadataMismatch);
      }
      if (expected.requireCover && info.coverStreamIndex == null) {
        return AudioValidationResult.failure(
            AudioValidationOutcome.coverMissing);
      }
      final decoded = await _backend.decodeAudio(file, info, operation);
      operation.throwIfCancelled();
      if (decoded.inMilliseconds <= 0 ||
          !_near(decoded, expected.duration, expected.durationTolerance) ||
          !_near(decoded, info.duration, expected.durationTolerance)) {
        return AudioValidationResult.failure(
            AudioValidationOutcome.invalidAudio);
      }
      if (info.coverStreamIndex != null) {
        await _backend.decodeCover(file, info, operation);
        operation.throwIfCancelled();
      }
      final after =
          await _hashSession.hashFileWithControl(file, control: operation);
      operation.throwIfCancelled();
      if (before.digest != after.digest ||
          before.sizeBytes != after.sizeBytes ||
          before.modifiedAt != after.modifiedAt ||
          before.changedAt != after.changedAt) {
        return AudioValidationResult.failure(AudioValidationOutcome.changed);
      }
      return AudioValidationResult.verified(
          DownloadedAssetVerification(
              actualQuality: expected.quality,
              container: info.container.name,
              codec: info.codec.name,
              fileSizeBytes: after.sizeBytes,
              duration: decoded,
              contentHash: after.digest,
              checkedAt: _clock()),
          info);
    } on LibraryScanCancelled {
      return AudioValidationResult.failure(timedOut
          ? AudioValidationOutcome.timedOut
          : AudioValidationOutcome.cancelled);
    } on FileContentChangedException {
      return AudioValidationResult.failure(AudioValidationOutcome.changed);
    } on AudioValidationException catch (error) {
      return AudioValidationResult.failure(operation.isCancellationRequested
          ? timedOut
              ? AudioValidationOutcome.timedOut
              : AudioValidationOutcome.cancelled
          : error.outcome);
    } on Object {
      return AudioValidationResult.failure(operation.isCancellationRequested
          ? timedOut
              ? AudioValidationOutcome.timedOut
              : AudioValidationOutcome.cancelled
          : AudioValidationOutcome.unreadable);
    } finally {
      timer.cancel();
      control?.removeCancellationListener(cancel);
      _activeDone = null;
      _activeControl = null;
      done.complete();
    }
  }

  Future<void> close() {
    _closed = true;
    _activeControl?.cancel();
    return _closing ??= _close(_activeDone?.future);
  }

  Future<void> _close(Future<void>? active) async {
    await active;
    await Future.wait([
      Future<void>.sync(_hashSession.close),
      Future<void>.sync(_backend.close)
    ]);
  }
}

bool _minimum(int? value, int? minimum) =>
    minimum == null || (value != null && value >= minimum);
bool _near(Duration value, Duration reference, Duration tolerance) =>
    (value - reference).abs() <= tolerance;
