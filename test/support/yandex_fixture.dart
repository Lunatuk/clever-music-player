import 'package:clever_music_player/src/domain/models/remote_library.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';

final yandexAccount =
    RemoteAccountIdentity(provider: 'yandex_music', accountId: '101');
final yandexLiked = RemoteCollectionKey(kind: RemoteCollectionKind.liked);
final yandexPlaylist = RemoteCollectionKey(
    kind: RemoteCollectionKind.playlist, ownerId: '101', externalId: '1000');
final yandexNow = DateTime.utc(2030);
Map<String, dynamic> yandexStatus({Object? uid = 101}) => {
      'account': {'uid': uid, 'displayName': 'Музыка', 'login': 'listener'},
    };
Map<String, dynamic> yandexTrack(String id, {Object? album = '009'}) =>
    {'id': id, 'albumId': album};
Map<String, dynamic> yandexLikes(
        {List<Object?>? tracks, Object? revision = 1, Object? uid = 101}) =>
    {
      'library': {
        'uid': uid,
        'revision': revision,
        'tracks':
            tracks ?? [yandexTrack('001'), yandexTrack('2'), yandexTrack('001')]
      },
    };
Map<String, dynamic> yandexList(
        {List<Object?>? tracks,
        int count = 3,
        Object? revision = 1,
        Object? uid = 101,
        Object? kind = 1000,
        Map<String, dynamic>? pager}) =>
    {
      'uid': uid,
      'owner': {'uid': uid},
      'kind': kind,
      'title': 'Мой плейлист',
      'trackCount': count,
      'revision': revision,
      'available': true,
      'tracks':
          tracks ?? [yandexTrack('001'), yandexTrack('2'), yandexTrack('001')],
      if (pager != null) 'pager': pager,
    };

final class YandexTestTransport implements YandexApiTransport {
  final requests = <YandexReadRequest>[];
  Future<Object?> Function(YandexReadRequest, LibraryScanControl)? onGet;
  bool closed = false;
  @override
  Future<Object?> get(YandexReadRequest request, YandexAccessToken token,
      LibraryScanControl control) async {
    requests.add(request);
    control.throwIfCancelled();
    if (onGet != null) return onGet!(request, control);
    return switch (request.endpoint) {
      YandexReadEndpoint.account => yandexStatus(),
      YandexReadEndpoint.playlists => [yandexList()],
      YandexReadEndpoint.likedTracks => yandexLikes(),
      YandexReadEndpoint.playlist => yandexList(),
      YandexReadEndpoint.likedPlaylists => [],
      YandexReadEndpoint.track ||
      YandexReadEndpoint.fileInfo =>
        throw StateError('Download fixture required.'),
    };
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
