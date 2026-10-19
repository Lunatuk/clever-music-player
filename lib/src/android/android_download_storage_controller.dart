import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/models/audio_source_reference.dart';
import '../domain/repositories/settings_repository.dart';
import '../library/library_scan_control.dart';
import 'android_download_folders.dart';
import 'android_download_workspace.dart';

typedef DownloadWorkspaceCheck = Future<void> Function(LibraryScanControl);

Future<void> _checkPrivateStorage(LibraryScanControl control) async {
  control.throwIfCancelled();
  final parent = await androidDownloadWorkspaceParent();
  await checkAndroidDownloadWorkspace(parent: parent, control: control);
}

/// App-owned: accepted persistence and private IO drain before SQLite closes.
/// The selected destination is independent of the library's read-only roots.
final class AndroidDownloadStorageController extends ChangeNotifier {
  AndroidDownloadStorageController(
      {required this.settings,
      this.documents = const AndroidDownloadFolders(),
      DownloadWorkspaceCheck? checkWorkspace})
      : _checkWorkspace = checkWorkspace ?? _checkPrivateStorage;

  static const settingKey = 'android.download_destination.v1';
  final SettingsRepository settings;
  final DownloadFolderDocuments documents;
  final DownloadWorkspaceCheck _checkWorkspace;
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
  bool get checkingWorkspace => _control != null;
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
        _message = 'Не удалось выполнить проверку. Проверь доступ к папке '
            'и свободное место, затем повтори действие.';
      } finally {
        _control = null;
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
      });

  Future<void> inspectFolder() => _run(() async {
        if (_folder != null) await _inspect();
      });

  Future<void> forgetFolder() => _run(() async {
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

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _control?.cancel();
    return _closing = _pending ?? Future.value();
  }
}
