import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'artwork_cache_service.dart';

abstract interface class CustomArtworkService {
  Future<CachedArtwork?> pickCustomArtwork();
}

final class FilePickerCustomArtworkService implements CustomArtworkService {
  const FilePickerCustomArtworkService({
    required ArtworkCacheService artworkCache,
  }) : _artworkCache = artworkCache;

  final ArtworkCacheService _artworkCache;

  @override
  Future<CachedArtwork?> pickCustomArtwork() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose cover image',
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      allowMultiple: false,
      lockParentWindow: true,
    );
    final selectedPath = result?.files.single.path;
    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return null;
    }

    return _artworkCache.saveCustomArtworkFile(File(selectedPath));
  }
}
