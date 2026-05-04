import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'metadata_enrichment.dart';

final class CachedArtwork {
  const CachedArtwork({
    required this.path,
    required this.hash,
    this.mimeType,
  });

  final String path;
  final String hash;
  final String? mimeType;
}

abstract interface class ArtworkCacheService {
  Future<CachedArtwork?> saveEmbeddedArtwork(EmbeddedArtwork? artwork);
}

final class NoopArtworkCacheService implements ArtworkCacheService {
  const NoopArtworkCacheService();

  @override
  Future<CachedArtwork?> saveEmbeddedArtwork(EmbeddedArtwork? artwork) async {
    return null;
  }
}

final class AppSupportArtworkCacheService implements ArtworkCacheService {
  // TODO: Add unused artwork garbage collection after library deletion and
  // rescan retention rules are defined.
  AppSupportArtworkCacheService({
    Directory? artworkDirectory,
    Future<Directory> Function()? supportDirectoryProvider,
  })  : _artworkDirectory = artworkDirectory,
        _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory;

  final Directory? _artworkDirectory;
  final Future<Directory> Function() _supportDirectoryProvider;

  @override
  Future<CachedArtwork?> saveEmbeddedArtwork(EmbeddedArtwork? artwork) async {
    if (artwork == null || artwork.bytes.isEmpty) {
      return null;
    }

    final directory = await _resolveArtworkDirectory();
    await directory.create(recursive: true);

    final bytes = artwork.bytes;
    final hash = sha256.convert(bytes).toString();
    final existing = _findExistingArtworkFile(directory, hash);
    final mimeType = _normalizeMimeType(artwork.mimeType);
    if (existing != null) {
      return CachedArtwork(
        path: existing.path,
        hash: hash,
        mimeType:
            mimeType ?? _mimeTypeFromExtension(p.extension(existing.path)),
      );
    }

    final extension = _extensionFor(mimeType: mimeType, bytes: bytes);
    final file = File(p.join(directory.path, '$hash.$extension'));
    await file.writeAsBytes(bytes, flush: true);

    return CachedArtwork(
      path: file.path,
      hash: hash,
      mimeType: mimeType,
    );
  }

  Future<Directory> _resolveArtworkDirectory() async {
    final configuredDirectory = _artworkDirectory;
    if (configuredDirectory != null) {
      return configuredDirectory;
    }

    final supportDirectory = await _supportDirectoryProvider();
    return Directory(
      p.join(supportDirectory.path, 'CleverMusicPlayer', 'artwork'),
    );
  }
}

File? _findExistingArtworkFile(Directory directory, String hash) {
  if (!directory.existsSync()) {
    return null;
  }

  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is File && p.basenameWithoutExtension(entity.path) == hash) {
      return entity;
    }
  }
  return null;
}

String _extensionFor({
  required String? mimeType,
  required Uint8List bytes,
}) {
  return switch (mimeType) {
    'image/jpeg' || 'image/jpg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    'image/tiff' => 'tif',
    'image/bmp' => 'bmp',
    _ => _extensionFromMagicBytes(bytes) ?? 'bin',
  };
}

String? _extensionFromMagicBytes(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    return 'jpg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 'png';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return 'gif';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'webp';
  }
  return null;
}

String? _normalizeMimeType(String? mimeType) {
  final normalized = mimeType?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

String? _mimeTypeFromExtension(String extension) {
  return switch (extension.toLowerCase().replaceFirst('.', '')) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'tif' || 'tiff' => 'image/tiff',
    'bmp' => 'image/bmp',
    _ => null,
  };
}
