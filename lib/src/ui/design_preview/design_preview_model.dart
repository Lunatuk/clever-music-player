import 'package:flutter/material.dart';

enum PreviewPage { home, library, player, queue }

final class PreviewSong {
  const PreviewSong(
      this.title, this.artist, this.album, this.duration, this.cover);
  final String title, artist, album, duration;
  final int cover;
}

/// One invented collection for all directions, offline and independent of app
/// repositories/credentials/audio. These covers are original vector paintings.
const previewSongs = [
  PreviewSong('За горизонт', 'Тихие улицы', 'После дождя', '3:42', 0),
  PreviewSong('Медленно', 'Северный берег', 'Тёплый воздух', '4:18', 1),
  PreviewSong('Оставаться здесь', 'Тихие улицы', 'После дождя', '3:16', 0),
  PreviewSong(
      'Город, которого больше нет', 'Линия света', 'Синий час', '5:02', 2),
  PreviewSong('Рядом', 'Северный берег', 'Тёплый воздух', '2:57', 1),
  PreviewSong('Без обложки', 'Пустая кассета', 'Первые записи', '3:28', -1),
  PreviewSong('Тихая вода', 'Линия света', 'Синий час', '4:06', 2),
  PreviewSong('Ненадолго', 'Пустая кассета', 'Первые записи', '2:46', -1),
];

final class PreviewCover extends StatelessWidget {
  const PreviewCover(
      {super.key, required this.index, this.size = 56, this.radius = 12});
  final int index;
  final double size, radius;
  @override
  Widget build(BuildContext context) => Semantics(
      label: index < 0 ? 'Альбом без обложки' : 'Демо-обложка альбома',
      image: true,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: SizedBox.square(
              dimension: size,
              child: index < 0
                  ? ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: Icon(Icons.music_note_rounded, size: size * .38))
                  : CustomPaint(painter: _CoverPainter(index)))));
}

final class _CoverPainter extends CustomPainter {
  const _CoverPainter(this.index);
  final int index;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final palettes = [
      [
        const Color(0xffcf926d),
        const Color(0xff6d554d),
        const Color(0xff274d4d),
        const Color(0xffe9c49a)
      ],
      [
        const Color(0xffd6c4a4),
        const Color(0xff889a7d),
        const Color(0xff475d50),
        const Color(0xfff4ddaa)
      ],
      [
        const Color(0xffa3b2cd),
        const Color(0xff516080),
        const Color(0xff29384c),
        const Color(0xffd6b9a4)
      ],
    ];
    final c = palettes[index % palettes.length];
    canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c[0], c[1]]).createShader(r));
    canvas.drawCircle(Offset(size.width * .72, size.height * .27),
        size.width * .15, Paint()..color = c[3]);
    final path = Path()
      ..moveTo(0, size.height * .64)
      ..cubicTo(size.width * .2, size.height * .36, size.width * .5,
          size.height * .88, size.width, size.height * .47)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = c[2]);
    canvas.drawPath(
        Path()
          ..moveTo(0, size.height * .84)
          ..quadraticBezierTo(
              size.width * .6, size.height * .52, size.width, size.height * .86)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close(),
        Paint()..color = c[1].withValues(alpha: .7));
    for (var i = 0; i < 12; i++) {
      final y = size.height * (.08 + i * .075);
      canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = Colors.white.withValues(alpha: .025)
            ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(_CoverPainter oldDelegate) => index != oldDelegate.index;
}
