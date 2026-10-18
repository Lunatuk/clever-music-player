import 'binary_download.dart';
import 'binary_http_download_transport.dart';

/// Provider artwork capability, never an arbitrary URL or an authenticated API
/// request. A fixed rendition avoids fetching unbounded original-size artwork.
final class YandexCoverAddress {
  const YandexCoverAddress._(this.address);
  final BinaryDownloadAddress address;

  static YandexCoverAddress? fromTemplate(Object? value, {Uri? testOrigin}) {
    if (value == null) return null;
    try {
      if (value is! String || value.length > 2048) {
        throw const FormatException();
      }
      final template =
          value.startsWith('https://') ? value.substring(8) : value;
      // Exact CDN, collection path, two opaque identifiers and one size token.
      // No query, credentials, port, escapes, traversal or provider-supplied size.
      final match = RegExp(
              r'^avatars\.yandex\.net/get-music-content/([A-Za-z0-9_-]+)/([A-Za-z0-9_.-]+)/%%$')
          .firstMatch(template);
      if (match == null || {'.', '..'}.contains(match.group(2))) {
        throw const FormatException();
      }
      final path =
          '/get-music-content/${match.group(1)}/${match.group(2)}/600x600';
      final address = testOrigin == null
          ? BinaryDownloadAddress.https('https://avatars.yandex.net$path',
              trustedHosts: const {'avatars.yandex.net'})
          : BinaryDownloadAddress.loopbackForTesting(
              testOrigin.replace(path: path).toString());
      return YandexCoverAddress._(address);
    } on Object {
      throw const BinaryDownloadException(BinaryDownloadFailure.invalidAddress);
    }
  }

  @override
  String toString() => 'YandexCoverAddress(<redacted>)';
}
