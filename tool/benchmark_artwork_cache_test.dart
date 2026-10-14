import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/metadata_enrichment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('isolated artwork-cache scaling probe; synthetic data only', () async {
    final root =
        await Directory.systemTemp.createTemp('cmp_scan_artwork_probe_');
    try {
      final bytes = Uint8List.fromList(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII='));
      final artwork = EmbeddedArtwork(bytes: bytes, mimeType: 'image/png');
      final cache = AppSupportArtworkCacheService(artworkDirectory: root);
      final existing = (await cache.saveEmbeddedArtwork(artwork))!;
      var filled = 1;
      final data = <Map<String, Object>>[];
      for (final target in [100, 1000, 4000]) {
        for (; filled < target; filled++) {
          File(p.join(root.path,
                  '${filled.toRadixString(16).padLeft(64, '0')}.png'))
              .writeAsBytesSync(bytes);
        }
        for (var i = 0; i < 3; i++) {
          await cache.saveEmbeddedArtwork(artwork);
        }
        final samples = <int>[];
        for (var i = 0; i < 50; i++) {
          final timer = Stopwatch()..start();
          final value = await cache.saveEmbeddedArtwork(artwork);
          timer.stop();
          expect(value!.path, existing.path);
          samples.add(timer.elapsedMicroseconds);
        }
        samples.sort();
        final direct = <int>[];
        for (var i = 0; i < 50; i++) {
          final timer = Stopwatch()..start();
          expect(await File(existing.path).exists(), true);
          timer.stop();
          direct.add(timer.elapsedMicroseconds);
        }
        direct.sort();
        data.add({
          'cachedFiles': target,
          'currentLookupMedianUs': samples[25],
          'currentLookupP95Us': samples[47],
          'directExistsMedianUs': direct[25]
        });
      }
      stdout.writeln('ARTWORK_PROBE ${jsonEncode(data)}');
      expect(await File(existing.path).readAsBytes(), bytes);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
