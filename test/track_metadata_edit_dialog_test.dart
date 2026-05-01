import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/ui/track_metadata_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edit metadata dialog opens with current values', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        track: _track(),
        onSaved: (_) {},
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Current Title'), findsOneWidget);
    expect(find.text('Current Artist'), findsOneWidget);
    expect(find.text('Current Album'), findsOneWidget);
    expect(find.text('Current Album Artist'), findsOneWidget);
    expect(find.text('Current Genre'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('edit metadata dialog validates invalid year', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        track: _track(),
        onSaved: (_) {},
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('metadataYearField')), 'twenty');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Enter a valid year.'), findsOneWidget);
  });

  testWidgets('edit metadata dialog returns trimmed update', (tester) async {
    TrackMetadataUpdate? saved;
    await tester.pumpWidget(
      _TestApp(
        track: _track(),
        onSaved: (update) {
          saved = update;
        },
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('metadataTitleField')),
      '  New Title  ',
    );
    await tester.enterText(
      find.byKey(const Key('metadataArtistField')),
      '  New Artist  ',
    );
    await tester.enterText(find.byKey(const Key('metadataAlbumField')), '  ');
    await tester.enterText(find.byKey(const Key('metadataYearField')), '');
    await tester.enterText(
      find.byKey(const Key('metadataTrackNumberField')),
      '8',
    );
    await tester.enterText(
      find.byKey(const Key('metadataDiscNumberField')),
      '1',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved?.trackId, 1);
    expect(saved?.title, 'New Title');
    expect(saved?.artist, 'New Artist');
    expect(saved?.album, isNull);
    expect(saved?.year, isNull);
    expect(saved?.trackNumber, 8);
    expect(saved?.discNumber, 1);
    expect(saved?.updatedAt, DateTime(2026, 5));
  });
}

Track _track() {
  return Track(
    id: 1,
    filePath: '/music/current.mp3',
    title: 'Current Title',
    artist: 'Current Artist',
    album: 'Current Album',
    albumArtist: 'Current Album Artist',
    genre: 'Current Genre',
    year: 2026,
    trackNumber: 5,
    discNumber: 2,
    addedAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

final class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.track,
    required this.onSaved,
  });

  final Track track;
  final ValueChanged<TrackMetadataUpdate> onSaved;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                final update = await showDialog<TrackMetadataUpdate>(
                  context: context,
                  builder: (context) => TrackMetadataEditDialog(
                    track: track,
                    now: () => DateTime(2026, 5),
                  ),
                );
                if (update != null) {
                  onSaved(update);
                }
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );
  }
}
