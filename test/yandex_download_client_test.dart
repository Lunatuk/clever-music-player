import 'dart:async';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';

import 'package:clever_music_player/src/domain/models/remote_library.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_client.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/yandex_download_fixture.dart';
import 'support/yandex_fixture.dart';

void main() {
  late YandexTestTransport transport;
  late YandexLibraryClient client;
  setUp(() {
    transport = YandexTestTransport();
    transport.onGet = (request, _) async => switch (request.endpoint) {
          YandexReadEndpoint.account => yandexStatus(),
          YandexReadEndpoint.track => yandexDownloadTrack(),
          YandexReadEndpoint.fileInfo => yandexDownloadInfo(),
          _ => throw StateError('Unexpected request'),
        };
    client = YandexLibraryClient(
        token: YandexAccessToken('synthetic-secret'),
        transport: transport,
        clock: () =>
            DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true));
  });
  tearDown(() async => client.close());
  Future<YandexDownloadVariant> resolve({LibraryScanControl? control}) =>
      client.resolveDownload(
          yandexAccount, yandexDownloadIdentity, yandexFlacSelection,
          control: control);
  Matcher failure(YandexLibraryFailure code) => throwsA(
      isA<YandexLibraryException>().having((e) => e.failure, 'failure', code));

  test(
      'resolved and rejected delivery diagnostics contain only fixed numeric fields',
      () async {
    await client.close();
    final diagnostics = _DownloadDiagnostics();
    client = YandexLibraryClient(
        token: YandexAccessToken('synthetic-secret'),
        transport: transport,
        diagnostics: diagnostics);
    await client.verifyAccount();
    await resolve();
    expect(diagnostics.events.last, DiagnosticEvent.yandexDownloadResolved);
    expect(diagnostics.fields.last[DiagnosticField.returnedEncoding], 0);
    transport.onGet =
        (request, _) async => request.endpoint == YandexReadEndpoint.track
            ? yandexDownloadTrack()
            : {
                'downloadInfo': {'quality': [], 'codec': 'PRIVATE_SECRET'}
              };
    await expectLater(resolve(), throwsA(isA<YandexDownloadException>()));
    expect(diagnostics.events.last, DiagnosticEvent.yandexDownloadRejected);
    expect(
        diagnostics.fields
            .every((entry) => entry.values.every((v) => v is num || v is bool)),
        isTrue);
    expect(diagnostics.fields.last[DiagnosticField.returnedEncoding], -1);
  });
  test('diagnostics failure cannot change a successful download capability',
      () async {
    await client.close();
    final diagnostics = _DownloadDiagnostics()..fail = true;
    client = YandexLibraryClient(
        token: YandexAccessToken('synthetic-secret'),
        transport: transport,
        diagnostics: diagnostics);
    await client.verifyAccount();
    expect(await resolve(), isA<YandexDownloadVariant>());
  });

  test('requires verified credential identity before requesting metadata',
      () async {
    await expectLater(resolve(), failure(YandexLibraryFailure.accountMismatch));
    expect(transport.requests, isEmpty);
    await client.verifyAccount();
    final result = await resolve();
    expect(result.account, yandexAccount);
    expect(result.metadata.identity, yandexDownloadIdentity);
    expect(transport.requests.map((r) => r.endpoint), [
      YandexReadEndpoint.account,
      YandexReadEndpoint.track,
      YandexReadEndpoint.fileInfo
    ]);
    final request = transport.requests.last;
    expect(request.trackKey, '001');
    expect(request.relativeUri.queryParameters['ts'], '1700000000');
  });
  test('different expected account refuses before track request', () async {
    await client.verifyAccount();
    await expectLater(
        client.resolveDownload(
            RemoteAccountIdentity(provider: 'yandex_music', accountId: '202'),
            yandexDownloadIdentity,
            yandexFlacSelection),
        failure(YandexLibraryFailure.accountMismatch));
    expect(transport.requests, hasLength(1));
  });
  test('metadata mismatch cannot start signed file-info request', () async {
    await client.verifyAccount();
    transport.onGet = (_, __) async => yandexDownloadTrack(album: '010');
    await expectLater(resolve(), throwsA(isA<YandexDownloadException>()));
    expect(transport.requests.last.endpoint, YandexReadEndpoint.track);
    expect(transport.requests, hasLength(2));
  });
  test('API errors retain typed status without exposing server content',
      () async {
    await client.verifyAccount();
    transport.onGet = (_, __) => Future.error(
        const YandexLibraryException(YandexLibraryFailure.accessDenied));
    await expectLater(resolve(), failure(YandexLibraryFailure.accessDenied));
    expect(transport.requests, hasLength(2));
  });
  for (final stage in [YandexReadEndpoint.track, YandexReadEndpoint.fileInfo]) {
    test('cancellation at ${stage.name} drains accepted read, prevents result',
        () async {
      await client.verifyAccount();
      final entered = Completer<void>();
      final finished = Completer<void>();
      transport.onGet = (request, control) async {
        if (request.endpoint != stage) return yandexDownloadTrack();
        entered.complete();
        final cancelled = Completer<void>();
        void cancel() => cancelled.complete();
        control.addCancellationListener(cancel);
        try {
          await cancelled.future;
          finished.complete();
          return stage == YandexReadEndpoint.track
              ? yandexDownloadTrack()
              : yandexDownloadInfo();
        } finally {
          control.removeCancellationListener(cancel);
        }
      };
      final control = LibraryScanControl();
      final operation = resolve(control: control);
      final rejected =
          expectLater(operation, failure(YandexLibraryFailure.cancelled));
      await entered.future;
      control.cancel();
      await rejected;
      expect(finished.isCompleted, isTrue);
      expect(transport.requests.last.endpoint, stage);
    });
  }
  test('busy and close cancel/drain resolver without closing issued variants',
      () async {
    await client.verifyAccount();
    final entered = Completer<void>();
    transport.onGet = (_, control) async {
      final done = Completer<void>();
      control.addCancellationListener(() => done.complete());
      entered.complete();
      await done.future;
      control.throwIfCancelled();
      return null;
    };
    final operation = resolve();
    final rejected =
        expectLater(operation, failure(YandexLibraryFailure.cancelled));
    await entered.future;
    await expectLater(resolve(), failure(YandexLibraryFailure.busy));
    await client.close();
    await rejected;
    expect(transport.closed, isTrue);
    await expectLater(resolve(), failure(YandexLibraryFailure.closed));
  });
  test('operation deadline cancels and drains accepted metadata read',
      () async {
    await client.close();
    transport = YandexTestTransport();
    client = YandexLibraryClient(
        token: YandexAccessToken('synthetic-secret'),
        transport: transport,
        limits: YandexLibraryLimits(
            operationTimeout: const Duration(milliseconds: 50)));
    await client.verifyAccount();
    var drained = false;
    transport.onGet = (_, control) async {
      final gate = Completer<void>();
      void cancel() => gate.complete();
      control.addCancellationListener(cancel);
      try {
        await gate.future;
        drained = true;
        return yandexDownloadTrack();
      } finally {
        control.removeCancellationListener(cancel);
      }
    };
    await expectLater(resolve(), failure(YandexLibraryFailure.timeout));
    expect(drained, isTrue);
  });
}

class _DownloadDiagnostics implements DiagnosticsService {
  bool fail = false;
  final events = <DiagnosticEvent>[];
  final fields = <Map<DiagnosticField, Object?>>[];
  @override
  void record(DiagnosticEvent event,
      {Map<DiagnosticField, Object?> fields = const {}, Object? error}) {
    if (fail) throw StateError('synthetic diagnostics failure');
    events.add(event);
    this.fields.add(Map.of(fields));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unused diagnostic IO');
}
