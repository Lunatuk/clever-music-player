import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/library/file_content_hasher.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late AppDatabase database;
  late DriftRepositories repositories;
  late _SessionFactory factory;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cmp_scan_session_');
    database = AppDatabase(NativeDatabase.memory());
    repositories = DriftRepositories(database);
    factory = _SessionFactory();
    for (var i = 0; i < 3; i++) {
      await File(p.join(root.path, '$i.wav')).writeAsBytes([i, 2, 3]);
    }
  });
  tearDown(() async {
    for (final session in factory.sessions) {
      await session.close();
    }
    await database.close();
    await root.delete(recursive: true);
  });
  LibraryScannerService scanner(
          {MetadataReaderService? reader,
          DirectoryEntityLister? lister,
          LibraryRepository? library,
          DiagnosticsService? diagnostics}) =>
      LibraryScannerService(
          libraryRepository: library ?? repositories.libraryFolders,
          trackRepository: repositories.tracks,
          metadataReader: reader ?? const FallbackMetadataReaderService(),
          contentHasher: factory,
          diagnostics: diagnostics ?? const NoopDiagnosticsService(),
          listEntities: lister ?? (dir) => dir.list());

  test('each complete scan owns and closes one worker session', () async {
    final first =
        await scanner().scanFolder(root.path, control: LibraryScanControl());
    final second =
        await scanner().scanFolder(root.path, control: LibraryScanControl());
    expect(first.errors, isEmpty);
    expect(second.errors, isEmpty);
    expect(first.addedTracks, 3);
    expect(second.addedTracks, 0);
    expect(second.updatedTracks, 3);
    expect(factory.sessions, hasLength(2));
    expect(factory.sessions.every((session) => session.closed), isTrue);
    for (final metrics in [first.metrics, second.metrics]) {
      expect(metrics.hashWorkerStarts, 1);
      expect(metrics.hashedFiles, 3);
      expect(metrics.hashReadUs, greaterThan(0));
      expect(metrics.hashComputeUs, greaterThan(0));
      expect(metrics.hashWorkerUs,
          greaterThanOrEqualTo(metrics.hashReadUs + metrics.hashComputeUs));
      expect(metrics.hashUs,
          greaterThanOrEqualTo(metrics.hashWorkerUs + metrics.hashOverheadUs));
      expect(
          metrics.databaseUs,
          greaterThanOrEqualTo(metrics.databaseLookupUs +
              metrics.databaseImportUs +
              metrics.databaseMaintenanceUs));
    }
  });

  test('legacy fallback starts one worker per file with compatible identities',
      () async {
    final fallback = LibraryScannerService(
        libraryRepository: repositories.libraryFolders,
        trackRepository: repositories.tracks,
        metadataReader: const FallbackMetadataReaderService(),
        reuseHashWorker: false);
    final first =
        await fallback.scanFolder(root.path, control: LibraryScanControl());
    expect(first.metrics.hashWorkerStarts, 3);
    final identities = (await repositories.tracks.listTracks())
        .map((t) => t.contentHash)
        .toSet();
    final second =
        await scanner().scanFolder(root.path, control: LibraryScanControl());
    expect(second.metrics.hashWorkerStarts, 1);
    expect(
        (await repositories.tracks.listTracks())
            .map((t) => t.contentHash)
            .toSet(),
        identities);
  });

  test('cancel closes its session and retry creates a fresh worker', () async {
    late LibraryScanControl control;
    control = LibraryScanControl(onProgress: (progress) {
      if (progress.processedFiles == 1) control.cancel();
    });
    final result = await scanner().scanFolder(root.path, control: control);
    expect(result.wasCancelled, isTrue);
    expect(result.addedTracks, 1);
    expect(factory.sessions.single.closed, isTrue);
    final retry =
        await scanner().scanFolder(root.path, control: LibraryScanControl());
    expect(retry.errors, isEmpty);
    expect(retry.addedTracks, 2);
    expect(retry.metrics.hashWorkerStarts, 1);
    expect(factory.sessions.every((s) => s.closed), isTrue);
  });

  test('metadata failure closes the session after recording file failures',
      () async {
    final result = await scanner(reader: _BrokenReader()).scanFolder(root.path);
    expect(result.errors, hasLength(3));
    expect(result.addedTracks, 0);
    expect(factory.sessions.single.closed, isTrue);
  });

  test('traversal error closes the worker after saving the prepared remainder',
      () async {
    Stream<FileSystemEntity> broken(Directory dir) async* {
      yield File(p.join(dir.path, '0.wav'));
      throw const FileSystemException('injected traversal failure');
    }

    final result = await scanner(lister: broken).scanFolder(root.path);
    expect(result.errors, hasLength(1));
    expect(result.addedTracks, 1);
    expect(factory.sessions.single.closed, isTrue);
  });

  test('fatal repository error still closes the unused session', () async {
    await expectLater(scanner(library: _BrokenLibrary()).scanFolder(root.path),
        throwsStateError);
    expect(factory.sessions.single.closed, isTrue);
  });

  test('completion and diagnostics wait until the session close drains',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    factory.onClose = () async {
      entered.complete();
      await release.future;
    };
    final diagnostics = _RecordingDiagnostics();
    var finished = false;
    final scanning =
        scanner(diagnostics: diagnostics).scanFolder(root.path).then((result) {
      finished = true;
      return result;
    });
    await entered.future;
    expect(finished, isFalse);
    expect(diagnostics.events, isNot(contains(DiagnosticEvent.scanCompleted)));
    release.complete();
    final result = await scanning;
    expect(result.errors, isEmpty);
    expect(diagnostics.events.last, DiagnosticEvent.scanCompleted);
  });

  test('independent scans do not share worker or cancellation state', () async {
    final a = await Directory(p.join(root.path, 'a')).create();
    final b = await Directory(p.join(root.path, 'b')).create();
    for (final dir in [a, b]) {
      await File(p.join(dir.path, 'track.wav')).writeAsBytes([1, 2, 3]);
    }
    final service = scanner();
    final results = await Future.wait(
        [service.scanFolder(a.path), service.scanFolder(b.path)]);
    expect(results.every((result) => result.errors.isEmpty), isTrue);
    expect(results.map((result) => result.metrics.hashWorkerStarts), [1, 1]);
    expect(factory.sessions, hasLength(2));
    expect(factory.sessions.every((s) => s.closed), isTrue);
    expect(await repositories.tracks.listTracks(), hasLength(2));
  });
}

