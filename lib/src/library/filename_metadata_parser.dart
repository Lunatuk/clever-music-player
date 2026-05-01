import 'package:path/path.dart' as p;

import '../domain/models/models.dart';

final class FilenameMetadataResult {
  const FilenameMetadataResult({
    required this.title,
    required this.confidence,
    required this.source,
    required this.patternMatched,
    this.artist,
    this.album,
  });

  final String title;
  final String? artist;
  final String? album;
  final double confidence;
  final MetadataSource source;
  final String patternMatched;
}

final class FilenameMetadataParser {
  const FilenameMetadataParser();

  FilenameMetadataResult parse(String filePath) {
    final rawTitle = p.basenameWithoutExtension(filePath);
    final cleanedTitle = _cleanFilenameText(rawTitle);
    if (cleanedTitle.isEmpty) {
      return fallback(filePath);
    }

    final dashMatch = _dashPattern.firstMatch(cleanedTitle);
    if (dashMatch != null) {
      final artist = _cleanFilenameText(dashMatch.group(1) ?? '');
      final title = _cleanFilenameText(dashMatch.group(2) ?? '');
      if (_isUsefulPart(artist) && _isUsefulPart(title)) {
        return FilenameMetadataResult(
          title: title,
          artist: artist,
          confidence: 0.72,
          source: MetadataSource.filename,
          patternMatched: 'artistDashTitle',
        );
      }
    }

    final bracketMatch = _bracketedArtistPattern.firstMatch(cleanedTitle);
    if (bracketMatch != null) {
      final artist = _cleanFilenameText(bracketMatch.group(1) ?? '');
      final title = _cleanFilenameText(bracketMatch.group(2) ?? '');
      if (_isUsefulPart(artist) && _isUsefulPart(title)) {
        return FilenameMetadataResult(
          title: title,
          artist: artist,
          confidence: 0.68,
          source: MetadataSource.filename,
          patternMatched: 'bracketedArtist',
        );
      }
    }

    final spacedUnderscoreMatch =
        _spacedUnderscorePattern.firstMatch(cleanedTitle);
    if (spacedUnderscoreMatch != null) {
      final artist = _cleanFilenameText(spacedUnderscoreMatch.group(1) ?? '');
      final title = _cleanFilenameText(spacedUnderscoreMatch.group(2) ?? '');
      if (_isUsefulPart(artist) && _isUsefulPart(title)) {
        return FilenameMetadataResult(
          title: title,
          artist: artist,
          confidence: 0.55,
          source: MetadataSource.filename,
          patternMatched: 'spacedUnderscore',
        );
      }
    }

    if (_singleUnderscorePattern.hasMatch(cleanedTitle)) {
      final parts = cleanedTitle.split('_');
      final artist = _cleanFilenameText(parts[0]);
      final title = _cleanFilenameText(parts[1]);
      if (_isUsefulUnderscoreArtist(artist) && _isUsefulPart(title)) {
        return FilenameMetadataResult(
          title: title,
          artist: artist,
          confidence: 0.48,
          source: MetadataSource.filename,
          patternMatched: 'singleUnderscore',
        );
      }
    }

    if (cleanedTitle.contains('_')) {
      return FilenameMetadataResult(
        title: _cleanFilenameText(cleanedTitle.replaceAll('_', ' ')),
        confidence: 0.35,
        source: MetadataSource.filename,
        patternMatched: 'underscoredTitle',
      );
    }

    return fallback(filePath);
  }

  FilenameMetadataResult fallback(String filePath) {
    final rawTitle = p.basenameWithoutExtension(filePath);
    final cleanedTitle = _cleanFilenameText(rawTitle);
    final title = cleanedTitle.isEmpty ? p.basename(filePath) : cleanedTitle;
    return FilenameMetadataResult(
      title: title,
      confidence: 0.2,
      source: MetadataSource.fallback,
      patternMatched: 'fallbackTitle',
    );
  }
}

final _dashPattern = RegExp(
  '^(.+?)\\s+[-${String.fromCharCode(0x2013)}'
  '${String.fromCharCode(0x2014)}]\\s+(.+)\$',
);
final _bracketedArtistPattern = RegExp(r'^\[([^\]]+)\]\s+(.+)$');
final _spacedUnderscorePattern = RegExp(r'^(.+?)\s+_\s+(.+)$');
final _singleUnderscorePattern = RegExp(r'^[^_]+_[^_]+$');
final _domainNoisePattern = RegExp(
  r'[\(\[\{]?\s*(?:https?://)?(?:www\.)?[a-z0-9][a-z0-9-]*'
  r'(?:\.[a-z0-9][a-z0-9-]*)+\S*?\s*[\)\]\}]?',
  caseSensitive: false,
);
final _separatorEdgesPattern = RegExp(
  '^[\\s._\\-${String.fromCharCode(0x2013)}'
  '${String.fromCharCode(0x2014)}]+|'
  '[\\s._\\-${String.fromCharCode(0x2013)}'
  '${String.fromCharCode(0x2014)}]+\$',
);

String _cleanFilenameText(String value) {
  return value
      .replaceAll(_domainNoisePattern, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(_separatorEdgesPattern, '')
      .trim();
}

bool _isUsefulPart(String value) {
  final text = value.trim();
  if (text.length < 2) {
    return false;
  }

  return _hasLetterOrDigit(text);
}

bool _isUsefulUnderscoreArtist(String value) {
  final lower = value.trim().toLowerCase();
  if (!_isUsefulPart(lower)) {
    return false;
  }

  const weakSingleWordPrefixes = {
    'track',
    'song',
    'audio',
    'music',
    'scars',
  };
  return !weakSingleWordPrefixes.contains(lower);
}

bool _hasLetterOrDigit(String value) {
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (RegExp(r'[A-Za-z0-9]').hasMatch(char)) {
      return true;
    }
    if (char.toLowerCase() != char.toUpperCase()) {
      return true;
    }
  }
  return false;
}
