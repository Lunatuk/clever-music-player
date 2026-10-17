import 'dart:async';

import 'package:flutter/foundation.dart';

import '../diagnostics/diagnostics_service.dart';
import '../domain/models/remote_library.dart';
import '../domain/repositories/remote_library_repository.dart';
import '../domain/repositories/yandex_session_repository.dart';
import '../library/library_scan_control.dart';
import 'yandex_collection_refresher.dart';
import 'yandex_credential_store.dart';
import 'yandex_http_transport.dart';
import 'yandex_library_client.dart';
import 'yandex_library_protocol.dart';

enum YandexConnectionActivity {
  idle,
  restoring,
  connecting,
  catalogue,
  checking,
  selecting,
  disconnecting,
  probing
}

enum YandexConnectionStep {
  verifyingAccount,
  loadingPlaylists,
  savingCredential
}

enum YandexConnectionFailure {
  invalidToken,
  storage,
  stale,
  unauthorized,
  accessDenied,
  network,
  timeout,
  rateLimited,
  invalidResponse,
  incomplete,
  changed,
  cancelled,
  unknown
}

final class YandexCollectionChoice {
  const YandexCollectionChoice(
      {required this.key,
      required this.title,
      required this.isSelected,
      this.itemCount,
      this.completedAt});
  final RemoteCollectionKey key;
  final String title;
  final bool isSelected;
  final int? itemCount;
  final DateTime? completedAt;
}

/// Lazy settings owner. Restoring reads only OS storage/SQLite, never the network.
/// API clients, secrets and raw failures are never exposed through view state.
final class YandexConnectionController extends ChangeNotifier {
  YandexConnectionController(
      {required RemoteLibraryRepository repository,
      required YandexSessionRepository sessions,
      required YandexCredentialStore credentials,
      this.diagnostics = const NoopDiagnosticsService(),
      YandexConnectionProbe Function()? probeFactory,
      YandexLibraryReader Function(YandexAccessToken)? readerFactory})
      : _repository = repository,
        _sessions = sessions,
        _credentials = credentials,
        _readerFactory = readerFactory ??
            ((token) => YandexLibraryClient(
                token: token,
                transport: YandexHttpTransport(diagnostics: diagnostics))),
        _probeFactory = probeFactory ??
            (() => YandexHttpTransport(diagnostics: diagnostics));
  final DiagnosticsService diagnostics;
  final YandexConnectionProbe Function() _probeFactory;
  final RemoteLibraryRepository _repository;
  final YandexSessionRepository _sessions;
  final YandexCredentialStore _credentials;
  final YandexLibraryReader Function(YandexAccessToken) _readerFactory;
  YandexLibraryReader? _reader;
  YandexCollectionRefresher? _refresher;
  RemoteLibraryAccount? _account;
  List<RemoteLibraryAccount> _expected = const [];
  List<YandexPlaylistDescriptor> _catalogue = const [];
  List<YandexCollectionChoice> _choices = const [];
  LibraryScanControl? _control;
  Future<void>? _active, _closing, _initializing;
  bool _closed = false;
  YandexConnectionActivity _activity = YandexConnectionActivity.idle;
  YandexConnectionFailure? _failure;
  String? _message;
  YandexRequestStage? _failureStage;
  YandexConnectionStep? _step;
  RemoteLibraryAccount? get account => _account;
  List<YandexCollectionChoice> get choices => _choices;
  bool get isBusy => _active != null;
  YandexConnectionActivity get activity => _activity;
  YandexConnectionFailure? get failure => _failure;
  String? get message => _message;
  YandexRequestStage? get failureStage => _failureStage;
  YandexConnectionStep? get connectionStep => _step;

