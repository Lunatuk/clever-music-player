import 'dart:async';
import 'dart:math';

import '../domain/models/external_track_ref.dart';
import '../diagnostics/diagnostics_service.dart';
import '../domain/models/remote_library.dart';
import '../library/library_scan_control.dart';
import 'yandex_audio_selection.dart';
import 'yandex_download_protocol.dart';
import 'yandex_http_transport.dart';
import 'yandex_library_protocol.dart';

final class YandexLibraryLimits {
  YandexLibraryLimits(
      {this.maxItems = RemoteCollectionSnapshot.maxItems,
      this.maxPlaylists = 2000,
      this.maxPages = 256,
      this.operationTimeout = const Duration(minutes: 5)}) {
    if (maxItems <= 0 ||
        maxItems > RemoteCollectionSnapshot.maxItems ||
        maxPlaylists <= 0 ||
        maxPlaylists > 10000 ||
        maxPages <= 0 ||
        maxPages > 512 ||
        operationTimeout <= Duration.zero ||
        operationTimeout > const Duration(minutes: 10)) {
      throw ArgumentError('Некорректные пределы чтения фонотеки.');
    }
  }
  final int maxItems, maxPlaylists, maxPages;
  final Duration operationTimeout;
}

/// One credential session, one operation at a time. No startup work or writes
/// to Yandex. Complete lists are observed twice before declaring a snapshot.
final class YandexLibraryClient
    implements YandexLibraryReader, YandexDownloadSessionReader {
  YandexLibraryClient(
      {required YandexAccessToken token,
      YandexApiTransport? transport,
      YandexLibraryLimits? limits,
      YandexDownloadParser downloadParser = const YandexDownloadParser(),
      this.diagnostics = const NoopDiagnosticsService(),
      DateTime Function()? clock})
      : _token = token,
        _transport = transport ?? YandexHttpTransport(),
        _limits = limits ?? YandexLibraryLimits(),
        _downloadParser = downloadParser,
        _clock = clock ?? DateTime.now;
  final YandexAccessToken _token;
  final DiagnosticsService diagnostics;
  final YandexApiTransport _transport;
  final YandexLibraryLimits _limits;
  final YandexDownloadParser _downloadParser;
  final DateTime Function() _clock;
  YandexAccountProfile? _profile;
  LibraryScanControl? _control;
  Future<Object?>? _active;
  Future<void>? _closing;
  bool _closed = false;
  @override
  YandexAccountProfile? get verifiedAccount => _profile;

  Future<T> _run<T extends Object>(
      Future<T> Function(LibraryScanControl) action,
      LibraryScanControl? external) {
    if (_closed || _active != null) {
      return Future.error(YandexLibraryException(
          _closed ? YandexLibraryFailure.closed : YandexLibraryFailure.busy));
    }
    final control = LibraryScanControl();
    _control = control;
    external?.addCancellationListener(control.cancel);
    var timedOut = false;
    final timer = Timer(_limits.operationTimeout, () {
      timedOut = true;
      control.cancel();
    });
    final accepted = () async {
      try {
        control.throwIfCancelled();
        final result = await action(control);
        control.throwIfCancelled();
        return result;
      } on Object catch (error) {
        if (timedOut) {
          throw const YandexLibraryException(YandexLibraryFailure.timeout);
        }
        if (control.isCancellationRequested) {
          throw const YandexLibraryException(YandexLibraryFailure.cancelled);
        }
        if (error is YandexLibraryException ||
            error is YandexDownloadException) {
          rethrow;
        }
        throw YandexLibraryException(error is FormatException ||
                error is TypeError ||
                error is ArgumentError
            ? YandexLibraryFailure.invalidResponse
            : YandexLibraryFailure.network);
      } finally {
        timer.cancel();
        external?.removeCancellationListener(control.cancel);
      }
    }();
    final operation = accepted.whenComplete(() {
      _control = null;
      _active = null;
    });
    operation.ignore();
    _active = operation;
    return operation;
  }

  Future<Object?> _get(
      YandexReadRequest request, LibraryScanControl control) async {
    control.throwIfCancelled();
    final result = await _transport.get(request, _token, control);
    control.throwIfCancelled();
    return result;
  }

  @override
  Future<YandexAccountProfile> verifyAccount({LibraryScanControl? control}) {
    final previous = _profile;
    return _run((token) async {
      _profile = null;
      final result = _map(await _get(YandexReadRequest.account(), token));
      final account = _map(result['account']);
      final uid = yandexNumericId(account['uid']);
      final profile = YandexAccountProfile(
          identity:
              RemoteAccountIdentity(provider: 'yandex_music', accountId: uid),
          displayName: _displayName(account));
      if (previous != null && previous.identity != profile.identity) {
        throw const YandexLibraryException(
            YandexLibraryFailure.accountMismatch);
      }
      return profile;
    }, control)
        .then((profile) {
      _profile = profile;
      return profile;
    });
  }

  String _account(RemoteAccountIdentity expected) {
    if (_profile == null ||
        _profile!.identity != expected ||
        expected.provider != 'yandex_music') {
      throw const YandexLibraryException(YandexLibraryFailure.accountMismatch);
    }
    return yandexNumericId(expected.accountId);
  }

  @override
  Future<YandexDownloadVariant> resolveDownload(RemoteAccountIdentity account,
          ExternalTrackIdentity identity, YandexAudioSelection selection,
          {LibraryScanControl? control}) =>
      _run((token) async {
        _account(account);
        if (identity.provider != 'yandex_music') {
          throw const YandexDownloadException(
              YandexDownloadFailure.identityMismatch);
        }
        final metadata = _downloadParser.metadata(
            await _get(
                YandexReadRequest.track(identity.externalId,
                    album: identity.variantKey),
                token),
            identity);
        final result = await _get(
            YandexReadRequest.fileInfo(identity.externalId,
                album: identity.variantKey,
                selection: selection,
                timestamp: _clock().toUtc().millisecondsSinceEpoch ~/ 1000),
            token);
        _account(account);
        final info = result is Map ? result['downloadInfo'] : null;
        int known(List<String> choices, Object? value) =>
            value is String ? choices.indexOf(value) : -1;
        final fields = <DiagnosticField, Object?>{
          DiagnosticField.requestedQuality: selection.quality.index,
          DiagnosticField.requestedEncoding: selection.encoding.index,
          if (info is Map) ...{
            DiagnosticField.returnedQuality:
                known(const ['lossless', 'hq', 'nq'], info['quality']),
            DiagnosticField.returnedEncoding: known(const [
              'flac',
              'mp3',
              'aac-mp4',
              'flac-mp4',
              'he-aac-mp4',
              'aac',
              'he-aac'
            ], info['codec']),
            DiagnosticField.returnedTransport:
                known(const ['raw', 'encraw'], info['transport']),
            if (info['bitrate'] is int &&
                info['bitrate'] >= 0 &&
                info['bitrate'] <= 10000)
              DiagnosticField.returnedBitrate: info['bitrate'],
          },
        };
        try {
          final variant =
              _downloadParser.variant(result, account, metadata, selection);
          _recordDownload(DiagnosticEvent.yandexDownloadResolved, fields);
          return variant;
        } on YandexDownloadException catch (error) {
          _recordDownload(DiagnosticEvent.yandexDownloadRejected, {
            ...fields,
            DiagnosticField.downloadFailure: error.failure.index
          });
          rethrow;
        }
      }, control);

  void _recordDownload(
      DiagnosticEvent event, Map<DiagnosticField, Object?> fields) {
    try {
      diagnostics.record(event, fields: fields);
    } on Object {/* Diagnostics cannot change download ownership or outcome. */}
  }

  @override
  Future<List<YandexPlaylistDescriptor>> listPlaylists(
          RemoteAccountIdentity account,
          {LibraryScanControl? control}) =>
      _run((token) async {
        final uid = _account(account);
        final descriptors = <RemoteCollectionKey, YandexPlaylistDescriptor>{};
        void append(Object? response, {required bool saved}) {
          if (response is! List) {
            _catalogueInvalid(YandexResponseIssue.catalogueList);
          }
          if (response.length > _limits.maxPlaylists) _tooLarge();
          for (final value in response) {
            token.throwIfCancelled();
            if (value is! Map<String, dynamic>) {
              _catalogueInvalid(YandexResponseIssue.playlistEntry);
            }
            if (saved && value['type'] != null && value['type'] != 'playlist') {
              _catalogueInvalid(YandexResponseIssue.savedPlaylistEntry);
            }
            final Object? data = saved ? value['playlist'] : value;
            if (data is! Map<String, dynamic>) {
              _catalogueInvalid(YandexResponseIssue.savedPlaylistEntry);
            }
            final owner = _catalogueOwner(data, fallback: saved ? null : uid);
            final kind =
                _catalogueId(data['kind'], YandexResponseIssue.playlistId);
            final key = RemoteCollectionKey(
                kind: RemoteCollectionKind.playlist,
                ownerId: owner,
                externalId: kind);
            // A repeated catalogue identity is one selectable resource. Ordered
            // track positions are never deduplicated by this operation.
            descriptors.putIfAbsent(
                key,
                () => YandexPlaylistDescriptor(
                    key: key,
                    title: _catalogueTitle(data['title']),
                    itemCount: data['trackCount'] is int &&
                            (data['trackCount'] as int) >= 0
                        ? data['trackCount'] as int
                        : null));
            if (descriptors.length > _limits.maxPlaylists) _tooLarge();
          }
        }

        append(await _get(YandexReadRequest.playlists(uid), token),
            saved: false);
        append(await _get(YandexReadRequest.likedPlaylists(uid), token),
            saved: true);
        return List.unmodifiable(descriptors.values);
      }, control);

  @override
  Future<RemoteCollectionSnapshot> readCollection(
          RemoteAccountIdentity account, RemoteCollectionKey key,
          {LibraryScanControl? control}) =>
      _run((token) async {
        final uid = _account(account);
        Future<_Pass> read() => key.kind == RemoteCollectionKind.liked
            ? _liked(uid, token)
            : _playlist(uid, key, token);
        final first = await read();
        final second = await read();
        if (first.revision != second.revision ||
            first.items.length != second.items.length ||
            first.items.indexed
                .any((item) => item.$2 != second.items[item.$1])) {
          throw const YandexLibraryException(YandexLibraryFailure.changed);
        }
        return RemoteCollectionSnapshot(
            items: second.items,
            isComplete: true,
            expectedItemCount: second.items.length,
            completedAt: _clock(),
            revisionAtStart: first.revision,
            revisionAtEnd: second.revision);
      }, control);

  Future<_Pass> _liked(String uid, LibraryScanControl control) async {
    final result = _map(await _get(YandexReadRequest.liked(uid), control));
    final library = _map(result['library']);
    if (yandexNumericId(library['uid']) != uid) {
      throw const YandexLibraryException(YandexLibraryFailure.accountMismatch);
    }
    final revision = _revision(library['revision']);
    if (revision == null) _invalid();
    final items = _tracks(library['tracks']);
    if ((library['trackCount'] != null &&
            _count(library['trackCount']) != items.length) ||
        library['hasMore'] == true ||
        library['truncated'] == true ||
        library['isComplete'] == false) {
      throw const YandexLibraryException(YandexLibraryFailure.incomplete);
    }
    if (library['pager'] != null) {
      final pager = _pager(library['pager']);
      if (pager.page > 1 ||
          pager.total != items.length ||
          pager.perPage < items.length) {
        throw const YandexLibraryException(YandexLibraryFailure.incomplete);
      }
    }
    return _Pass(items, revision);
  }

  Future<_Pass> _playlist(
      String uid, RemoteCollectionKey key, LibraryScanControl control) async {
    final owner = key.ownerId.isEmpty ? uid : yandexNumericId(key.ownerId);
    final kind = yandexNumericId(key.externalId);
    final first =
        _map(await _get(YandexReadRequest.playlist(owner, kind), control));
    _playlistIdentity(first, owner, kind);
    final count = _count(first['trackCount']);
    final revision = _revision(first['revision']);
    final items = _tracks(first['tracks']).toList();
    final initial = first['pager'] == null ? null : _pager(first['pager']);
    if (first['truncated'] == true ||
        first['isComplete'] == false ||
        items.length > count) {
      throw const YandexLibraryException(YandexLibraryFailure.incomplete);
    }
    if (initial == null) {
      if (items.length != count || first['hasMore'] == true) {
        throw const YandexLibraryException(YandexLibraryFailure.incomplete);
      }
    } else {
      if (initial.page > 1 ||
          initial.total != count ||
          items.length != min(initial.perPage, count)) {
        throw const YandexLibraryException(YandexLibraryFailure.incomplete);
      }
      final pages = max(1, (count + initial.perPage - 1) ~/ initial.perPage);
      if (pages > _limits.maxPages) _tooLarge();
      for (var offset = 1; offset < pages; offset++) {
        final page = initial.page + offset;
        final map = _map(await _get(
            YandexReadRequest.playlist(owner, kind,
                page: page, pageSize: initial.perPage),
            control));
        _playlistIdentity(map, owner, kind);
        if (_count(map['trackCount']) != count ||
            _revision(map['revision']) != revision) {
          throw const YandexLibraryException(YandexLibraryFailure.changed);
        }
        final pager = _pager(map['pager']);
        if (pager.page != page ||
            pager.total != count ||
            pager.perPage != initial.perPage) {
          throw const YandexLibraryException(YandexLibraryFailure.incomplete);
        }
        final tracks = _tracks(map['tracks']);
        if (tracks.length != min(initial.perPage, count - items.length) ||
            (map['hasMore'] == true && items.length + tracks.length >= count) ||
            map['truncated'] == true ||
            map['isComplete'] == false) {
          throw const YandexLibraryException(YandexLibraryFailure.incomplete);
        }
        items.addAll(tracks);
      }
    }
    if (items.length != count ||
        (initial != null &&
            count <= initial.perPage &&
            first['hasMore'] == true)) {
      throw const YandexLibraryException(YandexLibraryFailure.incomplete);
    }
    return _Pass(List.unmodifiable(items), revision);
  }

  void _playlistIdentity(Map<String, dynamic> map, String owner, String kind) {
    if (_owner(map) != owner) {
      throw const YandexLibraryException(YandexLibraryFailure.accountMismatch);
    }
    if (yandexNumericId(map['kind']) != kind) _invalid();
    if (map['available'] == false || map['playlistAbsence'] != null) {
      throw const YandexLibraryException(YandexLibraryFailure.accessDenied);
    }
  }

  String _owner(Map<String, dynamic> map) {
    final nested = map['owner'] == null ? null : _map(map['owner'])['uid'];
    final uid = yandexNumericId(map['uid'] ?? nested);
    if (nested != null && yandexNumericId(nested) != uid) _invalid();
    return uid;
  }

  int _count(Object? value) {
    final number = _number(value);
    if (number > _limits.maxItems) _tooLarge();
    return number;
  }

  _Pager _pager(Object? value) {
    final map = _map(value);
    final page = _number(map['page']);
    final perPage = _number(map['perPage']);
    if (perPage <= 0 || perPage > RemoteCollectionSnapshot.maxItems) _invalid();
    return _Pager(page, perPage, _count(map['total']));
  }

  List<ExternalTrackIdentity> _tracks(Object? value) {
    final values = _list(value);
    if (values.length > _limits.maxItems) _tooLarge();
    return List.unmodifiable(values.map((value) {
      final track = _map(value);
      final id = _trackId(track['id']);
      final album = track['albumId'];
      final variant =
          album == null || album == '' ? '' : yandexNumericId(album);
      final nested = track['track'];
      if (nested != null && _trackId(_map(nested)['id']) != id) _invalid();
      return ExternalTrackIdentity(
          provider: 'yandex_music', externalId: id, variantKey: variant);
    }));
  }

  @override
  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _drain();
  }

  Future<void> _drain() async {
    try {
      await _active;
    } on Object {/* Reported by the operation. */} finally {
      await _transport.close();
    }
  }
}

