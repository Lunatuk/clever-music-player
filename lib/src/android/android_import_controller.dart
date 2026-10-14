import 'package:flutter/foundation.dart';

import '../core/async_lifecycle.dart';
import '../domain/models/audio_source_reference.dart';
import '../domain/models/metadata_source.dart';
import '../domain/models/track.dart';
import '../domain/repositories/track_repository.dart';
import '../library/artwork_cache_service.dart';
import '../library/metadata_enrichment.dart';
import 'audio_documents.dart';
import 'android_folder_bookmarks.dart';

/// Owns explicit SAF imports. Cancellation preserves committed tracks; close
/// drains accepted provider/cache/DB work before the app closes SQLite.
final class AndroidImportController extends ChangeNotifier {
  AndroidImportController(
      {required this.documents,
      required this.imports,
      required this.artworkCache,
      AudioDocumentFolders? folders,
      this.bookmarks,
      DateTime Function()? clock})
      : _folders = folders ??
            (documents is AudioDocumentFolders
                ? documents as AudioDocumentFolders
                : null),
        _clock = clock ?? DateTime.now;
  final AudioDocuments documents;
  final TrackImportRepository imports;
  final ArtworkCacheService artworkCache;
  final AudioDocumentFolders? _folders;
  final AndroidFolderBookmarks? bookmarks;
  final DateTime Function() _clock;
  bool _closed = false,
      _busy = false,
      _cancelRequested = false,
      _folderImport = false;
  int _processed = 0, _total = 0, _visited = 0, _imported = 0, _failed = 0;
  int _failedFolders = 0;
  String? _message;
  int? _folderSession;
  Future<void>? _processing, _closing, _folderClosing;
  bool get busy => _busy;
  bool get supportsFolders => _folders != null;
  bool get folderImport => _folderImport;
  bool get canCancel =>
      !_closed && _busy && _processing != null && !_cancelRequested;
  bool get cancelling => _cancelRequested && _busy;
  int get processed => _processed;
  int get total => _total;
  int get visited => _visited;
  String? get message => _message;
  bool get _stopped => _closed || _cancelRequested;

  Future<void> importSelection() => _run(folder: false);
  Future<void> importFolder() =>
      _folders == null ? Future.value() : _run(folder: true);
  Future<void> refreshFolder(SavedAudioFolder folder) =>
      _run(folder: true, savedTree: folder.source);
  Future<void> restoreFolderAccess(SavedAudioFolder folder) =>
      _run(folder: true, savedTree: folder.source, restore: true);
  Future<void> refreshSavedFolders() => _run(folder: true, allSaved: true);

  Future<void> _run(
      {required bool folder,
      ContentUriAudioSource? savedTree,
      bool restore = false,
      bool allSaved = false}) async {
    if (_closed || _busy || (folder && _folders == null)) return;
    _busy = true;
    _cancelRequested = false;
    _folderImport = folder;
    _processed = _total = _visited = _imported = _failed = 0;
    _failedFolders = 0;
    _message = null;
    var started = false;
    notifyListeners();
    try {
      if (folder) {
        await bookmarks?.initialize();
        await bookmarks?.waitForWrites();
        if (_stopped) return;
        if (savedTree != null && !_hasSavedFolder(savedTree)) {
          _message = 'Папка уже убрана из библиотеки.';
          return;
        }
        if (allSaved) {
          final saved = bookmarks?.folders ?? const <SavedAudioFolder>[];
          if (saved.isEmpty) {
            _message = 'Сначала добавьте папку с музыкой.';
            return;
          }
          started = true;
          _processing = _refreshFolders(saved);
        } else {
          final tree = savedTree != null && !restore
              ? savedTree
              : await _folders!.pickAudioFolder();
          if (_stopped || tree == null) return;
          if (restore && tree != savedTree) {
            _message =
                'Выбрана другая папка. Для новой папки используйте «Добавить папку».';
            return;
          }
          started = true;
          _processing = _importFolder(tree, remember: savedTree == null);
        }
      } else {
        final selection = await documents.pickAudio();
        if (_stopped || selection == null) return;
        started = true;
        final sources = selection.sources.toSet().toList(growable: false);
        _total = sources.length;
        _failed = selection.skipped;
        _processing = _importSources(sources);
      }
      if (!_closed) notifyListeners();
      await _processing;
    } on Object {
      if (!_stopped) {
        _message =
            'Не удалось завершить импорт. Добавлено в библиотеку: $_imported. '
            'Проверьте доступ и повторите выбор.';
      }
    } finally {
      if (started && !_closed && _message == null) {
        _message = '${_cancelRequested ? 'Импорт остановлен. ' : ''}'
            'Добавлено в библиотеку: $_imported.'
            '${_failed == 0 ? '' : ' Не добавлено: $_failed. Выберите эти файлы заново.'}'
            '${_failedFolders == 0 ? '' : ' Не удалось обновить папок: $_failedFolders. Проверьте доступ на экране «Папки».'}';
      }
      _processing = null;
      _folderSession = null;
      _folderClosing = null;
      _busy = false;
      if (!_closed) {
        notifyListeners();
      }
    }
  }

