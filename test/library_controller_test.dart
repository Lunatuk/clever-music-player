import 'dart:async';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/library_folder.dart';
import 'package:clever_music_player/src/library/directory_picker_service.dart';
import 'package:clever_music_player/src/library/library_controller.dart';
import 'package:clever_music_player/src/library/library_management_service.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftRepositories repositories;
  late _Picker picker;
  late LibraryController controller;
  late LibraryFolder folder;
  late LibraryFolderScanner scanner;
  late List<String> scanned;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repositories = DriftRepositories(database);
    final now = DateTime(2026);
    await repositories.libraryFolders.upsertFolder(
        LibraryFolder(path: '/music/a', createdAt: now, updatedAt: now));
    folder = (await repositories.libraryFolders.findFolderByPath('/music/a'))!;
    picker = _Picker();
    scanned = [];
    scanner = (path) async => result(path);
    Future<LibraryScanResult> scan(String path) {
      scanned.add(path);
      return scanner(path);
    }

    controller = LibraryController(
        directoryPicker: picker,
        scanFolder: scan,
        management: LibraryManagementService(
            libraryRepository: repositories.libraryFolders, scanFolder: scan));
  });
  tearDown(() async {
    await controller.close();
    await database.close();
  });

  test('cancelled picker releases the library without scanning', () async {
    final choice = Completer<String?>();
    picker.choose = () => choice.future;
    final adding = controller.addFolder();
    expect(controller.state.isBusy, true);
    expect(controller.state.isScanning, false);
    choice.complete(null);
    expect(await adding, LibraryOperationOutcome.cancelled);
    expect(scanned, isEmpty);
    expect(controller.state.isBusy, false);
    expect(controller.state.error, isNull);
  });

  test('selected folder remains reserved until its scan completes', () async {
    picker.choose = () async => '/music/new';
    final entered = Completer<void>();
    final scan = Completer<LibraryScanResult>();
    scanner = (_) {
      entered.complete();
      return scan.future;
    };
    final adding = controller.addFolder();
    await entered.future;
    expect(controller.state.isBusy, true);
    expect(controller.state.isScanning, true);
    scan.complete(result('/music/new', files: 3));
    expect(await adding, LibraryOperationOutcome.completed);
    expect(scanned, ['/music/new']);
    expect(controller.state.lastScanResult?.scannedFiles, 3);
    expect(controller.state.isBusy, false);
  });

  test('picker failure is handled and a later request can retry', () async {
    picker.choose = () async => throw StateError('picker failed');
    expect(await controller.addFolder(), LibraryOperationOutcome.failed);
    expect(controller.state.error, isA<StateError>());
    expect(controller.state.isBusy, false);
    picker.choose = () async => null;
    expect(await controller.addFolder(), LibraryOperationOutcome.cancelled);
    expect(controller.state.error, isNull);
  });

  test('all competing commands are rejected while the picker is open',
      () async {
    final choice = Completer<String?>();
    picker.choose = () => choice.future;
    final adding = controller.addFolder();
    try {
      expect(await controller.addFolder(), LibraryOperationOutcome.busy);
      expect(await controller.rescanLibrary(), LibraryOperationOutcome.busy);
      expect(
          await controller.rescanFolder(folder), LibraryOperationOutcome.busy);
      expect(await controller.setFolderEnabled(folder, isEnabled: false),
          LibraryOperationOutcome.busy);
      expect(
          await controller.removeFolder(folder), LibraryOperationOutcome.busy);
      expect(picker.calls, 1);
      expect(scanned, isEmpty);
      expect(
          (await repositories.libraryFolders.findFolderByPath(folder.path))
              ?.isEnabled,
          true);
    } finally {
      choice.complete(null);
      await adding;
    }
  });

  test('scan cannot overlap with another scan or a folder mutation', () async {
    final gate = Completer<LibraryScanResult>();
    scanner = (_) => gate.future;
    final scanning = controller.rescanFolder(folder);
    try {
      expect(
          await controller.rescanFolder(folder), LibraryOperationOutcome.busy);
      expect(await controller.setFolderEnabled(folder, isEnabled: false),
          LibraryOperationOutcome.busy);
      expect(
          await controller.removeFolder(folder), LibraryOperationOutcome.busy);
      expect(scanned, [folder.path]);
      expect(
          (await repositories.libraryFolders.findFolderByPath(folder.path))
              ?.isEnabled,
          true);
    } finally {
      gate.complete(result(folder.path));
      await scanning;
    }
  });

  test('bulk scan owns the library across folder boundaries', () async {
    await repositories.libraryFolders.upsertFolder(LibraryFolder(
        path: '/music/b',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026)));
    final secondEntered = Completer<void>();
    final second = Completer<LibraryScanResult>();
    scanner = (path) async {
      if (path.endsWith('/b')) {
        secondEntered.complete();
        return second.future;
      }
      return result(path);
    };
    final scanning = controller.rescanLibrary();
    await secondEntered.future;
    try {
      expect(await controller.addFolder(), LibraryOperationOutcome.busy);
      expect(await controller.setFolderEnabled(folder, isEnabled: false),
          LibraryOperationOutcome.busy);
      expect(picker.calls, 0);
    } finally {
      second.complete(result('/music/b'));
      expect(await scanning, LibraryOperationOutcome.completed);
    }
    expect(controller.state.lastScanResult?.scannedFiles, 2);
  });

  test('scan failure retains the last result and enables a successful retry',
      () async {
    await controller.rescanFolder(folder);
    final previous = controller.state.lastScanResult;
    scanner = (_) async => throw StateError('scan failed');
    expect(
        await controller.rescanFolder(folder), LibraryOperationOutcome.failed);
    expect(controller.state.lastScanResult, previous);
    expect(controller.state.error, isA<StateError>());
    expect(controller.state.isBusy, false);
    scanner = (path) async => result(path, files: 4);
    expect(await controller.rescanFolder(folder),
        LibraryOperationOutcome.completed);
    expect(controller.state.error, isNull);
    expect(controller.state.lastScanResult?.scannedFiles, 4);
  });

  test('empty enabled library gives a recoverable error', () async {
    await controller.setFolderEnabled(folder, isEnabled: false);
    expect(await controller.rescanLibrary(), LibraryOperationOutcome.failed);
    expect(controller.state.error, isA<NoEnabledLibraryFoldersException>());
    expect(scanned, isEmpty);
    await controller.setFolderEnabled(folder, isEnabled: true);
    expect(await controller.rescanLibrary(), LibraryOperationOutcome.completed);
  });

  test('close does not wait for an external picker or scan its late result',
      () async {
    final choice = Completer<String?>();
    picker.choose = () => choice.future;
    final adding = controller.addFolder();
    await controller.close();
    expect(
        await controller.rescanFolder(folder), LibraryOperationOutcome.closed);
    choice.complete('/music/late');
    expect(await adding, LibraryOperationOutcome.closed);
    expect(scanned, isEmpty);
  });

  test('close drains active database work and suppresses later notifications',
      () async {
    final gate = Completer<LibraryScanResult>();
    scanner = (_) => gate.future;
    var notifications = 0;
    controller.addListener(() => notifications++);
    final scanning = controller.rescanFolder(folder);
    final previousNotifications = notifications;
    var closed = false;
    final closing = controller.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, false);
    expect(await controller.addFolder(), LibraryOperationOutcome.closed);
    gate.complete(result(folder.path));
    await scanning;
    await closing;
    expect(notifications, previousNotifications);
    expect(closed, true);
  });

  test('a listener closing on reservation prevents the picker from opening',
      () async {
    controller.addListener(() {
      if (controller.state.isBusy) controller.close();
    });
    expect(await controller.addFolder(), LibraryOperationOutcome.closed);
    expect(picker.calls, 0);
    expect(scanned, isEmpty);
  });

  test('a listener closing at the scan phase prevents new database work',
      () async {
    picker.choose = () async => '/music/new';
    controller.addListener(() {
      if (controller.state.isScanning) controller.close();
    });
    expect(await controller.addFolder(), LibraryOperationOutcome.closed);
    expect(scanned, isEmpty);
  });

  test('synchronous adapter failure releases the drain and reservation',
      () async {
    scanner = (_) => throw StateError('synchronous failure');
    expect(
        await controller.rescanFolder(folder), LibraryOperationOutcome.failed);
    expect(controller.state.isBusy, false);
    await controller.close();
  });

  test('dispose during a scan still permits the owner to drain it with close',
      () async {
    final gate = Completer<LibraryScanResult>();
    scanner = (_) => gate.future;
    final scanning = controller.rescanFolder(folder);
    controller.dispose();
    var closed = false;
    final closing = controller.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, false);
    gate.complete(result(folder.path));
    await scanning;
    await closing;
  });

  test('failed mutation can retry and then remove the disabled folder',
      () async {
    expect(
        await controller.removeFolder(folder), LibraryOperationOutcome.failed);
    expect((await repositories.libraryFolders.listFolders()), hasLength(1));
    expect(await controller.setFolderEnabled(folder, isEnabled: false),
        LibraryOperationOutcome.completed);
    expect(await controller.removeFolder(folder.copyWith(isEnabled: false)),
        LibraryOperationOutcome.completed);
    expect(await repositories.libraryFolders.listFolders(), isEmpty);
    expect(controller.state.error, isNull);
  });
}

LibraryScanResult result(String path, {int files = 1}) => LibraryScanResult(
    folderPath: path,
    scannedFiles: files,
    addedTracks: files,
    updatedTracks: 0,
    missingTracks: 0,
    errors: const []);

class _Picker implements DirectoryPickerService {
  int calls = 0;
  Future<String?> Function() choose = () async => null;
  @override
  Future<String?> pickMusicFolder() {
    calls++;
    return choose();
  }
}
