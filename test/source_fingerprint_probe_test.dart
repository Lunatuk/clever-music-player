import 'dart:io';

import 'package:clever_music_player/src/domain/models/audio_source_reference.dart';
import 'package:clever_music_player/src/library/file_content_hasher.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/asset_check_fixture.dart';

void main() {
  test(
      'fingerprint protocol accepts only positive length and canonical full digest',
      () {
    expect(SourceFingerprintResult.fingerprinted(3, abcHash).digest, abcHash);
    for (final hash in ['', 'a' * 63, 'A' * 64, 'g' * 64, '$abcHash\n']) {
      expect(() => SourceFingerprintResult.fingerprinted(3, hash),
          throwsFormatException);
    }
    expect(() => SourceFingerprintResult.fingerprinted(0, abcHash),
        throwsFormatException);
    expect(
        () => SourceFingerprintResult.failure(
            SourceFingerprintStatus.fingerprinted),
        throwsArgumentError);
  });
  test('streaming file read handles multiple buffers and session reuse',
      () async {
    final temp = await Directory.systemTemp.createTemp('cmp_probe_');
    final probe = FileSourceFingerprintProbe();
    try {
      final file = await File('${temp.path}/large.bin')
          .writeAsBytes(List.generate(700000, (index) => index % 251));
      final expected = await const Sha256FileContentHasher(preferNative: false)
          .hashFile(file);
      for (var i = 0; i < 2; i++) {
        final result = await probe.fingerprint(FileAudioSource(file.path),
            expectedSize: 700000, control: LibraryScanControl());
        expect(result.digest, expected.digest);
        expect(result.sizeBytes, 700000);
      }
      final result = await probe.fingerprint(FileAudioSource(file.path),
          expectedSize: 3, control: LibraryScanControl());
      expect(result.status, SourceFingerprintStatus.changed);
    } finally {
      await probe.close();
      await temp.delete(recursive: true);
    }
  });
  test('content URI on desktop is unsupported without changing resource state',
      () async {
    final probe = FileSourceFingerprintProbe();
    final result = await probe.fingerprint(
        ContentUriAudioSource('content://test/audio/1'),
        expectedSize: 3,
        control: LibraryScanControl());
    expect(result.status, SourceFingerprintStatus.unreadable);
    await probe.close();
    await expectLater(
        probe.fingerprint(FileAudioSource('/test'),
            expectedSize: 3, control: LibraryScanControl()),
        throwsStateError);
  });
  for (final error in [
    FileContentChangedException('/test'),
    const LibraryScanCancelled(),
    FileSystemException('sharing/busy', '/test', const OSError('', 32)),
    FileSystemException(
        'denied', '/test', OSError('', Platform.isWindows ? 5 : 13)),
    FileSystemException('missing', '/test', const OSError('', 2)),
  ]) {
    test(
        'structured error maps without inspecting message: ${error.runtimeType}/$error',
        () async {
      final session = _Session(error);
      final probe = FileSourceFingerprintProbe(session: session);
      final result = await probe.fingerprint(FileAudioSource('/test'),
          expectedSize: 3, control: LibraryScanControl());
      final expected = error is FileContentChangedException
          ? SourceFingerprintStatus.changed
          : error is LibraryScanCancelled
              ? SourceFingerprintStatus.cancelled
              : (error as FileSystemException).osError!.errorCode == 2
                  ? SourceFingerprintStatus.missing
                  : error.osError!.errorCode == 32
                      ? SourceFingerprintStatus.unreadable
                      : SourceFingerprintStatus.accessDenied;
      expect(result.status, expected);
      await probe.close();
      expect(session.closed, isTrue);
    });
  }
  test('ambiguous stat error with readable file stays unreadable', () async {
    final temp = await Directory.systemTemp.createTemp('cmp_probe_');
    final probe = FileSourceFingerprintProbe(
        session: _Session(const FileSystemException('stat')));
    try {
      final file = await File('${temp.path}/track').writeAsString('abc');
      expect(
          (await probe.fingerprint(FileAudioSource(file.path),
                  expectedSize: 3, control: LibraryScanControl()))
              .status,
          SourceFingerprintStatus.unreadable);
    } finally {
      await probe.close();
      await temp.delete(recursive: true);
    }
  });
}

final class _Session implements FileContentHashSession {
  _Session(this.error);
  final Object error;
  bool closed = false;
  @override
  Future<FileContentFingerprint> hashFileWithControl(File file,
          {required LibraryScanControl control,
          void Function(FileHashProgress)? onProgress}) =>
      Future.error(error);
  @override
  Future<FileContentFingerprint> hashFile(File file) => Future.error(error);
  @override
  Future<void> close() async => closed = true;
}
