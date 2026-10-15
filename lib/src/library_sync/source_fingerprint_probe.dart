import 'dart:io';

import '../domain/models/audio_source_reference.dart';
import '../library/file_content_hasher.dart';
import '../library/library_scan_control.dart';

enum SourceFingerprintStatus {
  fingerprinted,
  changed,
  missing,
  accessDenied,
  unreadable,
  cancelled,
}

final class SourceFingerprintResult {
  factory SourceFingerprintResult.fingerprinted(int sizeBytes, String digest) {
    if (sizeBytes <= 0 ||
        RegExp(r'^[0-9a-f]{64}$').stringMatch(digest) != digest) {
      throw const FormatException('Некорректный результат проверки файла.');
    }
    return SourceFingerprintResult._(
        SourceFingerprintStatus.fingerprinted, sizeBytes, digest);
  }

  factory SourceFingerprintResult.failure(SourceFingerprintStatus status) {
    if (status == SourceFingerprintStatus.fingerprinted) {
      throw ArgumentError('Требуется размер и SHA-256.');
    }
    return SourceFingerprintResult._(status, null, null);
  }
  const SourceFingerprintResult._(this.status, this.sizeBytes, this.digest);
  final SourceFingerprintStatus status;
  final int? sizeBytes;
  final String? digest;
}

/// Reads all bytes with bounded memory. No audio decoding or publication here.
abstract interface class SourceFingerprintProbe {
  Future<SourceFingerprintResult> fingerprint(AudioSourceReference source,
      {required int expectedSize, required LibraryScanControl control});
  Future<void> close();
}

final class FileSourceFingerprintProbe implements SourceFingerprintProbe {
  FileSourceFingerprintProbe({FileContentHashSession? session})
      : _session = session ?? const Sha256FileContentHasher().openSession();
  final FileContentHashSession _session;
  bool _closed = false;

  @override
  Future<SourceFingerprintResult> fingerprint(AudioSourceReference source,
      {required int expectedSize, required LibraryScanControl control}) async {
    if (_closed) throw StateError('Проверка файлов закрыта.');
    if (expectedSize <= 0) throw ArgumentError.value(expectedSize);
    if (source is! FileAudioSource) {
      return SourceFingerprintResult.failure(
          SourceFingerprintStatus.unreadable);
    }
    try {
      control.throwIfCancelled();
      final hash = await _session.hashFileWithControl(File(source.path),
          control: control);
      if (hash.sizeBytes != expectedSize) {
        return SourceFingerprintResult.failure(SourceFingerprintStatus.changed);
      }
      return SourceFingerprintResult.fingerprinted(hash.sizeBytes, hash.digest);
    } on LibraryScanCancelled {
      return SourceFingerprintResult.failure(SourceFingerprintStatus.cancelled);
    } on FileContentChangedException {
      return SourceFingerprintResult.failure(SourceFingerprintStatus.changed);
    } on FileSystemException catch (error) {
      // stat() can mask both missing files and denied access as notFound.
      // Recover the structured OS error with a read-only open; never parse text.
      var code = error.osError?.errorCode;
      if (code == null) {
        try {
          final input = await File(source.path).open();
          await input.close();
        } on FileSystemException catch (openError) {
          code = openError.osError?.errorCode;
        }
      }
      final missing = Platform.isWindows ? [2, 3] : [2, 20];
      final denied = Platform.isWindows ? [5] : [1, 13];
      return SourceFingerprintResult.failure(missing.contains(code)
          ? SourceFingerprintStatus.missing
          : denied.contains(code)
              ? SourceFingerprintStatus.accessDenied
              : SourceFingerprintStatus.unreadable);
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    return _session.close();
  }
}

final class RoutedSourceFingerprintProbe implements SourceFingerprintProbe {
  RoutedSourceFingerprintProbe({required this.files, required this.documents});
  final SourceFingerprintProbe files, documents;
  bool _closed = false;
  Future<void>? _closing;

  @override
  Future<SourceFingerprintResult> fingerprint(AudioSourceReference source,
      {required int expectedSize, required LibraryScanControl control}) {
    if (_closed) throw StateError('Проверка файлов закрыта.');
    return (source is FileAudioSource ? files : documents)
        .fingerprint(source, expectedSize: expectedSize, control: control);
  }

  @override
  Future<void> close() {
    _closed = true;
    return _closing ??=
        Future.wait([files.close(), documents.close()]).then((_) {});
  }
}