final class _Pass {
  const _Pass(this.items, this.revision);
  final List<ExternalTrackIdentity> items;
  final String? revision;
}

final class _Pager {
  const _Pager(this.page, this.perPage, this.total);
  final int page, perPage, total;
}

Never _invalid() =>
    throw const YandexLibraryException(YandexLibraryFailure.invalidResponse);
Never _tooLarge() =>
    throw const YandexLibraryException(YandexLibraryFailure.tooLarge);
Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : _invalid();
List<dynamic> _list(Object? value) => value is List ? value : _invalid();
int _number(Object? value) => value is int && value >= 0 ? value : _invalid();
String _text(Object? value) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > 512 ||
      value.runes.any((rune) => rune < 32 || rune == 127)) {
    _invalid();
  }
  return value;
}

String? _optionalText(Object? value) => value == null ? null : _text(value);
String? _displayName(Map<String, dynamic> account) {
  for (final field in ['displayName', 'firstName', 'login']) {
    final value = account[field];
    if (value == null || (value is String && value.trim().isEmpty)) continue;
    return _text(value);
  }
  return null;
}

String? _revision(Object? value) =>
    value is int ? '${_number(value)}' : _optionalText(value);
String _trackId(Object? value) {
  final text = value is int && value > 0 ? '$value' : value;
  if (text is! String ||
      RegExp(r'^[A-Za-z0-9._-]{1,512}$').stringMatch(text) != text) {
    _invalid();
  }
  return text;
}

