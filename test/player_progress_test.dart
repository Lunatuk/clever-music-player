import 'package:clever_music_player/src/player/player_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses zeroed progress while duration is unknown', () {
    const progress = PlayerProgress(
      position: Duration(seconds: 30),
      duration: null,
    );

    expect(progress.canSeek, isFalse);
    expect(progress.displayPosition, Duration.zero);
    expect(progress.displayDuration, Duration.zero);
    expect(progress.valueMilliseconds, 0);
    expect(progress.maxMilliseconds, 1);
  });

  test('drag position overrides playback position while clamped to duration',
      () {
    const progress = PlayerProgress(
      position: Duration(seconds: 20),
      dragPosition: Duration(minutes: 5),
      duration: Duration(minutes: 3),
    );

    expect(progress.canSeek, isTrue);
    expect(progress.displayPosition, const Duration(minutes: 3));
    expect(progress.valueMilliseconds, 180000);
    expect(progress.maxMilliseconds, 180000);
  });

  test('fromSliderValue clamps negative and oversized values', () {
    const duration = Duration(minutes: 2);

    expect(
      PlayerProgress.fromSliderValue(-10, duration),
      Duration.zero,
    );
    expect(
      PlayerProgress.fromSliderValue(999999, duration),
      duration,
    );
  });

  test('formatDuration supports minute and hour durations', () {
    expect(
      PlayerProgress.formatDuration(
        const Duration(minutes: 3, seconds: 4),
      ),
      '3:04',
    );
    expect(
      PlayerProgress.formatDuration(
        const Duration(hours: 1, minutes: 2, seconds: 3),
      ),
      '1:02:03',
    );
  });
}