final class _SessionFactory
    implements FileContentHasher, SessionFileContentHasher {
  final sessions = <_TrackedSession>[];
  Future<void> Function()? onClose;
  @override
  Future<FileContentFingerprint> hashFile(File file) =>
      throw StateError('Session was bypassed');
  @override
  FileContentHashSession openSession() {
    final session = _TrackedSession(onClose);
    sessions.add(session);
    return session;
  }
}

final class _TrackedSession implements FileContentHashSession {
  _TrackedSession(this.onClose);
  final Future<void> Function()? onClose;
  final inner = Sha256HashSession();
  bool closed = false;
  Future<void>? closing;
  @override
  Future<FileContentFingerprint> hashFile(File file) => inner.hashFile(file);
  @override
  Future<FileContentFingerprint> hashFileWithControl(File file,
          {required LibraryScanControl control,
          void Function(FileHashProgress)? onProgress}) =>
      inner.hashFileWithControl(file, control: control, onProgress: onProgress);
  @override
  Future<void> close() => closing ??= () async {
        await inner.close();
        closed = true;
        await onClose?.call();
      }();
}

final class _BrokenReader implements MetadataReaderService {
  @override
  Future<AudioMetadata> read(File file) =>
      Future.error(StateError('injected tag failure'));
}

final class _BrokenLibrary implements LibraryRepository {
  @override
  Future<LibraryFolder?> findFolderByPath(String path) =>
      Future.error(StateError('injected DB failure'));
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected call');
}

final class _RecordingDiagnostics implements DiagnosticsService {
  final events = <DiagnosticEvent>[];
  @override
  void record(DiagnosticEvent event,
      {Map<DiagnosticField, Object?> fields = const {}, Object? error}) {
    events.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected call');
}