Never _catalogueInvalid(YandexResponseIssue issue) =>
    throw YandexLibraryException(YandexLibraryFailure.invalidResponse,
        responseIssue: issue);

String _catalogueId(Object? value, YandexResponseIssue issue) {
  try {
    return yandexNumericId(value);
  } on YandexLibraryException {
    _catalogueInvalid(issue);
  }
}

String _catalogueOwner(Map<String, dynamic> map, {String? fallback}) {
  final owner = map['owner'];
  if (owner != null && owner is! Map<String, dynamic>) {
    _catalogueInvalid(YandexResponseIssue.playlistOwner);
  }
  final nested = owner == null ? null : (owner as Map<String, dynamic>)['uid'];
  if (map['uid'] == null && nested == null) {
    if (fallback != null) {
      return fallback; // Explicit own-catalogue request scope.
    }
    _catalogueInvalid(YandexResponseIssue.playlistOwner);
  }
  final uid =
      _catalogueId(map['uid'] ?? nested, YandexResponseIssue.playlistOwner);
  if (nested != null &&
      _catalogueId(nested, YandexResponseIssue.playlistOwner) != uid) {
    _catalogueInvalid(YandexResponseIssue.conflictingOwner);
  }
  return uid;
}

String _catalogueTitle(Object? value) {
  if (value is! String) return 'Плейлист без названия';
  // Presentation only: bound work even when a remote name fills the whole body.
  final preview = String.fromCharCodes(value.runes.take(2048));
  final text = preview
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isEmpty) return 'Плейлист без названия';
  final bounded = StringBuffer();
  for (final rune in text.runes) {
    if (bounded.length + (rune > 0xffff ? 2 : 1) > 512) break;
    bounded.writeCharCode(rune);
  }
  return bounded.toString();
}
