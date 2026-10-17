import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum DiagnosticEvent {
  appCleanupFailed,
  appStarted,
  appReady,
  appFailure,
  frameworkFailure,
  asyncFailure,
  databaseOpened,
  databaseFailure,
  migrationStarted,
  migrationCompleted,
  migrationFailed,
  libraryOperationStarted,
  libraryOperationFinished,
  libraryOperationFailed,
  scanStarted,
  scanCompleted,
  scanCancelled,
  scanCancelRequested,
  scanFailed,
  scanFileFailed,
  scanTraversalFailed,
  sourceMissing,
  audioLoadStarted,
  audioLoadCompleted,
  audioLoadFailed,
  audioEngineFailed,
  audioPlayRequested,
  audioPauseRequested,
  audioStateChanged,
  audioOperationFailed,
  settingsWriteFailed,
  cacheResolved,
  cacheFailed,
  systemMediaReady,
  systemMediaFailed,
  playbackHistoryWriteFailed,
  trackFeedbackWriteFailed,
  yandexRequestStarted,
  yandexRequestCompleted,
  yandexRequestFailed,
  yandexOperationStarted,
  yandexOperationCompleted,
  yandexOperationFailed,
}

enum DiagnosticField {
  cleanupStage,
  libraryOperation,
  trackId,
  elapsedMs,
  durationMs,
  preparing,
  playing,
  cached,
  reused,
  sourceBytes,
  cacheBytes,
  deletedFiles,
  schemaFrom,
  schemaTo,
  scannedFiles,
  addedTracks,
  updatedTracks,
  missingTracks,
  errorCount,
  nativeCode,
  hashUs,
  metadataUs,
  artworkUs,
  databaseUs,
  hashedBytes,
  hashedFiles,
  nativeHashFiles,
  metadataReads,
  fileSystemUs,
  importBatches,
  importRows,
  hashReadUs,
  hashComputeUs,
  hashWorkerUs,
  hashOverheadUs,
  hashStartupUs,
  hashWorkerStarts,
  databaseLookupUs,
  databaseImportUs,
  databaseMaintenanceUs,
  remoteEndpoint,
  remoteStage,
  remoteFailure,
  remoteConnectionFailure,
  remoteOperation,
  httpStatus,
  responseBytes,
  credentialAttached,
  networkErrorCode,
  remoteResponseIssue,
  outputVolume,
  outputGain,
}

/// Only fixed event/field names and numeric/boolean values enter the journal.
/// Exception messages, stack traces, paths, tags and arbitrary strings do not.
abstract interface class DiagnosticsService {
  void record(DiagnosticEvent event,
      {Map<DiagnosticField, Object?> fields = const {}, Object? error});
  Future<Directory> directory();
  Future<File> exportReport();
  Future<void> flush();
}

final class NoopDiagnosticsService implements DiagnosticsService {
  const NoopDiagnosticsService();

  @override
  void record(DiagnosticEvent event,
      {Map<DiagnosticField, Object?> fields = const {}, Object? error}) {}

  @override
  Future<void> flush() async {}

  @override
  Future<Directory> directory() =>
      Future.error(UnsupportedError('Диагностика не подключена.'));

  @override
  Future<File> exportReport() =>
      Future.error(UnsupportedError('Диагностика не подключена.'));
}

final class LocalDiagnosticsService implements DiagnosticsService {
  LocalDiagnosticsService({
    Future<Directory> Function()? directoryProvider,
    this.maxFileBytes = 256 * 1024,
    this.maxFiles = 4,
    this.maxReports = 3,
    this.maxPendingRecords = 128,
    DateTime Function()? clock,
  })  : assert(maxFileBytes >= 1024),
        assert(maxFiles > 0),
        assert(maxReports > 0),
        assert(maxPendingRecords > 0),
        _directoryProvider = directoryProvider ?? _defaultDirectory,
        _clock = clock ?? DateTime.now,
        _session = List.generate(8, (_) => Random.secure().nextInt(256))
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();

