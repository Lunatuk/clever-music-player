import 'dart:io';
import 'dart:typed_data';

import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/metadata_enrichment.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  final bytes = Uint8List.fromList(
      [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
  final artwork = EmbeddedArtwork(bytes: bytes, mimeType: 'image/png');
  setUp(() async =>
      root = await Directory.systemTemp.createTemp('cmp_artwork_lookup_'));
  tearDown(() => root.delete(recursive: true));

  test(
      'large cache is reused without enumerating the directory or rewriting bytes',
      () async {
    final guarded = _NoListingDirectory(root);
    final cache = AppSupportArtworkCacheService(artworkDirectory: guarded);
    final first = (await cache.saveEmbeddedArtwork(artwork))!;
    for (var i = 0; i < 100; i++) {
      await File(p.join(root.path, 'unrelated-$i.png')).writeAsBytes([i]);
    }
    final before = await File(first.path).stat();
    final second = (await cache.saveEmbeddedArtwork(artwork))!;
    expect(second.path, first.path);
    expect(second.hash, sha256.convert(bytes).toString());
    expect((await File(second.path).stat()).modified, before.modified);
    expect(await File(second.path).readAsBytes(), bytes);
    expect(guarded.creates, 1);
  });

  for (final extension in [
    'jpg',
    'jpeg',
    'webp',
    'gif',
    'tif',
    'tiff',
    'bmp',
    'bin'
  ]) {
    test('existing $extension alias is retained without a second cover file',
        () async {
      final hash = sha256.convert(bytes).toString();
      final existing =
          await File(p.join(root.path, '$hash.$extension')).writeAsBytes(bytes);
      final cache = AppSupportArtworkCacheService(
          artworkDirectory: _NoListingDirectory(root));
      final value = (await cache.saveEmbeddedArtwork(artwork))!;
      expect(value.path, existing.path);
      expect(await File(p.join(root.path, '$hash.png')).exists(), isFalse);
    });
  }

  test(
      'externally removed cover is recreated and a different hash remains separate',
      () async {
    final cache = AppSupportArtworkCacheService(
        artworkDirectory: _NoListingDirectory(root));
    final first = (await cache.saveEmbeddedArtwork(artwork))!;
    await File(first.path).delete();
    final replacement = (await cache.saveEmbeddedArtwork(artwork))!;
    expect(replacement.path, first.path);
    expect(await File(replacement.path).readAsBytes(), bytes);
    final other = (await cache.saveEmbeddedArtwork(EmbeddedArtwork(
        bytes: Uint8List.fromList([...bytes, 4]), mimeType: 'image/png')))!;
    expect(other.path, isNot(first.path));
    expect(await File(first.path).readAsBytes(), bytes);
  });

  test('embedded and custom cache directories keep separate references',
      () async {
    final embedded = Directory(p.join(root.path, 'embedded'));
    final custom = Directory(p.join(root.path, 'custom'));
    final source =
        await File(p.join(root.path, 'source.png')).writeAsBytes(bytes);
    final cache = AppSupportArtworkCacheService(
        artworkDirectory: embedded, customArtworkDirectory: custom);
    final first = (await cache.saveEmbeddedArtwork(artwork))!;
    final second = await cache.saveCustomArtworkFile(source);
    expect(first.hash, second.hash);
    expect(first.path, isNot(second.path));
    expect(await source.readAsBytes(), bytes);
  });
}

/// Any accidental list/listSync call fails, independent of wall-clock timings.
final class _NoListingDirectory implements Directory {
  _NoListingDirectory(this.inner);
  final Directory inner;
  var creates = 0;
  @override
  String get path => inner.path;
  @override
  Future<Directory> create({bool recursive = false}) {
    creates++;
    return inner.create(recursive: recursive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
      'Unexpected directory operation: ${invocation.memberName}');
}
