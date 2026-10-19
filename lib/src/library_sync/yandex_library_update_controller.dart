import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../diagnostics/diagnostics_service.dart';

import '../domain/models/models.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/library_sync_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/services/library_sync_planner.dart';
import '../library/library_scan_control.dart';
import 'downloaded_asset_checker.dart';
import 'yandex_audio_selection.dart';
import 'yandex_connection_controller.dart';
import 'yandex_download_runner.dart';

enum YandexUpdateQuality { mp3, flac }

extension YandexUpdateQualitySelection on YandexUpdateQuality {
  YandexAudioSelection get selection => switch (this) {
        YandexUpdateQuality.mp3 => YandexAudioSelection.lossy(
            quality: YandexFileQuality.hq,
            encoding: YandexFileEncoding.mp3,
            minimumDeclaredKbps: 320,
            minimumMeasuredBitRate: 256000),
        YandexUpdateQuality.flac => const YandexAudioSelection.losslessFlac(),
      };
}

enum YandexUpdateStage {
  idle,
  loading,
  saving,
  refreshing,
  checkingFiles,
  planning,
  running
}

enum YandexUpdateFailure {
  unsupported,
  connection,
  noAccount,
  noCollections,
  destination,
  stale,
  storage,
  fileAccess,
  cancelled,
  download
}

final class _UpdateFailure implements Exception {
  const _UpdateFailure(this.failure);
  final YandexUpdateFailure failure;
}

/// App-owned explicit update. Closing the settings view does not stop an
/// accepted update; application shutdown does. Construction performs no IO.
final class YandexLibraryUpdateController extends ChangeNotifier {
  YandexLibraryUpdateController(
      {required this.connection,
      required LibraryRepository library,
      required LibrarySyncRepository plans,
      required SettingsRepository settings,
      required DownloadedAssetChecker Function() checkerFactory,
      required YandexDownloadRunService Function() runnerFactory,
      required this.supported,
      this.diagnostics = const NoopDiagnosticsService(),
      DateTime Function()? clock})
      : _library = library,
        _plans = plans,
        _settings = settings,
        _checkerFactory = checkerFactory,
        _runnerFactory = runnerFactory,
        _clock = clock ?? DateTime.now {
    connection.addListener(_connectionChanged);
  }
  static const optionsKey = 'library_sync.yandex.options.v1';
  static const limits = [3, 10, 50, LibrarySyncSnapshot.maxEntries];
  final bool supported;
  final DiagnosticsService diagnostics;
  final YandexConnectionController connection;
  final LibraryRepository _library;
  final LibrarySyncRepository _plans;
  final SettingsRepository _settings;
  final DownloadedAssetChecker Function() _checkerFactory;
  final YandexDownloadRunService Function() _runnerFactory;
  final DateTime Function() _clock;
  StreamSubscription<List<LibraryFolder>>? _folderSubscription;
  List<LibraryFolder> _folders = const [];
  int? _folderId;
  YandexUpdateQuality _quality = YandexUpdateQuality.mp3;
  int _limit = 3;
  bool _closed = false, _initialized = false, _refreshing = false;
  Completer<void>? _active;
  Future<void>? _initializing, _closing;
  LibraryScanControl? _control;
  RemoteLibraryAccount? _accountInUse;
  Set<RemoteCollectionKey>? _selectionInUse;
  YandexDownloadRunService? _runner;
  YandexUpdateStage _stage = YandexUpdateStage.idle;
  YandexUpdateFailure? _failure;
  String? _message;
  YandexDownloadRunProgress? _progress;
  YandexDownloadRunResult? _result;
  int _checked = 0, _toCheck = 0, _planned = 0, _needsAction = 0;
  bool get isBusy => _active != null;
  bool get initialized => _initialized;
  List<LibraryFolder> get folders => _folders;
  int? get folderId =>
      _folders.any((f) => f.id == _folderId) ? _folderId : null;
  YandexUpdateQuality get quality => _quality;
  int get limit => _limit;
  YandexUpdateStage get stage => _stage;
  YandexUpdateFailure? get failure => _failure;
  String? get message => _message;
  YandexDownloadRunProgress? get progress => _progress;
  YandexDownloadRunResult? get result => _result;
  int get checked => _checked;
  int get toCheck => _toCheck;
  int get planned => _planned;
  int get needsAction => _needsAction;

  Future<void> _run(YandexUpdateStage stage,
      Future<void> Function(LibraryScanControl) action) {
    if (_closed || isBusy) return Future.value();
    final done = Completer<void>(), control = LibraryScanControl();
    _active = done;
    _control = control;
    _stage = stage;
    _failure = null;
    _message = null;
    _progress = null;
    _result = null;
    _record(DiagnosticEvent.yandexUpdateStarted);
    notifyListeners();
    final operation = () async {
      try {
        control.throwIfCancelled();
        await action(control);
      } on LibraryScanCancelled {
        _failure ??= YandexUpdateFailure.cancelled;
      } on _UpdateFailure catch (error) {
        _failure ??= error.failure;
      } on Object {
        _failure ??= YandexUpdateFailure.storage;
      } finally {
        _record(_failure == null
            ? DiagnosticEvent.yandexUpdateCompleted
            : DiagnosticEvent.yandexUpdateFailed);
        _accountInUse = null;
        _selectionInUse = null;
        _refreshing = false;
        _active = null;
        _control = null;
        _stage = YandexUpdateStage.idle;
        if (!_closed) notifyListeners();
        done.complete();
      }
    }();
    operation.ignore();
    return operation;
  }