  final Future<Directory> Function() _directoryProvider;
  final DateTime Function() _clock;
  final int maxFileBytes;
  final int maxFiles;
  final int maxReports;
  final int maxPendingRecords;
  final String _session;
  Future<void> _pending = Future.value();
  int _pendingRecords = 0;
  int _droppedRecords = 0;
  bool _lastWriteSucceeded = true;
  int _exportSequence = 0;

  // Serializes instances in the same isolate, in addition to the OS lock.
  static final Map<String, Future<void>> _directoryOperations = {};

  static Future<Directory> _defaultDirectory() async => Directory(p.join(
      (await getApplicationSupportDirectory()).path,
      'CleverMusicPlayer',
      'diagnostics'));

  @override
  Future<Directory> directory() async {
    final result = await _directoryProvider();
    await result.create(recursive: true);
    return result;
  }

  @override
  void record(DiagnosticEvent event,
      {Map<DiagnosticField, Object?> fields = const {}, Object? error}) {
    if (_pendingRecords >= maxPendingRecords) {
      _droppedRecords++;
      return;
    }
    final entry = <String, Object?>{
      'timeUtc': _clock().toUtc().toIso8601String(),
      'session': _session,
      'event': event.name,
      for (final field in fields.entries)
        if (field.value is bool ||
            (field.value is num && (field.value as num).isFinite))
          field.key.name: field.value,
      if (error != null) ..._errorDetails(error),
    };
    final bytes = utf8.encode('${jsonEncode(entry)}\n');
    if (bytes.length > maxFileBytes) {
      _droppedRecords++;
      return;
    }
    _pendingRecords++;
    _pending = _pending.then((_) async {
      try {
        await _locked((directory) async {
          final current = File(p.join(directory.path, 'journal-0.jsonl'));
          if (await current.exists() &&
              await current.length() + bytes.length > maxFileBytes) {
            for (var i = maxFiles - 1; i >= 0; i--) {
              final file = File(p.join(directory.path, 'journal-$i.jsonl'));
              if (!await file.exists()) continue;
              if (i == maxFiles - 1) {
                await file.delete();
              } else {
                await file
                    .rename(p.join(directory.path, 'journal-${i + 1}.jsonl'));
              }
            }
          }
          await current.writeAsBytes(bytes, mode: FileMode.append, flush: true);
        });
        _lastWriteSucceeded = true;
      } on Object {
        // Diagnostics must never interrupt playback or recursively log itself.
        _lastWriteSucceeded = false;
        _droppedRecords++;
      } finally {
        _pendingRecords--;
      }
    });
  }

  static Map<String, Object?> _errorDetails(Object error) => {
        'errorKind': switch (error) {
          FileSystemException() => 'fileSystem',
          TimeoutException() => 'timeout',
          MissingPluginException() => 'missingPlugin',
          PlatformException() => 'platform',
          FormatException() => 'format',
          StateError() => 'state',
          ArgumentError() => 'argument',
          UnsupportedError() => 'unsupported',
          _ => 'other',
        },
        if (error is FileSystemException && error.osError != null)
          'osErrorCode': error.osError!.errorCode,
      };

  Future<T> _locked<T>(
      Future<T> Function(Directory directory) operation) async {
    final target = await directory();
    final key = p.normalize(target.absolute.path);
    final previous = _directoryOperations[key] ?? Future<void>.value();
    final done = Completer<void>();
    _directoryOperations[key] = done.future;
    await previous;
    RandomAccessFile? lock;
    var acquired = false;
    try {
      lock = await File(p.join(target.path, 'journal.lock'))
          .open(mode: FileMode.append);
      // Nonblocking: another process must not stall the player's journal queue.
      await lock.lock(FileLock.exclusive);
      acquired = true;
      return await operation(target);
    } finally {
      try {
        if (acquired) await lock?.unlock();
      } finally {
        try {
          await lock?.close();
        } finally {
          done.complete();
          if (identical(_directoryOperations[key], done.future)) {
            _directoryOperations.remove(key);
          }
        }
      }
    }
  }

