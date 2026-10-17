import 'dart:io';

import 'package:clever_music_player/src/library_sync/binary_http_download_transport.dart';

/// Real loopback HTTP, repository-created synthetic bytes only; no OAuth/API.
final class TestBinaryDownloadServer {
  TestBinaryDownloadServer._(this._server);
  final HttpServer _server;
  Uri get origin => Uri.parse('http://127.0.0.1:${_server.port}');
  BinaryDownloadAddress get address =>
      BinaryDownloadAddress.loopbackForTesting('$origin/audio');
  static Future<TestBinaryDownloadServer> open(File source) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      Future<void>(() async {
        request.response.headers.contentType = ContentType.binary;
        request.response.contentLength = await source.length();
        await request.response.addStream(source.openRead());
        await request.response.close();
      }).catchError((Object _) {});
    });
    return TestBinaryDownloadServer._(server);
  }

  Future<void> close() => _server.close(force: true);
}
