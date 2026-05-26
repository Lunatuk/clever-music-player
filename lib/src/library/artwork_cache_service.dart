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

  Future<CachedArtwork> saveCustomArtworkFile(File imageFile);
}

final class NoopArtworkCacheService implements ArtworkCacheService {
  const NoopArtworkCacheService();

  @override
  Future<CachedArtwork?> saveEmbeddedArtwork(EmbeddedArtwork? artwork) async {
    return null;
  }

  @override
  Future<CachedArtwork> saveCustomArtworkFile(File imageFile) {
    throw UnsupportedError('Хранилище пользовательских обложек не настроено.');
  }
}

final class AppSupportArtworkCacheService implements ArtworkCacheService {
  // TODO: Add unused artwork garbage collection after reference tracking is
  // available for embedded and custom artwork files.
  AppSupportArtworkCacheService({
    Directory? artworkDirectory,
    Directory? customArtworkDirectory,
    Future<Directory> Function()? supportDirectoryProvider,
  })  : _artworkDirectory = artworkDirectory,
        _customArtworkDirectory = customArtworkDirectory,
        _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory;

  final Directory? _artworkDirectory;
  final Directory? _customArtworkDirectory;
  final Future<Directory> Function() _supportDirectoryProvider;

  @override
  Future<CachedArtwork?> saveEmbeddedArtwork(EmbeddedArtwork? artwork) async {
    if (artwork == null || artwork.bytes.isEmpty) {
      return null;
    }

    final bytes = artwork.bytes;
    final mimeType = _normalizeMimeType(artwork.mimeType);
    return _saveArtworkBytes(
      directory: await _resolveEmbeddedArtworkDirectory(),
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  @override
  Future<CachedArtwork> saveCustomArtworkFile(File imageFile) async {
    if (!await imageFile.exists()) {
      throw StateError('Выбранный файл обложки не существует.');
    }

    final bytes = await imageFile.readAsBytes();
    if (bytes.isEmpty) {
      throw FormatException('Выбранный файл обложки пуст.');
    }

    final mimeType = _supportedCustomMimeType(bytes);
    if (mimeType == null) {
      throw FormatException(
        'Выбранный файл обложки не является поддерживаемым изображением. '
        'Выберите PNG, JPEG или WebP.',
      );
    }

    return _saveArtworkBytes(
      directory: await _resolveCustomArtworkDirectory(),
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  Future<CachedArtwork> _saveArtworkBytes({
    required Directory directory,
    required Uint8List bytes,
    required String? mimeType,
  }) async {
    await directory.create(recursive: true);

    final hash = sha256.convert(bytes).toString();
    final existing = _findExistingArtworkFile(directory, hash);
    final resolvedMimeType = mimeType ?? _mimeTypeFromMagicBytes(bytes);
    if (existing != null) {
      return CachedArtwork(
        path: existing.path,
        hash: hash,
        mimeType: resolvedMimeType ??
            _mimeTypeFromExtension(p.extension(existing.path)),
      );
    }

    final extension = _extensionFor(mimeType: resolvedMimeType, bytes: bytes);
    final file = File(p.join(directory.path, '$hash.$extension'));
    await file.writeAsBytes(bytes, flush: true);

    return CachedArtwork(
      path: file.path,
      hash: hash,
      mimeType: resolvedMimeType,
    );
  }

  Future<Directory> _resolveEmbeddedArtworkDirectory() async {
    final configuredDirectory = _artworkDirectory;
    if (configuredDirectory != null) {
      return configuredDirectory;
    }

    final supportDirectory = await _supportDirectoryProvider();
    return Directory(
      p.join(supportDirectory.path, 'CleverMusicPlayer', 'artwork'),
    );
  }

  Future<Directory> _resolveCustomArtworkDirectory() async {
    final configuredDirectory = _customArtworkDirectory;
    if (configuredDirectory != null) {
      return configuredDirectory;
    }

    final supportDirectory = await _supportDirectoryProvider();
    return Directory(
      p.join(supportDirectory.path, 'CleverMusicPlayer', 'custom_artwork'),
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
  return switch (_mimeTypeFromMagicBytes(bytes)) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    _ => null,
  };
}

String? _mimeTypeFromMagicBytes(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    return 'image/jpeg';
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
    return 'image/png';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return 'image/gif';
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
    return 'image/webp';
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

String? _supportedCustomMimeType(Uint8List bytes) {
  final mimeType = _mimeTypeFromMagicBytes(bytes);
  return switch (mimeType) {
    'image/jpeg' || 'image/png' || 'image/webp' => mimeType,
    _ => null,
  };
}
