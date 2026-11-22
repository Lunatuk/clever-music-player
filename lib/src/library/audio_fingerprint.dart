import 'dart:isolate';
import 'dart:typed_data';

import '../domain/models/audio_source_reference.dart';
import 'library_scan_control.dart';

abstract interface class AudioFingerprintReader {
  Future<AudioFingerprint?> readFingerprint(
      AudioSourceReference source, LibraryScanControl control);
}

final class AudioFingerprint {
  const AudioFingerprint._(this.duration, this.words);

  static const _minDuration = Duration(seconds: 18);
  static const _maxDuration = Duration(minutes: 30);
  static const _maxWords = 15000;
  final Duration duration;
  final Uint32List words;

  static AudioFingerprint? decode(Map<String, dynamic> result) {
    final micros = result['durationUs'];
    final hex = result['fingerprint'];
    if (result['status'] != 'ok' ||
        micros is! int ||
        micros < _minDuration.inMicroseconds ||
        micros > _maxDuration.inMicroseconds ||
        hex is! String ||
        hex.isEmpty ||
        hex.length > _maxWords * 8 ||
        hex.length % 8 != 0) {
      return null;
    }
    final words = Uint32List(hex.length ~/ 8);
    for (var i = 0; i < words.length; i++) {
      var value = 0;
      for (var j = i * 8; j < (i + 1) * 8; j++) {
        final code = hex.codeUnitAt(j);
        if (code >= 48 && code <= 57) {
          value = (value << 4) | (code - 48);
        } else if (code >= 97 && code <= 102) {
          value = (value << 4) | (code - 87);
        } else {
          return null;
        }
      }
      words[i] = value;
    }
    return AudioFingerprint._(Duration(microseconds: micros), words);
  }
}

enum RecordingSimilarity { inconclusive, belowThreshold, possible }

Future<RecordingSimilarity> compareRecordingFingerprints(
        AudioFingerprint first, AudioFingerprint second) =>
    Isolate.run(() => _compare(first, second));

RecordingSimilarity _compare(AudioFingerprint first, AudioFingerprint second) {
  const maxLag = 12;
  const minWords = 96;
  const wordsPerWindow = 160; // About 20 seconds of TEST2 output.
  final left = first.words, right = second.words;
  final shorter = left.length < right.length ? left.length : right.length;
  final longer = left.length > right.length ? left.length : right.length;
  if ((first.duration - second.duration).abs() >
          const Duration(milliseconds: 1500) ||
      shorter < minWords ||
      shorter * 10 < longer * 9) {
    return RecordingSimilarity.inconclusive;
  }

  // Keep a single offset for the whole recording. Evaluate the whole overlap
  // in sections of similar length so a short or changed ending counts too.
  final windows = ((shorter + wordsPerWindow - 1) ~/ wordsPerWindow)
      .clamp(1, shorter ~/ minWords);
  var comparable = false;
  for (var lag = -maxLag; lag <= maxLag; lag++) {
    final l = lag < 0 ? -lag : 0;
    final r = lag > 0 ? lag : 0;
    final lCount = left.length - l, rCount = right.length - r;
    final count = lCount < rCount ? lCount : rCount;
    if (count < minWords || count * 10 < longer * 9) continue;

    var totalErrors = 0;
    var weakestFailed = false;
    var useful = true;
    for (var window = 0; window < windows; window++) {
      final start = window * count ~/ windows;
      final end = (window + 1) * count ~/ windows;
      if (!_varied(left, l + start, l + end) ||
          !_varied(right, r + start, r + end)) {
        useful = false;
        break;
      }
      var errors = 0;
      for (var i = start; i < end; i++) {
        errors += _bitCount(left[l + i] ^ right[r + i]);
      }
      totalErrors += errors;
      if (errors * 100 > (end - start) * 32 * 6) weakestFailed = true;
    }
    if (useful) {
      comparable = true;
      if (!weakestFailed && totalErrors * 100 <= count * 32 * 4) {
        return RecordingSimilarity.possible;
      }
    }
  }
  return comparable
      ? RecordingSimilarity.belowThreshold
      : RecordingSimilarity.inconclusive;
}

bool _varied(Uint32List words, int start, int end) {
  final distinct = <int>{};
  for (var i = start; i < end; i++) {
    distinct.add(words[i]);
    if (distinct.length == 12) return true;
  }
  return false;
}

int _bitCount(int word) {
  word -= (word >> 1) & 0x55555555;
  word = (word & 0x33333333) + ((word >> 2) & 0x33333333);
  word = (word + (word >> 4)) & 0x0f0f0f0f;
  word += word >> 8;
  return (word + (word >> 16)) & 0x3f;
}
