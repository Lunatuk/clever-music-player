import 'dart:io';

import 'package:path/path.dart' as p;

final class AudioMetadata {
  const AudioMetadata({
    required this.filePath,
    required this.fileSizeBytes,
    required this.modifiedAt,
    required this.title,
    required this.codec,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.duration,
    this.trackNumber,
    this.discNumber,
    this.year,
  });

  final String filePath;
  final int fileSizeBytes;
  final DateTime modifiedAt;
  final String title;
  final String codec;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final Duration? duration;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
}

abstract interface class MetadataReaderService {
  Future<AudioMetadata> read(File file);
}

final class FallbackMetadataReaderService implements MetadataReaderService {
  const FallbackMetadataReaderService();

  @override
  Future<AudioMetadata> read(File file) async {
    final stat = await file.stat();
    final normalizedPath = p.normalize(file.absolute.path);
    final extension = p.extension(file.path).replaceFirst('.', '').toLowerCase();
    final title = p.basenameWithoutExtension(file.path).trim();

    return AudioMetadata(
      filePath: normalizedPath,
      fileSizeBytes: stat.size,
      modifiedAt: stat.modified,
      title: title.isEmpty ? p.basename(file.path) : title,
      codec: extension,
    );
  }
}
