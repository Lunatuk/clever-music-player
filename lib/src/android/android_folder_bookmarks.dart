import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/async_lifecycle.dart';
import '../domain/models/audio_source_reference.dart';
import '../domain/repositories/settings_repository.dart';
import 'audio_documents.dart';

final class SavedAudioFolder {
  const SavedAudioFolder(this.source, {this.name, this.lastCompletedAt});
  final ContentUriAudioSource source;
  final String? name;
  final DateTime? lastCompletedAt;
  String get displayName =>
      name ?? source.uri.pathSegments.last.split('/').last;
}

/// Small refresh bookmarks, deliberately separate from track/source ownership.
/// Forgetting one never removes tracks or revokes grants used by existing URIs.
final class AndroidFolderBookmarks extends ChangeNotifier {
  AndroidFolderBookmarks({required this.settings, this.access});
  static const settingKey = 'android.audio_folder_bookmarks.v1';
  static const maxFolders = 128;
  static const maxBytes = 256 * 1024;
  final SettingsRepository settings;
  final AudioDocumentFolderAccess? access;
  final _operations = AsyncOperationTracker();
  List<SavedAudioFolder> _folders = const [];
  final _access = <String, AudioFolderAccess>{};
  Future<void>? _loading, _checking, _closing;
  Future<void> _tail = Future.value();
  bool _closed = false, _loaded = false, _loadFailed = false;
  List<SavedAudioFolder> get folders => _folders;
  bool get loaded => _loaded;
  bool get loadFailed => _loadFailed;
  AudioFolderAccess? accessFor(SavedAudioFolder folder) =>
      _access[folder.source.storageValue];
  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<void> initialize() => _operations.run(_ensureLoaded);
  Future<void> _ensureLoaded() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final stored = await settings.readString(settingKey);
      if (stored == null) {
        final grants = await access?.listAudioFolderGrants() ??
            const <ContentUriAudioSource>[];
        final folders = [
          for (final source in grants.toSet()) SavedAudioFolder(source)
        ];
        // Persist even an empty bootstrap: forgotten grants must not reappear.
        await settings.writeString(settingKey, _encode(folders));
        _folders = List.unmodifiable(folders);
      } else {
        _folders = _decode(stored);
      }
      _loaded = true;
    } on Object {
      _loadFailed = true;
      rethrow;
    } finally {
      _changed();
    }
  }

  Future<void> _mutate(
      List<SavedAudioFolder> Function(List<SavedAudioFolder>) update) {
    if (_closed) return Future.value();
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return _operations.run(() async {
      try {
        await previous;
        await _ensureLoaded();
        final next = update(_folders);
        final encoded = _encode(next);
        if (encoded == _encode(_folders)) return;
        await settings.writeString(settingKey, encoded);
        _folders = List.unmodifiable(next);
        _access.removeWhere(
            (uri, _) => !_folders.any((f) => f.source.storageValue == uri));
        _changed();
      } finally {
        done.complete();
      }
    });
  }

  Future<void> remember(ContentUriAudioSource tree, {String? name}) =>
      _mutate((folders) {
        if (!isAudioFolderUri(tree)) {
          throw const FormatException('Некорректная папка.');
        }
        final index = folders.indexWhere((f) => f.source == tree);
        final next = [...folders];
        final current = index < 0 ? null : folders[index];
        final folder = SavedAudioFolder(tree,
            name: name ?? current?.name,
            lastCompletedAt: current?.lastCompletedAt);
        if (index < 0) {
          next.add(folder);
        } else {
          next[index] = folder;
        }
        return next;
      });

  Future<void> markCompleted(ContentUriAudioSource tree, DateTime when) =>
      _mutate((folders) => [
            for (final f in folders)
              f.source == tree
                  ? SavedAudioFolder(f.source,
                      name: f.name, lastCompletedAt: when.toUtc())
                  : f,
          ]);
  Future<void> forget(ContentUriAudioSource tree) =>
      _mutate((folders) => folders.where((f) => f.source != tree).toList());

  Future<void> waitForWrites() => _tail;
  Future<void> updateName(ContentUriAudioSource tree, String name) =>
      _mutate((folders) => [
            for (final folder in folders)
              folder.source == tree
                  ? SavedAudioFolder(folder.source,
                      name: name, lastCompletedAt: folder.lastCompletedAt)
                  : folder,
          ]);

  Future<void> refreshAccess() {
    if (_closed) return Future.value();
    return _checking ??= _operations.run(() async {
      await _ensureLoaded();
      final inspector = access;
      if (inspector == null) return;
      for (final folder in List<SavedAudioFolder>.of(_folders)) {
        if (_closed) break;
        AudioFolderAccess result;
        try {
          result = await inspector.inspectAudioFolder(folder.source);
        } on Object {
          result = const AudioFolderAccess(readable: false);
        }
        if (!_closed && _folders.any((f) => f.source == folder.source)) {
          _access[folder.source.storageValue] = result;
          _changed();
        }
      }
    }).whenComplete(() => _checking = null);
  }

  static String _encode(List<SavedAudioFolder> folders) {
    if (folders.length > maxFolders ||
        folders.map((f) => f.source).toSet().length != folders.length) {
      throw const FormatException('Слишком много или повторные папки.');
    }
    for (final folder in folders) {
      if (!isAudioFolderUri(folder.source) ||
          (folder.name?.length ?? 0) > 256) {
        throw const FormatException('Некорректная папка.');
      }
    }
    final value = jsonEncode({
      'version': 1,
      'folders': [
        for (final f in folders)
          {
            'uri': f.source.storageValue,
            'name': f.name,
            'lastCompletedAt': f.lastCompletedAt?.toUtc().toIso8601String(),
          }
      ]
    });
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Список папок слишком большой.');
    }
    return value;
  }

  static List<SavedAudioFolder> _decode(String stored) {
    if (utf8.encode(stored).length > maxBytes) {
      throw const FormatException('Список папок слишком большой.');
    }
    final data = jsonDecode(stored);
    if (data is! Map || data['version'] != 1 || data['folders'] is! List) {
      throw const FormatException('Некорректный список папок.');
    }
    final folders = <SavedAudioFolder>[];
    for (final row in data['folders'] as List) {
      if (row is! Map ||
          row['uri'] is! String ||
          (row['name'] != null && row['name'] is! String) ||
          (row['lastCompletedAt'] != null &&
              row['lastCompletedAt'] is! String)) {
        throw const FormatException('Некорректная папка.');
      }
      final source = ContentUriAudioSource(row['uri'] as String);
      if (!isAudioFolderUri(source) ||
          (row['name'] is String && (row['name'] as String).length > 256)) {
        throw const FormatException('Некорректная папка.');
      }
      folders.add(SavedAudioFolder(source,
          name: row['name'] as String?,
          lastCompletedAt: row['lastCompletedAt'] == null
              ? null
              : DateTime.parse(row['lastCompletedAt'] as String)));
    }
    _encode(
        folders); // Validate count, uniqueness and encoded size as on writes.
    return List.unmodifiable(folders);
  }

  Future<void> close() {
    _closed = true;
    _operations.closeAdmission();
    return _closing ??= _operations.drain();
  }

  @override
  void dispose() {
    _closed = true;
    _operations.closeAdmission();
    super.dispose();
  }
}
