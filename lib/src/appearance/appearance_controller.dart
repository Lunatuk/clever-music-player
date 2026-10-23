import 'package:flutter/foundation.dart';

import '../domain/repositories/settings_repository.dart';
import 'appearance_settings.dart';

enum AppearanceFailure { load, save }

/// Optimistic visual updates, ordered durable writes, and drained shutdown.
/// A null store is an isolated in-memory controller for the design gallery.
final class AppearanceController extends ChangeNotifier {
  AppearanceController({SettingsRepository? settings}) : _settings = settings;
  final SettingsRepository? _settings;
  AppearanceSettings _value = const AppearanceSettings();
  AppearanceSettings get value => _value;
  AppearanceFailure? failure;
  bool initialized = false;
  bool get isSaving => _writes > 0;
  int _revision = 0, _writes = 0;
  bool _closed = false, _disposed = false;
  Future<void>? _initializing, _closing;
  Future<void> _tail = Future.value();

  Future<void> initialize() => _initializing ??= _load();
  Future<void> _load() async {
    final revision = _revision;
    try {
      final raw = await _settings?.readString(AppearanceSettings.storageKey);
      if (!_closed && revision == _revision) {
        _value = AppearanceSettings.decode(raw);
        failure = null;
      }
    } catch (_) {
      if (!_closed && revision == _revision) failure = AppearanceFailure.load;
    } finally {
      initialized = true;
      _notify();
    }
  }

  Future<void> update(AppearanceSettings next) {
    if (_closed) return Future.value();
    // Normalize public constructor values as well as deserialized input.
    next = next.copyWith();
    if (next == value && failure == null) return _tail;
    _value = next;
    failure = null;
    final revision = ++_revision;
    if (_settings == null) {
      initialized = true;
      _notify();
      return Future.value();
    }
    final encoded = next.encode();
    _writes++;
    _notify();
    return _tail = _tail.then((_) async {
      try {
        await _settings.writeString(AppearanceSettings.storageKey, encoded);
        if (revision == _revision) failure = null;
      } catch (_) {
        if (revision == _revision) failure = AppearanceFailure.save;
      } finally {
        _writes--;
        _notify();
      }
    });
  }

  Future<void> retry() {
    if (_closed) return Future.value();
    if (failure == AppearanceFailure.load) {
      _initializing = null;
      return initialize();
    }
    return update(value);
  }

  Future<void> reset() => update(const AppearanceSettings());
  void _notify() {
    if (!_closed && !_disposed) notifyListeners();
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    await _initializing;
    await _tail;
  }

  @override
  void dispose() {
    _disposed = true;
    _closed = true;
    super.dispose();
  }
}
