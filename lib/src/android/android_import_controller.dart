import 'package:flutter/foundation.dart';

import '../core/async_lifecycle.dart';
import '../diagnostics/diagnostics_service.dart';
import '../domain/models/audio_source_reference.dart';
import '../domain/models/external_track_ref.dart';
import '../domain/models/track.dart';
import '../domain/repositories/track_repository.dart';
import '../library/artwork_cache_service.dart';
import '../library/embedded_yandex_identity.dart';
import '../library/metadata_enrichment.dart';
import 'audio_documents.dart';
import 'android_folder_bookmarks.dart';
import 'android_audio_metadata.dart';

/// Owns explicit SAF imports. Cancellation flushes fully prepared tracks; close
/// drains accepted provider/cache/DB work before the app closes SQLite.
final class AndroidImportController extends ChangeNotifier {
  AndroidImportController(
      {required this.documents,
      required this.imports,
      required this.artworkCache,
      AudioDocumentFolders? folders,
      this.bookmarks,
      this.diagnostics = const NoopDiagnosticsService(),
      DateTime Function()? clock,
      int Function()? monotonicMicroseconds})
      : _folders = folders ??
            (documents is AudioDocumentFolders
                ? documents as AudioDocumentFolders
                : null),
        _clock = clock ?? DateTime.now,
        _tick = monotonicMicroseconds ?? _monotonicClock();
  final AudioDocuments documents;
  final TrackImportRepository imports;
  final ArtworkCacheService artworkCache;
  final AudioDocumentFolders? _folders;
  final AndroidFolderBookmarks? bookmarks;
  final DateTime Function() _clock;
  final DiagnosticsService diagnostics;
  final int Function() _tick;
  _ImportProfile? _profile;
  int? _lastProgressUs;
  bool _closed = false,
      _busy = false,
      _cancelRequested = false,
      _folderImport = false;
  int _processed = 0, _total = 0, _visited = 0, _imported = 0, _failed = 0;
  int _failedFolders = 0;
  int _sourceIdentities = 0;
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
    _sourceIdentities = 0;
    _message = null;
    _profile = null;
    _lastProgressUs = null;
    var started = false;
    _notifyProgress(force: true);
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
          _profile = _ImportProfile(_tick());
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
          _profile = _ImportProfile(_tick());
          _processing = _importFolder(tree, remember: savedTree == null);
        }
      } else {
        final selection = await documents.pickAudio();
        if (_stopped || selection == null) return;
        started = true;
        final sources = selection.sources.toSet().toList(growable: false);
        _total = sources.length;
        _failed = selection.skipped;
        _profile = _ImportProfile(_tick());
        _processing = _importSources(sources);
      }
      _notifyProgress(force: true);
      await _processing;
    } on Object {
      if (!_stopped) {
        _profile?.interrupted = true;
        _message =
            'Не удалось завершить импорт. Добавлено в библиотеку: $_imported. '
            'Проверьте доступ и повторите выбор.';
      }
    } finally {
      if (started && !_closed && _message == null) {
        _message = '${_cancelRequested ? 'Импорт остановлен. ' : ''}'
            'Добавлено в библиотеку: $_imported.'
            '${_sourceIdentities == 0 ? '' : ' Ссылок Яндекса: $_sourceIdentities.'}'
            '${_failed == 0 ? '' : ' Не добавлено: $_failed. Выберите эти файлы заново.'}'
            '${_failedFolders == 0 ? '' : ' Не удалось обновить папок: $_failedFolders. Проверьте доступ на экране «Папки».'}'
            ' Время: ${((_tick() - _profile!.startedUs) / 1000000).toStringAsFixed(1)} с.';
      }
      // Record before the final notification can start another run or close us.
      _recordProfile();
      _processing = null;
      _folderSession = null;
      _folderClosing = null;
      _busy = false;
      _notifyProgress(force: true);
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
      final openedAt = _tick();
      try {
        _folderSession = await _folders!.openAudioFolder(tree);
      } finally {
        _profile!.folderUs += _tick() - openedAt;
      }
      while (!_stopped) {
        final pageAt = _tick();
        late final AudioFolderPage page;
        try {
          page = await _folders.readAudioFolderPage(_folderSession!);
        } finally {
          _profile!.folderUs += _tick() - pageAt;
        }
        if (_stopped || !_hasSavedFolder(tree)) break;
        if (page.visited < _visited ||
            (!page.done && page.visited == _visited)) {
          throw const FormatException('Обход папки не продвигается.');
        }
        _visited = page.visited;
        _total += page.sources.length;
        _notifyProgress();
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
    final pending = <_PreparedImport>[];
    var batchAt = _tick();
    try {
      for (final source in sources.toSet()) {
        if (_stopped) break;
        try {
          final metadataAt = _tick();
          late final AudioDocumentMetadata metadata;
          try {
            metadata = await documents.readAudio(source);
            _profile!.addNative(metadata.readTimings);
          } finally {
            _profile!.metadataReads++;
            _profile!.metadataUs += _tick() - metadataAt;
          }
          if (_stopped) break;
          final comments = metadata.sourceComments;
          final identity =
              comments == null ? null : embeddedYandexIdentity(comments);
          final merged = mergeAudioDocumentMetadata(metadata);
          CachedArtwork? artwork;
          final artworkAt = _tick();
          try {
            artwork = await artworkCache.saveEmbeddedArtwork(
                metadata.artwork == null
                    ? null
                    : EmbeddedArtwork(
                        bytes: metadata.artwork!, mimeType: 'image/webp'));
          } on Object {
            /* A cover failure must not prevent importing readable music. */
          } finally {
            _profile!.artworkUs += _tick() - artworkAt;
          }
          if (_stopped) break;
          final now = _clock();
          pending.add(_PreparedImport(
              Track.fromSource(
                source: source,
                libraryFolderId: libraryFolderId,
                title: merged.title,
                artist: merged.artist,
                album: merged.album,
                albumArtist: merged.albumArtist,
                genre: merged.genre,
                duration: merged.duration,
                fileSizeBytes: metadata.size,
                artworkPath: artwork?.path,
                artworkHash: artwork?.hash,
                artworkMimeType: artwork?.mimeType,
                metadataSource: merged.source,
                metadataConfidence: merged.confidence,
                addedAt: now,
                updatedAt: now,
                lastSeenAt: now,
              ),
              identity: identity,
              commentsRead: comments != null));
        } on Object {
          if (_stopped) break;
          _failed++;
        }
        _processed++;
        // Check the time budget after every completed read, including failures.
        // A provider call already in flight cannot be interrupted by this budget.
        if (pending.length >= TrackImportRepository.maxBatchSize ||
            _tick() - batchAt >= 500000) {
          await _flushPrepared(pending);
          batchAt = _tick();
        }
        _notifyProgress();
      }
    } finally {
      // These records no longer need the provider. Keep them on cancel/close,
      // while the controller still owns the database lifetime.
      await _flushPrepared(pending);
    }
  }

  Future<void> _flushPrepared(List<_PreparedImport> pending) async {
    if (pending.isEmpty) return;
    final batch = List<_PreparedImport>.of(pending);
    pending.clear();
    try {
      await _writePrepared(batch);
    } on Object {
      if (batch.length == 1) {
        _failed++;
        return;
      }
      // The repository contract is atomic. Isolate bad rows without discarding
      // readable neighbours or retrying a failed batch indefinitely.
      for (final row in batch) {
        _profile!.fallbackRows++;
        try {
          await _writePrepared([row]);
        } on Object {
          _failed++;
        }
      }
    }
  }

  Future<void> _writePrepared(List<_PreparedImport> batch) async {
    final at = _tick();
    _profile!.batches++;
    try {
      await imports.upsertScannedTracks([
        for (final row in batch) row.track
      ], embeddedYandexIdentities: {
        for (final row in batch)
          if (row.commentsRead) row.track.filePath: row.identity,
      });
      _imported += batch.length;
      _sourceIdentities += batch.where((row) => row.identity != null).length;
    } finally {
      _profile!.databaseUs += _tick() - at;
    }
  }

  void _notifyProgress({bool force = false}) {
    if (_closed) return;
    final now = _tick();
    if (!force && _lastProgressUs != null && now - _lastProgressUs! < 100000) {
      return;
    }
    _lastProgressUs = now;
    if (_profile != null) _profile!.progressUpdates++;
    notifyListeners();
  }

  void _recordProfile() {
    final profile = _profile;
    if (profile == null) return;
    try {
      diagnostics.record(DiagnosticEvent.androidImportFinished, fields: {
        DiagnosticField.importCancelled: _cancelRequested,
        DiagnosticField.importFailed: profile.interrupted || _failedFolders > 0,
        DiagnosticField.importFolders: _folderImport,
        DiagnosticField.elapsedMs: (_tick() - profile.startedUs) ~/ 1000,
        DiagnosticField.scannedFiles: _processed,
        DiagnosticField.importRows: _imported,
        DiagnosticField.errorCount: _failed + _failedFolders,
        DiagnosticField.metadataReads: profile.metadataReads,
        DiagnosticField.metadataUs: profile.metadataUs,
        DiagnosticField.artworkUs: profile.artworkUs,
        DiagnosticField.fileSystemUs: profile.folderUs,
        DiagnosticField.databaseUs: profile.databaseUs,
        DiagnosticField.importBatches: profile.batches,
        DiagnosticField.importFallbackRows: profile.fallbackRows,
        DiagnosticField.progressUpdates: profile.progressUpdates,
        DiagnosticField.nativeMetadataReads: profile.nativeReads,
        DiagnosticField.nativeReadUs: profile.nativeReadUs,
        DiagnosticField.nativeQueryUs: profile.nativeQueryUs,
        DiagnosticField.nativeSourceUs: profile.nativeSourceUs,
        DiagnosticField.nativeTagsUs: profile.nativeTagsUs,
        DiagnosticField.nativeArtworkUs: profile.nativeArtworkUs,
      });
    } on Object {
      // Diagnostics must not affect import completion or shutdown.
    }
  }

  Future<void> cancel() async {
    if (!canCancel) return;
    _cancelRequested = true;
    _notifyProgress(force: true);
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

int Function() _monotonicClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsedMicroseconds;
}

final class _PreparedImport {
  const _PreparedImport(this.track,
      {required this.identity, required this.commentsRead});
  final Track track;
  final ExternalTrackIdentity? identity;
  final bool commentsRead;
}

final class _ImportProfile {
  _ImportProfile(this.startedUs);
  final int startedUs;
  bool interrupted = false;
  int metadataReads = 0, metadataUs = 0, artworkUs = 0, folderUs = 0;
  int databaseUs = 0, batches = 0, fallbackRows = 0, progressUpdates = 0;
  int nativeReads = 0, nativeReadUs = 0, nativeQueryUs = 0;
  int nativeSourceUs = 0, nativeTagsUs = 0, nativeArtworkUs = 0;

  void addNative(AudioDocumentReadTimings? timings) {
    if (timings == null) return;
    nativeReads++;
    nativeReadUs += timings.totalUs;
    nativeQueryUs += timings.queryUs;
    nativeSourceUs += timings.sourceUs;
    nativeTagsUs += timings.tagsUs;
    nativeArtworkUs += timings.artworkUs;
  }
}
