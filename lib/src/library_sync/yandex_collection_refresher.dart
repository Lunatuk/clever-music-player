import '../domain/models/remote_library.dart';
import '../domain/repositories/remote_library_repository.dart';
import '../library/library_scan_control.dart';
import 'yandex_library_protocol.dart';

enum YandexRefreshOutcome { updated, stale, cancelled, failed }

final class YandexRefreshResult {
  const YandexRefreshResult(this.outcome, {this.itemCount, this.failure});
  final YandexRefreshOutcome outcome;
  final int? itemCount;
  final YandexLibraryFailure? failure;
}

/// Owns the reader; close before SQLite. One selected collection per call.
/// A late cancellation after accepting commit drains the transaction's result.
final class YandexCollectionRefresher {
  YandexCollectionRefresher(
      {required RemoteLibraryRepository repository,
      required YandexLibraryReader reader})
      : _repository = repository,
        _reader = reader;
  final RemoteLibraryRepository _repository;
  final YandexLibraryReader _reader;
  bool _closed = false;
  LibraryScanControl? _control;
  Future<YandexRefreshResult>? _active;
  Future<void>? _closing;

  Future<YandexRefreshResult> refresh(
      RemoteLibraryAccount account, RemoteLibraryCollection collection,
      {LibraryScanControl? control}) {
    if (_closed || _active != null) {
      return Future.error(YandexLibraryException(
          _closed ? YandexLibraryFailure.closed : YandexLibraryFailure.busy));
    }
    final current = LibraryScanControl();
    _control = current;
    control?.addCancellationListener(current.cancel);
    final operation = _refresh(account, collection, current).whenComplete(() {
      control?.removeCancellationListener(current.cancel);
      _control = null;
      _active = null;
    });
    operation.ignore();
    return _active = operation;
  }

  Future<YandexRefreshResult> _refresh(RemoteLibraryAccount account,
      RemoteLibraryCollection collection, LibraryScanControl control) async {
    try {
      control.throwIfCancelled();
      if (account.identity != collection.account ||
          _reader.verifiedAccount?.identity != account.identity) {
        throw const YandexLibraryException(
            YandexLibraryFailure.accountMismatch);
      }
      final ticket = await _repository.beginRefresh(account, collection);
      control.throwIfCancelled();
      if (ticket == null) {
        return const YandexRefreshResult(YandexRefreshOutcome.stale);
      }
      final snapshot = await _reader
          .readCollection(account.identity, collection.key, control: control);
      control.throwIfCancelled();
      if (!snapshot.canCommit) {
        throw const YandexLibraryException(YandexLibraryFailure.incomplete);
      }
      final committed = await _repository.commitSnapshot(ticket, snapshot);
      return YandexRefreshResult(
          committed ? YandexRefreshOutcome.updated : YandexRefreshOutcome.stale,
          itemCount: committed ? snapshot.items.length : null);
    } on LibraryScanCancelled {
      return const YandexRefreshResult(YandexRefreshOutcome.cancelled,
          failure: YandexLibraryFailure.cancelled);
    } on YandexLibraryException catch (error) {
      return YandexRefreshResult(
          error.failure == YandexLibraryFailure.cancelled
              ? YandexRefreshOutcome.cancelled
              : YandexRefreshOutcome.failed,
          failure: error.failure);
    } on Object {
      return const YandexRefreshResult(YandexRefreshOutcome.failed,
          failure: YandexLibraryFailure.storage);
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
    } finally {
      await _reader.close();
    }
  }
}
