import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyWith can update and clear nullable playback fields', () {
    final now = DateTime(2026);
    final track = Track(
      id: 1,
      filePath: '/music/song.flac',
      title: 'Song',
      addedAt: now,
      updatedAt: now,
    );
    final state = PlayerState(
      currentTrack: track,
      isPlaying: true,
      position: const Duration(seconds: 10),
      duration: const Duration(minutes: 3),
      status: PlayerPlaybackStatus.playing,
      errorMessage: 'previous error',
    );

    final updated = state.copyWith(
      currentTrack: null,
      isPlaying: false,
      duration: null,
      status: PlayerPlaybackStatus.stopped,
      errorMessage: null,
    );

    expect(updated.currentTrack, isNull);
    expect(updated.isPlaying, isFalse);
    expect(updated.duration, isNull);
    expect(updated.status, PlayerPlaybackStatus.stopped);
    expect(updated.errorMessage, isNull);
  });
}
