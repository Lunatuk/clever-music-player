import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../diagnostics/diagnostics_service.dart';

import '../domain/models/audio_source_reference.dart';
import '../domain/repositories/settings_repository.dart';
import '../library/library_scan_control.dart';
import 'android_download_folders.dart';
import 'android_download_destination_check.dart';
import 'android_download_workspace.dart';

typedef DownloadWorkspaceCheck = Future<void> Function(LibraryScanControl);

Future<void> _checkPrivateStorage(
    LibraryScanControl control, DiagnosticsService diagnostics) async {
  control.throwIfCancelled();
  final Directory parent;
  try {
    parent = await androidDownloadWorkspaceParent();
  } on Object catch (error) {
    diagnostics.record(DiagnosticEvent.androidWorkspaceCheckFailed,
        error: error,
        fields: {
          DiagnosticField.workspaceStage:
              AndroidWorkspaceCheckStage.parent.index,
          if (error is FileSystemException && error.osError != null)
            DiagnosticField.nativeCode: error.osError!.errorCode,
        });
    rethrow;
  }
  await checkAndroidDownloadWorkspace(
      parent: parent, control: control, diagnostics: diagnostics);
}

/// App-owned: accepted persistence and private IO drain before SQLite closes.
/// The selected destination is independent of the library's read-only roots.
final class AndroidDownloadStorageController extends ChangeNotifier {
  AndroidDownloadStorageController(
      {required this.settings,
      DiagnosticsService diagnostics = const NoopDiagnosticsService(),
      this.documents = const AndroidDownloadFolders(),
      DownloadDestinationChecker? destinationChecker,
      this.onUseDestination,
      this.onClearDestination,
      DownloadWorkspaceCheck? checkWorkspace})
      : _diagnostics = diagnostics,
        _destinationChecker = destinationChecker ??
            AndroidDownloadDestinationCheck.audioPublication(),
        _checkWorkspace = checkWorkspace ??
            ((control) => _checkPrivateStorage(control, diagnostics));

  static const settingKey = 'android.download_destination.v1';
  final SettingsRepository settings;
  final DownloadFolderDocuments documents;
  final DownloadWorkspaceCheck _checkWorkspace;
  final DownloadDestinationChecker _destinationChecker;
  final Future<void> Function(ContentUriAudioSource, String?)? onUseDestination;
  final Future<void> Function()? onClearDestination;
  bool get canUseDestination => onUseDestination != null;
  final DiagnosticsService _diagnostics;
  bool _destinationCheck = false;
  ContentUriAudioSource? _folder;
  DownloadFolderAccess? _access;
  String? _message;
  bool _loaded = false, _busy = false, _closed = false;
  LibraryScanControl? _control;
  Future<void>? _pending, _closing;