  void _record(DiagnosticEvent event) {
    try {
      diagnostics.record(event, fields: {
        DiagnosticField.syncStage: _stage.index,
        if (_failure != null) DiagnosticField.syncFailure: _failure!.index,
        if (_result != null)
          DiagnosticField.syncRunOutcome: _result!.outcome.index,
        if (_result?.failure != null)
          DiagnosticField.syncRunFailure: _result!.failure!.index,
        if (_result?.jobFailure != null)
          DiagnosticField.syncJobFailure: _result!.jobFailure!.index,
        DiagnosticField.plannedTracks: _planned,
        DiagnosticField.addedTracks: _result?.completed ?? 0,
      });
    } on Object {/* Diagnostics cannot interrupt ownership or cleanup. */}
  }

  Future<void> initialize() {
    if (_initialized || _closed) return Future.value();
    return _initializing ??= _run(YandexUpdateStage.loading, (control) async {
      if (!supported) {
        _initialized = true;
        return;
      }
      final saved = await _settings.readString(optionsKey);
      control.throwIfCancelled();
      if (saved != null && saved.length <= 2048) {
        try {
          final data = jsonDecode(saved) as Map<String, dynamic>;
          final folder = data['folder'];
          final quality =
              YandexUpdateQuality.values.byName(data['quality'] as String);
          final limit = data['limit'];
          if (data['version'] == 1 &&
              (folder == null || (folder is int && folder > 0)) &&
              limits.contains(limit)) {
            _folderId = folder as int?;
            _quality = quality;
            _limit = limit as int;
          }
        } on Object {
          /* Corrupt options do not select a different destination. */
        }
      }
      _folders =
          List.unmodifiable(await _library.listFolders(includeDisabled: false));
      control.throwIfCancelled();
      _folderSubscription ??= _library
          .watchFolders(includeDisabled: false)
          .listen(_foldersChanged, onError: (Object _) {
        if (_closed) return;
        _failure = YandexUpdateFailure.storage;
        _control?.cancel();
        if (_refreshing) connection.cancel();
        notifyListeners();
      });
      _initialized = true;
    }).whenComplete(() => _initializing = null);
  }

  void _foldersChanged(List<LibraryFolder> folders) {
    if (_closed) return;
    _folders = List.unmodifiable(folders.where((f) => f.isEnabled));
    if (_accountInUse != null && folderId == null) {
      _failure = YandexUpdateFailure.destination;
      cancel();
    }
    notifyListeners();
  }

  Set<RemoteCollectionKey> get _selected => connection.choices
      .where((choice) => choice.isSelected)
      .map((choice) => choice.key)
      .toSet();
  void _connectionChanged() {
    final account = _accountInUse, selection = _selectionInUse;
    if (_closed || account == null) return;
    if (connection.account != account ||
        (selection != null && !setEquals(selection, _selected))) {
      _failure = YandexUpdateFailure.stale;
      cancel();
    }
  }

  Future<void> configure(
      {int? folderId, YandexUpdateQuality? quality, int? limit}) async {
    await initialize();
    if (!supported || _closed || isBusy) return;
    final nextFolder = folderId ?? this.folderId;
    final nextQuality = quality ?? _quality, nextLimit = limit ?? _limit;
    if ((nextFolder != null && !_folders.any((f) => f.id == nextFolder)) ||
        !limits.contains(nextLimit)) {
      return;
    }
    await _run(YandexUpdateStage.saving, (control) async {
      final value = jsonEncode({
        'version': 1,
        'folder': nextFolder,
        'quality': nextQuality.name,
        'limit': nextLimit
      });
      await _settings.writeString(
          optionsKey, value); // Accepted small write drains.
      _folderId = nextFolder;
      _quality = nextQuality;
      _limit = nextLimit;
    });
  }

  Future<LibrarySyncPlan> _capture(RemoteLibraryAccount account, int folder,
      DateTime freshSince, bool retryFailed) async {
    final snapshot = await _plans.capture(account,
        libraryFolderId: folder,
        quality: _quality.selection.resourceQuality,
        minimumCompletedAt: freshSince);
    if (snapshot == null) throw const _UpdateFailure(YandexUpdateFailure.stale);
    if (snapshot.collections.isEmpty) {
      throw const _UpdateFailure(YandexUpdateFailure.noCollections);
    }
    final plan = const LibrarySyncPlanner()
        .build(snapshot, retryTerminalJobs: retryFailed);
    if (!plan.isReady) throw const _UpdateFailure(YandexUpdateFailure.stale);
    return plan;
  }

