import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('custom cover storage copies image into app-local cache', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_custom_artwork_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final sourceFile = File(p.join(tempDirectory.path, 'source.png'));
    await sourceFile.writeAsBytes(_validPngBytes);
    final customArtworkDirectory = Directory(
      p.join(tempDirectory.path, 'CleverMusicPlayer', 'custom_artwork'),
    );
    final cache = AppSupportArtworkCacheService(
      customArtworkDirectory: customArtworkDirectory,
    );

    final artwork = await cache.saveCustomArtworkFile(sourceFile);

    expect(artwork.path, startsWith(customArtworkDirectory.path));
    expect(artwork.path, isNot(sourceFile.path));
    expect(artwork.hash, hasLength(64));
    expect(artwork.mimeType, 'image/png');
    expect(await File(artwork.path).readAsBytes(), _validPngBytes);
    expect(await sourceFile.readAsBytes(), _validPngBytes);
  });

  test('custom cover storage reuses identical selected image bytes', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_custom_artwork_reuse_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final firstFile = File(p.join(tempDirectory.path, 'first.png'));
    final secondFile = File(p.join(tempDirectory.path, 'second.png'));
    await firstFile.writeAsBytes(_validPngBytes);
    await secondFile.writeAsBytes(_validPngBytes);
    final customArtworkDirectory = Directory(
      p.join(tempDirectory.path, 'custom_artwork'),
    );
    final cache = AppSupportArtworkCacheService(
      customArtworkDirectory: customArtworkDirectory,
    );

    final first = await cache.saveCustomArtworkFile(firstFile);
    final second = await cache.saveCustomArtworkFile(secondFile);

    expect(second.hash, first.hash);
    expect(second.path, first.path);
    expect(customArtworkDirectory.listSync().whereType<File>(), hasLength(1));
  });

  test('setting custom cover updates track persistence fields', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repositories = DriftRepositories(database);
    final now = DateTime(2026, 5);
    final trackId = await repositories.tracks.upsertTrack(
      Track(
        filePath: '/music/track.mp3',
        title: 'Track',
        artworkPath: '/app/artwork/embedded.png',
        artworkHash: 'embedded-hash',
        artworkMimeType: 'image/png',
        addedAt: now,
        updatedAt: now,
      ),
    );

    await repositories.tracks.updateCustomArtwork(
      trackId: trackId,
      path: '/app/custom_artwork/custom.png',
      hash: 'custom-hash',
      mimeType: 'image/png',
      updatedAt: DateTime(2026, 5, 2),
    );

    final track = await repositories.tracks.findById(trackId);
    expect(track?.customArtworkPath, '/app/custom_artwork/custom.png');
    expect(track?.customArtworkHash, 'custom-hash');
    expect(track?.customArtworkMimeType, 'image/png');
    expect(track?.artworkPath, '/app/artwork/embedded.png');
    expect(track?.artworkHash, 'embedded-hash');
  });

  test('custom cover storage rejects invalid image bytes', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'clever_music_invalid_custom_artwork_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final sourceFile = File(p.join(tempDirectory.path, 'not-image.png'));
    await sourceFile.writeAsBytes([1, 2, 3, 4]);
    final cache = AppSupportArtworkCacheService(
      customArtworkDirectory: Directory(p.join(tempDirectory.path, 'covers')),
    );

    expect(
      () => cache.saveCustomArtworkFile(sourceFile),
      throwsA(isA<FormatException>()),
    );
  });
}

final _validPngBytes = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x04,
  0x00,
  0x00,
  0x00,
  0xb5,
  0x1c,
  0x0c,
  0x02,
  0x00,
  0x00,
  0x00,
  0x0b,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0xda,
  0x63,
  0xfc,
  0xff,
  0x1f,
  0x00,
  0x03,
  0x03,
  0x02,
  0x00,
  0xef,
  0xbf,
  0xa7,
  0xdb,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];
