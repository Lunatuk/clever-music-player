import '../domain/models/remote_library.dart';
import '../library/library_scan_control.dart';

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
  likedPlaylists
}

/// Fixed read endpoints; no arbitrary authenticated URL or remote mutations.
final class YandexReadRequest {
  YandexReadRequest.account()
      : endpoint = YandexReadEndpoint.account,
        ownerId = null,
        playlistId = null,
        page = null,
        pageSize = null;
  YandexReadRequest.playlists(String uid)
      : endpoint = YandexReadEndpoint.playlists,
        ownerId = yandexNumericId(uid),
        playlistId = null,
        page = null,
        pageSize = null;
  YandexReadRequest.liked(String uid)
      : endpoint = YandexReadEndpoint.likedTracks,
        ownerId = yandexNumericId(uid),
        playlistId = null,
        page = null,
        pageSize = null;
  YandexReadRequest.likedPlaylists(String uid)
      : endpoint = YandexReadEndpoint.likedPlaylists,
        ownerId = yandexNumericId(uid),
        playlistId = null,
        page = null,
        pageSize = null;
  YandexReadRequest.playlist(String uid, String kind,
      {this.page, this.pageSize})
      : endpoint = YandexReadEndpoint.playlist,
        ownerId = yandexNumericId(uid),
        playlistId = yandexNumericId(kind) {
    if ((page == null) != (pageSize == null) ||
        (page != null &&
            (page! < 0 ||
                page! > 100000 ||
                pageSize! <= 0 ||
                pageSize! > 100000))) {
      throw const YandexLibraryException(YandexLibraryFailure.invalidResponse);
    }
  }
  final YandexReadEndpoint endpoint;
  final String? ownerId, playlistId;
  final int? page, pageSize;
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
      };
}

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
