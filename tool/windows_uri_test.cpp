// Standalone regression tests for the URI transformation used by AudioPlayer.
#include "uri_utils.hpp"

#include <iostream>
#include <stdexcept>
#include <utility>
#include <vector>

int main() {
  const std::vector<std::pair<std::string, std::string>> cases = {
      {"", ""},
      {"file:///C:/Music/tone.mp3", "file:///C:/Music/tone.mp3"},
      {"file:///C:/My Files/tone.mp3", "file:///C:/My%20Files/tone.mp3"},
      {"file:///C:/My%20Files/tone.mp3", "file:///C:/My%20Files/tone.mp3"},
      {"file:///C:/%D0%9C%D1%83%D0%B7%D1%8B%D0%BA%D0%B0/tone.mp3",
       u8"file:///C:/Музыка/tone.mp3"},
      {"FILE:///C:/%d0%90/tone.mp3", u8"FILE:///C:/А/tone.mp3"},
      {"file:///C:/%E9%9F%B3%E6%A5%BD/tone.flac", u8"file:///C:/音楽/tone.flac"},
      {"file:///C:/%F0%9F%8E%B5/tone.m4a", u8"file:///C:/🎵/tone.m4a"},
      {u8"file:///C:/Музыка тест/tone.mp3", u8"file:///C:/Музыка%20тест/tone.mp3"},
      {"file:///C:/%D0%90%20%23%25%3F%2F%5C/tone.mp3",
       u8"file:///C:/А%20%23%25%3F%2F%5C/tone.mp3"},
      {"file:///C:/%25D0%2590/tone.mp3", "file:///C:/%25D0%2590/tone.mp3"},
      {"file://server/%D0%90/tone.mp3", u8"file://server/А/tone.mp3"},
      {"https://example.org/%D0%90/tone.mp3", "https://example.org/%D0%90/tone.mp3"},
      {"http://example.org/%E2%80%99 one.mp3", "http://example.org/%E2%80%99%20one.mp3"},
      {"content://music/%D0%90", "content://music/%D0%90"},
      {"file:///C:/%", "file:///C:/%"},
      {"file:///C:/%D0", "file:///C:/%D0"},
      {"file:///C:/%D0%GG", "file:///C:/%D0%GG"},
      {"file:///C:/%80%BF", "file:///C:/%80%BF"},
      {"file:///C:/%C0%AF", "file:///C:/%C0%AF"},
      {"file:///C:/%E0%80%AF", "file:///C:/%E0%80%AF"},
      {"file:///C:/%ED%A0%80", "file:///C:/%ED%A0%80"},
      {"file:///C:/%F0%80%80%AF", "file:///C:/%F0%80%80%AF"},
      {"file:///C:/%F4%90%80%80", "file:///C:/%F4%90%80%80"},
      {"file:///C:/%F5%80%80%80", "file:///C:/%F5%80%80%80"},
      {"file:///C:/%E2%82", "file:///C:/%E2%82"},
      {"file:///C:/%D0%41", "file:///C:/%D0%41"},
      {"file:///C:/%C2%80", u8"file:///C:/\u0080"},
      {"file:///C:/%E0%A0%80", u8"file:///C:/\u0800"},
      {"file:///C:/%ED%9F%BF", u8"file:///C:/\ud7ff"},
      {"file:///C:/%F0%90%80%80", u8"file:///C:/\U00010000"},
      {"file:///C:/%F4%8F%BF%BF", u8"file:///C:/\U0010ffff"},
  };
  for (size_t i = 0; i < cases.size(); ++i) {
    const auto& item = cases[i];
    const auto actual = EncodeSpacesInUri(DecodeFileUriUnicode(item.first));
    if (actual != item.second ||
        EncodeSpacesInUri(DecodeFileUriUnicode(actual)) != actual) {
      throw std::runtime_error("URI regression case " + std::to_string(i));
    }
  }
  std::cout << "Native Windows URI tests passed: " << cases.size() << "\n";
}
