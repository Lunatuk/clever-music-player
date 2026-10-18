import 'dart:async';
import 'dart:io';

import '../diagnostics/diagnostics_service.dart';
import '../library/library_scan_control.dart';
import 'binary_download.dart';
import 'raw_download_pool.dart';

/// The provider adapter supplies its independently trusted exact hosts. Never
/// derive trustedHosts from a returned URL. No arbitrary headers or OAuth input.
final class BinaryDownloadAddress {
  BinaryDownloadAddress.https(String value, {required Set<String> trustedHosts})
      : _uri = _parse(value),
        _loopback = false {
    if (trustedHosts.isEmpty ||
        trustedHosts.length > 32 ||
        !trustedHosts.every(_publicHost) ||
        _uri.scheme != 'https' ||
        _uri.port != 443 ||
        !trustedHosts.contains(_uri.host) ||
        !_publicHost(_uri.host)) {
      throw const BinaryDownloadException(BinaryDownloadFailure.invalidAddress);
    }
  }
  BinaryDownloadAddress.loopbackForTesting(String value)
      : _uri = _parse(value),
        _loopback = true {
    if (_uri.scheme != 'http' ||
        !{'127.0.0.1', '::1'}.contains(_uri.host) ||
        _uri.port <= 0) {
      throw const BinaryDownloadException(BinaryDownloadFailure.invalidAddress);
    }
  }
  final Uri _uri;
  final bool _loopback;
  static Uri _parse(String value) {
    final uri = Uri.tryParse(value);
    if (value.isEmpty ||
        value.length > 8192 ||
        value.codeUnits.any((c) => c <= 32 || c >= 127 || c == 92) ||
        uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !uri.hasAbsolutePath ||
        uri.path == '/') {
      throw const BinaryDownloadException(BinaryDownloadFailure.invalidAddress);
    }
    return uri;
  }

  static bool _publicHost(String host) =>
      host.length <= 253 &&
      RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$')
              .stringMatch(host) ==
          host &&
      InternetAddress.tryParse(host) == null &&
      !host.endsWith('.local') &&
      !host.endsWith('.localhost') &&
      !host.endsWith('.internal');

  @override
  String toString() => 'BinaryDownloadAddress(<redacted>)';
}

enum BinaryDownloadStage { connecting, waitingForResponse, receiving, flushing }

/// Separate allowlists; admitting artwork must not broaden audio responses.
enum BinaryDownloadContent { audio, cover }

const maximumDownloadedCoverBytes = 2 * 1024 * 1024;

/// Streams opaque bytes with backpressure into an owned bounded raw file.
/// It does not authenticate, decrypt, tag, verify or publish audio. Dedicated
/// clients never share credentials/cookies with the authenticated API client.
final class BinaryHttpDownloadTransport {
  BinaryHttpDownloadTransport(
      {required this.pool,
      this.timeout = const Duration(minutes: 10),
      this.idleTimeout = const Duration(seconds: 30),
      this.diagnostics = const NoopDiagnosticsService()})
      : _loopbackOrigin = null {
    _validate();
  }
  BinaryHttpDownloadTransport.loopbackForTesting(Uri origin,
      {required this.pool,
      this.timeout = const Duration(minutes: 10),
      this.idleTimeout = const Duration(seconds: 30),
      this.diagnostics = const NoopDiagnosticsService()})
      : _loopbackOrigin = origin {
    _validate();
    if (origin.scheme != 'http' ||
        !{'127.0.0.1', '::1'}.contains(origin.host) ||
        origin.port <= 0 ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw ArgumentError('Тестовый адрес должен быть loopback.');
    }
  }
  final RawDownloadPool pool;
  final Duration timeout, idleTimeout;
  final DiagnosticsService diagnostics;
  final Uri? _loopbackOrigin;
  bool _closed = false;
  Future<RawDownloadedAudio>? _active;
  Future<void>? _closing;
  LibraryScanControl? _control;

