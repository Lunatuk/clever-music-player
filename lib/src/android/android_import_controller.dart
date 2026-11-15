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
import 'android_import_metadata_cache.dart';

/// Owns explicit SAF imports. Cancellation flushes fully prepared tracks; close
/// drains accepted provider/cache/DB work before the app closes SQLite.
final class AndroidImportController extends ChangeNotifier {
  AndroidImportController(
      {required this.documents,
      required this.imports,
      required this.artworkCache,
      AudioDocumentFolders? folders,
      this.bookmarks,
      this.metadataCache,
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
  final AndroidImportMetadataCache? metadataCache;
  bool _forceRead = false, _cacheDisabled = false;
  bool _batchDisabled = false;
  static int _nextInspectionBatch = 0;
  int? _activeInspectionBatch;
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
  Future<void> refreshFolder(SavedAudioFolder folder,
          {bool forceRead = false}) =>
      _run(folder: true, savedTree: folder.source, forceRead: forceRead);
  Future<void> restoreFolderAccess(SavedAudioFolder folder) =>
      _run(folder: true, savedTree: folder.source, restore: true);
  Future<void> refreshSavedFolders() => _run(folder: true, allSaved: true);

  Future<void> _run(
      {required bool folder,
      ContentUriAudioSource? savedTree,
      bool restore = false,
      bool allSaved = false,
      bool forceRead = false}) async {
    if (_closed || _busy || (folder && _folders == null)) return;
    _busy = true;
    _cancelRequested = false;
    _folderImport = folder;
    _processed = _total = _visited = _imported = _failed = 0;
    _failedFolders = 0;
    _sourceIdentities = 0;
    _forceRead = forceRead;
    _cacheDisabled = false;
    _batchDisabled = false;
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
        _message = 'Не удалось завершить импорт. Обработано: $_imported. '
            'Проверьте доступ и повторите выбор.';
      }
    } finally {
      if (started && !_closed && _message == null) {
        _message = '${_cancelRequested ? 'Импорт остановлен. ' : ''}'
            'Обработано: $_imported.'
            '${_sourceIdentities == 0 ? '' : ' Ссылок Яндекса: $_sourceIdentities.'}'
            '${_failed == 0 ? '' : ' Не добавлено: $_failed. Выберите эти файлы заново.'}'
            '${_failedFolders == 0 ? '' : ' Не удалось обновить папок: $_failedFolders. Проверьте доступ на экране «Папки».'}'
            ' Время: ${((_tick() - _profile!.startedUs) / 1000000).toStringAsFixed(1)} с.'
            '${metadataCache == null ? '' : ' Без повторного чтения: ${_profile!.cacheHits}.'}';
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
    final pageSources = sources.toSet().toList(growable: false);
    final pending = <_PreparedImport>[];
    var batchAt = _tick();
    try {
      AndroidMetadataCachePage? cachePage;
      final cache = metadataCache;
      if (!_stopped &&
          documents is AudioDocumentInspection &&
          !_forceRead &&
          !_cacheDisabled &&
          cache is AndroidImportMetadataCachePages &&
          pageSources.length <= TrackImportRepository.maxBatchSize) {
        final at = _tick();
        try {
          cachePage = await (cache as AndroidImportMetadataCachePages)
              .prepareSources(pageSources);
          _profile!.cacheDatabaseUs += cachePage.databaseUs;
          _profile!.cacheDatabaseQueries += cachePage.databaseQueries;
        } on Object {
          _profile!.cacheFailures++;
          _cacheDisabled = true;
        } finally {
          _profile!.cacheUs += _tick() - at;
        }
      }
      Map<String, _NativeCachedCheck>? nativeChecks;
      for (var index = 0; index < pageSources.length; index++) {
        final source = pageSources[index];
        if (_stopped) break;
        try {
          late final AudioDocumentMetadata metadata;
          if (nativeChecks == null &&
              !_batchDisabled &&
              !_forceRead &&
              !_cacheDisabled &&
              cachePage != null &&
              cachePage.mayContain(source) &&
              documents is BatchedAudioDocumentInspection) {
            nativeChecks =
                await _prepareNativeChecks(pageSources, index, cachePage);
          }
          if (_stopped) break;
          final checked = nativeChecks?.remove(source.storageValue);
          if (nativeChecks?.isEmpty == true) nativeChecks = null;
          CachedAndroidAudio? cached;
          if (checked != null && checked.fresh(_tick())) {
            cached = await _useNativeCheck(checked, cachePage!);
          } else {
            if (checked != null) {
              _profile!.batchStale++;
              _batchDisabled = true;
              nativeChecks = null;
            }
            cached = await _cachedAudio(source, cachePage);
          }
          if (_stopped) break;
          if (cached != null) {
            metadata = cached.metadata;
          } else {
            // Do not hold proofs for following documents across a slow full read.
            nativeChecks = null;
            final readAt = _tick();
            try {
              metadata = await documents.readAudio(source);
              _profile!.addNative(metadata.readTimings);
            } finally {
              _profile!.metadataReads++;
              _profile!.metadataUs += _tick() - readAt;
            }
          }
          if (_stopped) break;
          final comments = metadata.sourceComments;
          final identity =
              comments == null ? null : embeddedYandexIdentity(comments);
          final merged = mergeAudioDocumentMetadata(metadata);
          CachedArtwork? artwork = cached?.artwork;
          var artworkSaved = true;
          final artworkAt = _tick();
          try {
            if (cached == null) {
              artwork = await artworkCache.saveEmbeddedArtwork(
                  metadata.artwork == null
                      ? null
                      : EmbeddedArtwork(
                          bytes: metadata.artwork!, mimeType: 'image/webp'));
            }
          } on Object {
            artworkSaved = false;
            /* A cover failure must not prevent importing readable music. */
          } finally {
            _profile!.artworkUs += _tick() - artworkAt;
          }
          if (_stopped) break;
          final now = _clock();
          final revision = metadata.cacheRevision;
          final cacheEntry = cached == null &&
                  revision != null &&
                  metadata.size == revision.size &&
                  comments != null &&
                  artworkSaved
              ? CachedAndroidAudio.fromRead(revision, metadata, artwork)
              : null;
          if (cached == null && cacheEntry == null && metadataCache != null) {
            _profile!.cacheIneligible++;
          }
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
              cacheEntry: cacheEntry,
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

  Future<Map<String, _NativeCachedCheck>?> _prepareNativeChecks(
      List<ContentUriAudioSource> sources,
      int first,
      AndroidMetadataCachePage page) async {
    final candidates = <CachedAndroidAudio>[];
    final requests = <AudioInspectionBatchRequest>[];
    final decodeAt = _tick();
    try {
      for (var i = first;
          i < sources.length && requests.length < maxAudioInspectionBatchSize;
          i++) {
        if (_stopped || !page.mayContain(sources[i])) break;
        final result = page.candidate(sources[i]);
        _profile!.cacheDecodeUs += result.decodeUs;
        if (result.value == null) break;
        candidates.add(result.value!);
        requests.add(AudioInspectionBatchRequest(sources[i],
            artworkPath: result.value!.artwork?.path,
            artworkHash: result.value!.artwork?.hash));
      }
    } finally {
      final elapsed = _tick() - decodeAt;
      _profile!.cacheUs += elapsed;
      _profile!.cacheLookupUs += elapsed;
    }
    if (requests.isEmpty || _stopped) return null;
    final id = ++_nextInspectionBatch;
    final at = _tick();
    _activeInspectionBatch = id;
    _profile!.inspectionBatches++;
    try {
      final result = await (documents as BatchedAudioDocumentInspection)
          .inspectAudioBatch(id, requests);
      if (_stopped) return null;
      if (result.cancelled ||
          result.entries.isEmpty ||
          result.entries.length > requests.length) {
        throw const FormatException('Incomplete inspection batch');
      }
      for (var i = 0; i < result.entries.length; i++) {
        if (result.entries[i].source != requests[i].source ||
            result.entries[i].ageUs < 0) {
          throw const FormatException(
              'Inspection batch does not match request');
        }
        if (!result.entries[i].failed &&
            ((requests[i].hasArtwork &&
                    result.entries[i].artwork == AudioArtworkCheck.absent) ||
                (!requests[i].hasArtwork &&
                    result.entries[i].artwork != AudioArtworkCheck.absent))) {
          throw const FormatException('Artwork proof does not match request');
        }
      }
      _profile!.batchItems += result.entries.length;
      _profile!.cacheChecks += result.entries.length;
      for (final entry in result.entries) {
        _profile!.addInspection(entry.inspection.timings);
        if (!entry.failed && entry.artwork != AudioArtworkCheck.unchecked) {
          _profile!.nativeArtworkChecks++;
        }
      }
      return {
        for (var i = 0; i < result.entries.length; i++)
          requests[i].source.storageValue:
              _NativeCachedCheck(candidates[i], result.entries[i], at),
      };
    } on Object {
      if (!_stopped) {
        _profile!.batchFallbacks++;
        _batchDisabled = true;
      }
      return null;
    } finally {
      final elapsed = _tick() - at;
      _profile!.cacheUs += elapsed;
      _profile!.cacheInspectionUs += elapsed;
      if (_activeInspectionBatch == id) _activeInspectionBatch = null;
    }
  }

  Future<CachedAndroidAudio?> _useNativeCheck(
      _NativeCachedCheck check, AndroidMetadataCachePage page) async {
    final entry = check.entry;
    CachedAndroidAudio? cached;
    final at = _tick();
    try {
      final revision = entry.inspection.revision;
      if (entry.failed) _profile!.cacheFailures++;
      if (!entry.failed && revision == check.candidate.revision) {
        switch (entry.artwork) {
          case AudioArtworkCheck.available:
          case AudioArtworkCheck.absent:
            cached = check.candidate;
            break;
          case AudioArtworkCheck.missing:
            break;
          case AudioArtworkCheck.unchecked:
            final result = await page.lookup(revision!);
            _profile!.cacheDecodeUs += result.decodeUs;
            _profile!.cacheArtworkStatUs += result.artworkStatUs;
            cached = result.value;
            break;
        }
      }
      if (!check.fresh(_tick())) {
        _profile!.batchStale++;
        _batchDisabled = true;
        cached = null;
      }
    } on Object {
      _profile!.cacheFailures++;
      _cacheDisabled = true;
    } finally {
      final elapsed = _tick() - at;
      _profile!.cacheLookupUs += elapsed;
      _profile!.cacheUs += elapsed;
    }
    if (cached == null) {
      _profile!.cacheMisses++;
    } else {
      _profile!.cacheHits++;
    }
    return cached;
  }

  Future<void> _cancelNativeInspection() async {
    final id = _activeInspectionBatch;
    if (id == null || documents is! BatchedAudioDocumentInspection) return;
    try {
      await (documents as BatchedAudioDocumentInspection)
          .cancelAudioInspectionBatch(id);
    } on Object {
      // Late results are still ignored and close drains the accepted call.
    }
  }

  Future<CachedAndroidAudio?> _cachedAudio(
      ContentUriAudioSource source, AndroidMetadataCachePage? page) async {
    if (metadataCache == null) return null;
    if (_forceRead && !_cacheDisabled) {
      final at = _tick();
      try {
        await metadataCache!.invalidateSource(source);
      } on Object {
        _profile!.cacheFailures++;
        _cacheDisabled = true;
      } finally {
        _profile!.cacheUs += _tick() - at;
      }
    }
    if (_forceRead || _cacheDisabled || documents is! AudioDocumentInspection) {
      _profile!.cacheMisses++;
      return null;
    }
    if (page != null && !page.mayContain(source)) {
      // No usable snapshot exists. The ordinary reader performs its own fresh
      // permission/descriptor/stamp checks; avoid a duplicate preliminary call.
      _profile!.cacheMisses++;
      _profile!.cacheInspectionSkipped++;
      return null;
    }
    final at = _tick();
    _profile!.cacheChecks++;
    try {
      AudioDocumentRevision? revision;
      final inspectAt = _tick();
      try {
        if (documents is ProfiledAudioDocumentInspection) {
          final result = await (documents as ProfiledAudioDocumentInspection)
              .inspectProfiledAudio(source);
          revision = result.revision;
          _profile!.addInspection(result.timings);
        } else {
          revision =
              await (documents as AudioDocumentInspection).inspectAudio(source);
        }
      } on Object {
        _profile!.cacheFailures++;
      } finally {
        _profile!.cacheInspectionUs += _tick() - inspectAt;
      }
      if (_stopped) return null;
      CachedAndroidAudio? cached;
      if (revision != null) {
        final lookupAt = _tick();
        try {
          if (page != null) {
            final result = await page.lookup(revision);
            cached = result.value;
            _profile!.cacheDecodeUs += result.decodeUs;
            _profile!.cacheArtworkStatUs += result.artworkStatUs;
          } else {
            _profile!.cacheLegacyLookups++;
            cached = await metadataCache!.lookup(revision);
          }
        } on Object {
          _profile!.cacheFailures++;
          _cacheDisabled = true;
        } finally {
          _profile!.cacheLookupUs += _tick() - lookupAt;
        }
      }
      if (cached == null) {
        _profile!.cacheMisses++;
      } else {
        _profile!.cacheHits++;
      }
      return cached;
    } finally {
      _profile!.cacheUs += _tick() - at;
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
      Future<List<int>> write() => imports.upsertScannedTracks([
            for (final row in batch) row.track
          ], embeddedYandexIdentities: {
            for (final row in batch)
              if (row.commentsRead) row.track.filePath: row.identity,
          });
      final entries = [
        for (final row in batch)
          if (row.cacheEntry != null) row.cacheEntry!
      ];
      if (metadataCache != null && !_cacheDisabled && entries.isNotEmpty) {
        try {
          await metadataCache!.commit(entries, write);
          _profile!.cacheWrites += entries.length;
        } on AndroidMetadataCacheWriteFailure {
          _cacheDisabled = true;
          _profile!.cacheFailures++;
          _profile!.batches++;
          await write();
        }
      } else {
        await write();
      }
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
        DiagnosticField.metadataCacheHits: profile.cacheHits,
        DiagnosticField.metadataCacheMisses: profile.cacheMisses,
        DiagnosticField.metadataCacheChecks: profile.cacheChecks,
        DiagnosticField.metadataCacheUs: profile.cacheUs,
        DiagnosticField.metadataCacheFailures: profile.cacheFailures,
        DiagnosticField.metadataForceRead: _forceRead,
        DiagnosticField.metadataCacheWrites: profile.cacheWrites,
        DiagnosticField.metadataCacheIneligible: profile.cacheIneligible,
        DiagnosticField.metadataCacheDatabaseUs: profile.cacheDatabaseUs,
        DiagnosticField.metadataCacheDatabaseQueries:
            profile.cacheDatabaseQueries,
        DiagnosticField.metadataCacheInspectionUs: profile.cacheInspectionUs,
        DiagnosticField.metadataCacheLookupUs: profile.cacheLookupUs,
        DiagnosticField.metadataCacheDecodeUs: profile.cacheDecodeUs,
        DiagnosticField.metadataCacheArtworkStatUs: profile.cacheArtworkStatUs,
        DiagnosticField.metadataCacheLegacyLookups: profile.cacheLegacyLookups,
        DiagnosticField.metadataCacheInspectionSkipped:
            profile.cacheInspectionSkipped,
        DiagnosticField.nativeInspectionReads: profile.inspectionReads,
        DiagnosticField.nativeInspectionUs: profile.inspectionUs,
        DiagnosticField.nativeInspectionPermissionUs:
            profile.inspectionPermissionUs,
        DiagnosticField.nativeInspectionRevisionUs:
            profile.inspectionRevisionUs,
        DiagnosticField.nativeInspectionVisibilityUs:
            profile.inspectionVisibilityUs,
        DiagnosticField.nativeInspectionDescriptorUs:
            profile.inspectionDescriptorUs,
        DiagnosticField.nativeInspectionArtworkUs: profile.inspectionArtworkUs,
        DiagnosticField.metadataCacheInspectionBatches:
            profile.inspectionBatches,
        DiagnosticField.metadataCacheBatchItems: profile.batchItems,
        DiagnosticField.metadataCacheBatchFallbacks: profile.batchFallbacks,
        DiagnosticField.metadataCacheBatchStale: profile.batchStale,
        DiagnosticField.metadataCacheNativeArtworkChecks:
            profile.nativeArtworkChecks,
      });
    } on Object {
      // Diagnostics must not affect import completion or shutdown.
    }
  }

  Future<void> cancel() async {
    if (!canCancel) return;
    _cancelRequested = true;
    _notifyProgress(force: true);
    await _cancelNativeInspection();
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
      _cancelNativeInspection,
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
      {required this.identity, required this.commentsRead, this.cacheEntry});
  final Track track;
  final ExternalTrackIdentity? identity;
  final bool commentsRead;
  final CachedAndroidAudio? cacheEntry;
}

final class _NativeCachedCheck {
  const _NativeCachedCheck(this.candidate, this.entry, this.startedUs);
  final CachedAndroidAudio candidate;
  final AudioInspectionBatchEntry entry;
  final int startedUs;
  bool fresh(int now) =>
      entry.ageUs <= audioInspectionProofLifetimeUs &&
      now >= startedUs &&
      now - startedUs <= audioInspectionProofLifetimeUs;
}

final class _ImportProfile {
  _ImportProfile(this.startedUs);
  final int startedUs;
  bool interrupted = false;
  int inspectionBatches = 0, batchItems = 0, batchFallbacks = 0, batchStale = 0;
  int nativeArtworkChecks = 0, inspectionArtworkUs = 0;
  int cacheInspectionSkipped = 0;
  int cacheDatabaseUs = 0, cacheDatabaseQueries = 0, cacheInspectionUs = 0;
  int cacheLookupUs = 0,
      cacheDecodeUs = 0,
      cacheArtworkStatUs = 0,
      cacheLegacyLookups = 0;
  int inspectionReads = 0, inspectionUs = 0, inspectionPermissionUs = 0;
  int inspectionRevisionUs = 0,
      inspectionVisibilityUs = 0,
      inspectionDescriptorUs = 0;
  int cacheWrites = 0, cacheIneligible = 0;
  int metadataReads = 0, metadataUs = 0, artworkUs = 0, folderUs = 0;
  int databaseUs = 0, batches = 0, fallbackRows = 0, progressUpdates = 0;
  int nativeReads = 0, nativeReadUs = 0, nativeQueryUs = 0;
  int nativeSourceUs = 0, nativeTagsUs = 0, nativeArtworkUs = 0;
  int cacheHits = 0,
      cacheMisses = 0,
      cacheChecks = 0,
      cacheUs = 0,
      cacheFailures = 0;

  void addInspection(AudioDocumentInspectionTimings? timings) {
    if (timings == null) return;
    inspectionReads++;
    inspectionUs += timings.totalUs;
    inspectionPermissionUs += timings.permissionUs;
    inspectionRevisionUs += timings.revisionUs;
    inspectionVisibilityUs += timings.visibilityUs;
    inspectionDescriptorUs += timings.descriptorUs;
    inspectionArtworkUs += timings.artworkUs;
  }

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