  @override
  Future<void> flush() => _pending;

  @override
  Future<File> exportReport() {
    final result = _pending.then((_) => _locked((directory) async {
          final entries = <Object?>[];
          var invalidLines = 0;
          for (var i = maxFiles - 1; i >= 0; i--) {
            final file = File(p.join(directory.path, 'journal-$i.jsonl'));
            if (!await file.exists()) continue;
            // Read only our bounded tail if a previous run left a larger file.
            final input = await file.open();
            late List<int> bytes;
            var truncated = false;
            try {
              final length = await input.length();
              truncated = length > maxFileBytes;
              if (truncated) await input.setPosition(length - maxFileBytes);
              bytes = await input.read(maxFileBytes);
            } finally {
              await input.close();
            }
            final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
            for (final line in lines.skip(truncated ? 1 : 0)) {
              if (line.trim().isEmpty) continue;
              try {
                final decoded = jsonDecode(line);
                final safe = _safeStoredEntry(decoded);
                if (safe == null) {
                  invalidLines++;
                } else {
                  entries.add(safe);
                }
              } on FormatException {
                invalidLines++;
              }
            }
          }
          final reportDirectory = Directory(p.join(directory.path, 'reports'));
          await reportDirectory.create(recursive: true);
          final existing = await reportDirectory
              .list(followLinks: false)
              .where((entity) =>
                  entity is File &&
                  RegExp(r'^report-[0-9]+-[a-f0-9]{16}-[0-9]+\.json$')
                      .hasMatch(p.basename(entity.path)))
              .cast<File>()
              .toList();
          existing
              .sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
          final file = File(p.join(reportDirectory.path,
              'report-${_clock().toUtc().microsecondsSinceEpoch}-$_session-${_exportSequence++}.json'));
          final pending = File(p.join(reportDirectory.path, 'report.pending'));
          await pending.writeAsString(
              const JsonEncoder.withIndent('  ').convert({
                'formatVersion': 1,
                'createdUtc': _clock().toUtc().toIso8601String(),
                'platform': Platform.operatingSystem,
                'buildMode': kReleaseMode
                    ? 'release'
                    : kProfileMode
                        ? 'profile'
                        : 'debug',
                'lastWriteSucceeded': _lastWriteSucceeded,
                'droppedRecordsThisSession': _droppedRecords,
                'invalidJournalLines': invalidLines,
                'events': entries,
              }),
              flush: true);
          await pending.rename(file.path);
          // Publish the replacement before removing any older complete report.
          while (existing.length >= maxReports) {
            await existing.removeAt(0).delete();
          }
          return file;
        }));
    // Export errors are delivered to the UI; subsequent writes still proceed.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Map<String, Object?>? _safeStoredEntry(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    if (!DiagnosticEvent.values.any((event) => event.name == value['event']) ||
        value['timeUtc'] is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T[0-9:.]+Z$')
            .hasMatch(value['timeUtc'] as String) ||
        value['session'] is! String ||
        !RegExp(r'^[a-f0-9]{16}$').hasMatch(value['session'] as String)) {
      return null;
    }
    return {
      'timeUtc': value['timeUtc'],
      'session': value['session'],
      'event': value['event'],
      for (final field in DiagnosticField.values)
        if (value[field.name] is bool ||
            (value[field.name] is num && (value[field.name] as num).isFinite))
          field.name: value[field.name],
      if (const {
        'fileSystem',
        'timeout',
        'missingPlugin',
        'platform',
        'format',
        'state',
        'argument',
        'unsupported',
        'other'
      }.contains(value['errorKind']))
        'errorKind': value['errorKind'],
      if (value['osErrorCode'] is int) 'osErrorCode': value['osErrorCode'],
    };
  }
}
