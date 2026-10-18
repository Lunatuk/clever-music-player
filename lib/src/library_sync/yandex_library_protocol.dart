import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/models/remote_library.dart';
import '../library/library_scan_control.dart';
import 'yandex_audio_selection.dart';

// Persisted diagnostic indices: append values; do not reorder existing entries.
enum YandexLibraryFailure {
  unauthorized,
  accessDenied,
  notFound,
  rateLimited,
  network,
  timeout,
  invalidResponse,
  incomplete,
  changed,
  accountMismatch,
  tooLarge,
  cancelled,
  storage,
  closed,
  busy,
}

/// Fixed diagnostic phases; connecting includes DNS, TCP and TLS.
enum YandexRequestStage {
  connecting,
  waitingForResponse,
  receivingBody,
  decoding
}

/// Never carries server text, URLs, headers, credentials or raw exceptions.
final class YandexLibraryException implements Exception {
  const YandexLibraryException(this.failure,
      {this.retryAfter, this.stage, this.responseIssue});
  final YandexLibraryFailure failure;
  final Duration? retryAfter;
  final YandexRequestStage? stage;
  final YandexResponseIssue? responseIssue;
  @override
  String toString() => 'YandexLibraryException(${failure.name})';
}

/// Safe catalogue validation codes, never field values. Append only.
enum YandexResponseIssue {
  catalogueList,
  playlistEntry,
  playlistOwner,
  conflictingOwner,
  playlistId,
  savedPlaylistEntry,
}

/// Session-scoped input. Persistence belongs to the future credential owner.
final class YandexAccessToken {
  YandexAccessToken(String value) : _value = value {
    if (value.isEmpty ||
        value.length > 4096 ||
        value.codeUnits.any((unit) => unit <= 32 || unit > 126)) {
      throw ArgumentError('Некорректный токен Яндекс Музыки.');
    }
  }
  final String _value;
  void authorize(void Function(String value) setHeader) =>
      setHeader('OAuth $_value');
  @override
  String toString() => 'YandexAccessToken(<redacted>)';
}

final class YandexAccountProfile {
  const YandexAccountProfile(
      {required this.identity, required this.displayName});
  final RemoteAccountIdentity identity;
  final String? displayName;
}

final class YandexPlaylistDescriptor {
  const YandexPlaylistDescriptor(
      {required this.key, required this.title, required this.itemCount});
  final RemoteCollectionKey key;
  final String title;
  final int? itemCount;
}

enum YandexReadEndpoint {
  account,
  playlists,
  likedTracks,
  playlist,
  likedPlaylists,
  track,
  fileInfo,
}

/// Fixed read endpoints; no arbitrary authenticated URL or remote mutations.
final class YandexReadRequest {
  const YandexReadRequest._(this.endpoint,
      {this.ownerId,
      this.playlistId,
      this.page,
      this.pageSize,
      this.trackKey,
      this.selection,
      this.timestamp});
  factory YandexReadRequest.account() =>
      const YandexReadRequest._(YandexReadEndpoint.account);
  factory YandexReadRequest.playlists(String uid) =>
      YandexReadRequest._(YandexReadEndpoint.playlists,
          ownerId: yandexNumericId(uid));
  factory YandexReadRequest.liked(String uid) =>
      YandexReadRequest._(YandexReadEndpoint.likedTracks,
          ownerId: yandexNumericId(uid));
  factory YandexReadRequest.likedPlaylists(String uid) =>
      YandexReadRequest._(YandexReadEndpoint.likedPlaylists,
          ownerId: yandexNumericId(uid));
  factory YandexReadRequest.playlist(String uid, String kind,
      {int? page, int? pageSize}) {
    if ((page == null) != (pageSize == null) ||
        (page != null &&
            (page < 0 ||
                page > 100000 ||
                pageSize! <= 0 ||
                pageSize > 100000))) {
      throw const YandexLibraryException(YandexLibraryFailure.invalidResponse);
    }
    return YandexReadRequest._(YandexReadEndpoint.playlist,
        ownerId: yandexNumericId(uid),
        playlistId: yandexNumericId(kind),
        page: page,
        pageSize: pageSize);
  }
  factory YandexReadRequest.track(String id, {String album = ''}) =>
      YandexReadRequest._(YandexReadEndpoint.track,
          trackKey: yandexTrackKey(id, album));
  factory YandexReadRequest.fileInfo(String id,
      {String album = '',
      required YandexAudioSelection selection,
      required int timestamp}) {
    if (timestamp <= 0 || timestamp > 9999999999) {
      throw const YandexLibraryException(YandexLibraryFailure.invalidResponse);
    }
    return YandexReadRequest._(YandexReadEndpoint.fileInfo,
        trackKey: yandexTrackKey(id, album),
        selection: selection,
        timestamp: timestamp);
  }
  final YandexReadEndpoint endpoint;
  final String? ownerId, playlistId, trackKey;
  final int? page, pageSize, timestamp;
  final YandexAudioSelection? selection;

