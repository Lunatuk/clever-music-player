import 'dart:async';

import 'package:clever_music_player/src/android/android_download_folders.dart';
import 'package:clever_music_player/src/android/android_download_storage_controller.dart';
import 'package:clever_music_player/src/android/android_folder_bookmarks.dart';
import 'package:clever_music_player/src/android/android_yandex_destination_guard.dart';
import 'package:clever_music_player/src/android/drift_android_folder_library.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_update_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/library_update_fixture.dart';
import 'support/test_audio_folders.dart';

void main() {
  late LibraryUpdateFixture x;
  late _Documents documents;
  late AndroidYandexDestinationGuard guard;
  setUp(() async {
    x = await LibraryUpdateFixture.open();
    documents = _Documents();
    await x.f.database.customStatement(
        'UPDATE library_folders SET path = ? WHERE id = ?',
        [documents.tree.storageValue, x.f.folderId]);
    guard = AndroidYandexDestinationGuard(
        settings: x.f.repositories.settings, documents: documents);
    x.validateDestination = guard.call;
    await x.ready();
    await x.f.repositories.settings.writeString(
        AndroidDownloadStorageController.settingKey,
        documents.tree.storageValue);
  });
  tearDown(() => x.close());
  for (final which in [
    'missing',
    'different',
    'read',
    'write',
    'create',
    'provider'
  ]) {
    test(
        '$which destination fails before collection refresh, plan or downloader',
        () async {
      switch (which) {
        case 'missing':
          await x.f.repositories.settings
              .delete(AndroidDownloadStorageController.settingKey);
        case 'different':
          await x.f.repositories.settings.writeString(
              AndroidDownloadStorageController.settingKey,
              'content://music.documents/tree/Other');
        case 'read':
          documents.access = const DownloadFolderAccess(
              readable: false, writable: true, canCreate: true);
        case 'write':
          documents.access = const DownloadFolderAccess(
              readable: true, writable: false, canCreate: true);
        case 'create':
          documents.access = const DownloadFolderAccess(
              readable: true, writable: true, canCreate: false);
        case 'provider':
          documents.failure = StateError('PRIVATE_PATH');
      }
      final before = x.transport.requests.length;
      await x.updates.start();
      expect(x.updates.failure, YandexUpdateFailure.destination);
      expect(x.transport.requests.length, before);
      expect(x.plans.captures, 0);
      expect(x.fakeRunner.calls, 0);
      expect(await x.f.count('download_jobs'), 0);
    });
  }
  test('cancellation during fresh provider inspection drains and never plans',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    documents.inspect = () async {
      entered.complete();
      await release.future;
    };
    final running = x.updates.start();
    await entered.future;
    x.updates.cancel();
    release.complete();
    await running;
    expect(x.updates.failure, YandexUpdateFailure.cancelled);
    expect(x.plans.captures, 0);
  });
  test('settings read failure is storage failure, never a false ready state',
      () async {
    final broken = TestFolderSettings()
      ..readAction = (_) async => throw StateError('PRIVATE_DB');
    x.validateDestination =
        AndroidYandexDestinationGuard(settings: broken, documents: documents)
            .call;
    await x.updates.start();
    expect(x.updates.failure, YandexUpdateFailure.storage);
    expect(documents.inspections, 0);
    expect(x.fakeRunner.calls, 0);
  });
  test(
      'clearing update destination persists null without deleting library folder',
      () async {
    await x.updates.configure(clearFolder: true);
    expect(x.updates.folderId, isNull);
    await x.updates.close();
    x.updates = x.newController();
    await x.updates.initialize();
    expect(x.updates.folderId, isNull);
    expect((await x.f.repositories.libraryFolders.listFolders()).length, 1);
  });
  test(
      'new download bookmark is selectable immediately and remains enabled on restart without scan',
      () async {
    final bookmarks = AndroidFolderBookmarks(
        settings: x.f.repositories.settings,
        library: DriftAndroidFolderLibrary(x.f.database));
    await bookmarks.initialize();
    await bookmarks.remember(documents.tree, name: 'Музыка');
    final id = bookmarks.folderIdFor(documents.tree)!;
    await x.updates.configure(folderId: id);
    expect(x.updates.folderId, id);
    expect(x.updates.failure, isNull);
    await bookmarks.close();
    bookmarks.dispose();
    final reopened = AndroidFolderBookmarks(
        settings: x.f.repositories.settings,
        library: DriftAndroidFolderLibrary(x.f.database));
    await reopened.initialize();
    expect(reopened.folderIdFor(documents.tree), id);
    expect(
        (await x.f.repositories.libraryFolders
                .listFolders(includeDisabled: false))
            .single
            .id,
        id);
    expect(await x.f.count('tracks'), 0);
    expect(x.fakeRunner.calls, 0);
    await reopened.close();
    reopened.dispose();
  });
  test(
      'legacy destination restores without auto registration; explicit reuse rechecks grants',
      () async {
    var calls = 0;
    final storage = AndroidDownloadStorageController(
        settings: x.f.repositories.settings,
        documents: documents,
        onUseDestination: (tree, name) async {
          calls++;
        });
    await storage.initialize();
    expect(calls, 0);
    await storage.useDestination();
    expect(calls, 1);
    documents.access = const DownloadFolderAccess(
        readable: true, writable: false, canCreate: true);
    await storage.useDestination();
    expect(calls, 1);
    await storage.close();
    storage.dispose();
  });
  test(
      'shutdown drains accepted destination registration before borrowed DB can close',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    final storage = AndroidDownloadStorageController(
        settings: x.f.repositories.settings,
        documents: documents,
        onUseDestination: (tree, name) async {
          entered.complete();
          await release.future;
        });
    final action = storage.chooseFolder();
    await entered.future;
    var closed = false;
    final closing = storage.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    release.complete();
    await action;
    await closing;
    expect(closed, isTrue);
    storage.dispose();
  });
  test('failed registration can be explicitly retried without a new picker',
      () async {
    var fail = true, calls = 0;
    final storage = AndroidDownloadStorageController(
        settings: x.f.repositories.settings,
        documents: documents,
        onUseDestination: (tree, name) async {
          calls++;
          if (fail) throw StateError('PRIVATE');
        });
    await storage.chooseFolder();
    expect(storage.folder, documents.tree);
    expect(storage.message, isNot(contains('PRIVATE')));
    fail = false;
    await storage.useDestination();
    expect(calls, 2);
    expect(storage.message, contains('подключена'));
    await storage.close();
    storage.dispose();
  });
  test('failed clear callback preserves saved destination', () async {
    final storage = AndroidDownloadStorageController(
        settings: x.f.repositories.settings,
        documents: documents,
        onClearDestination: () async => throw StateError('busy'));
    await storage.initialize();
    await storage.forgetFolder();
    expect(storage.folder, documents.tree);
    expect(
        await x.f.repositories.settings
            .readString(AndroidDownloadStorageController.settingKey),
        documents.tree.storageValue);
    await storage.close();
    storage.dispose();
  });
}

final class _Documents implements DownloadFolderDocuments {
  final tree =
      ContentUriAudioSource('content://music.documents/tree/primary%3AMusic');
  DownloadFolderAccess access = const DownloadFolderAccess(
      readable: true, writable: true, canCreate: true, name: 'Музыка');
  Object? failure;
  int inspections = 0;
  Future<void> Function()? inspect;
  @override
  Future<ContentUriAudioSource?> pickDownloadFolder() async => tree;
  @override
  Future<DownloadFolderAccess> inspectDownloadFolder(
      ContentUriAudioSource tree) async {
    inspections++;
    await inspect?.call();
    if (failure != null) throw failure!;
    return access;
  }
}
