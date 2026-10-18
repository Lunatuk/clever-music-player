import 'downloaded_audio_validation.dart';

enum YandexFileQuality { lossless, hq, nq }

enum YandexFileEncoding {
  flac('flac', DownloadedAudioContainer.flac, DownloadedAudioCodec.flac),
  mp3('mp3', DownloadedAudioContainer.mp3, DownloadedAudioCodec.mp3),
  aacMp4('aac-mp4', DownloadedAudioContainer.m4a, DownloadedAudioCodec.aac);

  const YandexFileEncoding(this.apiKey, this.container, this.codec);
  final String apiKey;
  final DownloadedAudioContainer container;
  final DownloadedAudioCodec codec;
}

/// Explicit policy, not a guess about the provider's bitrate/quality mapping.
/// Lossy callers must supply BOTH nominal and measured (possibly VBR) floors.
final class YandexAudioSelection {
  const YandexAudioSelection.losslessFlac()
      : quality = YandexFileQuality.lossless,
        encoding = YandexFileEncoding.flac,
        minimumDeclaredKbps = null,
        minimumMeasuredBitRate = null;

  YandexAudioSelection.lossy({
    required this.quality,
    required this.encoding,
    required int this.minimumDeclaredKbps,
    required int this.minimumMeasuredBitRate,
  }) {
    if (quality == YandexFileQuality.lossless ||
        encoding == YandexFileEncoding.flac ||
        minimumDeclaredKbps! <= 0 ||
        minimumDeclaredKbps! > 1000 ||
        minimumMeasuredBitRate! <= 0 ||
        minimumMeasuredBitRate! > minimumDeclaredKbps! * 1000) {
      throw ArgumentError('Некорректный профиль загрузки.');
    }
  }

  final YandexFileQuality quality;
  final YandexFileEncoding encoding;
  final int? minimumDeclaredKbps, minimumMeasuredBitRate;

  /// Includes the validation floors; distinct policies never share job keys.
  String get resourceQuality => encoding == YandexFileEncoding.flac
      ? 'yandex_flac_lossless'
      : 'yandex_${encoding.name}_${quality.name}_${minimumDeclaredKbps}_$minimumMeasuredBitRate';

  @override
  bool operator ==(Object other) =>
      other is YandexAudioSelection &&
      quality == other.quality &&
      encoding == other.encoding &&
      minimumDeclaredKbps == other.minimumDeclaredKbps &&
      minimumMeasuredBitRate == other.minimumMeasuredBitRate;
  @override
  int get hashCode => Object.hash(
      quality, encoding, minimumDeclaredKbps, minimumMeasuredBitRate);
}
