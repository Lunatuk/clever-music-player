import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../diagnostics/diagnostics_service.dart';
import '../library/library_scan_control.dart';
import 'yandex_library_protocol.dart';

/// Fixed HTTPS origin in production, no redirects/cookie jar/logging/retries.
final class YandexHttpTransport
    implements YandexApiTransport, YandexConnectionProbe {
  YandexHttpTransport(
      {this.requestTimeout = const Duration(seconds: 20),
      this.maxResponseBytes = 16 * 1024 * 1024,
      this.diagnostics = const NoopDiagnosticsService(),
      DateTime Function()? clock})
      : _origin = Uri.https('api.music.yandex.net'),
        _clock = clock ?? DateTime.now {
    _validate();
  }

  /// Loopback-only test seam; never accepts a remote credential destination.
  YandexHttpTransport.loopbackForTesting(Uri origin,
      {this.requestTimeout = const Duration(seconds: 20),
      this.maxResponseBytes = 16 * 1024 * 1024,
      this.diagnostics = const NoopDiagnosticsService(),
      DateTime Function()? clock})
      : _origin = origin,
        _clock = clock ?? DateTime.now {
    _validate();
    if (origin.scheme != 'http' ||
        !{'127.0.0.1', '::1'}.contains(origin.host) ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw ArgumentError('Тестовый адрес должен быть loopback.');
    }
  }
  final Uri _origin;
  final DiagnosticsService diagnostics;
  final DateTime Function() _clock;
  final Duration requestTimeout;
  final int maxResponseBytes;
  HttpClient? _client;
  LibraryScanControl? _control;
  Future<Object?>? _active;
  Future<void>? _closing;
  bool _closed = false;
  void _validate() {
    if (requestTimeout <= Duration.zero ||
        requestTimeout > const Duration(minutes: 2) ||
        maxResponseBytes <= 0 ||
        maxResponseBytes > 32 * 1024 * 1024) {
      throw ArgumentError('Некорректные пределы HTTP.');
    }
  }

  @override
  Future<Object?> get(YandexReadRequest request, YandexAccessToken token,
          LibraryScanControl control) =>
      _accept(request, token, control);

  @override
  Future<void> probe(LibraryScanControl control) =>
      _accept(YandexReadRequest.account(), null, control).then((_) {});

  Future<Object?> _accept(YandexReadRequest request, YandexAccessToken? token,
      LibraryScanControl control) {
    if (_closed || _active != null) {
      return Future.error(YandexLibraryException(
          _closed ? YandexLibraryFailure.closed : YandexLibraryFailure.busy));
    }
    final operation =
        _get(request, token, control).whenComplete(() => _active = null);
    operation.ignore();
    return _active = operation;
  }

  Future<Object?> _get(YandexReadRequest request, YandexAccessToken? token,
      LibraryScanControl external) async {
    final watch = Stopwatch()..start();
    var stage = YandexRequestStage.connecting;
    int? status;
    var received = 0;
    var credentialAttached = false;
    Map<DiagnosticField, Object?> fields() => {
          DiagnosticField.remoteEndpoint: request.endpoint.index,
          DiagnosticField.remoteStage: stage.index,
          DiagnosticField.credentialAttached: credentialAttached,
          DiagnosticField.elapsedMs: watch.elapsedMilliseconds,
          if (status != null) DiagnosticField.httpStatus: status,
          DiagnosticField.responseBytes: received,
        };
    diagnostics.record(DiagnosticEvent.yandexRequestStarted, fields: fields());
    var succeeded = false;
    final control = LibraryScanControl();
    _control = control;
    external.addCancellationListener(control.cancel);
    final client = HttpClient()..connectionTimeout = requestTimeout;
    _client = client;
    var timedOut = false;
    HttpClientRequest? pending;
    void abort() {
      pending
          ?.abort(const YandexLibraryException(YandexLibraryFailure.cancelled));
      client.close(force: true);
    }

    control.addCancellationListener(abort);
    final timer = Timer(requestTimeout, () {
      timedOut = true;
      control.cancel();
    });
    try {
      control.throwIfCancelled();
      final relative = request.relativeUri;
      final uri = _origin.replace(
          path: relative.path,
          queryParameters: relative.hasQuery ? relative.queryParameters : null);
      pending =
          await client.openUrl(request.usesFormPost ? 'POST' : 'GET', uri);
      control.throwIfCancelled();
      pending.followRedirects = false;
      pending.maxRedirects = 0;
      pending.headers.set(HttpHeaders.acceptHeader, 'application/json');
      pending.headers.set(HttpHeaders.acceptLanguageHeader, 'ru');
      pending.headers
          .set(HttpHeaders.userAgentHeader, 'CleverMusicPlayer/0.2.1');
      pending.headers.set('X-Yandex-Music-Client', request.clientHeader);
      token?.authorize((value) =>
          pending!.headers.set(HttpHeaders.authorizationHeader, value));
      credentialAttached = token != null;
      if (request.formBody case final body?) {
        final bytes = utf8.encode(body);
        pending.headers.contentType = ContentType(
            'application', 'x-www-form-urlencoded',
            charset: 'utf-8');
        pending.contentLength = bytes.length;
        pending.add(bytes);
      }
      stage = YandexRequestStage.waitingForResponse;
      final response = await pending.close();
      status = response.statusCode;
      stage = YandexRequestStage.receivingBody;
      control.throwIfCancelled();
      // A genuine HTTP 401 proves reachability without requiring authentication.
      if (token == null && status == HttpStatus.unauthorized) {
        succeeded = true;
        return null;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw YandexLibraryException(
            switch (response.statusCode) {
              401 => YandexLibraryFailure.unauthorized,
              403 => YandexLibraryFailure.accessDenied,
              404 => YandexLibraryFailure.notFound,
              429 => YandexLibraryFailure.rateLimited,
              304 => YandexLibraryFailure.incomplete,
              >= 500 && <= 599 => YandexLibraryFailure.network,
              _ => YandexLibraryFailure.invalidResponse,
            },
            retryAfter: response.statusCode == 429
                ? _retryAfter(response.headers.value('retry-after'))
                : null);
      }
      final mime = response.headers.contentType?.mimeType;
      if (mime != 'application/json' &&
          (mime == null || !mime.endsWith('+json'))) {
        throw const YandexLibraryException(
            YandexLibraryFailure.invalidResponse);
      }
      if (response.contentLength > maxResponseBytes) {
        throw const YandexLibraryException(YandexLibraryFailure.tooLarge);
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        control.throwIfCancelled();
        if (chunk.length > maxResponseBytes - bytes.length) {
          throw const YandexLibraryException(YandexLibraryFailure.tooLarge);
        }
        bytes.add(chunk);
        received = bytes.length;
      }
      control.throwIfCancelled();
      final input = bytes.takeBytes();
      stage = YandexRequestStage.decoding;
      final value = input.length >= 256 * 1024
          ? await _decodeLarge(input)
          : _decode(input);
      control.throwIfCancelled();
      if (value is! Map<String, dynamic>) {
        throw const YandexLibraryException(
            YandexLibraryFailure.invalidResponse);
      }
      final error = value['error'];
      if (error != null) {
        final name = error is Map ? error['name'] : error;
        if (token == null && name == 'unauthorized') {
          succeeded = true;
          return null;
        }
        throw YandexLibraryException(switch (name) {
          'unauthorized' => YandexLibraryFailure.unauthorized,
          'forbidden' => YandexLibraryFailure.accessDenied,
          'not-found' => YandexLibraryFailure.notFound,
          'too-many-requests' => YandexLibraryFailure.rateLimited,
          _ => YandexLibraryFailure.invalidResponse,
        });
      }
      if (!value.containsKey('result') || value['result'] == null) {
        throw const YandexLibraryException(
            YandexLibraryFailure.invalidResponse);
      }
      succeeded = true;
      return value['result'];
    } on Object catch (error) {
      final failure = timedOut || error is TimeoutException
          ? YandexLibraryFailure.timeout
          : control.isCancellationRequested
              ? YandexLibraryFailure.cancelled
              : error is YandexLibraryException
                  ? error.failure
                  : error is FormatException || error is HttpException
                      ? YandexLibraryFailure.invalidResponse
                      : YandexLibraryFailure.network;
      diagnostics.record(DiagnosticEvent.yandexRequestFailed, fields: {
        ...fields(),
        DiagnosticField.remoteFailure: failure.index,
        if (error is SocketException && error.osError != null)
          DiagnosticField.networkErrorCode: error.osError!.errorCode,
      });
      throw YandexLibraryException(failure,
          stage: stage,
          retryAfter:
              error is YandexLibraryException ? error.retryAfter : null);
    } finally {
      timer.cancel();
      control.removeCancellationListener(abort);
      external.removeCancellationListener(control.cancel);
      client.close(force: true);
      _client = null;
      _control = null;
      if (succeeded) {
        diagnostics.record(DiagnosticEvent.yandexRequestCompleted,
            fields: fields());
      }
    }
  }

  Duration? _retryAfter(String? value) {
    if (value == null || value.length > 128) return null;
    final seconds = int.tryParse(value);
    if (seconds != null) return Duration(seconds: seconds.clamp(0, 86400));
    try {
      return Duration(
          seconds: HttpDate.parse(value)
              .difference(_clock())
              .inSeconds
              .clamp(0, 86400));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    _control?.cancel();
    _client?.close(force: true);
    return _closing ??= _drain();
  }

  Future<void> _drain() async {
    try {
      await _active;
    } on Object {/* Reported by get. */}
  }
}

Object? _decode(Uint8List input) => jsonDecode(utf8.decode(input));
Future<Object?> _decodeLarge(Uint8List input) =>
    Isolate.run(() => _decode(input));
