import '../domain/models/downloaded_asset.dart';

enum DownloadedAudioContainer { mp3, m4a, flac }

enum DownloadedAudioCodec { mp3, aac, flac }

/// Trusted policy from the selected provider encoding, never a filename guess.
final class DownloadedAudioExpectation {
  DownloadedAudioExpectation({
    required this.quality,
    required this.container,
    required this.codec,
    required this.fileSizeBytes,
    required this.duration,
    required Map<String, String> tags,
    this.minimumBitRate,
    this.minimumSampleRate,
    this.minimumBitDepth,
    this.requireCover = false,
    this.durationTolerance = const Duration(milliseconds: 500),
  }) : tags = Map.unmodifiable(tags) {
    validateAssetQuality(quality);
    if (codec.name !=
        switch (container) {
          DownloadedAudioContainer.mp3 => 'mp3',
          DownloadedAudioContainer.m4a => 'aac',
          DownloadedAudioContainer.flac => 'flac',
        }) {
      throw ArgumentError('Несовместимые контейнер и кодек.');
    }
    if (fileSizeBytes <= 0 ||
        fileSizeBytes > 8 * 1024 * 1024 * 1024 ||
        duration.inMilliseconds <= 0 ||
        duration > const Duration(hours: 12) ||
        durationTolerance < Duration.zero ||
        durationTolerance > const Duration(seconds: 10)) {
      throw ArgumentError('Некорректные границы аудиофайла.');
    }
    for (final entry in [
      (minimumBitRate, 10000000),
      (minimumSampleRate, 192000),
      (minimumBitDepth, 32)
    ]) {
      if (entry.$1 != null && (entry.$1! <= 0 || entry.$1! > entry.$2)) {
        throw ArgumentError('Некорректные требования к аудио.');
      }
    }
    if (minimumBitDepth != null && codec != DownloadedAudioCodec.flac) {
      throw ArgumentError('Глубина задаётся для lossless-аудио.');
    }
    if (codec != DownloadedAudioCodec.flac && minimumBitRate == null) {
      throw ArgumentError('Для lossy-профиля нужен явный минимальный битрейт.');
    }
    if (tags.length > audioValidationTagKeys.length ||
        tags.entries.any((entry) =>
            !audioValidationTagKeys.contains(entry.key) ||
            entry.value.trim().isEmpty ||
            entry.value.length > 4096 ||
            entry.value.contains('\u0000'))) {
      throw ArgumentError('Некорректные ожидаемые теги.');
    }
  }
  final String quality;
  final DownloadedAudioContainer container;
  final DownloadedAudioCodec codec;
  final int fileSizeBytes;
  final Duration duration, durationTolerance;
  final Map<String, String> tags;
  final int? minimumBitRate, minimumSampleRate, minimumBitDepth;
  final bool requireCover;
}

const audioValidationTagKeys = {
  'title',
  'artist',
  'album',
  'album_artist',
  'genre',
  'track',
  'disc',
  'date'
};

final class DownloadedAudioInspection {
  DownloadedAudioInspection({
    required this.container,
    required this.codec,
    required this.duration,
    required this.sizeBytes,
    required this.audioStreamIndex,
    required this.sampleRate,
    required this.channels,
    required Map<String, String> tags,
    this.bitRate,
    this.bitDepth,
    this.coverStreamIndex,
  }) : tags = Map.unmodifiable(tags) {
    if (sizeBytes <= 0 ||
        audioStreamIndex < 0 ||
        duration.inMilliseconds <= 0 ||
        duration > const Duration(hours: 12) ||
        sampleRate < 8000 ||
        sampleRate > 192000 ||
        channels < 1 ||
        channels > 8 ||
        (bitRate != null && (bitRate! <= 0 || bitRate! > 10000000)) ||
        (bitDepth != null && (bitDepth! <= 0 || bitDepth! > 32)) ||
        (coverStreamIndex != null &&
            (coverStreamIndex! < 0 || coverStreamIndex == audioStreamIndex)) ||
        tags.length > audioValidationTagKeys.length ||
        tags.entries.any((entry) =>
            !audioValidationTagKeys.contains(entry.key) ||
            entry.value.length > 4096 ||
            entry.value.contains('\u0000'))) {
      throw const FormatException('Некорректные сведения об аудио.');
    }
  }
  final DownloadedAudioContainer container;
  final DownloadedAudioCodec codec;
  final Duration duration;
  final int sizeBytes, audioStreamIndex, sampleRate, channels;
  final int? bitRate, bitDepth, coverStreamIndex;
  final Map<String, String> tags;
}

enum AudioValidationOutcome {
  verified,
  unsupportedSource,
  backendUnavailable,
  unreadable,
  changed,
  invalidAudio,
  encodingMismatch,
  metadataMismatch,
  coverMissing,
  invalidCover,
  cancelled,
  timedOut,
}

final class AudioValidationException implements Exception {
  const AudioValidationException(this.outcome);
  final AudioValidationOutcome outcome;
}

final class AudioValidationResult {
  const AudioValidationResult.verified(this.verification, this.inspection)
      : outcome = AudioValidationOutcome.verified;
  factory AudioValidationResult.failure(AudioValidationOutcome outcome) {
    if (outcome == AudioValidationOutcome.verified) {
      throw ArgumentError.value(outcome);
    }
    return AudioValidationResult._(outcome);
  }
  const AudioValidationResult._(this.outcome)
      : verification = null,
        inspection = null;
  final AudioValidationOutcome outcome;
  final DownloadedAssetVerification? verification;
  final DownloadedAudioInspection? inspection;
}
