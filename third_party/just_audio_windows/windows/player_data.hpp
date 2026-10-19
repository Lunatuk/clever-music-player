#pragma once

#include <flutter/encodable_value.h>
#include <cstdint>

namespace just_audio_windows {

inline flutter::EncodableMap BuildPlaybackSnapshot(
    int32_t state, int64_t positionMs, int64_t durationMs, bool sourcePresent) {
  using flutter::EncodableValue;
  return {
      {EncodableValue("playbackState"), EncodableValue(state)},
      {EncodableValue("positionMs"), EncodableValue(positionMs)},
      {EncodableValue("durationMs"), EncodableValue(durationMs)},
      {EncodableValue("sourcePresent"), EncodableValue(sourcePresent)},
  };
}

inline flutter::EncodableMap BuildPlaybackErrorEvent(
    int32_t nativeCode, int64_t timestampMs) {
  // just_audio >= 0.10 consumes errors as playback event fields. EventChannel
  // error envelopes are discarded by that version and leave load() waiting.
  using flutter::EncodableValue;
  return {
      {EncodableValue("processingState"), EncodableValue(int32_t{0})},
      {EncodableValue("updatePosition"), EncodableValue(int64_t{0})},
      {EncodableValue("updateTime"), EncodableValue(timestampMs)},
      {EncodableValue("bufferedPosition"), EncodableValue(int64_t{0})},
      {EncodableValue("duration"), EncodableValue()},
      {EncodableValue("currentIndex"), EncodableValue(int32_t{0})},
      {EncodableValue("errorCode"), EncodableValue(
          nativeCode == 0 ? static_cast<int32_t>(0x80004005u) : nativeCode)},
      {EncodableValue("errorMessage"), EncodableValue("Windows media source failed")},
  };
}

inline flutter::EncodableMap BuildPlayerDataEvent(
    double volume, double speed, int loopMode, int shuffleMode) {
  // just_audio owns the requested playing state. WinRT Opening/Buffering or
  // a late Paused notification from load is not a user pause. Reporting it as
  // PlayerData.playing=false can cancel play() while audio-session activation
  // is pending, before any native Play call. SMTC commands are handled by the
  // application's single media-control service and call Dart play/pause.
  using flutter::EncodableValue;
  return {
      {EncodableValue("volume"), EncodableValue(volume)},
      {EncodableValue("speed"), EncodableValue(speed)},
      {EncodableValue("loopMode"), EncodableValue(loopMode)},
      {EncodableValue("shuffleMode"), EncodableValue(shuffleMode)},
  };
}

}  // namespace just_audio_windows
