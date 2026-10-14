// Emits the actual plugin payload used by the Dart protocol regression test.
#include "player_data.hpp"

#include <iomanip>
#include <iostream>
#include <stdexcept>

int main() {
  const auto payload = just_audio_windows::BuildPlayerDataEvent(.75, 1., 0, 0);
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
    } else {
      throw std::runtime_error("Unsupported test payload value");
    }
  }
  std::cout << "}\n";
}
