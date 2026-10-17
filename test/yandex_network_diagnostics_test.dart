import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/yandex_http_transport.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/recording_diagnostics.dart';

void main() {
  late HttpServer server;
  late YandexHttpTransport transport;
  late RecordingDiagnostics diagnostics;
  late Future<void> Function(HttpRequest) handler;
  final requests = <HttpRequest>[];
  setUp(() async {
    requests.clear();
    diagnostics = RecordingDiagnostics();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handler = (request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"result":{"value":"ok"}}');
      await request.response.close();
    };
    server.listen((request) {
      requests.add(request);
      Future<void>.sync(() => handler(request)).catchError((Object _) {});
    });
    transport = YandexHttpTransport.loopbackForTesting(
        Uri.parse('http://127.0.0.1:${server.port}'),
        diagnostics: diagnostics);
  });
  tearDown(() async {
    await transport.close();
    await server.close(force: true);
  });
  Future<Object?> get() => transport.get(YandexReadRequest.account(),
      YandexAccessToken('synthetic-secret'), LibraryScanControl());
  Matcher failure(YandexLibraryFailure value, [YandexRequestStage? stage]) =>
      throwsA(isA<YandexLibraryException>()
          .having((e) => e.failure, 'failure', value)
          .having((e) => e.stage, 'stage', stage ?? isNotNull));
  Future<void> shortTimeout() async {
    await transport.close();
    transport = YandexHttpTransport.loopbackForTesting(
        Uri.parse('http://127.0.0.1:${server.port}'),
        diagnostics: diagnostics,
        requestTimeout: const Duration(milliseconds: 300));
  }

  test('successful request diagnostics contain fixed codes and measurements',
      () async {
    await get();
    expect(diagnostics.entries.map((e) => e.event), [
      DiagnosticEvent.yandexRequestStarted,
      DiagnosticEvent.yandexRequestCompleted
    ]);
    final fields = diagnostics.entries.last.fields;
    expect(fields[DiagnosticField.remoteEndpoint],
        YandexReadEndpoint.account.index);
    expect(fields[DiagnosticField.httpStatus], 200);
    expect(
        fields[DiagnosticField.remoteStage], YandexRequestStage.decoding.index);
    expect(fields[DiagnosticField.credentialAttached], isTrue);
    expect(fields[DiagnosticField.responseBytes], greaterThan(0));
    expect(fields[DiagnosticField.elapsedMs], isNonNegative);
    expect(fields.values.every((v) => v is num || v is bool), isTrue);
    expect(fields.toString(), isNot(contains('synthetic-secret')));
  });
  test('public status probe never attaches a credential', () async {
    await transport.probe(LibraryScanControl());
    expect(requests.single.headers.value('authorization'), isNull);
    expect(requests.single.uri.path, '/account/status');
    expect(diagnostics.entries.last.fields[DiagnosticField.credentialAttached],
        isFalse);
    expect(
        diagnostics.entries.last.event, DiagnosticEvent.yandexRequestCompleted);
  });
  test('401 proves probe reachability but rejects authenticated requests',
      () async {
    handler = (r) async {
      r.response.statusCode = 401;
      await r.response.close();
    };
    await transport.probe(LibraryScanControl());
    expect(requests.single.headers.value('authorization'), isNull);
    expect(diagnostics.entries.last.fields[DiagnosticField.httpStatus], 401);
    await expectLater(get(), failure(YandexLibraryFailure.unauthorized));
  });
  test('unauthorized API envelope proves reachability only for a probe',
      () async {
    handler = (r) async {
      r.response.headers.contentType = ContentType.json;
      r.response.write(
          '{"error":{"name":"unauthorized","message":"private-secret"}}');
      await r.response.close();
    };
    await transport.probe(LibraryScanControl());
    await expectLater(get(), failure(YandexLibraryFailure.unauthorized));
    expect(diagnostics.entries.toString(), isNot(contains('private-secret')));
  });
  test('redirect is rejected by probe without forwarding', () async {
    handler = (r) async {
      r.response.statusCode = 302;
      r.response.headers.set('location', 'https://private.invalid/');
      await r.response.close();
    };
    await expectLater(transport.probe(LibraryScanControl()),
        failure(YandexLibraryFailure.invalidResponse));
    expect(requests, hasLength(1));
    expect(diagnostics.entries.last.event, DiagnosticEvent.yandexRequestFailed);
  });
  test('header timeout is distinguished from connection failure', () async {
    await shortTimeout();
    final release = Completer<void>();
    handler = (r) async {
      await release.future;
      await r.response.close();
    };
    try {
      await expectLater(
          get(),
          failure(YandexLibraryFailure.timeout,
              YandexRequestStage.waitingForResponse));
      expect(diagnostics.entries.last.fields[DiagnosticField.remoteStage],
          YandexRequestStage.waitingForResponse.index);
      expect(
          diagnostics.entries.last.fields
              .containsKey(DiagnosticField.httpStatus),
          isFalse);
    } finally {
      release.complete();
    }
  });
  test('incomplete body timeout records received bytes and response phase',
      () async {
    await shortTimeout();
    final release = Completer<void>();
    handler = (r) async {
      r.response.headers.contentType = ContentType.json;
      r.response.bufferOutput = false;
      r.response.write('{"result":"${'x' * 8192}');
      await r.response.flush();
      await release.future;
      await r.response.close();
    };
    try {
      await expectLater(
          get(),
          failure(
              YandexLibraryFailure.timeout, YandexRequestStage.receivingBody));
      final fields = diagnostics.entries.last.fields;
      expect(fields[DiagnosticField.httpStatus], 200);
      expect(fields[DiagnosticField.responseBytes], greaterThan(0));
      expect(fields[DiagnosticField.remoteFailure],
          YandexLibraryFailure.timeout.index);
    } finally {
      release.complete();
    }
  });
  test('invalid JSON records decode phase without raw body', () async {
    handler = (r) async {
      r.response.headers.contentType = ContentType.json;
      r.response.write('{synthetic-secret');
      await r.response.close();
    };
    await expectLater(
        get(),
        failure(
            YandexLibraryFailure.invalidResponse, YandexRequestStage.decoding));
    expect(diagnostics.entries.toString(), isNot(contains('synthetic-secret')));
  });
  test('closed local port records connect phase and numeric OS error',
      () async {
    await server.close(force: true);
    await expectLater(get(),
        failure(YandexLibraryFailure.network, YandexRequestStage.connecting));
    final fields = diagnostics.entries.last.fields;
    expect(fields[DiagnosticField.networkErrorCode], isA<int>());
    expect(fields[DiagnosticField.credentialAttached], isFalse);
    expect(fields.values.every((v) => v is num || v is bool), isTrue);
  });
  test(
      'export retains network events without token, URI, UID, title or server text',
      () async {
    final root = await Directory.systemTemp.createTemp('cmp_network_report_');
    final local = LocalDiagnosticsService(directoryProvider: () async => root);
    await transport.close();
    transport = YandexHttpTransport.loopbackForTesting(
        Uri.parse('http://127.0.0.1:${server.port}'),
        diagnostics: local);
    handler = (r) async {
      r.response.statusCode = 401;
      r.response.write('PRIVATE_UID_TITLE_SERVER_ERROR_synthetic-secret');
      await r.response.close();
    };
    try {
      await expectLater(get(), failure(YandexLibraryFailure.unauthorized));
      final text = await (await local.exportReport()).readAsString();
      final events = (jsonDecode(text) as Map)['events'] as List;
      expect(events.map((e) => e['event']),
          ['yandexRequestStarted', 'yandexRequestFailed']);
      expect(events.last['httpStatus'], 401);
      expect(
          events.last['remoteStage'], YandexRequestStage.receivingBody.index);
      for (final secret in [
        'synthetic-secret',
        'PRIVATE_UID_TITLE_SERVER_ERROR',
        '127.0.0.1',
        '/account/status',
        root.path
      ]) {
        expect(text, isNot(contains(secret)));
      }
    } finally {
      await local.flush();
      await root.delete(recursive: true);
    } // Exclusively our fixture.
  });
}
