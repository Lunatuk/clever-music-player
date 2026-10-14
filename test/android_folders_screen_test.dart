import 'dart:async';

import 'package:clever_music_player/src/android/android_folder_bookmarks.dart';
import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/android/android_folders_screen.dart';
import 'package:clever_music_player/src/android/android_import_controller.dart';
import 'package:clever_music_player/src/android/android_preview_app.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/track_repository.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/player/player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_audio_folders.dart';

void main() {
  testWidgets(
      'a captured forget callback checks current busy state before the next frame',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.close);
    await tester.pumpWidget(f.sources());
    await tester.pump();
    final oldCallback = tester
        .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.folder_off_outlined))
        .onPressed!;
    final info = Completer<AudioFolderAccess>();
    f.native.inspectAction = (_) => info.future;
    try {
      await tester.tap(find.text('Обновить'));
      oldCallback();
      await tester.pump();
      expect(f.importer.busy, isTrue);
      expect(f.bookmarks.folders.single.source, f.native.first);
    } finally {
      info.complete(const AudioFolderAccess(readable: true, name: 'Music'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets(
      'saved folders refresh without picker; removing a root preserves stored records',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.close);
    await tester.pumpWidget(f.sources());
    await tester.pump();
    expect(find.text('Музыка'), findsOneWidget);
    expect(find.text('Доступ есть'), findsOneWidget);
    await tester.tap(find.text('Обновить'));
    await tester.pump();
    expect(f.native.picks, 0);
    expect(f.native.opens, 1);
    expect(f.imports.saved, hasLength(2));
    expect(find.textContaining('Последнее обновление:'), findsOneWidget);
    await tester.tap(find.byTooltip('Убрать из библиотеки'));
    await tester.pump();
    expect(f.bookmarks.folders, isEmpty);
    expect(f.imports.saved, hasLength(2));
    expect(f.native.grants, [f.native.first]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'access loss exposes restore; a different picker tree cannot replace the saved one',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.close);
    f.native.inaccessible.add(f.native.first);
    f.native.picked = f.native.second;
    await tester.pumpWidget(f.sources());
    await tester.pump();
    expect(find.text('Разрешить доступ'), findsOneWidget);
    await tester.tap(find.text('Разрешить доступ'));
    await tester.pump();
    expect(f.native.picks, 1);
    expect(f.native.opens, 0);
    expect(f.bookmarks.folders.single.source, f.native.first);
    expect(find.textContaining('Выбрана другая папка.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('saved folders and main controls fit 200 percent text at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = _Fixture();
      addTearDown(f.close);
      await f.bookmarks.initialize();
      await tester.pumpWidget(f.root(textScale: 2));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Обновить библиотеку'));
      await tester.pump();
      expect(f.native.picks, 0);
      expect(f.native.opens, 1);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Папки библиотеки'));
      await tester.pumpAndSettle();
      expect(find.text('Музыка'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('failed registry loads show a fixed message and disable refresh',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.close);
    f.settings.values[AndroidFolderBookmarks.settingKey] = '{bad';
    await tester.pumpWidget(f.sources());
    await tester.pump();
    expect(find.textContaining('Не удалось открыть список папок.'),
        findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.refresh_rounded))
            .onPressed,
        isNull);
    expect(f.settings.values[AndroidFolderBookmarks.settingKey], '{bad');
    await tester.pumpWidget(const SizedBox());
  });
}

final class _Fixture {
  _Fixture() {
    native.grants = [native.first];
    bookmarks = AndroidFolderBookmarks(settings: settings, access: native);
    importer = AndroidImportController(
        documents: native,
        imports: imports,
        artworkCache: const NoopArtworkCacheService(),
        bookmarks: bookmarks);
  }
  final settings = TestFolderSettings();
  final native = TestAudioFolders();
  final imports = _Imports();
  late final AndroidFolderBookmarks bookmarks;
  late final AndroidImportController importer;
  Widget sources() => MaterialApp(
      home: AndroidFoldersScreen(bookmarks: bookmarks, importer: importer));
  Widget root({double textScale = 1}) => MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: AndroidLibraryScreen(
          importer: importer,
          tracks: Stream.value(const []),
          player: _IdlePlayer(),
          playTrack: (_, __) async {},
          previous: () async {},
          next: () async {}));
  Future<void> close() async {
    await importer.close();
    await bookmarks.close();
    importer.dispose();
    bookmarks.dispose();
  }
}

final class _Imports implements TrackImportRepository {
  final saved = <String, Track>{};
  @override
  Future<List<int>> upsertScannedTracks(List<Track> tracks) async {
    for (final track in tracks) {
      saved[track.filePath] = track;
    }
    return [for (var i = 0; i < tracks.length; i++) i + 1];
  }
}

final class _IdlePlayer implements PlayerService {
  @override
  PlayerState get state => const PlayerState.idle();
  @override
  Stream<PlayerState> get stateStream => Stream.value(state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
