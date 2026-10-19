import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/external_track_ref.dart';
import 'package:clever_music_player/src/library_sync/yandex_audio_selection.dart';
import 'package:clever_music_player/src/library_sync/yandex_audio_decoder.dart';

final yandexDownloadIdentity = ExternalTrackIdentity(
    provider: 'yandex_music', externalId: '001', variantKey: '009');
const yandexFlacSelection = YandexAudioSelection.losslessFlac();
const yandexCoverTemplate =
    'avatars.yandex.net/get-music-content/28589/synthetic.album-1/%%';
final yandexMp3Selection = YandexAudioSelection.lossy(
    quality: YandexFileQuality.hq,
    encoding: YandexFileEncoding.mp3,
    minimumDeclaredKbps: 128,
    minimumMeasuredBitRate: 96000);

List<Object?> yandexDownloadTrack(
        {String id = '001', String album = '009', int durationMs = 3000}) =>
    [
      {
        'id': id,
        'realId': id,
        'type': 'music',
        'available': true,
        'title': 'Provider title',
        'durationMs': durationMs,
        'artists': [
          {'name': 'Artist'}
        ],
        'albums': [
          {
            'id': album,
            'title': 'Album',
            'genre': 'Rock',
            'year': 2026,
            'artists': [
              {'name': 'Album artist'}
            ],
            'trackPosition': {'index': 2, 'volume': 1}
          }
        ],
      }
    ];

Map<String, dynamic> yandexDownloadInfo(
        {String url =
            'https://media.strm.yandex.net/music-v2/raw/synthetic/flac',
        YandexAudioSelection selection = yandexFlacSelection,
        int? size}) =>
    {
      'downloadInfo': {
        'trackId': '001:009',
        'realId': '001',
        'quality': selection.quality.name,
        'codec': selection.encoding.apiKey,
        'transport': 'raw',
        'bitrate': selection.minimumDeclaredKbps ?? 0,
        'url': url,
        'urls': [url],
        if (size != null) 'size': size,
      }
    };

/// Real API+CDN loopback; synthetic credentials/data only. Distinct transports
/// must keep OAuth on API requests even when test origins happen to coincide.
final class YandexDownloadTestServer {
  YandexDownloadTestServer._(this.server, this.source);
  final HttpServer server;
  final File source;
  Uri get origin => Uri.parse('http://127.0.0.1:${server.port}');
  String? encryptedKey;
  String get audioUrl =>
      '$origin/music-v2/${encryptedKey == null ? 'raw' : 'crypt'}/synthetic/audio';
  final requests = <({
    String path,
    String method,
    String body,
    String? authorization,
    String? client,
    String? contentType,
    Uri uri
  })>[];
  YandexAudioSelection selection = yandexFlacSelection;
  List<Object?> metadata = yandexDownloadTrack();
  Future<void> Function(HttpRequest)? onFileInfo;
  Future<void> Function(HttpRequest)? onAudio;
  File? cover;
  Future<void> Function(HttpRequest)? onCover;
  Map<String, dynamic> Function(Map<String, dynamic>)? transformInfo;
  static Future<YandexDownloadTestServer> open(File source) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final result = YandexDownloadTestServer._(server, source);
    server.listen((request) {
      Future<void>.sync(() => result._handle(request))
          .catchError((Object _) {});
    });
    return result;
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    requests.add((
      path: request.uri.path,
      method: request.method,
      body: body,
      authorization: request.headers.value('authorization'),
      client: request.headers.value('x-yandex-music-client'),
      contentType: request.headers.value('content-type'),
      uri: request.uri
    ));
    if (request.uri.path.startsWith('/get-music-content/')) {
      if (onCover != null) return onCover!(request);
      request.response.headers.contentType =
          ContentType('image', cover!.path.endsWith('.png') ? 'png' : 'jpeg');
      request.response.contentLength = await cover!.length();
      await request.response.addStream(cover!.openRead());
      await request.response.close();
      return;
    }
    if (request.uri.path == Uri.parse(audioUrl).path) {
      if (onAudio != null) return onAudio!(request);
      request.response.headers.contentType = ContentType.binary;
      request.response.contentLength = await source.length();
      final input = source.openRead();
      await request.response.addStream(encryptedKey == null
          ? input
          : YandexAudioDecoder('encraw', encryptedKey).decode(input));
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType.json;
    Object? result;
    switch (request.uri.path) {
      case '/account/status':
        result = {
          'account': {'uid': '101'}
        };
      case '/tracks':
        result = metadata;
      case '/get-file-info':
        await onFileInfo?.call(request);
        final value = yandexDownloadInfo(
            url: audioUrl, selection: selection, size: await source.length());
        if (encryptedKey != null) {
          (value['downloadInfo'] as Map)['transport'] = 'encraw';
          (value['downloadInfo'] as Map)['key'] = encryptedKey;
        }
        result = transformInfo?.call(value) ?? value;
      default:
        request.response.statusCode = 404;
    }
    request.response.write(jsonEncode({'result': result}));
    await request.response.close();
  }

  Future<void> close() => server.close(force: true);
}