  Future<void> _run(YandexConnectionActivity activity,
      Future<void> Function(LibraryScanControl) action) {
    if (_closed || _active != null) return Future.value();
    final done = Completer<void>();
    final control = LibraryScanControl();
    _active = done.future;
    _control = control;
    _activity = activity;
    _failure = null;
    _message = null;
    _failureStage = null;
    _step = null;
    final watch = Stopwatch()..start();
    YandexLibraryFailure? protocolFailure;
    YandexResponseIssue? responseIssue;
    diagnostics.record(DiagnosticEvent.yandexOperationStarted, fields: {
      DiagnosticField.remoteOperation: activity.index,
    });
    notifyListeners();
    final operation = () async {
      try {
        control.throwIfCancelled();
        await action(control);
      } on LibraryScanCancelled {
        _failure = YandexConnectionFailure.cancelled;
      } on YandexCredentialException {
        _initializing = null;
        _failure = YandexConnectionFailure.storage;
      } on _StaleSession {
        _initializing = null;
        _failure = YandexConnectionFailure.stale;
      } on YandexLibraryException catch (error) {
        protocolFailure = error.failure;
        responseIssue = error.responseIssue;
        _failure = _apiFailure(error.failure);
        _failureStage = error.stage;
        if (error.failure == YandexLibraryFailure.unauthorized &&
            _account != null &&
            activity != YandexConnectionActivity.connecting &&
            activity != YandexConnectionActivity.probing) {
          try {
            await _disconnect();
          } on Object {
            _failure = YandexConnectionFailure.storage;
          }
        }
      } on ArgumentError {
        _failure = YandexConnectionFailure.invalidToken;
      } on Object {
        _failure = YandexConnectionFailure.storage;
      } finally {
        diagnostics.record(
            _failure == null
                ? DiagnosticEvent.yandexOperationCompleted
                : DiagnosticEvent.yandexOperationFailed,
            fields: {
              DiagnosticField.remoteOperation: activity.index,
              DiagnosticField.elapsedMs: watch.elapsedMilliseconds,
              if (_failure != null)
                DiagnosticField.remoteConnectionFailure: _failure!.index,
              if (_failureStage != null)
                DiagnosticField.remoteStage: _failureStage!.index,
              if (protocolFailure != null)
                DiagnosticField.remoteFailure: protocolFailure!.index,
              if (responseIssue != null)
                DiagnosticField.remoteResponseIssue: responseIssue!.index,
            });
        _control = null;
        _active = null;
        _activity = YandexConnectionActivity.idle;
        if (!_closed) notifyListeners();
        done.complete();
      }
    }();
    operation.ignore();
    return operation;
  }

  Future<void> initialize() =>
      _initializing ??= _run(YandexConnectionActivity.restoring, (_) async {
        final old = _refresher;
        _reader = null;
        _refresher = null;
        _account = null;
        _catalogue = const [];
        _choices = const [];
        await old?.close();
        _expected = await _sessions.capture();
        final record = await _credentials.read();
        if (record == null) return;
        if (_expected.length != 1 || !record.matches(_expected.single)) {
          throw const _StaleSession();
        }
        _account = _expected.single;
        _adopt(_readerFactory(record.token));
        await _loadChoices();
      });

  void _adopt(YandexLibraryReader reader) {
    _reader = reader;
    _refresher =
        YandexCollectionRefresher(repository: _repository, reader: reader);
  }

  void _setStep(YandexConnectionStep step) {
    _step = step;
    if (!_closed) notifyListeners();
  }

  Future<void> probeConnection() =>
      _run(YandexConnectionActivity.probing, (control) async {
        final probe = _probeFactory();
        try {
          await probe.probe(control);
          _message =
              'API Яндекс Музыки доступен. Проверка выполнена без токена; теперь можно повторить подключение.';
        } finally {
          await probe.close();
        }
      });

  Future<void> connect(String input) =>
      _run(YandexConnectionActivity.connecting, (control) async {
        final token = parseYandexTokenInput(input);
        final expected = await _sessions.capture();
        YandexLibraryReader? candidate = _readerFactory(token);
        try {
          _setStep(YandexConnectionStep.verifyingAccount);
          final profile = await candidate.verifyAccount(control: control);
          control.throwIfCancelled();
          _setStep(YandexConnectionStep.savingCredential);
          // Once accepted, the small credential/DB commit drains despite late cancel.
          final account = await _sessions.connect(expected, profile.identity,
              displayName: profile.displayName,
              persist: (account) => _credentials.write(
                  YandexSavedCredential(account: account, token: token)));
          if (account == null) throw const _StaleSession();
          final old = _refresher;
          _account = account;
          _expected = [account];
          _catalogue = const [];
          _adopt(candidate);
          candidate = null;
          await old?.close();
          final configured =
              await _repository.listCollections(account.identity);
          if (!configured
              .any((c) => c.key.kind == RemoteCollectionKind.liked)) {
            await _repository.configureCollection(
                account, RemoteCollectionKey(kind: RemoteCollectionKind.liked),
                title: 'Мне нравится', isSelected: true);
          }
          await _loadChoices();
          _message = 'Аккаунт подключён. Выбери коллекции.';
          // Account verification is sufficient for login. Optional discovery
          // must never roll back a successfully saved, verified credential.
          if (control.isCancellationRequested) return;
          _setStep(YandexConnectionStep.loadingPlaylists);
          try {
            final catalogue = await _reader!
                .listPlaylists(account.identity, control: control);
            control.throwIfCancelled();
            _catalogue = catalogue;
            await _loadChoices();
          } on YandexLibraryException catch (error) {
            if (error.failure == YandexLibraryFailure.unauthorized) {
              await _disconnect();
              _message = null;
            } else {
              _message =
                  'Аккаунт подключён. Список плейлистов можно получить повторно отдельной кнопкой; «Мне нравится» уже доступно.';
            }
            rethrow;
          }
        } finally {
          await candidate?.close();
        }
      });

  Future<void> _verified(LibraryScanControl control) async {
    final account = _account, reader = _reader;
    if (account == null || reader == null) throw const _StaleSession();
    final profile =
        reader.verifiedAccount ?? await reader.verifyAccount(control: control);
    if (profile.identity != account.identity) {
      throw const YandexLibraryException(YandexLibraryFailure.unauthorized);
    }
  }

