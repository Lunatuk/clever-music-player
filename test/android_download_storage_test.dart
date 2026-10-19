import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/android/android_download_folders.dart';
import 'package:clever_music_player/src/android/android_download_storage_controller.dart';
import 'package:clever_music_player/src/android/android_download_storage_settings.dart';
import 'package:clever_music_player/src/domain/models/audio_source_reference.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_audio_folders.dart';

void main() {
  late TestFolderSettings settings;
  late _Documents documents;
  late AndroidDownloadStorageController controller;
  var checks = 0;
  setUp(() {
    settings = TestFolderSettings();
    documents = _Documents();
    checks = 0;
    controller = AndroidDownloadStorageController(
        settings: settings,
        documents: documents,
        checkWorkspace: (_) async {
          checks++;
        });
  });
  tearDown(() async {
    await controller.close();
    controller.dispose();
  });
  test('initialization does not run private check or picker', () async {
    await controller.initialize();
    expect(controller.loaded, isTrue);
    expect(checks, 0);
    expect(documents.picks, 0);
    expect(documents.inspections, 0);
    expect(settings.writes, 0);
  });
  test('choice persists separately, reload verifies actual provider grants',
      () async {
    await controller.chooseFolder();
    expect(settings.values, {
      AndroidDownloadStorageController.settingKey: documents.tree.storageValue
    });
    expect(controller.folderName, 'Музыка');
    final other = AndroidDownloadStorageController(
        settings: settings, documents: documents);
    await other.initialize();
    expect(other.folder, documents.tree);
    expect(other.access!.usable, isTrue);
    expect(documents.inspections, 2);
    await other.close();
    other.dispose();
  });
  test('picker cancellation preserves prior choice', () async {
    await controller.chooseFolder();
    documents.cancel = true;
    await controller.chooseFolder();
    expect(controller.folder, documents.tree);
    expect(settings.writes, 1);
  });
  test('read-only provider cannot replace saved destination', () async {
    await controller.chooseFolder();
    final before = Map.of(settings.values);
    documents.access = const DownloadFolderAccess(
        readable: true, writable: false, canCreate: true);
    await controller.chooseFolder();
    expect(settings.values, before);
    expect(settings.writes, 1);
    expect(controller.message, contains('нельзя создавать'));
  });
  test('lost grant invalidates readiness and can be restored', () async {
    await controller.chooseFolder();
    documents.access = const DownloadFolderAccess(
        readable: false, writable: false, canCreate: false);
    await controller.inspectFolder();
    expect(controller.access!.usable, isFalse);
    expect(controller.folder, documents.tree);
    documents.access = _Documents.usable;
    await controller.inspectFolder();
    expect(controller.access!.usable, isTrue);
  });
  test('provider failure clears cached readiness without exposing native text',
      () async {
    await controller.chooseFolder();
    documents.failure = PlatformException(
        code: 'folder_unavailable', message: 'secret content://private/path');
    await controller.inspectFolder();
    expect(controller.access, isNull);
    expect(controller.message, isNot(contains('secret')));
    expect(controller.message, isNot(contains('content://')));
  });
  test(
      'forget deletes only destination setting, without revoking shared grants',
      () async {
    settings.values['other'] = 'keep';
    await controller.chooseFolder();
    await controller.forgetFolder();
    expect(controller.folder, isNull);
    expect(settings.values, {'other': 'keep'});
    expect(documents.inspections, 1);
  });
  test('failed settings write preserves choice; retry succeeds', () async {
    settings.writeAction =
        (_, __) async => throw StateError('private database path');
    await controller.chooseFolder();
    expect(controller.folder, isNull);
    expect(settings.values, isEmpty);
    expect(controller.message, isNot(contains('private')));
    settings.writeAction = null;
    await controller.chooseFolder();
    expect(controller.folder, documents.tree);
  });
  test('close drains accepted persistence; no late notifier', () async {
    final started = Completer<void>(), release = Completer<void>();
    settings.writeAction = (_, __) async {
      started.complete();
      await release.future;
    };
    final action = controller.chooseFolder();
    await started.future;
    var closed = false, changes = 0;
    final closing = controller.close().then((_) => closed = true);
    controller.addListener(() => changes++);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    release.complete();
    await action;
    await closing;
    expect(settings.values[AndroidDownloadStorageController.settingKey],
        documents.tree.storageValue);
    expect(changes, 0);
    await controller.chooseFolder();
    expect(documents.picks, 1);
  });
  test('late picker result after close is never saved', () async {
    final selected = Completer<ContentUriAudioSource?>();
    documents.selection = selected.future;
    final action = controller.chooseFolder();
    final closing = controller.close();
    selected.complete(documents.tree);
    await action;
    await closing;
    expect(settings.writes, 0);
    expect(documents.inspections, 0);
  });

  testWidgets(
      'small screen and enlarged text show both actions without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.4)),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child:
                    AndroidDownloadStorageSettings(controller: controller)))));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Проверить временное хранилище'));
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(find.textContaining('Тестовые данные удалены'), findsOneWidget);
    await tester.ensureVisible(find.text('Выбрать папку загрузок'));
    await tester.pump();
    await tester.tap(find.text('Выбрать папку загрузок'));
    await tester.pumpAndSettle();
    expect(find.text('Папка загрузок: Музыка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel waits for cleanup and blocks a second check',
      (tester) async {
    await controller.close();
    controller.dispose();
    final finish = Completer<void>();
    LibraryScanControl? control;
    controller = AndroidDownloadStorageController(
        settings: settings,
        documents: documents,
        checkWorkspace: (value) {
          control = value;
          return finish.future;
        });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child:
                    AndroidDownloadStorageSettings(controller: controller)))));
    await tester.tap(find.text('Проверить временное хранилище'));
    await tester.pump();
    await tester.tap(find.text('Остановить проверку'));
    await tester.pump();
    expect(control!.isCancellationRequested, isTrue);
    expect(controller.busy, isTrue);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Выбрать папку загрузок'))
            .onPressed,
        isNull);
    finish.complete();
    await tester.pumpAndSettle();
    expect(controller.busy, isFalse);
    expect(find.textContaining('Проверка остановлена'), findsOneWidget);
  });

  test('OS no-space error is actionable and exposes no path', () async {
    await controller.close();
    controller.dispose();
    controller = AndroidDownloadStorageController(
        settings: settings,
        checkWorkspace: (_) async => throw const FileSystemException(
            'secret', '/private/path', OSError('private', 28)));
    await controller.checkWorkspace();
    expect(controller.message, contains('Недостаточно свободного места'));
    expect(controller.message, isNot(contains('private')));
  });
}

final class _Documents implements DownloadFolderDocuments {
  static const usable = DownloadFolderAccess(
      readable: true, writable: true, canCreate: true, name: 'Музыка');
  final tree =
      ContentUriAudioSource('content://music.documents/tree/primary%3AMusic');
  DownloadFolderAccess access = usable;
  bool cancel = false;
  Object? failure;
  int picks = 0, inspections = 0;
  Future<ContentUriAudioSource?>? selection;
  @override
  Future<ContentUriAudioSource?> pickDownloadFolder() async {
    picks++;
    return selection ?? (cancel ? null : tree);
  }

  @override
  Future<DownloadFolderAccess> inspectDownloadFolder(
      ContentUriAudioSource tree) async {
    inspections++;
    if (failure != null) throw failure!;
    return access;
  }
}
