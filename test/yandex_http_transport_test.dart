import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/yandex_http_transport.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late YandexHttpTransport transport;
  late Future<void> Function(HttpRequest) handler;
  final requests = <HttpRequest>[];
  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handler = (request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'result': {'value': 'Музыка'}
      }));
      await request.response.close();
    };
    server.listen((request) {
      requests.add(request);
      // Expected aborts must not leave server-side unhandled write errors.
      Future<void>.sync(() => handler(request)).catchError((Object _) {});
    });
    transport = YandexHttpTransport.loopbackForTesting(
        Uri.parse('http://127.0.0.1:${server.port}'));
  });
  tearDown(() async {
    await transport.close();
    await server.close(force: true);
  });
  Future<Object?> get({LibraryScanControl? control}) => transport.get(
      YandexReadRequest.account(),
      YandexAccessToken('synthetic-secret'),
      control ?? LibraryScanControl());
  Matcher failure(YandexLibraryFailure value) => throwsA(
      isA<YandexLibraryException>().having((e) => e.failure, 'failure', value));
  Future<void> replace(
      {int limit = 16 * 1024 * 1024,
      Duration timeout = const Duration(seconds: 20),
      DateTime Function()? clock}) async {
    await transport.close();
    transport = YandexHttpTransport.loopbackForTesting(
        Uri.parse('http://127.0.0.1:${server.port}'),
        maxResponseBytes: limit,
        requestTimeout: timeout,
        clock: clock);
  }

  test('real HTTP UTF-8 result, credential only in header, read-only method',
      () async {
    expect(await get(), {'value': 'Музыка'});
    final request = requests.single;
    expect(request.method, 'GET');
    expect(request.uri.toString(), '/account/status');
    expect(request.uri.toString(), isNot(contains('synthetic-secret')));
    expect(request.headers.value('authorization'), 'OAuth synthetic-secret');
    expect(request.headers.value('x-yandex-music-client'),
        'YandexMusicAndroid/24023621');
    expect(await request.drain<List<int>>(<int>[]), isEmpty);
    expect(await get(), {'value': 'Музыка'});
  });
  for (final entry in {
    401: YandexLibraryFailure.unauthorized,
    403: YandexLibraryFailure.accessDenied,
    404: YandexLibraryFailure.notFound,
    429: YandexLibraryFailure.rateLimited,
    500: YandexLibraryFailure.network,
    503: YandexLibraryFailure.network,
    302: YandexLibraryFailure.invalidResponse,
    304: YandexLibraryFailure.incomplete,
    400: YandexLibraryFailure.invalidResponse,
  }.entries) {
    test('HTTP ${entry.key} sanitized, not retried or accepted as empty result',
        () async {
      handler = (request) async {
        request.response.statusCode = entry.key;
        request.response.write('private server message synthetic-secret');
        await request.response.close();
      };
      await expectLater(get(), failure(entry.value));
      expect(requests, hasLength(1));
    });
  }
  test('cross-origin redirect is never followed with the credential', () async {
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var forwarded = false;
    other.listen((request) {
      forwarded = true;
      request.response.close();
    });
    try {
      handler = (request) async {
        request.response.statusCode = 302;
        request.response.headers
            .set('location', 'http://127.0.0.1:${other.port}/steal');
        await request.response.close();
      };
      await expectLater(get(), failure(YandexLibraryFailure.invalidResponse));
      expect(forwarded, isFalse);
    } finally {
      await other.close(force: true);
    }
  });
  for (final body in [
    '{broken',
    '[]',
    '{}',
    '{"result":null}',
    '{"error":{"name":"unknown","message":"synthetic-secret"},"result":[]}'
  ]) {
    test('malformed/unsuccessful JSON envelope rejected: $body', () async {
      handler = (request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(body);
        await request.response.close();
      };
      await expectLater(get(), failure(YandexLibraryFailure.invalidResponse));
    });
  }
  test('API authorization error in HTTP 200 remains authorization failure',
      () async {
    handler = (request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
          '{"error":{"name":"unauthorized","message":"synthetic-secret"}}');
      await request.response.close();
    };
    await expectLater(get(), failure(YandexLibraryFailure.unauthorized));
  });
  test('invalid UTF-8 and HTML are rejected', () async {
    handler = (request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.add([255]);
      await request.response.close();
    };
    await expectLater(get(), failure(YandexLibraryFailure.invalidResponse));
    handler = (request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('{"result":[]}');
      await request.response.close();
    };
    await expectLater(get(), failure(YandexLibraryFailure.invalidResponse));
  });
  test('explicit empty result array is valid', () async {
    handler = (request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"result":[]}');
      await request.response.close();
    };
    expect(await get(), isEmpty);
  });
  test('declared response size bounded before allocation', () async {
    await replace(limit: 10);
    handler = (request) async {
      request.response.headers.contentType = ContentType.json;
      final bytes = utf8.encode('{"result":"${'x' * 100}"}');
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    };
    await expectLater(get(), failure(YandexLibraryFailure.tooLarge));
  });
  test('chunked response bounded without Content-Length', () async {
    await replace(limit: 10);
    await expectLater(get(), failure(YandexLibraryFailure.tooLarge));
  });
  test('gzip decompressed size bounded, compressed length cannot bypass limit',
      () async {
    await replace(limit: 1024);
    handler = (request) async {
      request.response.headers.contentType = ContentType.json;
      final bytes = gzip.encode(utf8.encode('{"result":"${'x' * 32768}"}'));
      request.response.headers.set('content-encoding', 'gzip');
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    };
    await expectLater(get(), failure(YandexLibraryFailure.tooLarge));
  });
  test('large JSON is decoded on worker and remains reusable', () async {
    handler = (request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'result': {'value': 'x' * 300000}
      }));
      await request.response.close();
    };
    final result = await get() as Map<String, dynamic>;
    expect((result['value'] as String).length, 300000);
    expect((await get() as Map)['value'], result['value']);
  });
  test('request timeout aborts a socket waiting for headers', () async {
    await replace(timeout: const Duration(milliseconds: 300));
    final entered = Completer<void>(), release = Completer<void>();
    handler = (request) async {
      entered.complete();
      await release.future;
      await request.response.close();
    };
    final result = get();
    try {
      await entered.future;
      await expectLater(result, failure(YandexLibraryFailure.timeout));
    } finally {
      release.complete();
    }
  });
  test('cancellation aborts an incomplete response body', () async {
    final entered = Completer<void>(), release = Completer<void>();
    handler = (request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"result":"');
      await request.response.flush();
      entered.complete();
      await release.future;
      await request.response.close();
    };
    final control = LibraryScanControl();
    final result = get(control: control);
    try {
      await entered.future;
      control.cancel();
      await expectLater(result, failure(YandexLibraryFailure.cancelled));
    } finally {
      release.complete();
    }
  });
  test('close cancels accepted get and drains a forgotten Future', () async {
    final entered = Completer<void>(), release = Completer<void>();
    handler = (request) async {
      entered.complete();
      await release.future;
      await request.response.close();
    };
    final result = get();
    try {
      await entered.future;
      await expectLater(get(), failure(YandexLibraryFailure.busy));
      await transport.close();
      await expectLater(result, failure(YandexLibraryFailure.cancelled));
      await expectLater(get(), failure(YandexLibraryFailure.closed));
    } finally {
      release.complete();
    }
  });
  test('pre-cancelled request sends no credential and client can be reused',
      () async {
    await expectLater(get(control: LibraryScanControl()..cancel()),
        failure(YandexLibraryFailure.cancelled));
    expect(requests, isEmpty);
    expect(await get(), {'value': 'Музыка'});
  });
  test('Retry-After seconds/date bounded; invalid values ignored', () async {
    final now = DateTime.utc(2030);
    await replace(clock: () => now);
    for (final value in [
      '90',
      '999999',
      HttpDate.format(now.add(const Duration(minutes: 2))),
      'private-invalid'
    ]) {
      handler = (request) async {
        request.response.statusCode = 429;
        request.response.headers.set('retry-after', value);
        await request.response.close();
      };
      try {
        await get();
        fail('Must reject');
      } on YandexLibraryException catch (error) {
        expect(error.failure, YandexLibraryFailure.rateLimited);
        expect(
            error.retryAfter,
            switch (value) {
              '90' => const Duration(seconds: 90),
              '999999' => const Duration(days: 1),
              'private-invalid' => null,
              _ => const Duration(minutes: 2)
            });
      }
    }
  });
  test('connection failure exposes no raw address or token', () async {
    await server.close(force: true);
    try {
      await get();
      fail('Must reject');
    } on YandexLibraryException catch (error) {
      expect(error.toString(), 'YandexLibraryException(network)');
    }
  });
  test('testing origin and ids cannot redirect credentials to arbitrary hosts',
      () {
    for (final origin in [
      'https://example.com',
      'http://example.com',
      'http://localhost',
      'http://user@127.0.0.1',
      'http://127.0.0.1/path',
      'http://127.0.0.1?secret=yes'
    ]) {
      expect(() => YandexHttpTransport.loopbackForTesting(Uri.parse(origin)),
          throwsArgumentError);
    }
    expect(() => YandexReadRequest.playlists('../host'),
        throwsA(isA<YandexLibraryException>()));
    expect(() => YandexAccessToken('secret\r\nInjected: value'),
        throwsArgumentError);
  });
}
