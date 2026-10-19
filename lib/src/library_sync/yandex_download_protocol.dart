import 'dart:convert';

import '../domain/models/external_track_ref.dart';
import '../domain/models/remote_library.dart';
import '../library/library_scan_control.dart';
import 'binary_download.dart';
import 'binary_http_download_transport.dart';
import 'downloaded_audio_validation.dart';
import 'yandex_audio_selection.dart';
import 'yandex_library_protocol.dart';
import 'yandex_cover_address.dart';

enum YandexDownloadFailure {
  unavailable,
  identityMismatch,
  qualityMismatch,
  unsupportedTransport,
  invalidAddress,
  invalidMetadata,
  invalidResponse,
  internal,
}

/// No response text, signed URL, key, title or credential in errors.
final class YandexDownloadException implements Exception {
  const YandexDownloadException(this.failure);
  final YandexDownloadFailure failure;
  @override
  String toString() => 'YandexDownloadException(${failure.name})';
}

abstract interface class YandexDownloadReader {
  Future<YandexDownloadVariant> resolveDownload(RemoteAccountIdentity account,
      ExternalTrackIdentity identity, YandexAudioSelection selection,
      {LibraryScanControl? control});
  Future<void> close();
}

/// Dedicated credential-bound client, independent of the settings reader.
abstract interface class YandexDownloadSessionReader
    implements YandexDownloadReader {
  Future<YandexAccountProfile> verifyAccount({LibraryScanControl? control});
}

final class YandexDownloadMetadata {
  YandexDownloadMetadata._(
      this.identity, this.duration, Map<String, String> tags, this.cover)
      : tags = Map.unmodifiable(tags);
  final ExternalTrackIdentity identity;
  final Duration duration;
  final Map<String, String> tags;
  final YandexCoverAddress? cover;
  @override
  String toString() => 'YandexDownloadMetadata(<redacted>)';
}

/// A short-lived in-memory capability. Never serialize/cache its signed address.
/// A variant is NOT proof that downloaded bytes contain the requested music.
final class YandexDownloadVariant {
  const YandexDownloadVariant._(this.account, this.metadata, this.selection,
      this.address, this.expectedBytes, this.declaredKbps);
  final RemoteAccountIdentity account;
  final YandexDownloadMetadata metadata;
  final YandexAudioSelection selection;
  final BinaryDownloadAddress address;
  final int? expectedBytes;
  final int declaredKbps;

  DownloadedAudioExpectation expectation(int receivedBytes,
      {bool requireCover = false}) {
    if (expectedBytes != null && expectedBytes != receivedBytes) {
      throw const YandexDownloadException(
          YandexDownloadFailure.invalidResponse);
    }
    return DownloadedAudioExpectation(
        quality: selection.resourceQuality,
        container: selection.encoding.container,
        codec: selection.encoding.codec,
        fileSizeBytes: receivedBytes,
        duration: metadata.duration,
        minimumBitRate: selection.minimumMeasuredBitRate,
        tags: metadata.tags,
        requireCover: requireCover);
  }

  @override
  String toString() => 'YandexDownloadVariant(<redacted>)';
}

/// Bounded provider parsing. Only Yandex's raw streaming domain is supported;
/// changing the CDN/transport contract requires an explicit adapter update.
final class YandexDownloadParser {
  const YandexDownloadParser() : _testOrigin = null;
  YandexDownloadParser.loopbackForTesting(Uri origin) : _testOrigin = origin {
    // Also validates literal loopback, userinfo, fragment and origin shape.
    BinaryDownloadAddress.loopbackForTesting(
        origin.replace(path: '/origin-check').toString());
    if (origin.hasQuery || (origin.path.isNotEmpty && origin.path != '/')) {
      throw ArgumentError('Тестовый адрес должен быть loopback origin.');
    }
  }
  final Uri? _testOrigin;

  YandexDownloadMetadata metadata(
      Object? value, ExternalTrackIdentity identity) {
    _identity(identity);
    if (value is! List || value.length != 1) _fail();
    final data = _map(value.single);
    _trackIdentity(data['id'], identity, allowBare: true);
    if (data['realId'] != null) {
      _trackIdentity(data['realId'], identity, allowBare: true);
    }
    if (data['substituted'] != null || data['matchedTrack'] != null) {
      _fail(YandexDownloadFailure.identityMismatch);
    }
    if (data['error'] != null ||
        (data['available'] != true &&
            data['availableForPremiumUsers'] != true)) {
      _fail(YandexDownloadFailure.unavailable);
    }
    if (data['type'] != null && data['type'] != 'music') {
      _fail(YandexDownloadFailure.unavailable);
    }
    final duration = data['durationMs'];
    if (duration is! int || duration <= 0 || duration > 43200000) {
      _fail(YandexDownloadFailure.invalidMetadata);
    }
    var title = _text(data['title']);
    if (data['version'] != null) title = '$title (${_text(data['version'])})';
    final tags = <String, String>{
      'title': title,
      'artist': _artists(data['artists']),
    };
    if (identity.variantKey.isNotEmpty) {
      final albums = data['albums'];
      if (albums is! List || albums.length > 256) _fail();
      final matching = albums
          .map(_map)
          .where((album) => yandexNumericId(album['id']) == identity.variantKey)
          .toList();
      if (matching.length != 1) _fail(YandexDownloadFailure.identityMismatch);
      final album = matching.single;
      tags['album'] = _text(album['title']);
      if (album['artists'] != null) {
        final artists = album['artists'];
        if (artists is! List) _fail(YandexDownloadFailure.invalidMetadata);
        if (artists.isNotEmpty) tags['album_artist'] = _artists(artists);
      }
      if (album['genre'] != null) tags['genre'] = _text(album['genre']);
      if (album['year'] != null) {
        final year = album['year'];
        if (year is! int || year < 1 || year > 9999) _fail();
        tags['date'] = '$year';
      }
      if (album['trackPosition'] != null) {
        final position = _map(album['trackPosition']);
        for (final entry in {'index': 'track', 'volume': 'disc'}.entries) {
          if (position[entry.key] != null) {
            final number = position[entry.key];
            if (number is! int || number <= 0 || number > 100000) _fail();
            tags[entry.value] = '$number';
          }
        }
      }
    }
    // Leave enough room for helper arguments, including escaped UTF-8 metadata.
    if (tags.values.any((v) => v.length > 4096) ||
        tags.values.fold<int>(0, (sum, v) => sum + utf8.encode(v).length) >
            8192) {
      _fail(YandexDownloadFailure.invalidMetadata);
    }
    final YandexCoverAddress? cover;
    try {
      cover = YandexCoverAddress.fromTemplate(data['coverUri'],
          testOrigin: _testOrigin);
    } on BinaryDownloadException {
      _fail(YandexDownloadFailure.invalidAddress);
    }
    return YandexDownloadMetadata._(
        identity, Duration(milliseconds: duration), tags, cover);
  }

