import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/ui/track_metadata_subtitle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subtitle shows artist before codec and metadata source', () {
    final track = _track(
      title: 'Tagged',
      artist: 'Artist',
      codec: 'mp3',
      metadataSource: MetadataSource.embeddedTags,
      metadataConfidence: 0.95,
    );

    expect(buildTrackMetadataSubtitle(track), 'Artist · MP3 · теги 0.95');
  });

  test('subtitle labels fallback metadata without inventing an artist', () {
    final track = _track(
      title: 'scars',
      codec: 'mp3',
      metadataSource: MetadataSource.fallback,
      metadataConfidence: 0.2,
    );

    expect(
      buildTrackMetadataSubtitle(track),
      'Неизвестный исполнитель · MP3 · резерв 0.20',
    );
    expect(track.artist, isNull);
  });
}

Track _track({
  required String title,
  String? artist,
  String? codec,
  MetadataSource? metadataSource,
  double? metadataConfidence,
}) {
  final now = DateTime(2026);
  return Track(
    filePath: '/music/$title.mp3',
    title: title,
    artist: artist,
    codec: codec,
    metadataSource: metadataSource,
    metadataConfidence: metadataConfidence,
    addedAt: now,
    updatedAt: now,
  );
}
