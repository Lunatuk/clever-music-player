import 'dart:async';

import 'package:clever_music_player/src/android/android_import_controller.dart';
import 'package:clever_music_player/src/android/android_preview_app.dart';
import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/track_repository.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:clever_music_player/src/ui/design_preview/design_preview_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_audio_engine.dart';

void main() {
  for (final query in [
    'SECOND',
    'второй артист',
    'ВТОРОЙ АЛЬБОМ',
    'unique-b'
  ]) {
    testWidgets('phone search finds $query and starts only its visible context',
        (tester) async {
      final f = _Fixture();
      addTearDown(f.close);
      final tracks = [
        f.track.copyWith(
            id: 1,
            title: 'First',
            artist: 'Первый артист',
            album: 'Первый альбом'),
        f.track.copyWith(
            id: 2,
            title: 'Second',
            artist: 'Второй артист',
            album: 'Второй альбом',
            filePath: 'content://test/document/unique-b')
      ];
      await tester.pumpWidget(f.app(library: tracks));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('android-library-search')), query);
      await tester.pumpAndSettle();
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();
      expect(f.lastContext!.map((t) => t.id), [2]);
      expect(f.player.currentTrack?.id, 2);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('empty search result and clear leave actual playback running',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.player.playTrack(f.track);
    await tester.pumpWidget(f.app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('android-library-search')),
        'Нет такого трека');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
    expect(f.player.isPlaying, isTrue);
    await tester.tap(find.text('Сбросить поиск'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(ListTile), matching: find.text('Тестовый трек')),
        findsOneWidget);
    expect(f.engine.playCalls, 1);
    await tester.pumpWidget(const SizedBox());
  });
  for (final choice in {
    'Название': [2, 1, 3],
    'Исполнитель': [2, 3, 1],
    'Альбом': [3, 2, 1],
    'Недавно добавленные': [3, 2, 1]
  }.entries) {
    testWidgets('phone ${choice.key} order is also used for playback context',
        (tester) async {
      final f = _Fixture();
      addTearDown(f.close);
      final tracks = [
        f.track.copyWith(
            id: 1,
            title: 'Beta',
            artist: 'Z',
            album: 'Z',
            filePath: 'content://test/document/b',
            addedAt: DateTime(2026, 1, 1)),
        f.track.copyWith(
            id: 2,
            title: 'Alpha',
            artist: 'A',
            album: 'B',
            filePath: 'content://test/document/a',
            addedAt: DateTime(2026, 1, 2)),
        f.track.copyWith(
            id: 3,
            title: 'Gamma',
            artist: 'M',
            album: 'A',
            filePath: 'content://test/document/g',
            addedAt: DateTime(2026, 1, 3))
      ];
      await tester.pumpWidget(f.app(library: tracks));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('android-library-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice.key));
      await tester.pumpAndSettle();
      final title =
          tracks.singleWhere((t) => t.id == choice.value.first).title!;
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(f.lastContext!.map((t) => t.id), choice.value);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'search stays applied when library stream adds another matching song',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.close);
    final stream = StreamController<List<Track>>();
    addTearDown(stream.close);
    await tester.pumpWidget(f.app(stream: stream.stream));
    stream.add([f.track.copyWith(id: 1, title: 'Alpha')]);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('android-library-search')), 'Beta');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
    stream.add([
      f.track.copyWith(id: 1, title: 'Alpha'),
      f.track.copyWith(id: 2, title: 'Beta')
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    await tester.tap(find.descendant(
        of: find.byType(ListTile), matching: find.text('Beta')));
    await tester.pumpAndSettle();
    expect(f.lastContext!.single.id, 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'landscape keyboard and large text preserve search and ongoing audio',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = _Fixture();
    addTearDown(f.close);
    await f.player.playTrack(f.track);
    await tester.pumpWidget(f.app(textScale: 2, keyboard: 220));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('android-library-search')), 'Тест');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(f.player.isPlaying, isTrue);
    expect(find.byTooltip('Пауза'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'design gallery opens from About while real playback and search survive',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.player.playTrack(f.track);
    await tester.pumpWidget(f.app());
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('android-library-search')), 'Тест');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('О версии'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Варианты дизайна'));
    await tester.pumpAndSettle();
    expect(find.byType(DesignPreviewScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Пауза'));
    await tester.pumpAndSettle();
    expect(f.player.isPlaying, isTrue);
    expect(f.engine.playCalls, 1);
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('android-library-search')))
            .controller!
            .text,
        'Тест');
    expect(f.player.isPlaying, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('phone layout selects once, plays, pauses and seeks',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await tester.pumpWidget(fixture.app());
    await tester.pump();
    await tester.tap(find.text('Тестовый трек'));
    await tester.pump();
    expect(fixture.selections, 1);
    expect(fixture.engine.playCalls, 1);
    expect(fixture.engine.sources.single, fixture.track.source);
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.byTooltip('Пауза'));
    await tester.pump();
    expect(fixture.player.isPlaying, isFalse);
    await tester.tap(find.byTooltip('Воспроизвести'));
    await tester.pump();
    expect(fixture.player.isPlaying, isTrue);
    await tester.tap(find.byType(Slider));
    await tester.pump();
    expect(fixture.engine.seekPositions, isNotEmpty);
    await tester.tap(find.byTooltip('Следующий трек'));
    await tester.pump();
    expect(fixture.nextCalls, 1);
    await tester.tap(find.byTooltip('Остановить'));
    await tester.pump();
    expect(fixture.stopCalls, 1);
    expect(fixture.player.currentTrack, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compact landscape and large text do not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.player.playTrack(fixture.track);
    await tester.pumpWidget(fixture.app(textScale: 2));
    await tester.pump();
    expect(find.byTooltip('Пауза'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets('6000 phone tracks jump lazily at text scale $textScale',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _Fixture();
      addTearDown(fixture.close);
      final tracks = List.generate(
          6000,
          (index) => fixture.track.copyWith(
              id: index + 1,
              title: 'Phone track ${index.toString().padLeft(4, '0')}'));
      await tester
          .pumpWidget(fixture.app(textScale: textScale, library: tracks));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(find
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
              .first)
          .position;
      final extent = position.maxScrollExtent;
      var newRows = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (!builtOnce && element.widget is ListTile) newRows++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (final fraction in [0.5, 0.9, 0.1, 1.0, 0.0]) {
        newRows = 0;
        position.jumpTo(extent * fraction);
        await tester.pumpAndSettle();
        expect(newRows, lessThan(60));
        expect(find.byType(ListTile).evaluate().length, lessThan(60));
        expect(position.maxScrollExtent, closeTo(extent, 1));
        expect(position.pixels, closeTo(extent * fraction, 1));
        expect(tester.takeException(), isNull);
        debugPrint('6000 phone tracks, scale $textScale, jump $fraction: '
            '$newRows new rows');
      }
      position.jumpTo(extent * 0.5);
      await tester.pumpAndSettle();
      final row = find.byType(ListTile).hitTestable().first;
      final title = (tester.widget<ListTile>(row).title! as Text).data;
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(fixture.player.currentTrack?.displayTitle, title);
      expect(fixture.lastContext, orderedEquals(tracks));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'phone collapses nested grant aliases before display and queue context, keeping distinct same-title songs',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final parent = fixture.track.copyWith(
        id: 1,
        filePath:
            'content://music.documents/tree/parent/document/opaque%3Asong',
        title: 'Shared song');
    final child = parent.copyWith(
        id: 2,
        filePath:
            'content://music.documents/tree/child/document/opaque%3Asong');
    final other = parent.copyWith(
        id: 3,
        filePath: 'content://music.documents/tree/child/document/other',
        title: 'Another song');
    await tester.pumpWidget(fixture.app(library: [child, parent, other]));
    await tester.pumpAndSettle();
    expect(find.text('Shared song'), findsOneWidget);
    expect(find.text('Another song'), findsOneWidget);
    await tester.tap(find.text('Shared song'));
    await tester.pumpAndSettle();
    expect(fixture.player.currentTrack?.source, parent.source);
    expect(fixture.lastContext!.map((t) => t.id), [3, 1]);
    expect(fixture.engine.sources.single, parent.source);
    await tester.pumpWidget(fixture.app(library: [child, other]));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(ListTile), matching: find.text('Shared song')));
    await tester.pumpAndSettle();
    expect(fixture.player.currentTrack?.source, child.source);
    expect(fixture.lastContext!.map((t) => t.id), [3, 2]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'folder button enters busy state and survives picker cancellation',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.player.playTrack(fixture.track);
    await tester.pumpWidget(fixture.app(textScale: 2));
    await tester.pump();
    await tester.tap(find.byTooltip('Добавить папку'));
    await tester.pump();
    expect(fixture.documents.folderPicks, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.add_rounded))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
    fixture.documents.picker.complete(null);
    await tester.pump();
    expect(fixture.importer.busy, isFalse);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
        'folder cancel button drains traversal with large text at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _Fixture();
      addTearDown(fixture.close);
      await fixture.player.playTrack(fixture.track);
      await tester.pumpWidget(fixture.app(textScale: 2));
      await tester.pump();
      await tester.tap(find.byTooltip('Добавить папку'));
      fixture.documents.picker
          .complete(ContentUriAudioSource('content://test/tree/Music'));
      await tester.pump();
      expect(fixture.importer.canCancel, isTrue);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Остановить импорт'));
      await tester.pump();
      expect(fixture.documents.closes, 1);
      expect(fixture.importer.busy, isFalse);
      expect(find.textContaining('Импорт остановлен.'), findsOneWidget);
      expect(fixture.player.isPlaying, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

final class _Fixture {
  _Fixture() {
    importer = AndroidImportController(
        documents: documents,
        imports: DriftRepositories(database).tracks as TrackImportRepository,
        artworkCache: const NoopArtworkCacheService());
    player = JustAudioPlayerService(
        audioEngine: engine,
        isWindows: false,
        playbackEvents: DriftRepositories(database).playbackEvents);
  }
  final database = AppDatabase(NativeDatabase.memory());
  final engine = TestAudioEngine();
  final documents = _Documents();
  late final AndroidImportController importer;
  late final JustAudioPlayerService player;
  int selections = 0, nextCalls = 0, stopCalls = 0;
  List<Track>? lastContext;
  final track = Track.fromSource(
      source: ContentUriAudioSource('content://music.test/song'),
      title: 'Тестовый трек',
      artist: 'Исполнитель',
      duration: const Duration(minutes: 1),
      addedAt: DateTime(2026),
      updatedAt: DateTime(2026));
  Widget app(
          {double textScale = 1,
          List<Track>? library,
          Stream<List<Track>>? stream,
          double keyboard = 0}) =>
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                viewInsets: EdgeInsets.only(bottom: keyboard)),
            child: child!),
        home: AndroidLibraryScreen(
            importer: importer,
            tracks: stream ?? Stream.value(library ?? [track]),
            player: player,
            playTrack: (track, tracks) async {
              selections++;
              lastContext = tracks;
              await player.playTrack(track);
            },
            previous: () async {},
            next: () async {
              nextCalls++;
            },
            stop: () async {
              stopCalls++;
              await player.stop();
            }),
      );
  Future<void> close() async {
    await importer.close();
    importer.dispose();
    await player.dispose();
    await database.close();
  }
}

final class _Documents implements AudioDocuments, AudioDocumentFolders {
  int folderPicks = 0;
  int closes = 0;
  final picker = Completer<ContentUriAudioSource?>();
  final page = Completer<AudioFolderPage>();
  @override
  Future<ContentUriAudioSource?> pickAudioFolder() {
    folderPicks++;
    return picker.future;
  }

  @override
  Future<int> openAudioFolder(ContentUriAudioSource tree) async => 1;
  @override
  Future<AudioFolderPage> readAudioFolderPage(int session) async => page.future;
  @override
  Future<void> closeAudioFolder(int session) async {
    closes++;
    if (!page.isCompleted) {
      page.complete(const AudioFolderPage([], visited: 0, done: true));
    }
  }

  @override
  Future<AudioDocumentSelection?> pickAudio() async => null;
  @override
  Future<AudioDocumentMetadata> readAudio(ContentUriAudioSource source) async =>
      const AudioDocumentMetadata();
}
