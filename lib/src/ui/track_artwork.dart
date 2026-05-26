import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/models/track.dart';

final class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    required this.track,
    required this.size,
    this.borderRadius = 12,
    super.key,
  });

  final Track? track;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final fallback = FallbackTrackArtwork(
      track: track,
      size: size,
      borderRadius: borderRadius,
    );
    Widget artwork = fallback;
    final candidates = trackArtworkPathCandidates(track);
    for (final artworkPath in candidates.reversed) {
      artwork = _ArtworkFile(
        artworkPath: artworkPath,
        size: size,
        borderRadius: borderRadius,
        fallback: artwork,
      );
    }

    return artwork;
  }
}

List<String> trackArtworkPathCandidates(Track? track) {
  return [
    track?.customArtworkPath,
    track?.artworkPath,
  ].whereType<String>().map((path) => path.trim()).where((path) {
    return path.isNotEmpty;
  }).toList(growable: false);
}

final class _ArtworkFile extends StatelessWidget {
  const _ArtworkFile({
    required this.artworkPath,
    required this.size,
    required this.borderRadius,
    required this.fallback,
  });

  final String? artworkPath;
  final double size;
  final double borderRadius;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final artworkPath = this.artworkPath?.trim();
    if (artworkPath == null || artworkPath.isEmpty) {
      return fallback;
    }
    final cacheDimension = _thumbnailCacheDimension(context, size);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.square(
        dimension: size,
        child: Image.file(
          File(artworkPath),
          cacheWidth: cacheDimension,
          cacheHeight: cacheDimension,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      ),
    );
  }
}

int _thumbnailCacheDimension(BuildContext context, double size) {
  final scaledSize = size * MediaQuery.of(context).devicePixelRatio;
  return scaledSize.ceil().clamp(1, 4096).toInt();
}

final class FallbackTrackArtwork extends StatelessWidget {
  const FallbackTrackArtwork({
    required this.track,
    required this.size,
    this.borderRadius = 12,
    super.key,
  });

  final Track? track;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final seed = _trackSeed(track);
    final hash = _stableHash(seed);
    final palette = _artworkPalette(colorScheme);
    final first = palette[hash % palette.length];
    final second = palette[(hash ~/ palette.length + 3) % palette.length];
    final letter = _artworkLetter(track);
    final iconSize = (size * 0.34).clamp(14.0, 28.0).toDouble();
    final letterSize = (size * 0.38).clamp(15.0, 32.0).toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                first,
                second,
                Color.alphaBlend(
                  colorScheme.surface.withValues(alpha: 0.28),
                  second,
                ),
              ],
            ),
          ),
          child: CustomPaint(
            painter: _FallbackArtworkWavePainter(
              color: Colors.white.withValues(alpha: 0.18),
              hash: hash,
            ),
            child: Center(
              child: track == null
                  ? Icon(
                      Icons.album_outlined,
                      size: iconSize,
                      color: Colors.white.withValues(alpha: 0.84),
                    )
                  : Text(
                      letter,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: letterSize,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _FallbackArtworkWavePainter extends CustomPainter {
  const _FallbackArtworkWavePainter({
    required this.color,
    required this.hash,
  });

  final Color color;
  final int hash;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.shortestSide * 0.06).clamp(2.0, 5.0)
      ..strokeCap = StrokeCap.round;
    final amplitude = size.height * (0.08 + (hash % 7) * 0.006);
    final baseY = size.height * 0.68;

    for (var line = 0; line < 3; line++) {
      final path = Path();
      final offsetY = baseY - line * size.height * 0.16;
      path.moveTo(-size.width * 0.05, offsetY);
      for (var x = 0.0; x <= size.width * 1.08; x += size.width / 4) {
        path.quadraticBezierTo(
          x + size.width / 8,
          offsetY - amplitude,
          x + size.width / 4,
          offsetY,
        );
        path.quadraticBezierTo(
          x + size.width * 3 / 8,
          offsetY + amplitude,
          x + size.width / 2,
          offsetY,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_FallbackArtworkWavePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.hash != hash;
  }
}

List<Color> _artworkPalette(ColorScheme colorScheme) {
  return [
    colorScheme.primary,
    colorScheme.secondary,
    colorScheme.tertiary,
    const Color(0xff00c2a8),
    const Color(0xffffb454),
    const Color(0xfff36f7b),
    const Color(0xff55a6ff),
    const Color(0xffb878ff),
  ];
}

String _trackSeed(Track? track) {
  if (track == null) {
    return 'clever-music-player';
  }
  return [
    track.stableId,
    track.id?.toString(),
    track.title,
    track.artist,
    track.filePath,
  ].whereType<String>().join('|');
}

String _artworkLetter(Track? track) {
  final title = track?.displayTitle.trim();
  if (title != null && title.isNotEmpty) {
    return String.fromCharCode(title.runes.first).toUpperCase();
  }
  final artist = track?.artist?.trim();
  if (artist != null && artist.isNotEmpty) {
    return String.fromCharCode(artist.runes.first).toUpperCase();
  }
  return 'М';
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}
