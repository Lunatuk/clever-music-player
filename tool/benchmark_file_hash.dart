import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clever_music_player/src/library/file_content_hasher.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';

/// Compile with `dart compile exe tool/benchmark_file_hash.dart -o <output>`.
/// Own synthetic files only; no application database or user music is opened.
Future<void> main() async {
  final directory =
      await Directory.systemTemp.createTemp('cmp_hash_benchmark_');
  try {
    final file = File('${directory.path}/payload.bin');
    final bytes = Uint8List(16 * 1024 * 1024);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = i % 251;
    }
    await file.writeAsBytes(bytes);
    final results = <Map<String, Object>>[];
    String? identity;
    for (final native in [false, true]) {
      final hasher = Sha256FileContentHasher(preferNative: native);
      await hasher.hashFileWithControl(file, control: LibraryScanControl());
      final samples = <int>[];
      for (var run = 0; run < 7; run++) {
        final timer = Stopwatch()..start();
        final fingerprint = await hasher.hashFileWithControl(file,
            control: LibraryScanControl());
        samples.add(timer.elapsedMicroseconds);
        identity ??= fingerprint.storageKey;
        if (identity != fingerprint.storageKey) {
          throw StateError('Hash mismatch.');
        }
      }
      samples.sort();
      final fingerprint = await hasher.hashFile(file);
      results.add({
        'backend': fingerprint.backend.name,
        'fileMiB': 16,
        'medianMs': samples[3] / 1000,
        'p95Ms': samples.last / 1000,
        'medianMiBPerSecond': 16 * 1000000 / samples[3]
      });
    }
    stdout.writeln(jsonEncode({
      'platform': Platform.operatingSystem,
      'results': results,
      'identitiesMatch': true,
      'conditions': 'AOT recommended; fresh synthetic file; warm OS cache likely. '
          'Includes file IO, worker startup and cleanup; not full import throughput.'
    }));
  } finally {
    await directory.delete(recursive: true);
  }
}
