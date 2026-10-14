import 'dart:async';

import 'package:flutter/foundation.dart';

import '../diagnostics/diagnostics_service.dart';
import '../domain/models/library_folder.dart';
import 'directory_picker_service.dart';
import 'library_management_service.dart';
import 'library_scanner_service.dart';
import 'library_scan_control.dart';

enum LibraryOperation {
  addFolder(1),
  rescanLibrary(2),
  rescanFolder(3),
  setFolderEnabled(4),
  removeFolder(5);

  const LibraryOperation(this.diagnosticCode);
  final int diagnosticCode;
}

enum LibraryOperationPhase {
  choosingFolder,
  scanning,
  cancelling,
  changingFolder
}

enum LibraryOperationOutcome { completed, cancelled, busy, failed, closed }

final class LibraryOperationState {
  const LibraryOperationState({
    this.operation,
    this.phase,
    this.lastScanResult,
    this.error,
  });

  final LibraryOperation? operation;
  final LibraryOperationPhase? phase;
  final LibraryScanResult? lastScanResult;
  final Object? error;
  bool get isBusy => operation != null;
  bool get isScanning =>
      phase == LibraryOperationPhase.scanning ||
      phase == LibraryOperationPhase.cancelling;
  bool get isCancelling => phase == LibraryOperationPhase.cancelling;
  bool get canCancelScan => phase == LibraryOperationPhase.scanning;
}

/// App-scoped command entry point. Reserves the library before any async work,
/// including a picker; competing requests are rejected, not queued for later.
/// Widgets subscribe to state and do not own ongoing scans or database lifetime.
final class LibraryController implements Listenable {
  LibraryController({
    required DirectoryPickerService directoryPicker,
    required LibraryFolderScanner scanFolder,
    ControlledLibraryFolderScanner? controlledScanFolder,
    required LibraryManagementService management,
    this.diagnostics = const NoopDiagnosticsService(),
  })  : _directoryPicker = directoryPicker,
        _scanFolder = scanFolder,
        _controlledScanFolder = controlledScanFolder,
        _management = management;

  final DirectoryPickerService _directoryPicker;
  final LibraryFolderScanner _scanFolder;
  final ControlledLibraryFolderScanner? _controlledScanFolder;
  final LibraryManagementService _management;
  final DiagnosticsService diagnostics;
  final _LibraryNotifications _notifier = _LibraryNotifications();
  LibraryOperationState _state = const LibraryOperationState();
  Future<void>? _databaseWork;
  bool _closed = false;
  bool _disposed = false;
  bool _notifierDisposed = false;
  int _notificationDepth = 0;
  Future<void>? _closing;
  LibraryScanControl? _activeScan;
  final _progress = ValueNotifier<LibraryScanProgress?>(null);
  Timer? _progressTimer;
  LibraryScanProgress? _pendingProgress;

  LibraryOperationState get state => _state;
  ValueListenable<LibraryScanProgress?> get scanProgress => _progress;

  bool cancelScan() {
    if (_closed || !_state.canCancelScan || _activeScan == null) return false;
    _activeScan!.cancel();
    diagnostics.record(DiagnosticEvent.scanCancelRequested);
    _changePhase(LibraryOperationPhase.cancelling);
    return true;
  }

  Future<LibraryScanResult> _scan(String path) {
    final controlled = _controlledScanFolder;
    final control = _activeScan!;
    if (control.isCancellationRequested) {
      return Future.value(LibraryScanResult.cancelled(path));
    }
    return controlled == null
        ? _scanFolder(path)
        : controlled(path, control: control);
  }

  LibraryOperationOutcome _finishScan(LibraryScanResult result) {
    _setScanResult(result);
    if (_closed) return LibraryOperationOutcome.closed;
    return result.wasCancelled ||
            (_activeScan?.isCancellationRequested ?? false)
        ? LibraryOperationOutcome.cancelled
        : LibraryOperationOutcome.completed;
  }

  @override
  void addListener(VoidCallback listener) {
    if (!_disposed) _notifier.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (!_notifierDisposed) _notifier.removeListener(listener);
  }

  Future<LibraryOperationOutcome> addFolder() => _run(
        LibraryOperation.addFolder,
        LibraryOperationPhase.choosingFolder,
        () async {
          final path = await _directoryPicker.pickMusicFolder();
          if (_closed) return LibraryOperationOutcome.closed;
          if (path == null || path.trim().isEmpty) {
            return LibraryOperationOutcome.cancelled;
          }
          _changePhase(LibraryOperationPhase.scanning);
          return _finishScan(await _withDatabase(() => _scan(path)));
        },
      );

  Future<LibraryOperationOutcome> rescanLibrary() => _run(
        LibraryOperation.rescanLibrary,
        LibraryOperationPhase.scanning,
        () async {
          return _finishScan(await _withDatabase(
              () => _management.rescanEnabledFolders(control: _activeScan)));
        },
      );

  Future<LibraryOperationOutcome> rescanFolder(LibraryFolder folder) => _run(
        LibraryOperation.rescanFolder,
        LibraryOperationPhase.scanning,
        () async {
          return _finishScan(await _withDatabase(
              () => _management.rescanFolder(folder, control: _activeScan)));
        },
      );

  Future<LibraryOperationOutcome> setFolderEnabled(LibraryFolder folder,
          {required bool isEnabled}) =>
      _run(LibraryOperation.setFolderEnabled,
          LibraryOperationPhase.changingFolder, () async {
        await _withDatabase(
            () => _management.setFolderEnabled(folder, isEnabled: isEnabled));
        return LibraryOperationOutcome.completed;
      });