  Future<void> start({bool retryFailed = false}) async {
    await initialize();
    if (_closed || isBusy) return;
    await _run(YandexUpdateStage.refreshing, (control) async {
      if (!supported) {
        throw const _UpdateFailure(YandexUpdateFailure.unsupported);
      }
      if (connection.isBusy) {
        throw const _UpdateFailure(YandexUpdateFailure.connection);
      }
      final account = connection.account, folder = folderId;
      if (account == null) {
        throw const _UpdateFailure(YandexUpdateFailure.noAccount);
      }
      if (folder == null) {
        throw const _UpdateFailure(YandexUpdateFailure.destination);
      }
      if (_selected.isEmpty) {
        throw const _UpdateFailure(YandexUpdateFailure.noCollections);
      }
      _accountInUse = account;
      _selectionInUse = _selected;
      _checked = 0;
      _toCheck = 0;
      _planned = 0;
      _needsAction = 0;
      final freshSince = _clock();
      _refreshing = true;
      try {
        await connection.checkCollections();
      } finally {
        _refreshing = false;
      }
      control.throwIfCancelled();
      if (connection.failure != null || connection.isBusy) {
        throw const _UpdateFailure(YandexUpdateFailure.connection);
      }
      var plan = await _capture(account, folder, freshSince, retryFailed);
      control.throwIfCancelled();
      final candidates = {
        for (final item in plan.items)
          for (final candidate in item.candidates)
            candidate.publication.trackId: candidate
      }.values.toList();
      _toCheck = candidates.length;
      if (candidates.isNotEmpty) {
        _stage = YandexUpdateStage.checkingFiles;
        notifyListeners();
        final checker = _checkerFactory();
        try {
          for (final candidate in candidates) {
            control.throwIfCancelled();
            final outcome = await checker.check(candidate, control: control);
            control.throwIfCancelled();
            if (outcome == AssetCheckOutcome.accessDenied ||
                outcome == AssetCheckOutcome.unreadable) {
              throw const _UpdateFailure(YandexUpdateFailure.fileAccess);
            }
            if (outcome == AssetCheckOutcome.stale) {
              throw const _UpdateFailure(YandexUpdateFailure.stale);
            }
            if (outcome == AssetCheckOutcome.cancelled) {
              throw const LibraryScanCancelled();
            }
            _checked++;
            notifyListeners();
          }
        } finally {
          await checker.close();
        }
        plan = await _capture(account, folder, freshSince, retryFailed);
      }
      control.throwIfCancelled();
      _stage = YandexUpdateStage.planning;
      notifyListeners();
      final applied = await _plans.apply(plan, now: _clock());
      control.throwIfCancelled();
      if (applied.status != LibrarySyncApplyStatus.applied) {
        throw const _UpdateFailure(YandexUpdateFailure.stale);
      }
      _planned = plan.items
          .where((item) =>
              item.action != LibrarySyncAction.checkExisting &&
              item.action != LibrarySyncAction.needsAction)
          .length;
      _needsAction = plan.items
          .where((item) => item.action == LibrarySyncAction.needsAction)
          .length;
      if (_planned == 0) {
        _message = _needsAction == 0
            ? 'Новых заданий для загрузки нет.'
            : 'Доступных новых заданий нет.';
        return;
      }
      _stage = YandexUpdateStage.running;
      notifyListeners();
      control.throwIfCancelled();
      final runner = _runner ??= _runnerFactory();
      final result = await runner.run(
          account: account,
          libraryFolderId: folder,
          selection: _quality.selection,
          maxJobs: _limit,
          control: control,
          onProgress: (value) {
            _progress = value;
            if (!_closed) notifyListeners();
          });
      _result = result;
      switch (result.outcome) {
        case YandexDownloadRunOutcome.completed:
          _message = result.completed == 0
              ? 'Новых заданий для загрузки нет.'
              : 'Добавлено треков: ${result.completed}.';
        case YandexDownloadRunOutcome.limited:
          _message =
              'Добавлено треков: ${result.completed}. Достигнут выбранный лимит; можно продолжить обновление.';
        case YandexDownloadRunOutcome.cancelled:
          _failure ??= YandexUpdateFailure.cancelled;
        case YandexDownloadRunOutcome.staleSession:
          _failure ??= YandexUpdateFailure.stale;
        case YandexDownloadRunOutcome.failed ||
              YandexDownloadRunOutcome.cleanupFailed:
          _failure ??= YandexUpdateFailure.download;
      }
    });
  }

  void cancel() {
    _control?.cancel();
    if (_refreshing) connection.cancel();
    _runner?.cancel();
  }

  Future<void> close() {
    _closed = true;
    cancel();
    return _closing ??= _close();
  }

  Future<void> _close() async {
    await _active?.future;
    Object? first;
    StackTrace? stack;
    for (final close in <Future<void> Function()>[
      if (_runner != null) _runner!.close,
      () async {
        await _folderSubscription?.cancel();
      },
    ]) {
      try {
        await close();
      } on Object catch (error, trace) {
        first ??= error;
        stack ??= trace;
      }
    }
    connection.removeListener(_connectionChanged);
    super.dispose();
    if (first != null) Error.throwWithStackTrace(first, stack!);
  }
}
