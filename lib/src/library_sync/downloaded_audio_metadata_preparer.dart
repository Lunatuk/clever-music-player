import 'dart:async';
import 'dart:io';

import '../domain/models/audio_source_reference.dart';
import '../library/file_content_hasher.dart';
import '../library/library_scan_control.dart';
import 'downloaded_audio_metadata.dart';
import 'downloaded_audio_validation.dart';
import 'downloaded_audio_validator.dart';

/// Preparation of an exclusively owned downloaded staging source, never an
/// in-place metadata editor. Only the returned validated file may be published.
final class DownloadedAudioMetadataPreparer {
  DownloadedAudioMetadataPreparer(
      {required AudioMetadataBackend backend,
      FileContentHashSession? hashSession,
      Directory? temporaryParent,
      DateTime Function()? clock,
      Duration timeout = const Duration(minutes: 10)})
      : _backend = backend,
        _hash = hashSession ?? const Sha256FileContentHasher().openSession(),
        _temporaryParent = temporaryParent ?? Directory.systemTemp,
        _timeout = timeout {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 30)) {
      throw ArgumentError.value(timeout);
    }
    _validator = DownloadedAudioValidator(
        backend: backend, hashSession: _hash, clock: clock, timeout: timeout);
  }
  final AudioMetadataBackend _backend;
  final FileContentHashSession _hash;
  final Directory _temporaryParent;
  final Duration _timeout;
  late final DownloadedAudioValidator _validator;
  bool _closed = false;
  Completer<void>? _active;
  LibraryScanControl? _control;
  Future<void>? _closing;

  /// A supplied cover replaces the old one; otherwise an existing cover is kept.
  /// The expected tag set replaces provider tags; user metadata edits are not
  /// input to this service. expected.fileSizeBytes describes the source bytes.
  Future<PreparedDownloadedAudio> prepare(
      AudioSourceReference source, DownloadedAudioExpectation expected,
      {EmbeddedCover? cover, LibraryScanControl? control}) {
    final result = _prepare(source, expected, cover: cover, control: control);
    // Shutdown still owns/drains an accepted call if a coordinator forgot await.
    result.ignore();
    return result;
  }

  Future<PreparedDownloadedAudio> _prepare(
      AudioSourceReference source, DownloadedAudioExpectation expected,
      {EmbeddedCover? cover, LibraryScanControl? control}) async {
    if (_closed) throw StateError('Подготовка аудио закрыта.');
    if (_active != null) throw StateError('Аудиофайл уже подготавливается.');
    if (source is! FileAudioSource) {
      throw const AudioValidationException(
          AudioValidationOutcome.unsupportedSource);
    }
    // Bound argv independently of individual tag limits on Windows.
    if (expected.tags.values.fold(0, (n, text) => n + text.length) > 8192) {
      throw const AudioValidationException(
          AudioValidationOutcome.metadataMismatch);
    }
    final done = Completer<void>();
    _active = done;
    final operation = LibraryScanControl();
    _control = operation;
    void cancel() => operation.cancel();
    control?.addCancellationListener(cancel);
    var timedOut = false, delivered = false;
    AudioPreparationTemporary? temporary;
    final timer = Timer(_timeout, () {
      timedOut = true;
      operation.cancel();
    });
    try {
      operation.throwIfCancelled();
      final input = File(source.path).absolute;
      if (await FileSystemEntity.type(input.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const AudioValidationException(AudioValidationOutcome.unreadable);
      }
      if (await input.length() != expected.fileSizeBytes) {
        throw const AudioValidationException(AudioValidationOutcome.changed);
      }
      final before = await _hash.hashFileWithControl(input, control: operation);
      operation.throwIfCancelled();
      if (before.sizeBytes != expected.fileSizeBytes) {
        throw const AudioValidationException(AudioValidationOutcome.changed);
      }
      final original = await _backend.inspect(input, operation);
      operation.throwIfCancelled();
      if (original.sizeBytes != before.sizeBytes ||
          original.container != expected.container ||
          original.codec != expected.codec) {
        throw const AudioValidationException(
            AudioValidationOutcome.encodingMismatch);
      }
      if (cover == null &&
          original.coverStreamIndex == null &&
          expected.requireCover) {
        throw const AudioValidationException(
            AudioValidationOutcome.coverMissing);
      }
      final packets =
          await _digest(input, original, AudioCopyDigest.packets, operation);
      final pcm =
          await _digest(input, original, AudioCopyDigest.decodedPcm, operation);
      temporary = await AudioPreparationTemporary.create(_temporaryParent);
      operation.throwIfCancelled();
      final String? expectedCoverHash;
      if (cover != null) {
        await temporary.cover.create(exclusive: true);
        await temporary.cover.writeAsBytes(cover.bytes, flush: true);
        expectedCoverHash = (await _hash.hashFileWithControl(temporary.cover,
                control: operation))
            .digest;
      } else if (original.coverStreamIndex != null) {
        expectedCoverHash =
            await _digest(input, original, AudioCopyDigest.cover, operation);
      } else {
        expectedCoverHash = null;
      }
      // -y can only replace this reserved file in our freshly created directory.
      await temporary.audio.create(exclusive: true);
      await _backend.writeMetadata(
          input, temporary.audio, original, expected, operation,
          cover: cover == null ? null : temporary.cover,
          coverFormat: cover?.format);
      operation.throwIfCancelled();
      if (await FileSystemEntity.type(temporary.audio.path,
              followLinks: false) !=
          FileSystemEntityType.file) {
        throw const AudioValidationException(AudioValidationOutcome.unreadable);
      }
      final size = await temporary.audio.length();
      if (size <= 0 || size > 8 * 1024 * 1024 * 1024) {
        throw const AudioValidationException(
            AudioValidationOutcome.invalidAudio);
      }
      final result = await _validator.validate(
          FileAudioSource(temporary.audio.path),
          DownloadedAudioExpectation(
              quality: expected.quality,
              container: expected.container,
              codec: expected.codec,
              fileSizeBytes: size,
              duration: expected.duration,
              tags: expected.tags,
              minimumBitRate: expected.minimumBitRate,
              minimumSampleRate: expected.minimumSampleRate,
              minimumBitDepth: expected.minimumBitDepth,
              requireCover: expected.requireCover || expectedCoverHash != null,
              durationTolerance: expected.durationTolerance),
          control: operation);
      operation.throwIfCancelled();
      if (result.outcome != AudioValidationOutcome.verified) {
        throw AudioValidationException(result.outcome);
      }
      final prepared = result.inspection!;
      if (original.sampleRate != prepared.sampleRate ||
          original.channels != prepared.channels ||
          original.bitDepth != prepared.bitDepth ||
          await _digest(temporary.audio, prepared, AudioCopyDigest.packets,
                  operation) !=
              packets ||
          await _digest(temporary.audio, prepared, AudioCopyDigest.decodedPcm,
                  operation) !=
              pcm) {
        throw const AudioValidationException(AudioValidationOutcome.changed);
      }
      if (expectedCoverHash != null &&
          await _digest(temporary.audio, prepared, AudioCopyDigest.cover,
                  operation) !=
              expectedCoverHash) {
        throw const AudioValidationException(
            AudioValidationOutcome.invalidCover);
      }
      if (expectedCoverHash == null && prepared.coverStreamIndex != null) {
        throw const AudioValidationException(
            AudioValidationOutcome.invalidCover);
      }
      final after = await _hash.hashFileWithControl(input, control: operation);
      if (!_same(before, after)) {
        throw const AudioValidationException(AudioValidationOutcome.changed);
      }
      // Backend processes after validation also read output. Recheck the full
      // file so the delivered evidence describes its final bytes, not an earlier
      // intermediate state from the validator.
      final finalBytes =
          await _hash.hashFileWithControl(temporary.audio, control: operation);
      operation.throwIfCancelled();
      if (finalBytes.digest != result.verification!.contentHash ||
          finalBytes.sizeBytes != result.verification!.fileSizeBytes) {
        throw const AudioValidationException(AudioValidationOutcome.changed);
      }
      final ready = PreparedDownloadedAudio.fromValidation(temporary, result);
      delivered = true;
      return ready;
    } on LibraryScanCancelled {
      throw AudioValidationException(timedOut
          ? AudioValidationOutcome.timedOut
          : AudioValidationOutcome.cancelled);
    } on FileContentChangedException {
      throw const AudioValidationException(AudioValidationOutcome.changed);
    } on AudioValidationException {
      if (operation.isCancellationRequested) {
        throw AudioValidationException(timedOut
            ? AudioValidationOutcome.timedOut
            : AudioValidationOutcome.cancelled);
      }
      rethrow;
    } on Object {
      throw AudioValidationException(operation.isCancellationRequested
          ? timedOut
              ? AudioValidationOutcome.timedOut
              : AudioValidationOutcome.cancelled
          : AudioValidationOutcome.unreadable);
    } finally {
      timer.cancel();
      control?.removeCancellationListener(cancel);
      try {
        if (!delivered) await temporary?.close();
      } finally {
        _control = null;
        _active = null;
        done.complete();
      }
    }
  }

  Future<String> _digest(File file, DownloadedAudioInspection info,
      AudioCopyDigest mode, LibraryScanControl control) async {
    control.throwIfCancelled();
    final digest = await _backend.digest(file, info, mode, control);
    control.throwIfCancelled();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const AudioValidationException(AudioValidationOutcome.unreadable);
    }
    return digest;
  }

  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _close(_active?.future);
  }

  Future<void> _close(Future<void>? active) async {
    await active;
    await _validator
        .close(); // Owns the shared hash session and backend/runner.
  }
}

bool _same(FileContentFingerprint left, FileContentFingerprint right) =>
    left.digest == right.digest &&
    left.sizeBytes == right.sizeBytes &&
    left.modifiedAt == right.modifiedAt &&
    left.changedAt == right.changedAt;