  ContentUriAudioSource? get folder => _folder;
  DownloadFolderAccess? get access => _access;
  String? get message => _message;
  bool get loaded => _loaded;
  bool get busy => _busy;
  bool get checkingWorkspace => _control != null && !_destinationCheck;
  bool get checkingDestination => _control != null && _destinationCheck;
  String get folderName => _access?.name ?? 'Выбранная папка';

  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) {
    if (_closed || _busy) return Future.value();
    _busy = true;
    _message = null;
    // Install the drain future before notifying listeners (including shutdown).
    final done = Completer<void>();
    _pending = done.future;
    _changed();
    unawaited(Future<void>.sync(() async {
      try {
        if (!_closed) await action();
      } on LibraryScanCancelled {
        _message = 'Проверка остановлена. Можно запустить её снова.';
      } on FileSystemException catch (error) {
        _message = const {28, 122, 112}.contains(error.osError?.errorCode)
            ? 'Недостаточно свободного места. Освободи память и повтори проверку.'
            : 'Хранилище недоступно. Проверь свободное место и доступ.';
      } on Object {
        // Never put platform exception text, document URIs or paths in the UI.
        _message = _control != null
            ? 'Не удалось проверить внутреннее хранилище. Создай диагностический '
                'отчёт в настройках и передай его для проверки.'
            : 'Не удалось выполнить проверку. Проверь доступ к папке '
                'и свободное место, затем повтори действие.';
      } finally {
        _control = null;
        _destinationCheck = false;
        _busy = false;
        _pending = null;
        done.complete();
        _changed();
      }
    }));
    return done.future;
  }

  Future<void> initialize() => _run(() async {
        if (_loaded) return;
        final value = await settings.readString(settingKey);
        if (_closed) return;
        if (value != null) {
          _folder = AndroidDownloadFolders.parseTree(value);
          // Keep a saved choice when access disappears; allow re-selection.
          _access = null;
          await _inspect();
        }
        _loaded = true;
      });

  Future<void> _inspect() async {
    _access = null;
    final result = await documents.inspectDownloadFolder(_folder!);
    if (_closed) return;
    _access = result;
    _message = result.usable
        ? 'Доступ сохранён. Папка поддерживает создание файлов.'
        : 'Нет доступа для создания файлов. Выбери папку заново.';
  }

  Future<void> chooseFolder() => _run(() async {
        final selected = await documents.pickDownloadFolder();
        if (_closed || selected == null) return;
        final result = await documents.inspectDownloadFolder(selected);
        if (_closed) return;
        if (!result.usable) {
          _message =
              'В этой папке нельзя создавать файлы. Выбери другую папку.';
          return;
        }
        await settings.writeString(settingKey, selected.storageValue);
        if (_closed) return;
        _folder = selected;
        _access = result;
        _loaded = true;
        _message = 'Папка сохранена. Музыкальные файлы пока не записывались.';
        if (onUseDestination != null) {
          await onUseDestination!(selected, result.name);
          _message =
              'Папка подключена к загрузкам. Новые треки появятся в библиотеке автоматически.';
        }
      });

  Future<void> useDestination() => _run(() async {
        final selected = _folder;
        if (selected == null || onUseDestination == null) return;
        await _inspect();
        if (_closed || _access?.usable != true) return;
        await onUseDestination!(selected, _access?.name);
        _message =
            'Папка подключена к загрузкам. Новые треки появятся в библиотеке автоматически.';
      });

  Future<void> inspectFolder() => _run(() async {
        if (_folder != null) await _inspect();
      });

  Future<void> forgetFolder() => _run(() async {
        await onClearDestination?.call();
        await settings.delete(settingKey);
        if (_closed) return;
        _folder = null;
        _access = null;
        _loaded = true;
        _message = 'Выбор папки сброшен.';
      });

  Future<void> checkWorkspace() => _run(() async {
        final control = _control = LibraryScanControl();
        _changed();
        await _checkWorkspace(control);
        control.throwIfCancelled();
        _message = 'Временное хранилище проверено: запись, чтение, блокировка '
            'и лимит работают. Тестовые данные удалены.';
      });

  void cancelCheck() => _control?.cancel();

  Future<void> checkDestination() => _run(() async {
        final folder = _folder;
        if (folder == null || _access?.usable != true) return;
        _destinationCheck = true;
        final control = _control = LibraryScanControl();
        _changed();
        _diagnostics.record(DiagnosticEvent.androidDestinationCheckStarted);
        final DownloadDestinationResult result;
        try {
          result = await _destinationChecker.check(folder, control);
        } on Object catch (error) {
          _diagnostics.record(DiagnosticEvent.androidDestinationCheckFailed,
              error: error);
          _message =
              'Не удалось проверить запись. Создай диагностический отчёт '
              'в настройках и передай его для проверки.';
          return;
        }
        _diagnostics
            .record(DiagnosticEvent.androidDestinationCheckFinished, fields: {
          DiagnosticField.destinationStage: result.stage,
          DiagnosticField.destinationStatus: result.status.index,
          DiagnosticField.sourceBytes: result.verifiedBytes,
          DiagnosticField.recoveredProbes: result.recovered,
          DiagnosticField.retainedProbes: result.retained,
          DiagnosticField.publicationRecoveryChecks: result.recoveryChecks,
        });
        if (result.status == DownloadDestinationStatus.accessDenied) {
          _access = null;
        }
        _message = switch (result.status) {
          DownloadDestinationStatus.ready =>
            '${result.recoveryChecks == 3 ? 'Запись и восстановление проверены. Тестовые файлы удалены.' : 'Запись в папку проверена. Содержимое совпадает, тестовый файл удалён.'}'
                '${result.recovered > 0 ? ' Удалены тестовые файлы предыдущей проверки: ${result.recovered}.' : ''}',
          DownloadDestinationStatus.cancelled =>
            'Проверка остановлена. Можно запустить её снова.',
          DownloadDestinationStatus.accessDenied =>
            'Доступ к папке потерян. Выбери её заново.',
          DownloadDestinationStatus.unsupported =>
            'Эта папка не поддерживает проверку записи. Попробуй другую папку.',
          DownloadDestinationStatus.busy =>
            'Папка уже проверяется. Повтори позже.',
          DownloadDestinationStatus.retained =>
            'Остались данные незавершённой проверки. Следующая проверка '
                'сначала попробует восстановить её результат. Верни доступ '
                'к папке и повтори проверку. Если сообщение остаётся, создай '
                'диагностический отчёт.',
          DownloadDestinationStatus.io =>
            'Не удалось проверить запись. Проверь доступ и свободное место. '
                'Если ошибка повторяется, создай диагностический отчёт.',
        };
      });

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _control?.cancel();
    return _closing = _closeAfter(_pending);
  }

  Future<void> _closeAfter(Future<void>? pending) async {
    await pending;
    await _destinationChecker.close();
  }
}
