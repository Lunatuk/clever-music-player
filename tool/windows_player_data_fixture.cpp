// Emits the actual plugin payload used by the Dart protocol regression test.
#include "player_data.hpp"

#include <iomanip>
#include <iostream>
#include <stdexcept>

int main(int argc, char** argv) {
  const auto fallback = just_audio_windows::BuildPlaybackErrorEvent(0, 0);
  if (std::get<int32_t>(fallback.at(flutter::EncodableValue("errorCode"))) !=
      static_cast<int32_t>(0x80004005u)) {
    throw std::runtime_error("Missing HRESULT must still produce an error");
  }
  const auto payload = argc > 1 && std::string(argv[1]) == "snapshot"
      ? just_audio_windows::BuildPlaybackSnapshot(3, 2500, 60000, true)
      : argc > 1 && std::string(argv[1]) == "error"
      ? just_audio_windows::BuildPlaybackErrorEvent(
          static_cast<int32_t>(0xc00d36c4u), 1700000000000LL)
      : just_audio_windows::BuildPlayerDataEvent(.75, 1., 0, 0);
  std::cout << "{";
  bool first = true;
  for (const auto& field : payload) {
    if (!first) std::cout << ",";
    first = false;
    std::cout << '"' << std::get<std::string>(field.first) << "\":";
    if (const auto* value = std::get_if<bool>(&field.second)) {
      std::cout << (*value ? "true" : "false");
    } else if (const auto* value = std::get_if<double>(&field.second)) {
      std::cout << std::showpoint << std::setprecision(17) << *value;
    } else if (const auto* value = std::get_if<int32_t>(&field.second)) {
      std::cout << *value;
    } else if (const auto* value = std::get_if<int64_t>(&field.second)) {
      std::cout << *value;
    } else if (const auto* value = std::get_if<std::string>(&field.second)) {
      std::cout << '"' << *value << '"';
    } else if (field.second.IsNull()) {
      std::cout << "null";
    } else {
      throw std::runtime_error("Unsupported test payload value");
    }
  }
  std::cout << "}\n";
}
