import '../domain/models/external_track_ref.dart';

/// A source annotation carried by the file, independent of its display tags.
/// Conflicting source comments cannot establish one catalogue identity.
ExternalTrackIdentity? embeddedYandexIdentity(Iterable<String> comments) {
  ExternalTrackIdentity? found;
  var count = 0;
  for (final comment in comments) {
    if (++count > 32) return null;
    final ExternalTrackIdentity? identity;
    try {
      identity = _fromSourceUrl(comment);
    } on FormatException {
      continue;
    }
    if (identity == null) continue;
    if (found != null && found != identity) return null;
    found = identity;
  }
  return found;
}

ExternalTrackIdentity? _fromSourceUrl(String comment) {
  if (comment.length > 4096) return null;
  final text = comment
      .trim()
      .replaceFirst(RegExp(r'^\x00+'), '')
      .replaceFirst(RegExp(r'\x00+$'), '')
      .trim();
  final uri = Uri.tryParse(text);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      !_hosts.contains(uri.host.toLowerCase())) {
    return null;
  }
  final parts = uri.pathSegments.toList();
  if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
  if (parts.length == 4 &&
      parts[0] == 'album' &&
      parts[2] == 'track' &&
      _validId(parts[1]) &&
      _validId(parts[3])) {
    return ExternalTrackIdentity(
        provider: 'yandex_music', externalId: parts[3], variantKey: parts[1]);
  }
  if (parts.length == 2 && parts[0] == 'track' && _validId(parts[1])) {
    return ExternalTrackIdentity(
        provider: 'yandex_music', externalId: parts[1]);
  }
  return null;
}

bool _validId(String text) =>
    RegExp(r'^[0-9]{1,32}$').stringMatch(text) == text &&
    text.contains(RegExp(r'[1-9]'));

const _hosts = {
  'music.yandex.ru',
  'music.yandex.com',
  'music.yandex.by',
  'music.yandex.kz',
  'music.yandex.uz',
};