  void _validate() {
    if (timeout <= Duration.zero ||
        timeout > const Duration(minutes: 30) ||
        idleTimeout <= Duration.zero ||
        idleTimeout > const Duration(minutes: 2)) {
      throw ArgumentError('Некорректные пределы загрузки.');
    }
  }

  Future<RawDownloadedAudio> download(BinaryDownloadAddress address,
      {required int maxBytes,
      BinaryDownloadContent content = BinaryDownloadContent.audio,
      int? expectedBytes,
      LibraryScanControl? control,
      void Function(BinaryDownloadProgress)? onProgress}) {
    if (_closed || _active != null) {
      return Future.error(BinaryDownloadException(
          _closed ? BinaryDownloadFailure.closed : BinaryDownloadFailure.busy));
    }
    final origin = _loopbackOrigin;
    if ((origin == null && address._loopback) ||
        (origin != null &&
            (!address._loopback || address._uri.origin != origin.origin))) {
      return Future.error(
          const BinaryDownloadException(BinaryDownloadFailure.invalidAddress));
    }
    if (maxBytes <= 0 ||
        maxBytes >
            (content == BinaryDownloadContent.cover
                ? maximumDownloadedCoverBytes
                : maximumRawDownloadBytes) ||
        (expectedBytes != null &&
            (expectedBytes <= 0 || expectedBytes > maxBytes))) {
      return Future.error(
          const BinaryDownloadException(BinaryDownloadFailure.tooLarge));
    }
    // Register before callbacks (diagnostics/progress) can re-enter close().
    final accepted = Completer<RawDownloadedAudio>();
    final operation = accepted.future.whenComplete(() => _active = null);
    operation.ignore();
    _active = operation;
    unawaited(Future<RawDownloadedAudio>.sync(() => _download(
            address, maxBytes, expectedBytes, content, control, onProgress))
        .then(accepted.complete, onError: accepted.completeError));
    return operation;
  }

