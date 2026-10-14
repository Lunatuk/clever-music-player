import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clever_music_player/src/library/file_content_hasher.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';

/// AOT recommended. Own synthetic files only, likely warm OS cache; no user DB.
Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('cmp_worker_bench_');
  final output = <Map<String, Object>>[];
  try {
    for (final corpus in [(64, 64), (32, 4096), (8, 16384)]) {
      final (count, kib) = corpus;
      final directory = await Directory('${root.path}/$kib').create();
      final files = <File>[];
      final buffer = Uint8List(64 * 1024);
      for (var i = 0; i < buffer.length; i++) {
        buffer[i] = i % 251;
      }
      for (var i = 0; i < count; i++) {
        final file = File('${directory.path}/$i.bin');
        final writer = await file.open(mode: FileMode.write);
        try {
          for (var written = 0; written < kib; written += 64) {
            await writer.writeFrom(buffer);
          }
        } finally {
          await writer.close();
        }
        files.add(file);
      }
      final identities = <String, String>{};
      for (final mode in ['one-shot-64', 'session-64', 'session-256']) {
        final samples = <Map<String, num>>[];
        for (var run = 0; run < 3; run++) {
          final session = mode == 'one-shot-64'
              ? null
              : Sha256HashSession(
                  bufferSize: (mode == 'session-64' ? 64 : 256) * 1024);
          final hasher = session ?? const Sha256FileContentHasher();
          final timer = Stopwatch()..start();
          var io = 0,
              compute = 0,
              worker = 0,
              overhead = 0,
              startup = 0,
              starts = 0;
          try {
            for (final file in files) {
              final result = await hasher.hashFileWithControl(file,
                  control: LibraryScanControl());
              final previous =
                  identities.putIfAbsent(file.path, () => result.storageKey);
              if (previous != result.storageKey) {
                throw StateError('Identity mismatch');
              }
              io += result.timings.ioUs;
              compute += result.timings.digestUs;
              worker += result.timings.workerUs;
              overhead += result.timings.roundTripUs;
              startup += result.timings.startupUs;
              starts += result.timings.workerStarts;
            }
          } finally {
            await session?.close();
          }
          samples.add({
            'totalMs': timer.elapsedMicroseconds / 1000,
            'ioMs': io / 1000,
            'computeMs': compute / 1000,
            'workerMs': worker / 1000,
            'overheadMs': overhead / 1000,
            'startupMs': startup / 1000,
            'workerStarts': starts
          });
        }
        samples.sort((a, b) => a['totalMs']!.compareTo(b['totalMs']!));
        output.add({
          'mode': mode,
          'files': count,
          'fileKiB': kib,
          'median': samples[1],
          'samplesMs': samples.map((s) => s['totalMs']).toList()
        });
      }
    }
    stdout.writeln(jsonEncode({
      'conditions':
          'AOT; freshly generated temporary data; likely warm OS cache; hashing only',
      'results': output
    }));
  } finally {
    await root.delete(recursive: true);
  }
}
