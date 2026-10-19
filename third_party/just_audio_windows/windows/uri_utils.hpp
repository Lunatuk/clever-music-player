#pragma once

#include <string>

// WinRT MediaSource does not consistently resolve file: URIs whose Unicode
// path components are percent-encoded UTF-8. Supply those characters as UTF-8
// (converted to UTF-16 by the caller). Keep escaped ASCII, especially %, #, ?
// and separators, intact so that literal filenames are not reinterpreted.
// Network URIs retain their original escaping.
inline std::string DecodeFileUriUnicode(const std::string& uri) {
  if (uri.size() < 5 ||
      (uri[0] != 'f' && uri[0] != 'F') ||
      (uri[1] != 'i' && uri[1] != 'I') ||
      (uri[2] != 'l' && uri[2] != 'L') ||
      (uri[3] != 'e' && uri[3] != 'E') || uri[4] != ':') {
    return uri;
  }
  const auto hex = [](char c) -> int {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
  };
  const auto byteAt = [&](size_t index) -> int {
    if (index + 2 >= uri.size() || uri[index] != '%') return -1;
    const int high = hex(uri[index + 1]);
    const int low = hex(uri[index + 2]);
    return high < 0 || low < 0 ? -1 : (high << 4) | low;
  };
  std::string decoded;
  decoded.reserve(uri.size());
  for (size_t i = 0; i < uri.size();) {
    const int first = byteAt(i);
    const int length = first >= 0xc2 && first <= 0xdf ? 2
        : first >= 0xe0 && first <= 0xef ? 3
        : first >= 0xf0 && first <= 0xf4 ? 4 : 0;
    bool valid = length != 0;
    for (int j = 1; valid && j < length; ++j) {
      const int next = byteAt(i + 3 * j);
      valid = next >= 0x80 && next <= 0xbf;
      if (j == 1) {
        // Reject overlong encodings, surrogate code points and > U+10FFFF.
        valid = valid && !(first == 0xe0 && next < 0xa0) &&
            !(first == 0xed && next >= 0xa0) &&
            !(first == 0xf0 && next < 0x90) &&
            !(first == 0xf4 && next >= 0x90);
      }
    }
    if (valid) {
      for (int j = 0; j < length; ++j) {
        decoded += static_cast<char>(byteAt(i + 3 * j));
      }
      i += 3 * length;
    } else {
      decoded += uri[i++];
    }
  }
  return decoded;
}

// Encodes literal space characters in a URI string as "%20" so that
// Windows::Foundation::Uri accepts URIs that contain unencoded spaces
// (e.g. local file paths like "file:///C:/My Files/song.mp3").
//
// Already percent-encoded sequences such as "%20" or "%E2%80%99" are never
// modified, because they contain no literal space character.
inline std::string EncodeSpacesInUri(const std::string& uri) {
  std::string encoded;
  // Reserve worst-case capacity (every char is a space → 3 chars each).
  encoded.reserve(uri.length() * 3);
  for (char c : uri) {
    if (c == ' ') {
      encoded += "%20";
    } else {
      encoded += c;
    }
  }
  return encoded;
}