  /// The UI obtains confirmation before requesting this operation.
  Future<LibraryOperationOutcome> removeFolder(LibraryFolder folder) =>
      _run(LibraryOperation.removeFolder, LibraryOperationPhase.changingFolder,
          () async {
        await _withDatabase(() => _management.removeFolderFromLibrary(folder));
        return LibraryOperationOutcome.completed;
      });

  Future<LibraryOperationOutcome> _run(
      LibraryOperation operation,
      LibraryOperationPhase phase,
      Future<LibraryOperationOutcome> Function() action) async {
    if (_closed) return LibraryOperationOutcome.closed;
    if (_state.isBusy) return LibraryOperationOutcome.busy;
    if (operation == LibraryOperation.addFolder ||
        operation == LibraryOperation.rescanLibrary ||
        operation == LibraryOperation.rescanFolder) {
      late final LibraryScanControl scan;
      scan = LibraryScanControl(onProgress: (progress) {
        if (identical(_activeScan, scan)) _onScanProgress(progress);
      });
      _activeScan = scan;
    }
    final timer = Stopwatch()..start();
    _publish(LibraryOperationState(
        operation: operation,
        phase: phase,
        lastScanResult: _state.lastScanResult));
    diagnostics.record(DiagnosticEvent.libraryOperationStarted,
        fields: {DiagnosticField.libraryOperation: operation.diagnosticCode});
    try {
      // A state listener may close the controller during the initial publish.
      if (_closed) return LibraryOperationOutcome.closed;
      if (_activeScan != null) _progress.value = null;
      if (_closed) return LibraryOperationOutcome.closed;
      return await action();
    } on _ClosedLibraryOperation {
      return LibraryOperationOutcome.closed;
    } on Object catch (error) {
      diagnostics.record(DiagnosticEvent.libraryOperationFailed,
          error: error,
          fields: {DiagnosticField.libraryOperation: operation.diagnosticCode});
      if (!_closed) {
        _publish(LibraryOperationState(
            operation: operation,
            phase: _state.phase,
            lastScanResult: _state.lastScanResult,
            error: error));
      }
      return _closed
          ? LibraryOperationOutcome.closed
          : LibraryOperationOutcome.failed;
    } finally {
      _flushProgress();
      _activeScan = null;
      diagnostics.record(DiagnosticEvent.libraryOperationFinished, fields: {
        DiagnosticField.libraryOperation: operation.diagnosticCode,
        DiagnosticField.elapsedMs: timer.elapsedMilliseconds,
      });
      if (!_closed) {
        _publish(LibraryOperationState(
            lastScanResult: _state.lastScanResult, error: _state.error));
      }
    }
  }

  void _onScanProgress(LibraryScanProgress progress) {
    if (_closed) return;
    _pendingProgress = progress;
    if (_progress.value == null) {
      _flushProgress();
    } else {
      _progressTimer ??=
          Timer(const Duration(milliseconds: 100), _flushProgress);
    }
  }

  void _flushProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
    final pending = _pendingProgress;
    _pendingProgress = null;
    if (!_closed && pending != null) _progress.value = pending;
  }

  Future<T> _withDatabase<T>(Future<T> Function() work) {
    if (_closed) return Future.error(const _ClosedLibraryOperation());
    // Install the drain future before invoking work, which may notify listeners
    // synchronously. App disposal waits for it before closing SQLite.
    final done = Completer<void>();
    _databaseWork = done.future;
    return Future<T>.sync(work).whenComplete(() {
      done.complete();
      if (identical(_databaseWork, done.future)) _databaseWork = null;
    });
  }

  void _changePhase(LibraryOperationPhase phase) {
    if (_closed) return;
    _publish(LibraryOperationState(
        operation: _state.operation,
        phase: phase,
        lastScanResult: _state.lastScanResult));
  }

  void _setScanResult(LibraryScanResult result) {
    if (_closed) return;
    _publish(LibraryOperationState(
        operation: _state.operation,
        phase: _state.phase,
        lastScanResult: result));
  }

  void _publish(LibraryOperationState state) {
    if (_disposed) return;
    _state = state;
    _notificationDepth++;
    try {
      _notifier.publish();
    } finally {
      _notificationDepth--;
    }
  }

  /// Does not wait for an external picker: its late result is ignored. Work
  /// already using the database is allowed to finish before the owner closes it.
  Future<void> close() {
    if (_closing != null) return _closing!;
    dispose();
    return _closing = _databaseWork ?? Future<void>.value();
  }

  void dispose() {
    if (_disposed) return;
    _closed = true;
    _disposed = true;
    _activeScan?.cancel();
    _progressTimer?.cancel();
    _pendingProgress = null;
    // A progress listener is also allowed to close the application.
    scheduleMicrotask(_progress.dispose);
    if (_notificationDepth > 0) {
      scheduleMicrotask(_disposeNotifier);
    } else {
      _disposeNotifier();
    }
  }

  void _disposeNotifier() {
    if (_notifierDisposed) return;
    _notifierDisposed = true;
    _notifier.dispose();
  }
}

final class _ClosedLibraryOperation implements Exception {
  const _ClosedLibraryOperation();
}

final class _LibraryNotifications extends ChangeNotifier {
  void publish() => notifyListeners();
}