  // /tracks is a read-only form POST in the upstream SDK, never an arbitrary
  // authenticated POST. Every other endpoint retains its previous GET.
  bool get usesFormPost => endpoint == YandexReadEndpoint.track;
  String? get formBody => usesFormPost
      ? Uri(queryParameters: {'track-ids': trackKey!, 'with-positions': 'True'})
          .query
      : null;
  String get clientHeader => endpoint == YandexReadEndpoint.fileInfo
      ? 'YandexMusicDesktopAppWindows/5.95.0'
      : 'YandexMusicAndroid/24023621';

  Uri get relativeUri => switch (endpoint) {
        YandexReadEndpoint.account => Uri(path: '/account/status'),
        YandexReadEndpoint.playlists =>
          Uri(path: '/users/$ownerId/playlists/list'),
        YandexReadEndpoint.likedTracks => Uri(
            path: '/users/$ownerId/likes/tracks',
            queryParameters: {'if-modified-since-revision': '0'}),
        YandexReadEndpoint.playlist =>
          Uri(path: '/users/$ownerId/playlists/$playlistId', queryParameters: {
            'richTracks': 'false',
            if (page != null) 'page': '$page',
            if (pageSize != null) 'pageSize': '$pageSize'
          }),
        YandexReadEndpoint.likedPlaylists =>
          Uri(path: '/users/$ownerId/likes/playlists'),
        YandexReadEndpoint.track => Uri(path: '/tracks'),
        YandexReadEndpoint.fileInfo =>
          Uri(path: '/get-file-info', queryParameters: {
            'ts': '$timestamp',
            'trackId': trackKey!,
            'quality': selection!.quality.name,
            'codecs': selection!.encoding.apiKey,
            'transports': 'raw',
            'sign': _fileSignature(),
          }),
      };

  String _fileSignature() {
    // Public desktop protocol constant, not the user's OAuth credential.
    // Pinned upstream sign_request.py: base64 SHA-256, drop ONE '=' padding.
    final message = '$timestamp$trackKey${selection!.quality.name}'
        '${selection!.encoding.apiKey}raw';
    final digest = Hmac(sha256, utf8.encode('kzqU4XhfCaY6B6JTHODeq5'))
        .convert(utf8.encode(message));
    final encoded = base64.encode(digest.bytes);
    return encoded.substring(0, encoded.length - 1);
  }

  @override
  String toString() => 'YandexReadRequest(${endpoint.name}, <redacted>)';
}

String yandexTrackKey(String id, String album) =>
    '${yandexNumericId(id)}${album.isEmpty ? '' : ':${yandexNumericId(album)}'}';

String yandexNumericId(Object? value) {
  final text = value is int && value > 0 ? '$value' : value;
  if (text is! String ||
      RegExp(r'^[0-9]{1,128}$').stringMatch(text) != text ||
      !text.codeUnits.any((unit) => unit != 48)) {
    throw const YandexLibraryException(YandexLibraryFailure.invalidResponse);
  }
  return text;
}

abstract interface class YandexApiTransport {
  /// The decoded result envelope. Must observe cancellation and release sockets.
  Future<Object?> get(YandexReadRequest request, YandexAccessToken token,
      LibraryScanControl control);
  Future<void> close();
}

/// Explicit API reachability check; never reads or attaches a credential.
abstract interface class YandexConnectionProbe {
  Future<void> probe(LibraryScanControl control);
  Future<void> close();
}

abstract interface class YandexLibraryReader {
  YandexAccountProfile? get verifiedAccount;
  Future<YandexAccountProfile> verifyAccount({LibraryScanControl? control});
  Future<List<YandexPlaylistDescriptor>> listPlaylists(
      RemoteAccountIdentity account,
      {LibraryScanControl? control});
  Future<RemoteCollectionSnapshot> readCollection(
      RemoteAccountIdentity account, RemoteCollectionKey key,
      {LibraryScanControl? control});
  Future<void> close();
}