  YandexDownloadVariant variant(Object? value, RemoteAccountIdentity account,
      YandexDownloadMetadata metadata, YandexAudioSelection selection) {
    final info = _map(value)['downloadInfo'];
    if (info == null) _fail(YandexDownloadFailure.unavailable);
    final data = _map(info);
    _trackIdentity(data['trackId'], metadata.identity, allowBare: true);
    if (data['realId'] != null) {
      _trackIdentity(data['realId'], metadata.identity, allowBare: true);
    }
    if (data['transport'] != 'raw' || data['key'] != null) {
      _fail(YandexDownloadFailure.unsupportedTransport);
    }
    if (data['quality'] != selection.quality.name ||
        data['codec'] != selection.encoding.apiKey) {
      _fail(YandexDownloadFailure.qualityMismatch);
    }
    final bitrate = data['bitrate'];
    if (bitrate is! int || bitrate < 0 || bitrate > 10000) _fail();
    if (selection.minimumDeclaredKbps != null &&
        bitrate < selection.minimumDeclaredKbps!) {
      _fail(YandexDownloadFailure.qualityMismatch);
    }
    final size = data['size'];
    if (size != null &&
        (size is! int || size < 0 || size > maximumRawDownloadBytes)) {
      _fail();
    }
    final urls = data['urls'];
    if (urls is! List || urls.isEmpty || urls.length > 8) _fail();
    final addresses = urls.map(_address).toList();
    // Some providers only return urls; never choose an unlisted primary URL.
    final primary = data['url'];
    final address = primary == null ? addresses.first : _address(primary);
    if (primary != null && !urls.contains(primary)) {
      _fail(YandexDownloadFailure.invalidAddress);
    }
    return YandexDownloadVariant._(account, metadata, selection, address,
        size is int && size > 0 ? size : null, bitrate);
  }

  BinaryDownloadAddress _address(Object? value) {
    try {
      if (value is! String || value.length > 16384) _fail();
      final uri = Uri.parse(value);
      // The SDK contract is raw full audio. Preview/crypt/encraw URLs cannot be
      // promoted to a complete song even if an erroneous response says 'raw'.
      if (!uri.path.startsWith('/music-v2/raw/') ||
          uri.pathSegments.any((part) => {
                '.',
                '..',
                'smart_preview',
                'preview',
                'crypt',
                'encraw'
              }.contains(part))) {
        _fail();
      }
      if (_testOrigin case final origin?) {
        if (uri.scheme != origin.scheme ||
            uri.host != origin.host ||
            uri.port != origin.port) {
          _fail();
        }
        return BinaryDownloadAddress.loopbackForTesting(value);
      }
      // Trust this label-bound Yandex domain independently of the response URL.
      // BinaryDownloadAddress additionally rejects credentials, local/IP hosts,
      // fragments, non-HTTPS and nonstandard ports. No redirect or OAuth on CDN.
      if (!uri.host.endsWith('.strm.yandex.net') ||
          uri.host.length <= '.strm.yandex.net'.length) {
        _fail();
      }
      return BinaryDownloadAddress.https(value, trustedHosts: {uri.host});
    } on Object {
      _fail(YandexDownloadFailure.invalidAddress);
    }
  }
}

void _identity(ExternalTrackIdentity identity) {
  if (identity.provider != 'yandex_music') {
    _fail(YandexDownloadFailure.identityMismatch);
  }
  yandexTrackKey(identity.externalId, identity.variantKey);
}

void _trackIdentity(Object? value, ExternalTrackIdentity expected,
    {required bool allowBare}) {
  final text = value is int ? '$value' : value;
  final key = yandexTrackKey(expected.externalId, expected.variantKey);
  if (text != key && !(allowBare && text == expected.externalId)) {
    _fail(YandexDownloadFailure.identityMismatch);
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) _fail();
  return value;
}

String _text(Object? value) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > 1024 ||
      value.runes.any((r) => r < 32 || r == 127)) {
    _fail(YandexDownloadFailure.invalidMetadata);
  }
  return value;
}

String _artists(Object? value) {
  if (value is! List || value.isEmpty || value.length > 64) {
    _fail(YandexDownloadFailure.invalidMetadata);
  }
  return value.map((artist) => _text(_map(artist)['name'])).join('; ');
}

Never _fail(
        [YandexDownloadFailure reason =
            YandexDownloadFailure.invalidResponse]) =>
    throw YandexDownloadException(reason);
