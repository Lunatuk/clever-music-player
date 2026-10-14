import 'dart:async';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/directory_picker_service.dart';
import 'package:clever_music_player/src/library/library_controller.dart';
import 'package:clever_music_player/src/library/library_management_service.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/library_scan_metrics.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/ui/library/library_scan_status.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftRepositories repositories;
  late LibraryController controller;
  late ControlledLibraryFolderScanner scan;
  late List<LibraryFolder> folders;
  late List<String> visited;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repositories = DriftRepositories(database);
    visited = [];
    for (final path in ['/a', '/b']) {
      await repositories.libraryFolders.upsertFolder(LibraryFolder(
        path: path,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));
    }
    folders = await repositories.libraryFolders.listFolders();
    scan = (path, {required control}) async => _result(path);
    Future<LibraryScanResult> controlled(String path,
        {required LibraryScanControl control}) {
      visited.add(path);
      return scan(path, control: control);
    }

    Future<LibraryScanResult> legacy(String path) =>
        throw StateError('Controlled adapter expected');
    controller = LibraryController(
      directoryPicker: const _Picker(),
      scanFolder: legacy,
      controlledScanFolder: controlled,
      management: LibraryManagementService(
        libraryRepository: repositories.libraryFolders,
        scanFolder: legacy,
        controlledScanFolder: controlled,
      ),
    );
  });
  tearDown(() async {
    await controller.close();
    await database.close();
  });

  test(
      'bulk progress accumulates folders and stays separate from command notifications',
      () async {
    var commandNotifications = 0;
    final progress = <LibraryScanProgress>[];
    controller.addListener(() => commandNotifications++);
    controller.scanProgress.addListener(() {
      final value = controller.scanProgress.value;
      if (value != null) progress.add(value);
    });
    scan = (path, {required control}) async {
      for (var i = 0; i < 100; i++) {
        control.report(LibraryScanProgress(
            folderPath: path,
            stage: LibraryScanStage.hashing,
            fileBytesRead: i,
            fileSizeBytes: 100));
      }
      control.report(LibraryScanProgress(
          folderPath: path,
          stage: LibraryScanStage.finishing,
          processedFiles: 2,
          addedTracks: 1,
          updatedTracks: 1));
      return _result(path, files: 2, added: 1, updated: 1);
    };
    expect(await controller.rescanLibrary(), LibraryOperationOutcome.completed);
    expect(visited, ['/a', '/b']);
    expect(progress.first.folderNumber, 1);
    expect(progress.last.folderNumber, 2);
    expect(progress.last.folderCount, 2);
    expect(progress.last.processedFiles, 4);
    expect(progress.last.addedTracks, 2);
    expect(progress.last.updatedTracks, 2);
    expect(progress.length, lessThanOrEqualTo(3));
    expect(commandNotifications, 3);
    expect(controller.state.lastScanResult!.processedFiles, 4);
  });

  test('cancel remains busy until drain and skips all later folders', () async {
    final entered = Completer<LibraryScanControl>();
    final release = Completer<void>();
    scan = (path, {required control}) async {
      control.report(_progress(path));
      entered.complete(control);
      await release.future;
      return _result(path,
          files: 1, cancelled: control.isCancellationRequested);
    };
    final scanning = controller.rescanLibrary();
    final control = await entered.future;
    expect(controller.cancelScan(), isTrue);
    expect(control.isCancellationRequested, isTrue);
    expect(controller.state.isCancelling, isTrue);
    expect(controller.state.isBusy, isTrue);
    expect(controller.cancelScan(), isFalse);
    expect(await controller.addFolder(), LibraryOperationOutcome.busy);
    expect(await controller.setFolderEnabled(folders.last, isEnabled: false),
        LibraryOperationOutcome.busy);
    release.complete();
    expect(await scanning, LibraryOperationOutcome.cancelled);
    expect(visited, ['/a']);
    expect(controller.state.isBusy, isFalse);
    expect(controller.state.error, isNull);
    expect(controller.state.lastScanResult!.wasCancelled, isTrue);
    scan = (path, {required control}) async => _result(path);
    expect(await controller.rescanLibrary(), LibraryOperationOutcome.completed);
  });

  test('cancel on initial reservation avoids starting any folder', () async {
    controller.addListener(() {
      if (controller.state.canCancelScan) controller.cancelScan();
    });
    expect(await controller.rescanLibrary(), LibraryOperationOutcome.cancelled);
    expect(visited, isEmpty);
    expect(controller.state.lastScanResult!.processedFiles, 0);
    expect(controller.cancelScan(), isFalse);
  });

  test('close requests cancellation and drains work without late notifications',
      () async {
    final entered = Completer<LibraryScanControl>();
    final release = Completer<void>();
    scan = (path, {required control}) async {
      entered.complete(control);
      await release.future;
      control.report(_progress('/late'));
      return _result(path, cancelled: control.isCancellationRequested);
    };
    final scanning = controller.rescanLibrary();
    final control = await entered.future;
    var closed = false;
    final closing = controller.close().then((_) => closed = true);
    expect(control.isCancellationRequested, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    release.complete();
    expect(await scanning, LibraryOperationOutcome.closed);
    await closing;
    expect(closed, isTrue);
    expect(visited, ['/a']);
  });

  test('late progress from a completed operation cannot overwrite a new scan',
      () async {
    late LibraryScanControl old;
    scan = (path, {required control}) async {
      old = control;
      return _result(path);
    };
    await controller.rescanFolder(folders.first);
    final entered = Completer<void>();
    final release = Completer<void>();
    scan = (path, {required control}) async {
      control.report(_progress(path));
      entered.complete();
      await release.future;
      return _result(path);
    };
    final scanning = controller.rescanFolder(folders.last);
    await entered.future;
    old.report(_progress('/stale', processed: 999));
    expect(controller.scanProgress.value!.folderPath, '/b');
    release.complete();
    await scanning;
    old.report(_progress('/stale', processed: 999));
    expect(controller.scanProgress.value!.folderPath, '/b');
  });

  test('a progress listener can close the controller safely', () async {
    controller.scanProgress.addListener(() {
      if (controller.scanProgress.value != null) controller.close();
    });
    scan = (path, {required control}) async {
      control.report(_progress(path));
      return _result(path, cancelled: control.isCancellationRequested);
    };
    expect(await controller.rescanLibrary(), LibraryOperationOutcome.closed);
    await controller.close();
    expect(visited, ['/a']);
  });

  test('failure releases the scan and a successful retry resets its error',
      () async {
    scan = (path, {required control}) async {
      control.report(_progress(path));
      throw StateError('failed');
    };
    expect(await controller.rescanFolder(folders.first),
        LibraryOperationOutcome.failed);
    expect(controller.state.error, isA<StateError>());
    expect(controller.cancelScan(), isFalse);
    scan = (path, {required control}) async => _result(path);
    expect(await controller.rescanFolder(folders.first),
        LibraryOperationOutcome.completed);
    expect(controller.state.error, isNull);
  });

  testWidgets(
      'status displays file progress, cancels, remounts, and shows partial result',
      (tester) async {
    final entered = Completer<LibraryScanControl>();
    final release = Completer<void>();
    scan = (path, {required control}) async {
      control.report(LibraryScanProgress(
          folderPath: path,
          stage: LibraryScanStage.hashing,
          fileName: 'song.wav',
          processedFiles: 12,
          addedTracks: 3,
          fileBytesRead: 50,
          fileSizeBytes: 100,
          metrics: const LibraryScanMetrics(
              elapsedUs: 2000000, hashedBytes: 1048576)));
      entered.complete(control);
      await release.future;
      return _result(path,
          files: 12, added: 3, cancelled: control.isCancellationRequested);
    };
    Widget panel() => MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360, child: LibraryScanStatus(controller: controller))));
    await tester.pumpWidget(panel());
    final scanning = controller.rescanFolder(folders.first);
    await entered.future;
    await tester.pump();
    expect(find.textContaining('Обработано файлов: 12'), findsOneWidget);
    expect(find.textContaining('song.wav'), findsOneWidget);
    expect(find.textContaining('6.0 файлов/с'), findsOneWidget);
    expect(find.textContaining('1.0 МиБ'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0.5);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(panel());
    expect(find.textContaining('Обработано файлов: 12'), findsOneWidget);
    await tester.tap(find.text('Остановить сканирование'));
    await tester.pump();
    expect(find.text('Останавливаем сканирование…'), findsOneWidget);
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    release.complete();
    expect(await scanning, LibraryOperationOutcome.cancelled);
    await tester.pumpAndSettle();
    expect(find.textContaining('Сканирование остановлено.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

LibraryScanProgress _progress(String path, {int processed = 1}) =>
    LibraryScanProgress(
      folderPath: path,
      stage: LibraryScanStage.discovering,
      processedFiles: processed,
    );
LibraryScanResult _result(String path,
        {int files = 0,
        int added = 0,
        int updated = 0,
        bool cancelled = false}) =>
    LibraryScanResult(
        folderPath: path,
        scannedFiles: files,
        addedTracks: added,
        updatedTracks: updated,
        missingTracks: 0,
        errors: const [],
        wasCancelled: cancelled);

final class _Picker implements DirectoryPickerService {
  const _Picker();
  @override
  Future<String?> pickMusicFolder() async => '/new';
}
