import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WaveMode storage keys round-trip', () {
    for (final mode in WaveMode.values) {
      expect(WaveMode.fromStorageKey(mode.storageKey), mode);
    }
  });

  test('Track displayTitle falls back to file name', () {
    final now = DateTime(2026);
    final track = Track(
      filePath: r'C:\Music\Library\track-one.flac',
      addedAt: now,
      updatedAt: now,
    );

    expect(track.displayTitle, 'track-one.flac');
  });
}