  Future<RawDownloadedAudio> _download(
      BinaryDownloadAddress address,
      int maxBytes,
      int? expected,
      BinaryDownloadContent content,
      LibraryScanControl? external,
      void Function(BinaryDownloadProgress)? onProgress) async {
    final watch = Stopwatch()..start();
    var stage = BinaryDownloadStage.connecting;
    int? status;
    RawDownloadReservation? reservation;
    final control = LibraryScanControl();
    _control = control;
    var timedOut = false, delivered = false;
    HttpClient? client;
    HttpClientRequest? request;
    Future<HttpClientRequest>? opening;
    Future<HttpClientResponse>? headers;
    void abort() {
      request?.abort(
          const BinaryDownloadException(BinaryDownloadFailure.cancelled));
      client?.close(force: true);
    }

    external?.addCancellationListener(control.cancel);
    control.addCancellationListener(abort);
    final timer = Timer(timeout, () {
      timedOut = true;
      control.cancel();
    });
    Map<DiagnosticField, Object?> fields() => {
          DiagnosticField.transferStage: stage.index,
          DiagnosticField.elapsedMs: watch.elapsedMilliseconds,
          DiagnosticField.responseBytes: reservation?.bytesWritten ?? 0,
          if (status != null) DiagnosticField.httpStatus: status,
        };
    diagnostics.record(DiagnosticEvent.downloadTransferStarted,
        fields: fields());
    try {
      control.throwIfCancelled();
      reservation = pool.reserve(maxBytes);
      client = HttpClient()
        ..connectionTimeout = idleTimeout
        ..autoUncompress = false
        ..maxConnectionsPerHost = 1;
      control.throwIfCancelled();
      opening = client.getUrl(address._uri);
      request = await opening.timeout(idleTimeout);
      control.throwIfCancelled();
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.headers.set(
          HttpHeaders.acceptHeader,
          content == BinaryDownloadContent.cover
              ? 'image/jpeg, image/png, application/octet-stream'
              : 'application/octet-stream, audio/*');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers
          .set(HttpHeaders.userAgentHeader, 'CleverMusicPlayer/0.2.1');
      stage = BinaryDownloadStage.waitingForResponse;
      headers = request.close();
      final response = await headers.timeout(idleTimeout);
      control.throwIfCancelled();
      status = response.statusCode;
      if (status != HttpStatus.ok) {
        throw BinaryDownloadException(switch (status) {
          401 => BinaryDownloadFailure.unauthorized,
          403 => BinaryDownloadFailure.accessDenied,
          404 => BinaryDownloadFailure.notFound,
          429 => BinaryDownloadFailure.rateLimited,
          >= 500 && <= 599 => BinaryDownloadFailure.network,
          _ => BinaryDownloadFailure.invalidResponse,
        });
      }
      final type = response.headers.contentType?.mimeType;
      const audioTypes = {
        'application/octet-stream',
        'audio/mpeg',
        'audio/mp3',
        'audio/mp4',
        'audio/x-m4a',
        'audio/aac',
        'audio/flac',
        'audio/x-flac'
      };
      const coverTypes = {
        'image/jpeg',
        'image/png',
        'application/octet-stream'
      };
      final types =
          content == BinaryDownloadContent.cover ? coverTypes : audioTypes;
      if ((type != null && !types.contains(type)) ||
          response.headers[HttpHeaders.contentRangeHeader] != null ||
          (response.headers[HttpHeaders.contentEncodingHeader] != null &&
              response.headers
                      .value(HttpHeaders.contentEncodingHeader)
                      ?.toLowerCase() !=
                  'identity')) {
        throw const BinaryDownloadException(
            BinaryDownloadFailure.invalidResponse);
      }
      final length = response.contentLength;
      if (length > maxBytes) {
        throw const BinaryDownloadException(BinaryDownloadFailure.tooLarge);
      }
      if (length == 0 ||
          (expected != null && length >= 0 && length != expected)) {
        throw const BinaryDownloadException(BinaryDownloadFailure.incomplete);
      }
      stage = BinaryDownloadStage.receiving;
      final result = await reservation.write(response.timeout(idleTimeout),
          expectedBytes: expected ?? (length >= 0 ? length : null),
          control: control,
          onProgress: onProgress,
          onFlushing: () => stage = BinaryDownloadStage.flushing);
      control.throwIfCancelled();
      delivered = true;
      diagnostics.record(DiagnosticEvent.downloadTransferCompleted,
          fields: fields());
      return result;
    } on Object catch (error) {
      final failure = timedOut || error is TimeoutException
          ? BinaryDownloadFailure.timeout
          : control.isCancellationRequested
              ? BinaryDownloadFailure.cancelled
              : error is BinaryDownloadException
                  ? error.failure
                  : error is FileSystemException
                      ? BinaryDownloadFailure.storage
                      : BinaryDownloadFailure.network;
      diagnostics.record(DiagnosticEvent.downloadTransferFailed, fields: {
        ...fields(),
        DiagnosticField.transferFailure: failure.index,
      });
      throw BinaryDownloadException(failure);
    } finally {
      timer.cancel();
      control.removeCancellationListener(abort);
      external?.removeCancellationListener(control.cancel);
      client?.close(force: true);
      try {
        // A timer may win before a native DNS/connect/header future settles.
        // Closing the client revokes it; drain accepted work before releasing
        // ownership. Timeouts are cooperative with uninterruptible OS calls.
        for (final pending in <Future<Object?>?>[opening, headers]) {
          try {
            await pending;
          } on Object {
            // The original typed failure is already recorded above.
          }
        }
        if (!delivered) {
          try {
            await reservation?.close();
          } on BinaryDownloadException catch (error) {
            diagnostics.record(DiagnosticEvent.downloadTransferCleanupFailed,
                fields: {
                  ...fields(),
                  DiagnosticField.transferFailure: error.failure.index
                });
            rethrow;
          }
        }
      } finally {
        _control = null;
      }
    }
  }

  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _drain();
  }

  Future<void> _drain() async {
    try {
      await _active;
    } on Object {
      // The caller receives the typed failure; shutdown still drains it.
    }
  }
}
