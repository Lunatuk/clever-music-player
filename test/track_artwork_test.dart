import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/ui/track_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TrackArtwork fallback renders without artwork path',
      (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: TrackArtwork(
          track: _track(),
          size: 48,
        ),
      ),
    );

    expect(find.byType(FallbackTrackArtwork), findsOneWidget);
    expect(find.text('T'), findsOneWidget);
  });

  testWidgets('TrackArtwork handles missing file path gracefully',
      (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: TrackArtwork(
          track: _track(
            artworkPath: '/tmp/clever_music_missing_artwork_widget_test.png',
          ),
          size: 48,
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.errorBuilder, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TrackArtwork requests thumbnail-sized file decoding',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _TestApp(
        child: TrackArtwork(
          track: _track(
            artworkPath: '/tmp/clever_music_thumbnail_artwork_test.png',
          ),
          size: 48,
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final resizeImage = image.image as ResizeImage;
    expect(resizeImage.width, 96);
    expect(resizeImage.height, 96);
  });

  test('artwork candidates prefer custom artwork over embedded artwork', () {
    expect(
      trackArtworkPathCandidates(
        _track(
          artworkPath: ' /app/artwork/embedded.png ',
          customArtworkPath: ' /app/custom_artwork/custom.png ',
        ),
      ),
      ['/app/custom_artwork/custom.png', '/app/artwork/embedded.png'],
    );
  });

  test('artwork candidates use embedded artwork after custom removal', () {
    expect(
      trackArtworkPathCandidates(
        _track(artworkPath: '/app/artwork/embedded.png'),
      ),
      ['/app/artwork/embedded.png'],
    );
  });

  test('artwork candidates are empty when no artwork fields exist', () {
    expect(trackArtworkPathCandidates(_track()), isEmpty);
  });
}

final class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(body: Center(child: child)),
    );
  }
}

Track _track({String? artworkPath, String? customArtworkPath}) {
  return Track(
    stableId: 'stable-track',
    filePath: '/music/test-track.mp3',
    title: 'Test Track',
    artist: 'Test Artist',
    artworkPath: artworkPath,
    customArtworkPath: customArtworkPath,
    addedAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}