  bool _hasSavedFolder(ContentUriAudioSource tree) =>
      bookmarks == null ||
      bookmarks!.folders.any((folder) => folder.source == tree);

  Future<void> _importFolder(ContentUriAudioSource tree,
      {bool remember = true}) async {
    _visited = 0;
    final failuresBefore = _failed;
    var completed = false;
    try {
      if (remember) {
        await bookmarks?.remember(tree);
      } else {
        await bookmarks?.waitForWrites();
      }
      if (_stopped) return;
      if (!_hasSavedFolder(tree)) return;
      final access = documents;
      if (bookmarks != null && access is AudioDocumentFolderAccess) {
        final info = await (access as AudioDocumentFolderAccess)
            .inspectAudioFolder(tree);
        if (_stopped) return;
        if (!info.readable) throw StateError('Нет доступа к папке.');
        if (info.name != null) await bookmarks!.updateName(tree, info.name!);
        await bookmarks!.waitForWrites();
        if (_stopped) return;
        if (!_hasSavedFolder(tree)) return;
      }
      _folderSession = await _folders!.openAudioFolder(tree);
      while (!_stopped) {
        final page = await _folders.readAudioFolderPage(_folderSession!);
        if (_stopped || !_hasSavedFolder(tree)) break;
        if (page.visited < _visited ||
            (!page.done && page.visited == _visited)) {
          throw const FormatException('Обход папки не продвигается.');
        }
        _visited = page.visited;
        _total += page.sources.length;
        notifyListeners();
        await _importSources(page.sources,
            libraryFolderId: bookmarks?.folderIdFor(tree));
        if (page.done) {
          completed = true;
          break;
        }
      }
    } finally {
      try {
        await _releaseFolder();
      } finally {
        _folderSession = null;
        _folderClosing = null;
      }
    }
    if (completed && !_stopped && _failed == failuresBefore) {
      await bookmarks?.markCompleted(tree, _clock());
    }
  }

  Future<void> _refreshFolders(List<SavedAudioFolder> folders) async {
    for (final folder in folders) {
      if (_stopped) break;
      try {
        await _importFolder(folder.source, remember: false);
      } on Object {
        if (!_stopped) _failedFolders++;
      }
    }
  }

  Future<void> _importSources(Iterable<ContentUriAudioSource> sources,
      {int? libraryFolderId}) async {
    for (final source in sources) {
      if (_stopped) break;
      try {
        final metadata = await documents.readAudio(source);
        if (_stopped) break;
        CachedArtwork? artwork;
        try {
          artwork = await artworkCache.saveEmbeddedArtwork(
              metadata.artwork == null
                  ? null
                  : EmbeddedArtwork(
                      bytes: metadata.artwork!, mimeType: 'image/webp'));
        } on Object {
          /* A cover failure must not prevent importing readable music. */
        }
        if (_stopped) break;
        final now = _clock();
        await imports.upsertScannedTracks([
          Track.fromSource(
            source: source,
            libraryFolderId: libraryFolderId,
            title: metadata.title ?? metadata.name ?? 'Без названия',
            artist: metadata.artist,
            album: metadata.album,
            albumArtist: metadata.albumArtist,
            genre: metadata.genre,
            duration: metadata.duration,
            fileSizeBytes: metadata.size,
            artworkPath: artwork?.path,
            artworkHash: artwork?.hash,
            artworkMimeType: artwork?.mimeType,
            metadataSource: metadata.title == null
                ? MetadataSource.filename
                : MetadataSource.embeddedTags,
            addedAt: now,
            updatedAt: now,
            lastSeenAt: now,
          )
        ]);
        _imported++;
      } on Object {
        _failed++;
      }
      if (_closed) return;
      _processed++;
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    if (!canCancel) return;
    _cancelRequested = true;
    notifyListeners();
    await _releaseFolder();
  }

  Future<void> _releaseFolder() {
    final session = _folderSession;
    if (session == null) return Future.value();
    return _folderClosing ??= _folders!.closeAudioFolder(session);
  }

  Future<void> close() {
    _closed = true;
    _cancelRequested = true;
    return _closing ??= finishCleanup([
      _releaseFolder,
      () async {
        await _processing;
      },
    ]);
  }

  @override
  void dispose() {
    _closed = true;
    _cancelRequested = true;
    super.dispose();
  }
}
