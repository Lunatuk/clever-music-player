import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart'
    as audio_reader;
import 'package:path/path.dart' as p;

import '../domain/models/models.dart';
import 'filename_metadata_parser.dart';
import 'metadata_enrichment.dart';

final class AudioMetadata {
  const AudioMetadata({
    required this.filePath,
    required this.fileSizeBytes,
    required this.modifiedAt,
    required this.title,
    required this.codec,
    required this.metadataSource,
    required this.metadataConfidence,
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
  final MetadataSource metadataSource;
  final double metadataConfidence;
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

typedef EmbeddedMetadataReader = Future<EmbeddedAudioMetadata?> Function(
  String filePath,
);

final class AudioMetadataReaderService implements MetadataReaderService {
  const AudioMetadataReaderService({
    EmbeddedMetadataReader? embeddedMetadataReader,
    this.filenameParser = const FilenameMetadataParser(),
  }) : _embeddedMetadataReader = embeddedMetadataReader;

  final EmbeddedMetadataReader? _embeddedMetadataReader;
  final FilenameMetadataParser filenameParser;

  @override
  Future<AudioMetadata> read(File file) async {
    final baseMetadata = await _baseFileMetadata(file);
    EmbeddedAudioMetadata? tagMetadata;

    try {
      final reader = _embeddedMetadataReader ?? _readEmbeddedAudioTags;
      tagMetadata = await reader(baseMetadata.filePath);
    } on Object {
      tagMetadata = null;
    }

    return _mergeFileMetadata(
      baseMetadata: baseMetadata,
      tagMetadata: tagMetadata,
      filenameParser: filenameParser,
    );
  }
}

final class FallbackMetadataReaderService implements MetadataReaderService {
  const FallbackMetadataReaderService({
    this.filenameParser = const FilenameMetadataParser(),
  });

  final FilenameMetadataParser filenameParser;

  @override
  Future<AudioMetadata> read(File file) async {
    return _mergeFileMetadata(
      baseMetadata: await _baseFileMetadata(file),
      tagMetadata: null,
      filenameParser: filenameParser,
    );
  }
}

final class _BaseFileMetadata {
  const _BaseFileMetadata({
    required this.filePath,
    required this.fileSizeBytes,
    required this.modifiedAt,
    required this.codec,
  });

  final String filePath;
  final int fileSizeBytes;
  final DateTime modifiedAt;
  final String codec;
}

Future<_BaseFileMetadata> _baseFileMetadata(File file) async {
  final stat = await file.stat();
  final normalizedPath = p.normalize(file.absolute.path);
  final extension = p.extension(file.path).replaceFirst('.', '').toLowerCase();

  return _BaseFileMetadata(
    filePath: normalizedPath,
    fileSizeBytes: stat.size,
    modifiedAt: stat.modified,
    codec: extension,
  );
}

AudioMetadata _mergeFileMetadata({
  required _BaseFileMetadata baseMetadata,
  required EmbeddedAudioMetadata? tagMetadata,
  required FilenameMetadataParser filenameParser,
}) {
  final filenameMetadata = filenameParser.parse(baseMetadata.filePath);
  final fallbackMetadata = filenameParser.fallback(baseMetadata.filePath);
  final merged = mergeMetadata(
    tagMetadata: tagMetadata,
    filenameMetadata: filenameMetadata,
    fallbackMetadata: fallbackMetadata,
  );

  return AudioMetadata(
    filePath: baseMetadata.filePath,
    fileSizeBytes: baseMetadata.fileSizeBytes,
    modifiedAt: baseMetadata.modifiedAt,
    title: merged.title,
    codec: baseMetadata.codec,
    metadataSource: merged.source,
    metadataConfidence: merged.confidence,
    artist: merged.artist,
    album: merged.album,
    albumArtist: merged.albumArtist,
    genre: merged.genre,
    duration: merged.duration,
    trackNumber: merged.trackNumber,
    discNumber: merged.discNumber,
    year: merged.year,
  );
}

Future<EmbeddedAudioMetadata?> _readEmbeddedAudioTags(String filePath) async {
  final tag = audio_reader.readMetadata(File(filePath), getImage: false);

  return EmbeddedAudioMetadata(
    title: tag.title,
    artist: tag.artist,
    album: tag.album,
    genre: tag.genres.isEmpty ? null : tag.genres.first,
    duration: tag.duration,
    trackNumber: tag.trackNumber,
    discNumber: tag.discNumber,
    year: tag.year?.year,
  );
}
