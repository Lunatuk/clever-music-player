import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/library_track_list.dart';
import 'package:clever_music_player/src/library/metadata_completeness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Track track(
          {String? title,
          String? artist,
          String? album,
          String? albumArtist,
          String? genre,
          int? year,
          String? artwork,
          String? customArtwork,
          int? number,
          int? disc,
          double? confidence,
          MetadataSource? source,
          String path = '/unavailable/audio.m4a'}) =>
      Track(
          filePath: path,
          title: title,
          artist: artist,
          album: album,
          albumArtist: albumArtist,
          genre: genre,
          year: year,
          artworkPath: artwork,
          customArtworkPath: customArtwork,
          trackNumber: number,
          discNumber: disc,
          metadataConfidence: confidence,
          metadataSource: source,
          addedAt: DateTime(2026),
          updatedAt: DateTime(2026));

  test('richer card has more coverage even when legacy confidence is lower',
      () {
    final poor =
        track(title: 'Andromeda', artist: 'LXST CXNTURY', confidence: 1);
    final rich = track(
        title: 'Andromeda',
        artist: 'LXST CXNTURY',
        album: 'Andromeda',
        albumArtist: 'LXST CXNTURY',
        genre: 'phonkgenre',
        year: 2019,
        artwork: '/missing/cover.webp',
        confidence: 0.95);
    expect(MetadataCompleteness.forTrack(poor).count, 2);
    expect(MetadataCompleteness.forTrack(rich).count, 7);
    expect(MetadataCompleteness.forTrack(rich).missing, isEmpty);
  });

  test('placeholders and blank values do not fill fields', () {
    for (final value in [
      null,
      '',
      ' ',
      '<unknown>',
      'N/A',
      'Track 01',
      'Unknown Album',
      'Без названия',
      'Неизвестный исполнитель'
    ]) {
      final valueTrack = track(
          title: value,
          artist: value,
          album: value,
          albumArtist: value,
          genre: value,
          year: 0,
          artwork: ' ');
      expect(MetadataCompleteness.forTrack(valueTrack).count, 0,
          reason: '$value');
    }
  });

  test('year uses existing supported bounds', () {
    for (final year in [null, -1, 0, 10000]) {
      expect(MetadataCompleteness.forTrack(track(year: year)).count, 0);
    }
    for (final year in [1, 2019, 9999]) {
      expect(MetadataCompleteness.forTrack(track(year: year)).count, 1);
    }
  });

  test('track and disc numbers are not mandatory or score multipliers', () {
    final without = MetadataCompleteness.forTrack(track(title: 'Andromeda'));
    for (final number in [-1, 0, 1, 1000001]) {
      final numbered = MetadataCompleteness.forTrack(
          track(title: 'Andromeda', number: number, disc: number));
      expect(numbered.count, without.count);
      expect(numbered.total, 7);
    }
  });

  test('artwork reference is counted without reading disk or requiring a hash',
      () {
    expect(
        MetadataCompleteness.forTrack(track(artwork: '/does/not/exist')).count,
        1);
    expect(
        MetadataCompleteness.forTrack(track(customArtwork: '/private/custom'))
            .count,
        1);
    expect(
        MetadataCompleteness.forTrack(
                track(artwork: 'one', customArtwork: 'two'))
            .count,
        1);
  });

  test(
      'manual and inferred fields count as card data without granting completeness',
      () {
    for (final source in MetadataSource.values) {
      final summary = MetadataCompleteness.forTrack(
          track(title: 'Andromeda', source: source, confidence: 1));
      expect(summary.count, 1);
      expect(summary.missing, contains(MetadataDetail.artist));
    }
  });

  test('normalization and immutable snapshots keep the missing fields accurate',
      () {
    final summary = MetadataCompleteness.forTrack(
        track(title: ' Andromeda\u0000 ', artist: ' Performer '));
    expect(summary.present, {MetadataDetail.title, MetadataDetail.artist});
    expect(summary.missing.length, 5);
    expect(() => summary.present.add(MetadataDetail.album),
        throwsUnsupportedError);
  });

  test(
      'explicit completeness sort ignores confidence and never merges same titles',
      () {
    final rich = track(
        title: 'Andromeda',
        artist: 'Artist',
        album: 'Album',
        confidence: 0.95,
        path: '/rich.mp3');
    final poor = track(title: 'Andromeda', confidence: 1, path: '/poor.flac');
    final sorted = sortLibraryTracks([rich, poor],
        sortOption: LibraryTrackSortOption.metadataCompletenessLowFirst);
    expect(sorted, [poor, rich]);
    expect(sorted, hasLength(2));
  });
}
