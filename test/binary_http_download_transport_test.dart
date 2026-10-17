import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/binary_download.dart';
import 'package:clever_music_player/src/library_sync/binary_http_download_transport.dart';
import 'package:clever_music_player/src/library_sync/raw_download_pool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late HttpServer server;
  late RawDownloadPool pool;
  late BinaryHttpDownloadTransport transport;
  late Future<void> Function(HttpRequest) handler;
  final requests = <HttpRequest>[];
  final results = <RawDownloadedAudio>[];
  final gates = <Completer<void>>[];
  Uri getOrigin() => Uri.parse('http://127.0.0.1:${server.port}');
  setUp(() async {
    requests.clear();
    results.clear();
    gates.clear();
    root = await Directory.systemTemp.createTemp('cmp_binary_http_');
    pool = RawDownloadPool(parent: root, maxReservedBytes: 64, maxFiles: 2);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handler = (request) async {
      request.response.headers.contentType = ContentType.binary;
      request.response.contentLength = 3;
      request.response.add([0, 128, 255]);
      await request.response.close();
    };
    server.listen((request) {
      requests.add(request);
      request.response.headers.contentType = ContentType.binary;
      // Aborted requests can make the test server's response fail too.
      Future<void>.sync(() => handler(request)).catchError((Object _) {});
    });
    transport =
        BinaryHttpDownloadTransport.loopbackForTesting(getOrigin(), pool: pool);
  });
  tearDown(() async {
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete();
    }
    await transport.close();
    for (final raw in results) {
      await raw.close();
    }
    await pool.retryFailedCleanup();
    await server.close(force: true);
    await root.delete(recursive: true); // Exclusively this test's root.
  });
  Completer<void> gate() {
    final result = Completer<void>();
    gates.add(result);
    return result;
  }

  Future<RawDownloadedAudio> download(
      {int limit = 32,
      int? expected,
      LibraryScanControl? control,
      void Function(BinaryDownloadProgress)? onProgress}) async {
    final result = await transport.download(
        BinaryDownloadAddress.loopbackForTesting(
            '${getOrigin()}/audio?sign=PRIVATE_SIGNED_LINK'),
        maxBytes: limit,
        expectedBytes: expected,
        control: control,
        onProgress: onProgress);
    results.add(result);
    return result;
  }

  Future<void> replace(
      {Duration timeout = const Duration(minutes: 10),
      Duration idle = const Duration(seconds: 30),
      DiagnosticsService diagnostics = const NoopDiagnosticsService()}) async {
    await transport.close();
    transport = BinaryHttpDownloadTransport.loopbackForTesting(getOrigin(),
        pool: pool,
        timeout: timeout,
        idleTimeout: idle,
        diagnostics: diagnostics);
  }

  test('binary GET streams exact bytes without OAuth, cookies, range or body',
      () async {
    final raw = await download(expected: 3);
    expect(raw.sizeBytes, 3);
    expect(await File(raw.source.path).readAsBytes(), [0, 128, 255]);
    final request = requests.single;
    expect(request.method, 'GET');
    for (final name in [
      'authorization',
      'proxy-authorization',
      'cookie',
      'range',
      'referer',
      'x-yandex-music-client'
    ]) {
      expect(request.headers.value(name), isNull, reason: name);
    }
    expect(request.headers.value('accept-encoding'), 'identity');
    expect(await request.fold<int>(0, (n, chunk) => n + chunk.length), 0);
    expect(pool.reservedBytes, 32);
    expect(raw.source.path, isNot(contains('PRIVATE_SIGNED_LINK')));
  });
  test('server cookies are never reused for another download', () async {
    handler = (request) async {
      request.response.headers.add('set-cookie', 'PRIVATE=secret; Path=/');
      request.response.add([1]);
      await request.response.close();
    };
    final first = await download();
    await first.close();
    await download();
    expect(requests, hasLength(2));
    expect(requests.last.headers.value('cookie'), isNull);
  });
  test('unknown chunked length is bounded and reports completed byte count',
      () async {
    handler = (request) async {
      request.response.headers.contentType = ContentType.binary;
      for (var i = 0; i < 3; i++) {
        request.response.add([i]);
        await request.response.flush();
      }
      await request.response.close();
    };
    final progress = <BinaryDownloadProgress>[];
    final raw = await download(onProgress: progress.add);
    expect(await File(raw.source.path).readAsBytes(), [0, 1, 2]);
    expect(progress.first.receivedBytes, 0);
    expect(progress.last.receivedBytes, 3);
    expect(progress.last.totalBytes, isNull);
  });
  test('a large stream has bounded UI progress and exact binary output',
      () async {
    pool = RawDownloadPool(parent: root, maxReservedBytes: 1024 * 1024);
    await replace();
    handler = (request) async {
      final chunk = List.generate(1024, (i) => i % 256);
      for (var i = 0; i < 1024; i++) {
        request.response.add(chunk);
        await request.response.flush();
      }
      await request.response.close();
    };
    final progress = <BinaryDownloadProgress>[];
    final raw = await download(limit: 1024 * 1024, onProgress: progress.add);
    expect(raw.sizeBytes, 1024 * 1024);
    expect(progress.length, lessThan(128));
    expect(progress.last.receivedBytes, raw.sizeBytes);
    final output = await File(raw.source.path).open();
    try {
      await output.setPosition(1024 * 1024 - 4);
      expect(await output.read(4), [252, 253, 254, 255]);
    } finally {
      await output.close();
    }
  });
  for (final type in [null, 'audio/mpeg', 'audio/mp4', 'audio/flac']) {
    test('opaque audio MIME $type is accepted for later audio validation',
        () async {
      handler = (request) async {
        if (type != null) {
          request.response.headers.set('content-type', type);
        } else {
          request.response.headers.removeAll('content-type');
        }
        request.response.add([1]);
        await request.response.close();
      };
      expect((await download()).sizeBytes, 1);
    });
  }
  for (final type in ['text/html', 'application/json', 'text/xml']) {
    test('HTTP200 $type is not accepted as audio', () async {
      handler = (request) async {
        request.response.headers.set('content-type', type);
        request.response.write('PRIVATE error response');
        await request.response.close();
      };
      await expectLater(
          download(), _throws(BinaryDownloadFailure.invalidResponse));
      expect(pool.reservedBytes, 0);
      expect(await root.list().toList(), isEmpty);
    });
  }
  for (final entry in {
    401: BinaryDownloadFailure.unauthorized,
    403: BinaryDownloadFailure.accessDenied,
    404: BinaryDownloadFailure.notFound,
    429: BinaryDownloadFailure.rateLimited,
    500: BinaryDownloadFailure.network,
    503: BinaryDownloadFailure.network,
    206: BinaryDownloadFailure.invalidResponse,
    302: BinaryDownloadFailure.invalidResponse,
    304: BinaryDownloadFailure.invalidResponse,
    307: BinaryDownloadFailure.invalidResponse,
  }.entries) {
    test('HTTP ${entry.key} is typed, drained, not retried', () async {
      handler = (request) async {
        request.response.statusCode = entry.key;
        request.response.write('PRIVATE error');
        await request.response.close();
      };
      await expectLater(download(), _throws(entry.value));
      expect(requests, hasLength(1));
      expect(pool.reservedBytes, 0);
    });
  }
  test('redirect is never followed, including a second loopback origin',
      () async {
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var forwarded = 0;
    other.listen((request) {
      forwarded++;
      request.response.close();
    });
    try {
      handler = (request) async {
        request.response.statusCode = 302;
        request.response.headers
            .set('location', 'http://127.0.0.1:${other.port}/PRIVATE');
        await request.response.close();
      };
      await expectLater(
          download(), _throws(BinaryDownloadFailure.invalidResponse));
      expect(forwarded, 0);
    } finally {
      await other.close(force: true);
    }
  });
  test('gzip is refused instead of confusing encoded and decoded sizes',
      () async {
    handler = (request) async {
      final bytes = gzip.encode(List.filled(2048, 1));
      request.response.headers.set('content-encoding', 'gzip');
      request.response.headers.contentType = ContentType.binary;
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    };
    await expectLater(
        download(limit: 64), _throws(BinaryDownloadFailure.invalidResponse));
    expect(await root.list().toList(), isEmpty);
  });
  test('range metadata on HTTP200 is rejected', () async {
    handler = (request) async {
      request.response.headers.set('content-range', 'bytes 0-2/100');
      request.response.add([1, 2, 3]);
      await request.response.close();
    };
    await expectLater(
        download(), _throws(BinaryDownloadFailure.invalidResponse));
  });
  test('declared size beyond cap is rejected before creating a raw file',
      () async {
    await expectLater(
        download(limit: 2), _throws(BinaryDownloadFailure.tooLarge));
    expect(pool.reservedBytes, 0);
    expect(await root.list().toList(), isEmpty);
  });
  test('provider size and content length must agree', () async {
    await expectLater(
        download(expected: 4), _throws(BinaryDownloadFailure.incomplete));
    expect(await root.list().toList(), isEmpty);
  });
  test('chunked bytes beyond cap leave no deliverable file', () async {
    handler = (request) async {
      request.response.add(List.filled(33, 1));
      await request.response.close();
    };
    await expectLater(
        download(limit: 32), _throws(BinaryDownloadFailure.tooLarge));
    expect(pool.reservedBytes, 0);
    expect(await root.list().toList(), isEmpty);
  });
  test('chunked short EOF does not satisfy provider size', () async {
    handler = (request) async {
      request.response.add([1]);
      await request.response.close();
    };
    await expectLater(
        download(expected: 3), _throws(BinaryDownloadFailure.incomplete));
    expect(pool.reservedBytes, 0);
  });
  test('truncated declared HTTP body is not delivered', () async {
    handler = (request) async {
      request.response.contentLength = 20;
      final socket = await request.response.detachSocket();
      socket.add([1, 2]);
      await socket.flush();
      socket.destroy();
    };
    await expectLater(download(), _throws(BinaryDownloadFailure.incomplete));
    expect(pool.reservedBytes, 0);
  });
  test('empty HTTP response is incomplete', () async {
    handler = (request) async {
      request.response.contentLength = 0;
      await request.response.close();
    };
    await expectLater(download(), _throws(BinaryDownloadFailure.incomplete));
  });
  test('cancel before connection opens neither socket nor file', () async {
    await expectLater(download(control: LibraryScanControl()..cancel()),
        _throws(BinaryDownloadFailure.cancelled));
    expect(requests, isEmpty);
    expect(pool.reservedBytes, 0);
    expect(await root.list().toList(), isEmpty);
  });
  for (final body in [false, true]) {
    test('${body ? 'body' : 'headers'} idle timeout aborts and frees resources',
        () async {
      final held = gate();
      handler = (request) async {
        if (body) {
          request.response.headers.contentType = ContentType.binary;
          await request.response.flush();
        }
        await held.future;
        request.response.add([1]);
        await request.response.close();
      };
      await replace(idle: const Duration(milliseconds: 50));
      await expectLater(download(), _throws(BinaryDownloadFailure.timeout));
      expect(pool.reservedBytes, 0);
      expect(await root.list().toList(), isEmpty);
    });
  }
  test('overall deadline interrupts a slowly progressing transfer', () async {
    handler = (request) async {
      for (var i = 0; i < 200; i++) {
        request.response.add([i]);
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await request.response.close();
    };
    await replace(timeout: const Duration(milliseconds: 60));
    await expectLater(
        download(limit: 64), _throws(BinaryDownloadFailure.timeout));
    expect(pool.reservedBytes, 0);
  });
  for (final close in [false, true]) {
    test(
        '${close ? 'close' : 'cancel'} while awaiting headers drains the request',
        () async {
      final held = gate();
      handler = (request) async {
        await held.future;
        request.response.add([1]);
        await request.response.close();
      };
      final control = LibraryScanControl();
      final downloading = download(control: control);
      final failed =
          expectLater(downloading, _throws(BinaryDownloadFailure.cancelled));
      await _until(() => requests.isNotEmpty);
      if (close) {
        final closing = transport.close();
        expect(identical(closing, transport.close()), isTrue);
        await closing;
      } else {
        control.cancel();
      }
      await failed;
      expect(pool.reservedBytes, 0);
      expect(await root.list().toList(), isEmpty);
    });
  }
  test('busy does not open a second connection or reserve a second file',
      () async {
    final held = gate();
    handler = (request) async {
      await held.future;
      request.response.add([1]);
      await request.response.close();
    };
    final first = download();
    await _until(() => requests.isNotEmpty);
    await expectLater(download(), _throws(BinaryDownloadFailure.busy));
    expect(pool.reservedBytes, 32);
    held.complete();
    await first;
    expect(requests, hasLength(1));
  });
  test('quota admission rejects before making any request', () async {
    final held = pool.reserve(64);
    try {
      await expectLater(
          download(), _throws(BinaryDownloadFailure.quotaExceeded));
      expect(requests, isEmpty);
    } finally {
      await held.close();
    }
  });
  test('close retains the delivered file for its metadata reader', () async {
    final raw = await download();
    await transport.close();
    expect(await File(raw.source.path).readAsBytes(), [0, 128, 255]);
    await expectLater(download(), _throws(BinaryDownloadFailure.closed));
  });
  test('failed cleanup keeps quota, preserves unknown files and supports retry',
      () async {
    File? unknown;
    final control = LibraryScanControl();
    await expectLater(
        download(
            control: control,
            onProgress: (_) {
              final owned = root.listSync().whereType<Directory>().single;
              unknown = File(p.join(owned.path, 'keep.txt'))
                ..writeAsStringSync('preserve');
              control.cancel();
            }),
        _throws(BinaryDownloadFailure.storage));
    expect(pool.reservedBytes, 32);
    expect(await unknown!.readAsString(), 'preserve');
    await unknown!.delete(); // Exclusively the test-created unknown file.
    await pool.retryFailedCleanup();
    expect(pool.reservedBytes, 0);
    expect(await root.list().toList(), isEmpty);
  });
  test('closing from initial progress cancels without a late file or deadlock',
      () async {
    Future<void>? closing;
    await expectLater(
        download(onProgress: (_) => closing ??= transport.close()),
        _throws(BinaryDownloadFailure.cancelled));
    await closing;
    expect(pool.reservedBytes, 0);
    expect(await root.list().toList(), isEmpty);
  });
  test('close from diagnostics still drains an already registered operation',
      () async {
    Future<void>? closing;
    await replace(diagnostics: _ReentrantDiagnostics(() {
      closing ??= transport.close();
    }));
    await expectLater(download(), _throws(BinaryDownloadFailure.cancelled));
    await closing;
    expect(requests, isEmpty);
    expect(pool.reservedBytes, 0);
  });
  test('release report excludes signed URL, filesystem paths and server text',
      () async {
    final directory =
        await Directory(p.join(root.path, 'diagnostics')).create();
    final diagnostics =
        LocalDiagnosticsService(directoryProvider: () async => directory);
    await replace(diagnostics: diagnostics);
    final raw = await download();
    await raw.close();
    handler = (request) async {
      request.response.statusCode = 403;
      request.response.write('PRIVATE server account token and track title');
      await request.response.close();
    };
    await expectLater(download(), _throws(BinaryDownloadFailure.accessDenied));
    final report = await (await diagnostics.exportReport()).readAsString();
    expect(report, contains('downloadTransferCompleted'));
    expect(report, contains('downloadTransferFailed'));
    expect(report, isNot(contains('PRIVATE')));
    expect(report, isNot(contains(root.path)));
    expect(report, isNot(contains('${getOrigin()}')));
    final events = (jsonDecode(report) as Map)['events'] as List;
    expect(events.last['httpStatus'], 403);
    expect(events.last['transferFailure'],
        BinaryDownloadFailure.accessDenied.index);
    await diagnostics.flush();
  });
}

Matcher _throws(BinaryDownloadFailure value) => throwsA(
    isA<BinaryDownloadException>().having((e) => e.failure, 'failure', value));

Future<void> _until(bool Function() predicate) async {
  final watch = Stopwatch()..start();
  while (!predicate()) {
    if (watch.elapsed > const Duration(seconds: 3)) {
      fail('Request did not arrive');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

final class _ReentrantDiagnostics extends Fake implements DiagnosticsService {
  _ReentrantDiagnostics(this.onStart);
  final void Function() onStart;
  @override
  void record(DiagnosticEvent event,
      {Map<DiagnosticField, Object?> fields = const {}, Object? error}) {
    if (event == DiagnosticEvent.downloadTransferStarted) onStart();
  }
}
