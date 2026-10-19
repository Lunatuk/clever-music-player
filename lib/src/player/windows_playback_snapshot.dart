import 'package:flutter/services.dart';

/// Actual WinRT properties, independent of Dart/UI progress extrapolation.
/// Slots refer to all live native players, including a preloaded second deck.
final class WindowsPlaybackSnapshot {
  const WindowsPlaybackSnapshot(
      this.state, this.positionMs, this.durationMs, this.sourcePresent);
  final int state, positionMs, durationMs;
  final bool sourcePresent;
}

typedef WindowsPlaybackProbe = Future<List<WindowsPlaybackSnapshot>> Function();

Future<List<WindowsPlaybackSnapshot>> readWindowsPlaybackSnapshots() async {
  final values = await const MethodChannel('com.ryanheise.just_audio.methods')
      .invokeListMethod<Object?>('getPlaybackDiagnostics', <String, Object?>{});
  if (values == null || values.length > 8) {
    throw const FormatException('Некорректное состояние декодеров.');
  }
  return List.unmodifiable(values.map((value) {
    if (value is! Map) throw const FormatException('Некорректный декодер.');
    final state = value['playbackState'],
        position = value['positionMs'],
        duration = value['durationMs'],
        source = value['sourcePresent'];
    if (state is! int ||
        state < 0 ||
        state > 4 ||
        position is! int ||
        position < 0 ||
        duration is! int ||
        duration < 0 ||
        source is! bool) {
      throw const FormatException('Некорректное состояние декодера.');
    }
    return WindowsPlaybackSnapshot(state, position, duration, source);
  }));
}