  Future<void> loadPlaylists() =>
      _run(YandexConnectionActivity.catalogue, (control) async {
        await _verified(control);
        final catalogue =
            await _reader!.listPlaylists(_account!.identity, control: control);
        control.throwIfCancelled();
        _catalogue = catalogue;
        await _loadChoices();
        _message = 'Список плейлистов обновлён.';
      });

  Future<void> _loadChoices() async {
    final account = _account;
    if (account == null) {
      _choices = const [];
      return;
    }
    final configured = await _repository.listCollections(account.identity);
    final saved = {
      for (final collection in configured) collection.key: collection
    };
    final descriptors = {for (final item in _catalogue) item.key: item};
    final keys = <RemoteCollectionKey>{
      RemoteCollectionKey(kind: RemoteCollectionKind.liked),
      ...descriptors.keys,
      ...saved.keys
    };
    _choices = List.unmodifiable(keys.map((key) {
      final collection = saved[key], descriptor = descriptors[key];
      return YandexCollectionChoice(
          key: key,
          title: key.kind == RemoteCollectionKind.liked
              ? 'Мне нравится'
              : descriptor?.title ??
                  collection?.title ??
                  'Плейлист ${key.externalId}',
          isSelected: collection?.isSelected ?? false,
          itemCount: collection?.completedAt != null
              ? collection!.itemCount
              : descriptor?.itemCount,
          completedAt: collection?.completedAt);
    }));
  }

  Future<void> select(RemoteCollectionKey key, bool selected) =>
      _run(YandexConnectionActivity.selecting, (_) async {
        final account = _account;
        final choices = _choices.where((choice) => choice.key == key);
        if (account == null || choices.length != 1) throw const _StaleSession();
        final saved = await _repository.configureCollection(account, key,
            title: choices.single.title, isSelected: selected);
        if (saved == null) throw const _StaleSession();
        await _loadChoices();
      });

  Future<void> checkCollections() =>
      _run(YandexConnectionActivity.checking, (control) async {
        final account = _account;
        if (account == null) throw const _StaleSession();
        final collections = await _repository.listCollections(account.identity,
            selectedOnly: true);
        if (collections.isEmpty) {
          _message = 'Выбери хотя бы одну коллекцию.';
          return;
        }
        await _verified(control);
        var updated = 0, positions = 0;
        try {
          for (final collection in collections) {
            control.throwIfCancelled();
            final result = await _refresher!
                .refresh(account, collection, control: control);
            switch (result.outcome) {
              case YandexRefreshOutcome.updated:
                updated++;
                positions += result.itemCount!;
              case YandexRefreshOutcome.stale:
                throw const _StaleSession();
              case YandexRefreshOutcome.cancelled:
                throw const LibraryScanCancelled();
              case YandexRefreshOutcome.failed:
                throw YandexLibraryException(
                    result.failure ?? YandexLibraryFailure.storage,
                    stage: result.stage);
            }
          }
          _message = 'Проверено коллекций: $updated. Позиций: $positions.';
        } finally {
          await _loadChoices();
        }
      });

  Future<void> disconnect() =>
      _run(YandexConnectionActivity.disconnecting, (_) => _disconnect());
  Future<void> _disconnect() async {
    final expected = _account == null ? _expected : [_account!];
    if (!await _sessions.disconnect(expected, forget: _credentials.delete)) {
      throw const _StaleSession();
    }
    final old = _refresher;
    _refresher = null;
    _reader = null;
    _account = null;
    _expected = const [];
    _catalogue = const [];
    _choices = const [];
    await old?.close();
    _message = 'Подключение удалено. Локальная музыка сохранена.';
  }

  void cancel() => _control?.cancel();
  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _drain();
  }

  Future<void> _drain() async {
    await _active;
    final old = _refresher;
    _reader = null;
    _refresher = null;
    try {
      await old?.close();
    } finally {
      super.dispose();
    }
  }
}

final class _StaleSession implements Exception {
  const _StaleSession();
}

YandexConnectionFailure _apiFailure(YandexLibraryFailure value) =>
    switch (value) {
      YandexLibraryFailure.unauthorized => YandexConnectionFailure.unauthorized,
      YandexLibraryFailure.accessDenied => YandexConnectionFailure.accessDenied,
      YandexLibraryFailure.network => YandexConnectionFailure.network,
      YandexLibraryFailure.timeout => YandexConnectionFailure.timeout,
      YandexLibraryFailure.rateLimited => YandexConnectionFailure.rateLimited,
      YandexLibraryFailure.incomplete => YandexConnectionFailure.incomplete,
      YandexLibraryFailure.changed => YandexConnectionFailure.changed,
      YandexLibraryFailure.cancelled => YandexConnectionFailure.cancelled,
      YandexLibraryFailure.storage => YandexConnectionFailure.storage,
      _ => YandexConnectionFailure.invalidResponse,
    };
