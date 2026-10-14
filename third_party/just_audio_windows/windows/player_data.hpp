#pragma once

#include <flutter/encodable_value.h>

namespace just_audio_windows {

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
