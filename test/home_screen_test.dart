import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:clever_music_player/src/app/clever_music_player_app.dart';
import 'package:clever_music_player/src/app/dependency_scope.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/library_sync/yandex_connection_controller.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_update_controller.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/repositories.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/library/custom_artwork_service.dart';
import 'package:clever_music_player/src/library/directory_picker_service.dart';
import 'package:clever_music_player/src/library/library_scanner_service.dart';
import 'package:clever_music_player/src/library/library_controller.dart';
import 'package:clever_music_player/src/library/library_management_service.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:clever_music_player/src/player/player_service.dart';
import 'package:clever_music_player/src/player/player_state.dart';
import 'package:clever_music_player/src/queue/playback_queue_service.dart';
import 'package:clever_music_player/src/queue/queue_state.dart';
import 'package:clever_music_player/src/recommendation/recommendation_service.dart';
import 'package:clever_music_player/src/smtc/smtc_service.dart';
import 'package:clever_music_player/src/ui/track_artwork.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/learning_repository_helpers.dart';
import 'support/yandex_connection_fixture.dart';

void main() {
  testWidgets(
      'scan progress survives navigation and can stop without pausing music',
      (tester) async {
    await _setLargeSurface(tester);
    final entered = Completer<LibraryScanControl>();
    final release = Completer<void>();
    final fixture = await _HomeScreenFixture.create(
        seedLibrary: true,
        controlledScanFolder: (path, {required control}) async {
          control.report(LibraryScanProgress(
              folderPath: path,
              stage: LibraryScanStage.hashing,
              processedFiles: 7,
              fileName: 'large.wav',
              fileBytesRead: 50,
              fileSizeBytes: 100));
          entered.complete(control);
          await release.future;
          return LibraryScanResult(
              folderPath: path,
              scannedFiles: 7,
              addedTracks: 0,
              updatedTracks: 7,
              missingTracks: 0,
              errors: const [],
              wasCancelled: control.isCancellationRequested);
        });
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    await fixture.player.playTrack(_testTrack());
    final scanning = fixture.dependencies.libraryController.rescanLibrary();
    final control = await entered.future;
    try {
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Обработано файлов: 7'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-music')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('large.wav'), findsOneWidget);
      await tester.tap(find.text('Остановить сканирование'));
      await tester.pump();
      expect(control.isCancellationRequested, isTrue);
      expect(find.text('Останавливаем сканирование…'), findsOneWidget);
      expect(fixture.player.state.isPlaying, isTrue);
    } finally {
      release.complete();
      await scanning;
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('Сканирование остановлено.'), findsOneWidget);
    expect(fixture.dependencies.libraryController.state.isBusy, isFalse);
  });

  testWidgets(
      'exact copies toggle and search produce the visible playback context',
      (tester) async {
    await _setLargeSurface(tester);
    final hash = 'file-sha256-v1:3:${'a' * 64}';
    final original =
        _testTrack(id: 1, title: 'Same title').copyWith(contentHash: hash);
    final copy = original.copyWith(id: 2, filePath: '/copies/song.mp3');
    final different = original.copyWith(
        id: 3,
        filePath: '/other/song.mp3',
        contentHash: 'file-sha256-v1:3:${'b' * 64}');
    final fixture = await _HomeScreenFixture.create(
        seedTracks: [original, copy, different]);
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();
    expect(find.text('Same title'), findsNWidgets(2));
    final toggle = find.widgetWithText(FilterChip, 'Показывать точные копии');
    expect(tester.widget<FilterChip>(toggle).selected, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Same title'), findsNWidgets(3));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Same title'), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).first, 'copies');
    await tester.pumpAndSettle();
    expect(find.text('Same title'), findsOneWidget);
    await tester.tap(find.text('Same title'));
    await tester.pumpAndSettle();
    expect(fixture.player.state.currentTrack?.id, 2);
    expect(fixture.queue.state.playbackContext.tracks.map((track) => track.id),
        [2]);
    expect(await fixture.dependencies.repositories.tracks.listTracks(),
        hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'default library playback omits copies while retaining same-title tracks',
      (tester) async {
    await _setLargeSurface(tester);
    final original = _testTrack(id: 1, title: 'Same title')
        .copyWith(contentHash: 'file-sha256-v1:3:${'a' * 64}');
    final fixture = await _HomeScreenFixture.create(seedTracks: [
      original.copyWith(id: 2, filePath: '/copy/song.mp3'),
      original,
      original.copyWith(
          id: 3,
          filePath: '/different/song.mp3',
          contentHash: 'file-sha256-v1:3:${'b' * 64}'),
    ]);
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Same title').first);
    await tester.pumpAndSettle();
    expect(fixture.queue.state.playbackContext.tracks.map((track) => track.id),
        [3, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library scan survives navigation and keeps actions disabled',
      (tester) async {
    await _setLargeSurface(tester);
    final gate = Completer<LibraryScanResult>();
    final fixture = await _HomeScreenFixture.create(
        seedLibrary: true, scanFolder: (_) => gate.future);
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    final scanning =
        fixture.dependencies.libraryController.rescanFolder(_testFolder());
    try {
      await tester.pump();
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pump();
      expect(
          tester
              .widget<OutlinedButton>(find.widgetWithText(
                  OutlinedButton, 'Пересканировать библиотеку'))
              .onPressed,
          isNull);
      await tester.tap(find.text('Папки библиотеки'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Отключить'))
              .onPressed,
          isNull);
      await tester.tap(find.text('Моя музыка').first);
      await tester.pump();
      expect(fixture.dependencies.libraryController.state.isBusy, true);
      expect(fixture.player.state.status, PlayerPlaybackStatus.idle);
    } finally {
      gate.complete(_controlledScanResult());
      await scanning;
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(
                OutlinedButton, 'Пересканировать библиотеку'))
            .onPressed,
        isNotNull);
    expect(find.textContaining('Просканировано файлов: 3'), findsOneWidget);
  });

  testWidgets(
      'recreated home observes the app-scoped picker and its cancellation',
      (tester) async {
    await _setLargeSurface(tester);
    final picker = _GatedDirectoryPicker();
    final fixture = await _HomeScreenFixture.create(directoryPicker: picker);
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    await tester.tap(find.text('Добавить папку с музыкой'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(AppDependenciesScope(
        dependencies: fixture.dependencies,
        child: const CleverMusicPlayerApp()));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Добавить папку с музыкой'))
            .onPressed,
        isNull);
    picker.result.complete(null);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Добавить папку с музыкой'))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing dependencies ignores the old library result',
      (tester) async {
    await _setLargeSurface(tester);
    final gate = Completer<LibraryScanResult>();
    final old = await _HomeScreenFixture.create(scanFolder: (_) => gate.future);
    final current = await _HomeScreenFixture.create();
    _addFixtureTearDown(tester, old);
    _addFixtureTearDown(tester, current);
    await old.pump(tester);
    final scanning =
        old.dependencies.libraryController.rescanFolder(_testFolder());
    await tester.pump();
    await current.pump(tester);
    gate.complete(_controlledScanResult());
    await scanning;
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(current.dependencies.libraryController.state.lastScanResult, isNull);
    expect(find.textContaining('Просканировано файлов: 3'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('folder picker reserves library actions before its result',
      (tester) async {
    await _setLargeSurface(tester);
    final picker = _GatedDirectoryPicker();
    final fixture = await _HomeScreenFixture.create(directoryPicker: picker);
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    try {
      await tester.tap(find.text('Добавить папку с музыкой'));
      await tester.pump();
      await tester.tap(find.text('Добавить папку с музыкой'));
      await tester.pump();
      expect(picker.calls, 1);
      expect(fixture.player.state.status, PlayerPlaybackStatus.idle);
    } finally {
      picker.result.complete(null);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('settings exposes a diagnostic report without playback changes',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create();
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Создать диагностический отчёт'), findsOneWidget);
    expect(find.text('Открыть папку диагностики'), findsOneWidget);
    expect(fixture.player.state.status, PlayerPlaybackStatus.idle);
  });
  testWidgets('bottom player can pause a source that is still loading',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    fixture.player._emit(PlayerState(
      currentTrack: _testTrack(),
      isPlaying: true,
      duration: const Duration(minutes: 3),
      status: PlayerPlaybackStatus.loading,
    ));
    await tester.pump();
    await tester.pump();

    final pauseButton = find.byTooltip('Пауза');
    expect(pauseButton, findsOneWidget);
    await tester.tap(pauseButton);
    await tester.pump();
    expect(fixture.player.state.status, PlayerPlaybackStatus.paused);
    await tester.pump();
    expect(find.byTooltip('Воспроизвести'), findsOneWidget);
  });

  testWidgets('home shows Liquid Wave actions and bottom player bar',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create();
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);

    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, isTrue);
    expect(find.text('Запустить волну'), findsOneWidget);
    expect(find.text('Настроить'), findsOneWidget);
    expect(find.text('Добавить папку с музыкой'), findsOneWidget);
    expect(find.text('Пересканировать'), findsOneWidget);
    expect(find.text('Волна'), findsOneWidget);
    expect(find.text('Моя музыка'), findsAtLeastNWidgets(2));
    expect(find.text('Плейлисты'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Clever'), findsNothing);
    expect(find.byTooltip('Открыть Моя музыка'), findsNothing);
    expect(find.byKey(const ValueKey('active-nav-wave')), findsOneWidget);
    expect(find.text('Трек не играет'), findsOneWidget);
    expect(find.byType(TrackArtwork), findsOneWidget);
    expect(find.text('Liquid Wave'), findsNothing);
    expect(find.text('Local-first music flow'), findsNothing);
    expect(
      find.text('Волна играет. Нажатие поставит воспроизведение на паузу.'),
      findsNothing,
    );
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    expect(find.byTooltip('Stop'), findsNothing);
  });

  testWidgets('bottom player bar renders volume control and changes volume',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create();
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);

    expect(
      find.byKey(const ValueKey('bottom-player-volume-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bottom-player-volume-slider')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('bottom-player-volume-slider')),
    );
    slider.onChanged!(0.35);
    await tester.pump();

    expect(fixture.player.setVolumeCalls.last, 0.35);

    await tester.tap(find.byKey(const ValueKey('bottom-player-volume-button')));
    await tester.pump();

    expect(fixture.player.toggleMuteCalls, 1);
  });

  testWidgets('narrow bottom bar shows hover volume popup', (tester) async {
    await _setNarrowSurface(tester);
    final fixture = await _HomeScreenFixture.create();
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);

    expect(
      find.byKey(const ValueKey('bottom-player-volume-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bottom-player-volume-slider')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('bottom-player-volume-popup-slider')),
      findsNothing,
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(
      location: tester.getCenter(
        find.byKey(const ValueKey('bottom-player-volume-button')),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('bottom-player-volume-popup-slider')),
      findsOneWidget,
    );
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('bottom-player-volume-button')),
    );
    final popupRect = tester.getRect(
      find.byKey(const ValueKey('bottom-player-volume-popup')),
    );
    expect(buttonRect.top - popupRect.bottom, closeTo(8, 1));

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('bottom-player-volume-popup-slider')),
    );
    slider.onChanged!(0.6);
    await tester.pump();

    expect(fixture.player.setVolumeCalls.last, 0.6);
  });

  testWidgets('central launch icon stays start for non-Wave playback',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);

    await fixture.player.playTrack(_testTrack());
    await fixture.pump(tester);

    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_filled_rounded), findsNothing);
    expect(find.textContaining('Волна играет'), findsNothing);
    expect(find.text('Test Track - Test Artist'), findsNothing);
  });

  testWidgets('hero Wave action interrupts playlist context and starts Wave',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: [
        _testTrack(id: 1, title: 'Playlist Track'),
        _testTrack(id: 2, title: 'Wave Track', artist: 'Wave Artist'),
      ],
    );
    _addFixtureTearDown(tester, fixture);
    final playlistId =
        await fixture.dependencies.repositories.playlists.createPlaylist(
      'Road Mix',
    );
    await fixture.dependencies.repositories.playlists.addTrackToPlaylist(
      playlistId,
      1,
    );
    final entries = await fixture.dependencies.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;

    await fixture.queue.playPlaylist(
      playlistId: playlistId,
      playlistName: 'Road Mix',
      entries: entries,
      startTrackId: 1,
    );
    await fixture.pump(tester);

    expect(fixture.queue.state.isWaveCurrentSource, isFalse);
    expect(find.textContaining('Волна играет'), findsNothing);
    expect(find.text('Playlist Track - Test Artist'), findsNothing);

    await tester.tap(find.text('Запустить волну'));
    await tester.pumpAndSettle();
    await _waitUntil(() => fixture.queue.state.isWaveCurrentSource);
    await tester.pumpAndSettle();

    expect(fixture.queue.state.isWaveCurrentSource, isTrue);
    expect(fixture.queue.state.playbackContext.source, PlaybackSource.none);
    expect(fixture.queue.state.lastRecommendationResult, isNotNull);
    expect(find.textContaining('Волна играет'), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_filled_rounded), findsOneWidget);
  });

  testWidgets('hero Wave action interrupts standalone playback and starts Wave',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: [
        _testTrack(id: 1, title: 'Standalone Track'),
        _testTrack(id: 2, title: 'Wave Track', artist: 'Wave Artist'),
      ],
    );
    _addFixtureTearDown(tester, fixture);

    await fixture.queue.playTrackManually(_testTrack(
      id: 1,
      title: 'Standalone Track',
    ));
    await fixture.pump(tester);

    expect(fixture.queue.state.activeSource, PlaybackSource.singleTrack);
    expect(fixture.queue.state.isWaveCurrentSource, isFalse);

    await tester.tap(find.text('Запустить волну'));
    await tester.pumpAndSettle();
    await _waitUntil(() => fixture.queue.state.isWaveCurrentSource);
    await tester.pumpAndSettle();

    expect(fixture.queue.state.isWaveCurrentSource, isTrue);
    expect(fixture.queue.state.lastRecommendationResult, isNotNull);
    expect(fixture.player.isPlaying, isTrue);
  });

  testWidgets('hero Wave action pauses while Wave is playing', (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: [
        _testTrack(id: 1, title: 'Wave Track'),
        _testTrack(id: 2, title: 'Second Wave Track'),
      ],
    );
    _addFixtureTearDown(tester, fixture);

    await fixture.queue.playSmartNext();
    await fixture.pump(tester);

    expect(fixture.queue.state.isWaveCurrentSource, isTrue);
    expect(fixture.player.isPlaying, isTrue);

    await tester.tap(find.text('Запустить волну'));
    await tester.pumpAndSettle();

    expect(fixture.queue.state.isWaveCurrentSource, isTrue);
    expect(fixture.player.isPlaying, isFalse);
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
  });

  testWidgets('hero Wave action resumes while Wave is paused', (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: [
        _testTrack(id: 1, title: 'Wave Track'),
        _testTrack(id: 2, title: 'Second Wave Track'),
      ],
    );
    _addFixtureTearDown(tester, fixture);

    await fixture.queue.playSmartNext();
    await fixture.player.pause();
    await fixture.pump(tester);

    expect(fixture.queue.state.isWaveCurrentSource, isTrue);
    expect(fixture.player.isPlaying, isFalse);

    await tester.tap(find.text('Запустить волну'));
    await tester.pumpAndSettle();

    expect(fixture.queue.state.isWaveCurrentSource, isTrue);
    expect(fixture.player.isPlaying, isTrue);
    expect(find.byIcon(Icons.pause_circle_filled_rounded), findsOneWidget);
  });

  testWidgets('My Music navigation shows track library and keeps player bar',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();

    expect(find.text('Библиотека треков'), findsOneWidget);
    expect(find.text('Test Track'), findsOneWidget);
    expect(find.text('Трек не играет'), findsOneWidget);
    expect(find.byType(TrackArtwork), findsNWidgets(2));
  });

  testWidgets('My Music renders a large library lazily', (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: _largeLibraryTracks(600),
    );
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
        find.text(
          'Видимых: 600 / Проиндексировано: 600 / '
          'Отсутствует: 0 / Папок: 1',
        ),
        findsOneWidget);
    expect(find.text('Track 000'), findsOneWidget);
    expect(find.text('Track 599'), findsNothing);
    expect(find.byType(TrackArtwork).evaluate().length, lessThan(600));
  });

  testWidgets('far library jumps build only nearby rows', (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: _largeLibraryTracks(6000),
    );
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final position = scrollable.position;
    final extent = position.maxScrollExtent;
    var builtCovers = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (!builtOnce && element.widget is TrackArtwork) builtCovers++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    for (final fraction in [0.5, 0.9, 0.2, 1.0, 0.0]) {
      builtCovers = 0;
      final clock = Stopwatch()..start();
      position.jumpTo(extent * fraction);
      await tester.pumpAndSettle();
      clock.stop();
      debugPrint('6000-track jump $fraction: $builtCovers new rows, '
          '${clock.elapsedMilliseconds} ms (widget test)');
      expect(builtCovers, lessThan(80));
      expect(find.byType(TrackArtwork).evaluate().length, lessThan(80));
      expect(position.maxScrollExtent, closeTo(extent, 1));
      expect(position.pixels, closeTo(extent * fraction, 1));
      expect(tester.takeException(), isNull);
    }

    position.jumpTo(extent * 0.5);
    await tester.pumpAndSettle();
    final cover = find.byType(TrackArtwork).hitTestable().first;
    final selectedTrack = tester.widget<TrackArtwork>(cover).track!;
    await tester.tap(cover);
    await tester.pumpAndSettle();
    expect(fixture.player.currentTrack?.id, selectedTrack.id);
    expect(fixture.queue.state.playbackContext.tracks, hasLength(6000));
  });

  testWidgets('dragging desktop scrollbar skips distant library rows',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: _largeLibraryTracks(6000),
    );
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(find
        .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable))
        .first);
    final rect = tester.getRect(find.byType(CustomScrollView));
    // Automatic desktop scrollbars fade out when idle. Give the thumb a real
    // scroll notification before attempting to grab its painted hit target.
    scrollable.position.jumpTo(1);
    await tester.pump(const Duration(milliseconds: 200));
    scrollable.position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 16));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    final start = Offset(rect.right - 8, rect.top + 16);
    await pointer.addPointer(location: rect.center);
    await pointer.moveTo(start);
    await tester.pump(const Duration(milliseconds: 16));
    var builtCovers = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (!builtOnce && element.widget is TrackArtwork) builtCovers++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    await pointer.down(start);
    await tester.pump(const Duration(milliseconds: 100));
    await pointer.moveTo(Offset(start.dx, rect.center.dy));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels,
        greaterThan(scrollable.position.maxScrollExtent * 0.3));
    expect(builtCovers, lessThan(80));
    debugPrint('6000-track mouse thumb drag: $builtCovers new rows');
    await pointer.up();
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets('library row height adapts to larger text after a far jump',
      (tester) async {
    await _setNarrowSurface(tester);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: _largeLibraryTracks(6000),
    );
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first)
        .position;
    final smallExtent = position.maxScrollExtent;
    position.jumpTo(smallExtent * 0.5);
    await tester.pumpAndSettle();
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await tester.pumpAndSettle();
    expect(position.maxScrollExtent, greaterThan(smallExtent));
    position.jumpTo(position.maxScrollExtent * 0.8);
    await tester.pumpAndSettle();
    final cover = find.byType(TrackArtwork).hitTestable().first;
    final row = find.ancestor(of: cover, matching: find.byType(Material)).first;
    final rowRect = tester.getRect(row);
    final labels = find.descendant(
        of: row,
        matching: find.byWidgetPredicate((widget) =>
            widget is Text && widget.overflow == TextOverflow.ellipsis));
    expect(labels, findsNWidgets(2));
    for (final label in labels.evaluate()) {
      final labelRect = tester.getRect(find.byWidget(label.widget));
      expect(labelRect.top, greaterThanOrEqualTo(rowRect.top));
      expect(labelRect.bottom, lessThanOrEqualTo(rowRect.bottom));
    }
    expect(find.byType(TrackArtwork).evaluate().length, lessThan(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('filtering a distant library position clamps and clears safely',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: _largeLibraryTracks(6000),
    );
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();
    final search = tester.widget<TextField>(find.byType(TextField).first);
    final position = tester
        .state<ScrollableState>(find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first)
        .position;
    final extent = position.maxScrollExtent;
    position.jumpTo(extent * 0.9);
    await tester.pumpAndSettle();
    search.controller!.text = 'Track 599';
    search.onChanged!('Track 599');
    await tester.pumpAndSettle();
    expect(position.maxScrollExtent, lessThan(extent * 0.01));
    expect(position.outOfRange, isFalse);
    expect(find.text('Track 5999'), findsOneWidget);
    search.controller!.text = 'no matching tracks';
    search.onChanged!('no matching tracks');
    await tester.pumpAndSettle();
    expect(
        find.text('Нет треков, подходящих под эти фильтры.'), findsOneWidget);
    expect(position.outOfRange, isFalse);
    search.controller!.clear();
    search.onChanged!('');
    await tester.pumpAndSettle();
    expect(position.maxScrollExtent, closeTo(extent, 1));
    expect(find.text('Track 000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('player progress ticks do not recreate library streams',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: _largeLibraryTracks(50),
    );
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();
    await fixture.player.playTrack(_largeLibraryTracks(1).single);
    await tester.pumpAndSettle();

    final trackRepository =
        fixture.dependencies.repositories.tracks as _FakeTrackRepository;
    final userStateRepository = fixture.dependencies.repositories.trackUserState
        as _FakeTrackUserStateRepository;
    final activeTrackStreamCreations =
        trackRepository.activeTrackStreamCreations;
    final indexedTrackStreamCreations =
        trackRepository.indexedTrackStreamCreations;
    final userStateStreamCreations =
        userStateRepository.watchTrackStatesByTrackIdsCalls;

    for (var second = 1; second <= 5; second++) {
      fixture.player.emitPositionTick(Duration(seconds: second));
      await tester.pump();
    }

    expect(
        trackRepository.activeTrackStreamCreations, activeTrackStreamCreations);
    expect(trackRepository.indexedTrackStreamCreations,
        indexedTrackStreamCreations);
    expect(userStateRepository.watchTrackStatesByTrackIdsCalls,
        userStateStreamCreations);
    expect(
        find.text(
          'Видимых: 50 / Проиндексировано: 50 / '
          'Отсутствует: 0 / Папок: 1',
        ),
        findsOneWidget);
  });

  testWidgets(
      'count stream avoids a second full library subscription and updates',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture =
        await _HomeScreenFixture.create(seedTracks: _largeLibraryTracks(2));
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();
    final tracks =
        fixture.dependencies.repositories.tracks as _FakeTrackRepository;
    expect(tracks.activeTrackStreamCreations, 1);
    expect(tracks.indexedTrackStreamCreations, 0);
    expect(tracks.indexedCountStreamCreations, 1);
    await tracks.upsertTrack(_testTrack(id: 99, title: 'New imported track'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Проиндексировано: 3'), findsOneWidget);
    expect(find.text('New imported track'), findsOneWidget);
  });

  testWidgets('changing track order retains the same feedback subscription',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture =
        await _HomeScreenFixture.create(seedTracks: _largeLibraryTracks(3));
    _addFixtureTearDown(tester, fixture);
    await fixture.pump(tester);
    final tracks =
        fixture.dependencies.repositories.tracks as _FakeTrackRepository;
    final feedback = fixture.dependencies.repositories.trackUserState
        as _FakeTrackUserStateRepository;
    final creations = feedback.watchTrackStatesByTrackIdsCalls;
    tracks._tracks.setAll(0, tracks._tracks.reversed.toList());
    tracks._emit();
    await tester.pumpAndSettle();
    expect(feedback.watchTrackStatesByTrackIdsCalls, creations);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar navigates primary pages and keeps player bar',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);

    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();
    expect(find.text('Библиотека треков'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-nav-music')), findsOneWidget);
    expect(find.text('Трек не играет'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-playlists')));
    await tester.pumpAndSettle();
    expect(find.text('Создать плейлист'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-nav-playlists')), findsOneWidget);
    expect(find.text('Трек не играет'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Папки библиотеки'), findsOneWidget);
    expect(find.text('Почему выбран трек'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-nav-settings')), findsOneWidget);
    expect(find.text('Трек не играет'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-wave')));
    await tester.pumpAndSettle();
    expect(find.text('Запустить волну'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-nav-wave')), findsOneWidget);
    expect(find.text('Трек не играет'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsNothing);
  });

  testWidgets('sidebar compacts on narrow windows without overflow',
      (tester) async {
    await _setNarrowSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('nav-wave')), findsOneWidget);
    expect(find.text('Волна'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('nav-playlists')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Создать плейлист'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-nav-playlists')), findsOneWidget);
  });

  testWidgets('page transition keeps content and bottom player visible',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    expect(find.byType(AnimatedSwitcher), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pump(const Duration(milliseconds: 90));

    expect(find.text('Библиотека треков'), findsOneWidget);
    expect(find.text('Трек не играет'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('Библиотека треков'), findsOneWidget);
  });

  testWidgets('desktop sidebar collapses without losing active state',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);

    final waveLabelInNav = find.descendant(
      of: find.byKey(const ValueKey('nav-wave')),
      matching: find.text('Волна'),
    );
    expect(waveLabelInNav, findsOneWidget);
    expect(find.byKey(const ValueKey('active-nav-wave')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sidebar-collapse-toggle')));
    await tester.pumpAndSettle();

    expect(waveLabelInNav, findsNothing);
    expect(find.byKey(const ValueKey('active-nav-wave')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('active-nav-music')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sidebar-collapse-toggle')));
    await tester.pumpAndSettle();

    final musicLabelInNav = find.descendant(
      of: find.byKey(const ValueKey('nav-music')),
      matching: find.text('Моя музыка'),
    );
    expect(musicLabelInNav, findsOneWidget);
    expect(find.byKey(const ValueKey('active-nav-music')), findsOneWidget);
  });

  testWidgets('Playlists page can create a playlist', (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-playlists')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Создать плейлист'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Road Mix');
    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();

    expect(find.text('Road Mix'), findsOneWidget);
    expect(find.textContaining('0 треков'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-nav-playlists')), findsOneWidget);
  });

  testWidgets('track row can add a track to an existing playlist',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);
    await fixture.dependencies.repositories.playlists.createPlaylist(
      'Road Mix',
    );

    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Добавить в плейлист'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road Mix'));
    await tester.pumpAndSettle();

    final playlists = await fixture.dependencies.repositories.playlists
        .watchPlaylists()
        .first;

    expect(playlists.single.name, 'Road Mix');
    expect(playlists.single.trackCount, 1);
  });

  testWidgets('track row can set and remove custom cover art', (tester) async {
    await _setLargeSurface(tester);
    final customArtwork = _FakeCustomArtworkService(
      artwork: const CachedArtwork(
        path: '/app/custom_artwork/cover.png',
        hash: 'custom-hash',
        mimeType: 'image/png',
      ),
    );
    final fixture = await _HomeScreenFixture.create(
      seedLibrary: true,
      customArtwork: customArtwork,
    );
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Действия с треком'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Установить обложку'));
    await tester.pumpAndSettle();

    final coveredTrack =
        await fixture.dependencies.repositories.tracks.findById(1);
    expect(customArtwork.pickCount, 1);
    expect(coveredTrack?.customArtworkPath, '/app/custom_artwork/cover.png');
    expect(coveredTrack?.customArtworkHash, 'custom-hash');
    expect(coveredTrack?.customArtworkMimeType, 'image/png');

    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Действия с треком'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить пользовательскую обложку'));
    await tester.pumpAndSettle();

    final updatedTrack =
        await fixture.dependencies.repositories.tracks.findById(1);
    expect(updatedTrack?.customArtworkPath, isNull);
    expect(updatedTrack?.customArtworkHash, isNull);
    expect(updatedTrack?.customArtworkMimeType, isNull);
  });

  testWidgets('track row surfaces custom cover picker errors', (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedLibrary: true,
      customArtwork: _FakeCustomArtworkService(
        error: const FormatException('not an image'),
      ),
    );
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Действия с треком'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Установить обложку'));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Не удалось установить обложку'), findsOneWidget);
    final track = await fixture.dependencies.repositories.tracks.findById(1);
    expect(track?.customArtworkPath, isNull);
  });

  testWidgets('playlist detail can add tracks from the active library',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: [
        _testTrack(id: 1, title: 'Test Track'),
        _testTrack(id: 2, title: 'Second Track', artist: 'Second Artist'),
      ],
    );
    _addFixtureTearDown(tester, fixture);
    final playlistId =
        await fixture.dependencies.repositories.playlists.createPlaylist(
      'Road Mix',
    );
    await fixture.dependencies.repositories.playlists.addTrackToPlaylist(
      playlistId,
      1,
    );

    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-playlists')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road Mix'));
    await tester.pumpAndSettle();

    expect(find.text('К плейлистам'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-nav-playlists')), findsOneWidget);

    await tester.tap(find.text('Добавить треки'));
    await tester.pumpAndSettle();

    expect(find.text('Test Track'), findsWidgets);
    expect(find.text('Second Track'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Добавлен'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Добавить'));
    await tester.pumpAndSettle();

    final entries = await fixture.dependencies.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;

    expect(entries.map((entry) => entry.trackId), [1, 2]);
    expect(find.widgetWithText(TextButton, 'Добавлен'), findsNWidgets(2));
  });

  testWidgets('playlist detail exposes reorder and preserves row actions',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: [
        _testTrack(id: 1, title: 'First Track'),
        _testTrack(id: 2, title: 'Second Track'),
      ],
    );
    _addFixtureTearDown(tester, fixture);
    final playlistId =
        await fixture.dependencies.repositories.playlists.createPlaylist(
      'Road Mix',
    );
    await fixture.dependencies.repositories.playlists.addTrackToPlaylist(
      playlistId,
      1,
    );
    await fixture.dependencies.repositories.playlists.addTrackToPlaylist(
      playlistId,
      2,
    );

    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-playlists')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road Mix'));
    await tester.pumpAndSettle();

    expect(find.text('К плейлистам'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-nav-playlists')), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.byTooltip('Изменить порядок трека'), findsNWidgets(2));
    expect(find.byTooltip('Добавить в очередь'), findsNWidgets(2));
    expect(find.byTooltip('Удалить из плейлиста'), findsNWidgets(2));
    expect(find.byTooltip('Воспроизвести'), findsAtLeastNWidgets(2));

    await tester.drag(
      find.byIcon(Icons.drag_handle_outlined).first,
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();
    final entries = await fixture.dependencies.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;
    final trackIds =
        entries.map((entry) => entry.trackId).toList(growable: false);
    expect(trackIds, [2, 1]);
    await tester.pumpAndSettle();

    final firstTrackTop = tester.getTopLeft(find.text('First Track').first).dy;
    final secondTrackTop =
        tester.getTopLeft(find.text('Second Track').first).dy;

    expect(secondTrackTop, lessThan(firstTrackTop));
  });

  testWidgets('All Tracks row starts library context with visible order',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: [
        _testTrack(id: 1, title: 'Beta Track'),
        _testTrack(id: 2, title: 'Alpha Track'),
        _testTrack(id: 3, title: 'Missing Track', isMissing: true),
      ],
    );
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta Track'));
    await tester.pumpAndSettle();

    expect(fixture.queue.state.activeSource, PlaybackSource.library);
    expect(fixture.queue.state.playbackContext.currentIndex, 1);
    expect(
        fixture.queue.state.playbackContext.tracks.map((track) => track.id), [
      2,
      1,
    ]);
    expect(find.text('Играет из: Все треки'), findsOneWidget);
    expect(find.byTooltip('Без повтора'), findsOneWidget);
    expect(find.byTooltip('Перемешать плейлист'), findsNothing);
  });

  testWidgets('library repeat control cycles without showing shuffle',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: [
        _testTrack(id: 1, title: 'First Track'),
        _testTrack(id: 2, title: 'Second Track'),
      ],
    );
    _addFixtureTearDown(tester, fixture);

    await fixture.queue.playLibraryTrack(
      track: _testTrack(id: 1, title: 'First Track'),
      visibleTracks: [
        _testTrack(id: 1, title: 'First Track'),
        _testTrack(id: 2, title: 'Second Track'),
      ],
    );
    await fixture.pump(tester);

    expect(find.byTooltip('Без повтора'), findsOneWidget);
    expect(find.byTooltip('Перемешать плейлист'), findsNothing);

    await tester.tap(find.byTooltip('Без повтора'));
    await tester.pumpAndSettle();

    expect(fixture.queue.state.repeatMode, PlaybackRepeatMode.playlist);
    expect(find.byTooltip('Повторять библиотеку'), findsOneWidget);
  });

  testWidgets('playlist bottom controls expose repeat and shuffle',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: [
        _testTrack(id: 1, title: 'First Track'),
        _testTrack(id: 2, title: 'Second Track'),
      ],
    );
    _addFixtureTearDown(tester, fixture);
    final playlistId =
        await fixture.dependencies.repositories.playlists.createPlaylist(
      'Road Mix',
    );
    await fixture.dependencies.repositories.playlists.addTrackToPlaylist(
      playlistId,
      1,
    );
    await fixture.dependencies.repositories.playlists.addTrackToPlaylist(
      playlistId,
      2,
    );
    final entries = await fixture.dependencies.repositories.playlists
        .watchPlaylistTracks(playlistId)
        .first;

    await fixture.queue.playPlaylist(
      playlistId: playlistId,
      playlistName: 'Road Mix',
      entries: entries,
      startTrackId: 1,
    );
    await fixture.pump(tester);

    expect(find.byTooltip('Без повтора'), findsOneWidget);
    expect(find.byTooltip('Перемешать плейлист'), findsOneWidget);

    await tester.tap(find.byTooltip('Перемешать плейлист'));
    await tester.pumpAndSettle();

    expect(fixture.queue.state.isPlaylistShuffleEnabled, isTrue);
  });

  testWidgets('Wave bottom controls hide repeat and shuffle', (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: [
        _testTrack(id: 1, title: 'Wave Track'),
        _testTrack(id: 2, title: 'Second Wave Track'),
      ],
    );
    _addFixtureTearDown(tester, fixture);

    await fixture.queue.playSmartNext();
    await fixture.pump(tester);

    expect(fixture.queue.state.activeSource, PlaybackSource.wave);
    expect(find.byTooltip('Без повтора'), findsNothing);
    expect(find.byTooltip('Перемешать плейлист'), findsNothing);
  });

  testWidgets('settings gear opens library folders and recommendation debug',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();

    expect(find.text('Папки библиотеки'), findsOneWidget);
    expect(find.text('Почему выбран трек'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-nav-settings')), findsOneWidget);
    expect(find.text('Трек не играет'), findsOneWidget);
  });

  testWidgets('recommendation debug shows Russian reasons and candidate labels',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(
      seedTracks: [
        _testTrack(id: 1, title: 'First Track', artist: 'First Artist'),
        _testTrack(id: 2, title: 'Second Track', artist: 'Second Artist'),
      ],
    );
    _addFixtureTearDown(tester, fixture);

    await fixture.queue.playSmartNext();
    await fixture.pump(tester);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Почему выбран трек'));
    await tester.pumpAndSettle();

    expect(find.textContaining('балл'), findsWidgets);
    expect(find.textContaining('кандидатов:'), findsOneWidget);
    expect(
      find.textContaining(
        'У трека есть метаданные, их можно учитывать при подборе.',
      ),
      findsOneWidget,
    );
    expect(find.text('Кандидаты'), findsOneWidget);
    expect(find.textContaining('вес'), findsWidgets);
    expect(find.textContaining('(выбран)'), findsOneWidget);
  });

  testWidgets('settings reset learning state can be cancelled', (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);
    final repositories = fixture.dependencies.repositories;
    await repositories.trackUserState.upsertState(
      TrackUserState(
        trackId: 1,
        isFavorite: true,
        rating: 5,
        updatedAt: DateTime(2026, 5),
      ),
    );
    await repositories.playbackEvents.addEvent(
      PlaybackEvent(
        trackId: 1,
        type: PlaybackEventType.started,
        occurredAt: DateTime(2026, 5),
      ),
    );

    await fixture.pump(tester);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить историю и рекомендации'));
    await tester.pumpAndSettle();

    expect(find.text('Сбросить историю и рекомендации?'), findsOneWidget);
    expect(
      find.textContaining('Треки, плейлисты, папки, обложки и аудиофайлы'),
      findsOneWidget,
    );

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    final state = await repositories.trackUserState.findByTrackId(1);
    expect(state?.isFavorite, isTrue);
    expect(await repositories.playbackEvents.recentEvents(), isNotEmpty);
  });

  testWidgets('settings reset learning state clears visible feedback',
      (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create(seedLibrary: true);
    _addFixtureTearDown(tester, fixture);
    final repositories = fixture.dependencies.repositories;
    await repositories.trackUserState.upsertState(
      TrackUserState(
        trackId: 1,
        isFavorite: true,
        rating: 5,
        updatedAt: DateTime(2026, 5),
      ),
    );
    await repositories.playbackEvents.addEvent(
      PlaybackEvent(
        trackId: 1,
        type: PlaybackEventType.started,
        occurredAt: DateTime(2026, 5),
      ),
    );

    await fixture.pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();

    expect(find.text('Test Track'), findsOneWidget);
    expect(find.byTooltip('Убрать лайк'), findsOneWidget);

    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить историю и рекомендации'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить').last);
    await tester.pumpAndSettle();

    expect(await repositories.trackUserState.findByTrackId(1), isNull);
    expect(await repositories.playbackEvents.recentEvents(), isEmpty);
    expect(find.text('История и рекомендации сброшены.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-music')));
    await tester.pumpAndSettle();

    expect(find.text('Test Track'), findsOneWidget);
    expect(find.byTooltip('Убрать лайк'), findsNothing);
    expect(find.byTooltip('Лайк'), findsAtLeastNWidgets(1));
  });

  testWidgets('wave mode dialog updates selected mode', (tester) async {
    await _setLargeSurface(tester);
    final fixture = await _HomeScreenFixture.create();
    _addFixtureTearDown(tester, fixture);

    await fixture.pump(tester);
    await tester.tap(find.text('Настроить'));
    await tester.pumpAndSettle();

    expect(find.text('Текущий режим: Сбалансированный'), findsOneWidget);

    await tester.tap(find.text('Открытия'));
    await tester.pumpAndSettle();

    expect(fixture.queue.state.selectedWaveMode, WaveMode.discovery);
    expect(find.text('Текущий режим: Открытия'), findsOneWidget);
  });
}

Future<void> _setLargeSurface(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _setNarrowSurface(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(600, 760);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met before timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void _addFixtureTearDown(
  WidgetTester tester,
  _HomeScreenFixture fixture,
) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
    await tester.pump();
  });
}

final class _HomeScreenFixture {
  _HomeScreenFixture._({
    required this.dependencies,
    required this.queue,
    required this.player,
  });

  final AppDependencies dependencies;
  final PlaybackQueueService queue;
  final _FakePlayerService player;

  static Future<_HomeScreenFixture> create({
    bool seedLibrary = false,
    List<Track>? seedTracks,
    CustomArtworkService? customArtwork,
    DirectoryPickerService? directoryPicker,
    LibraryFolderScanner? scanFolder,
    ControlledLibraryFolderScanner? controlledScanFolder,
  }) async {
    final initialTracks =
        seedTracks ?? (seedLibrary ? [_testTrack()] : const <Track>[]);
    final database = AppDatabase(NativeDatabase.memory());
    final repositories = _FakeAppRepositories(
      initialTracks,
      initialTracks.isEmpty ? const [] : [_testFolder()],
    );
    final recommendationService = RecommendationService(
      tracks: repositories.tracks,
      trackUserState: repositories.trackUserState,
      playbackEvents: repositories.playbackEvents,
    );
    final libraryScanner = LibraryScannerService(
      libraryRepository: repositories.libraryFolders,
      trackRepository: repositories.tracks,
      metadataReader: const FallbackMetadataReaderService(),
    );
    final player = _FakePlayerService();
    final queue = PlaybackQueueService(
      playerService: player,
      tracks: repositories.tracks,
      trackUserState: repositories.trackUserState,
      playbackEvents: repositories.playbackEvents,
      recommendationService: recommendationService,
    );
    final library = LibraryController(
      directoryPicker: directoryPicker ?? const _NoopDirectoryPickerService(),
      scanFolder: scanFolder ?? libraryScanner.scanFolder,
      controlledScanFolder: controlledScanFolder,
      management: LibraryManagementService(
        libraryRepository: repositories.libraryFolders,
        scanFolder: scanFolder ?? libraryScanner.scanFolder,
        controlledScanFolder: controlledScanFolder,
      ),
    );
    late final AppDependencies dependencies;
    dependencies = AppDependencies(
      database: database,
      repositories: repositories,
      recommendationService: recommendationService,
      libraryScanner: libraryScanner,
      libraryController: library,
      directoryPicker: directoryPicker ?? const _NoopDirectoryPickerService(),
      customArtwork: customArtwork ?? _FakeCustomArtworkService(),
      playerService: player,
      playbackQueue: queue,
      smtcService: const NoopSmtcService(),
      yandexConnectionFactory: () => YandexConnectionController(
          repository: DriftRepositories(database).remoteLibrary,
          sessions: DriftRepositories(database).yandexSessions,
          credentials: MemoryYandexCredentials()),
      yandexUpdateFactory: () => YandexLibraryUpdateController(
          connection: dependencies.yandexConnection,
          library: repositories.libraryFolders,
          plans: DriftRepositories(database).librarySync,
          settings: repositories.settings,
          checkerFactory: () => throw StateError('Unused in player UI fixture'),
          runnerFactory: () => throw StateError('Unused in player UI fixture'),
          supported: false),
    );
    return _HomeScreenFixture._(
      dependencies: dependencies,
      queue: queue,
      player: player,
    );
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: const CleverMusicPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    final repositories = dependencies.repositories;
    if (repositories is _FakeAppRepositories) {
      await repositories.dispose();
    }
    await dependencies.dispose();
  }
}

final class _FakeAppRepositories implements AppRepositories {
  _FakeAppRepositories(List<Track> initialTracks, List<LibraryFolder> folders)
      : libraryFolders = _FakeLibraryRepository(folders),
        tracks = _FakeTrackRepository(initialTracks),
        playlists = _FakePlaylistRepository(initialTracks),
        playbackEvents = _FakePlaybackEventRepository(),
        trackUserState = _FakeTrackUserStateRepository(),
        settings = _FakeSettingsRepository() {
    (playbackEvents as _FakePlaybackEventRepository).userState = trackUserState;
  }

  @override
  final LibraryRepository libraryFolders;

  @override
  final TrackRepository tracks;

  @override
  ExternalTrackRepository get externalTracks => throw UnsupportedError(
      'External identities are not used by this UI fixture.');

  @override
  RemoteLibraryRepository get remoteLibrary =>
      throw UnsupportedError('Unused in UI tests');

  @override
  DownloadJobRepository get downloadJobs =>
      throw UnsupportedError('Unused in UI tests');

  @override
  LibrarySyncRepository get librarySync =>
      throw UnsupportedError('Unused in UI tests');

  @override
  DownloadImportRepository get downloadImports =>
      throw UnsupportedError('Unused in UI tests');
  @override
  PublicationRetentionRepository get publicationRetention =>
      throw UnsupportedError('Unused in UI tests');
  @override
  YandexSessionRepository get yandexSessions =>
      throw UnsupportedError('Unused in UI tests');

  @override
  DownloadedAssetRepository get downloadedAssets => throw UnsupportedError(
      'Downloaded assets are not used by this UI fixture.');

  @override
  final PlaybackEventRepository playbackEvents;

  @override
  final PlaylistRepository playlists;

  @override
  final TrackUserStateRepository trackUserState;

  @override
  final SettingsRepository settings;

  @override
  Future<void> resetLearningState() async {
    (playbackEvents as _FakePlaybackEventRepository).clear();
    (trackUserState as _FakeTrackUserStateRepository).clear();
  }

  Future<void> dispose() async {
    await (tracks as _FakeTrackRepository).dispose();
    await (trackUserState as _FakeTrackUserStateRepository).dispose();
  }
}

final class _FakeLibraryRepository implements LibraryRepository {
  _FakeLibraryRepository(List<LibraryFolder> folders) : _folders = [...folders];

  final List<LibraryFolder> _folders;

  @override
  Future<int> upsertFolder(LibraryFolder folder) async {
    final existingIndex = _folders.indexWhere((item) => item.id == folder.id);
    if (existingIndex >= 0) {
      _folders[existingIndex] = folder;
      return folder.id!;
    }

    final id = folder.id ?? _folders.length + 1;
    _folders.add(folder.copyWith(id: id));
    return id;
  }

  @override
  Future<LibraryFolder?> findFolderByPath(String path) async {
    for (final folder in _folders) {
      if (folder.path == path) {
        return folder;
      }
    }
    return null;
  }

  @override
  Future<List<LibraryFolder>> listFolders({bool includeDisabled = true}) async {
    return _folders
        .where((folder) => includeDisabled || folder.isEnabled)
        .toList(growable: false);
  }

  @override
  Stream<List<LibraryFolder>> watchFolders({bool includeDisabled = true}) {
    return Stream.value(
      _folders
          .where((folder) => includeDisabled || folder.isEnabled)
          .toList(growable: false),
    );
  }

  @override
  Future<void> setFolderEnabled(
    int id, {
    required bool isEnabled,
    required DateTime updatedAt,
  }) async {
    final index = _folders.indexWhere((folder) => folder.id == id);
    if (index < 0) {
      return;
    }
    _folders[index] = _folders[index].copyWith(
      isEnabled: isEnabled,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> deleteFolder(int id) async {
    _folders.removeWhere((folder) => folder.id == id);
  }
}

final class _FakeTrackRepository
    implements TrackRepository, TrackLibraryCountRepository {
  _FakeTrackRepository(List<Track> tracks) : _tracks = [...tracks];

  final List<Track> _tracks;
  final StreamController<void> _controller = StreamController<void>.broadcast();
  int watchAllTracksCalls = 0;
  int activeTrackStreamCreations = 0;
  int indexedTrackStreamCreations = 0;
  int indexedCountStreamCreations = 0;

  @override
  Stream<int> watchIndexedTrackCount() async* {
    indexedCountStreamCreations++;
    yield _tracks.length;
    await for (final _ in _controller.stream) {
      yield _tracks.length;
    }
  }

  @override
  Future<int> upsertTrack(Track track) async {
    final existingIndex = _tracks.indexWhere(
      (item) =>
          (track.id != null && item.id == track.id) ||
          item.filePath == track.filePath,
    );
    if (existingIndex >= 0) {
      final id = _tracks[existingIndex].id ?? track.id ?? existingIndex + 1;
      _tracks[existingIndex] = track.copyWith(id: id);
      _emit();
      return id;
    }

    final id = track.id ?? _tracks.length + 1;
    _tracks.add(track.copyWith(id: id));
    _emit();
    return id;
  }

  @override
  Future<void> updateTrackMetadata(TrackMetadataUpdate metadata) async {}

  @override
  Future<void> updateCustomArtwork({
    required int trackId,
    required String path,
    required String hash,
    required String? mimeType,
    required DateTime updatedAt,
  }) async {
    final index = _tracks.indexWhere((track) => track.id == trackId);
    if (index < 0) {
      throw StateError('Track $trackId was not found.');
    }
    _tracks[index] = _tracks[index].copyWith(
      customArtworkPath: path,
      customArtworkHash: hash,
      customArtworkMimeType: mimeType,
      updatedAt: updatedAt,
    );
    _emit();
  }

  @override
  Future<void> clearCustomArtwork({
    required int trackId,
    required DateTime updatedAt,
  }) async {
    final index = _tracks.indexWhere((track) => track.id == trackId);
    if (index < 0) {
      throw StateError('Track $trackId was not found.');
    }
    _tracks[index] = _tracks[index].copyWith(
      customArtworkPath: null,
      customArtworkHash: null,
      customArtworkMimeType: null,
      updatedAt: updatedAt,
    );
    _emit();
  }

  @override
  Future<Track?> findById(int id) async {
    for (final track in _tracks) {
      if (track.id == id) {
        return track;
      }
    }
    return null;
  }

  @override
  Future<Track?> findByStableId(String stableId) async {
    for (final track in _tracks) {
      if (track.stableId == stableId) {
        return track;
      }
    }
    return null;
  }

  @override
  Future<Track?> findByPath(String filePath) async {
    for (final track in _tracks) {
      if (track.filePath == filePath) {
        return track;
      }
    }
    return null;
  }

  @override
  Future<List<Track>> listTracks({
    int limit = 100,
    int offset = 0,
    bool includeDisabledFolders = false,
  }) async {
    return _visibleTracks(includeMissing: false)
        .skip(offset)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<Track>> listTracksByLibraryFolder(
    int libraryFolderId, {
    bool includeMissing = true,
  }) async {
    return _tracks
        .where((track) =>
            track.libraryFolderId == libraryFolderId &&
            (includeMissing || !track.isMissing))
        .toList(growable: false);
  }

  @override
  Stream<List<Track>> watchAllTracks({
    bool includeMissing = false,
    bool includeDisabledFolders = false,
  }) async* {
    watchAllTracksCalls += 1;
    if (includeMissing && !includeDisabledFolders) {
      activeTrackStreamCreations += 1;
    }
    if (includeMissing && includeDisabledFolders) {
      indexedTrackStreamCreations += 1;
    }
    yield _visibleTracks(includeMissing: includeMissing);
    await for (final _ in _controller.stream) {
      yield _visibleTracks(includeMissing: includeMissing);
    }
  }

  @override
  Stream<List<Track>> watchTracks({
    int limit = 100,
    bool includeDisabledFolders = false,
  }) {
    return Stream.value(
      _visibleTracks(includeMissing: false).take(limit).toList(growable: false),
    );
  }

  @override
  Future<void> deleteTracksByLibraryFolder(int libraryFolderId) async {
    _tracks.removeWhere((track) => track.libraryFolderId == libraryFolderId);
    _emit();
  }

  @override
  Future<void> deleteTrack(int id) async {
    _tracks.removeWhere((track) => track.id == id);
    _emit();
  }

  List<Track> _visibleTracks({required bool includeMissing}) {
    return _tracks
        .where((track) => includeMissing || !track.isMissing)
        .toList(growable: false);
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}

final class _FakePlaylistRepository implements PlaylistRepository {
  _FakePlaylistRepository(List<Track> tracks) : _tracks = tracks;

  final List<Track> _tracks;
  final List<Playlist> _playlists = [];
  final List<PlaylistEntry> _entries = [];
  final StreamController<List<PlaylistWithCount>> _controller =
      StreamController<List<PlaylistWithCount>>.broadcast();
  final Map<int, StreamController<List<PlaylistEntry>>> _entryControllers = {};

  @override
  Stream<List<PlaylistWithCount>> watchPlaylists() async* {
    yield _snapshot();
    yield* _controller.stream;
  }

  @override
  Future<int> createPlaylist(String name, {String? description}) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Playlist name cannot be empty.');
    }
    final now = DateTime(2026, 5);
    final id = _playlists.length + 1;
    _playlists.add(
      Playlist(
        id: id,
        name: trimmedName,
        description: description,
        createdAt: now,
        updatedAt: now,
      ),
    );
    _emit();
    return id;
  }

  @override
  Future<void> renamePlaylist(int id, String name) async {
    final index = _playlists.indexWhere((playlist) => playlist.id == id);
    if (index < 0) {
      return;
    }
    _playlists[index] = _playlists[index].copyWith(
      name: name.trim(),
      updatedAt: DateTime(2026, 5, 1, 0, 1),
    );
    _emit();
  }

  @override
  Future<void> deletePlaylist(int id) async {
    _playlists.removeWhere((playlist) => playlist.id == id);
    _entries.removeWhere((entry) => entry.playlistId == id);
    _emit();
  }

  @override
  Stream<List<PlaylistEntry>> watchPlaylistTracks(int playlistId) async* {
    yield _playlistEntriesSnapshot(playlistId);
    final controller = _entryControllers.putIfAbsent(
      playlistId,
      () => StreamController<List<PlaylistEntry>>.broadcast(),
    );
    yield* controller.stream;
  }

  @override
  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    final alreadyAdded = _entries.any(
      (entry) => entry.playlistId == playlistId && entry.trackId == trackId,
    );
    if (alreadyAdded) {
      return;
    }
    final track = _tracks.firstWhere((track) => track.id == trackId);
    _entries.add(
      PlaylistEntry(
        playlistId: playlistId,
        trackId: trackId,
        position:
            _entries.where((entry) => entry.playlistId == playlistId).length,
        addedAt: DateTime(2026, 5),
        track: track,
        unavailableReason: track.isMissing ? 'Отсутствует' : null,
      ),
    );
    _emit();
    _emitPlaylistTracks(playlistId);
  }

  @override
  Future<void> reorderPlaylistTracks({
    required int playlistId,
    required List<int> trackIds,
  }) async {
    final currentEntries = _playlistEntriesSnapshot(playlistId);
    final currentTrackIds = {for (final entry in currentEntries) entry.trackId};
    final requestedTrackIds = trackIds.toSet();
    if (requestedTrackIds.length != trackIds.length ||
        requestedTrackIds.length != currentTrackIds.length ||
        !requestedTrackIds.containsAll(currentTrackIds)) {
      throw ArgumentError.value(
        trackIds,
        'trackIds',
        'Reorder input must contain each target playlist track exactly once.',
      );
    }

    for (var index = 0; index < trackIds.length; index++) {
      final entryIndex = _entries.indexWhere(
        (entry) =>
            entry.playlistId == playlistId && entry.trackId == trackIds[index],
      );
      final entry = _entries[entryIndex];
      _entries[entryIndex] = PlaylistEntry(
        playlistId: entry.playlistId,
        trackId: entry.trackId,
        position: index,
        addedAt: entry.addedAt,
        track: entry.track,
        unavailableReason: entry.unavailableReason,
      );
    }
    _emit();
    _emitPlaylistTracks(playlistId);
  }

  @override
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    _entries.removeWhere(
      (entry) => entry.playlistId == playlistId && entry.trackId == trackId,
    );
    _emit();
    _emitPlaylistTracks(playlistId);
  }

  List<PlaylistWithCount> _snapshot() {
    return [
      for (final playlist in _playlists)
        PlaylistWithCount(
          playlist: playlist,
          trackCount:
              _entries.where((entry) => entry.playlistId == playlist.id).length,
        ),
    ];
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_snapshot());
    }
  }

  List<PlaylistEntry> _playlistEntriesSnapshot(int playlistId) {
    return _entries
        .where((entry) => entry.playlistId == playlistId)
        .toList(growable: false)
      ..sort((left, right) {
        final positionOrder = left.position.compareTo(right.position);
        if (positionOrder != 0) {
          return positionOrder;
        }
        final addedOrder = left.addedAt.compareTo(right.addedAt);
        if (addedOrder != 0) {
          return addedOrder;
        }
        return left.trackId.compareTo(right.trackId);
      });
  }

  void _emitPlaylistTracks(int playlistId) {
    final controller = _entryControllers[playlistId];
    if (controller != null && !controller.isClosed) {
      controller.add(_playlistEntriesSnapshot(playlistId));
    }
  }
}

final class _FakeTrackUserStateRepository implements TrackUserStateRepository {
  final Map<int, TrackUserState> _states = {};
  final StreamController<void> _controller = StreamController<void>.broadcast();
  int watchTrackStatesByTrackIdsCalls = 0;

  @override
  Future<TrackUserState> toggleFeedback(int trackId, TrackFeedback feedback,
          {required DateTime updatedAt}) =>
      toggleTestFeedback(this, trackId, feedback, updatedAt);

  @override
  Future<void> upsertState(TrackUserState state) async {
    _states[state.trackId] = state;
    _emit();
  }

  @override
  Future<TrackUserState?> findByTrackId(int trackId) async => _states[trackId];

  @override
  Future<Map<int, TrackUserState>> findByTrackIds(
    Iterable<int> trackIds,
  ) async {
    return {
      for (final id in trackIds)
        if (_states[id] != null) id: _states[id]!,
    };
  }

  @override
  Stream<TrackUserState?> watchTrackState(int trackId) async* {
    yield _states[trackId];
    await for (final _ in _controller.stream) {
      yield _states[trackId];
    }
  }

  @override
  Stream<Map<int, TrackUserState>> watchTrackStatesByTrackIds(
    Iterable<int> trackIds,
  ) async* {
    watchTrackStatesByTrackIdsCalls += 1;
    final ids = trackIds.toSet().toList(growable: false);
    Map<int, TrackUserState> snapshot() {
      return {
        for (final id in ids)
          if (_states[id] != null) id: _states[id]!,
      };
    }

    yield snapshot();
    await for (final _ in _controller.stream) {
      yield snapshot();
    }
  }

  @override
  Future<void> deleteState(int trackId) async {
    _states.remove(trackId);
    _emit();
  }

  void clear() {
    _states.clear();
    _emit();
  }

  Future<void> dispose() {
    return _controller.close();
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }
}

final class _FakePlaybackEventRepository implements PlaybackEventRepository {
  final List<PlaybackEvent> _events = [];

  TrackUserStateRepository? userState;

  @override
  Future<int> recordEvent(PlaybackEvent event) =>
      recordTestEvent(this, userState, event);

  @override
  Future<int> addEvent(PlaybackEvent event) async {
    _events.add(event);
    return _events.length;
  }

  @override
  Future<List<PlaybackEvent>> recentEvents({int limit = 100}) async {
    return _events.reversed.take(limit).toList(growable: false);
  }

  @override
  Future<List<PlaybackEvent>> recentForTrack(
    int trackId, {
    int limit = 50,
  }) async {
    return _events
        .where((event) => event.trackId == trackId)
        .toList(growable: false)
        .reversed
        .take(limit)
        .toList(growable: false);
  }

  void clear() {
    _events.clear();
  }
}

final class _FakeSettingsRepository implements SettingsRepository {
  final Map<String, AppSetting> _settings = {};

  @override
  Future<AppSetting?> read(String key) async => _settings[key];

  @override
  Future<String?> readString(String key) async => _settings[key]?.value;

  @override
  Future<void> writeString(String key, String value) async {
    _settings[key] = AppSetting(
      key: key,
      value: value,
      updatedAt: DateTime(2026, 5),
    );
  }

  @override
  Future<void> delete(String key) async {
    _settings.remove(key);
  }
}

LibraryFolder _testFolder() {
  final now = DateTime(2026, 5);
  return LibraryFolder(
    id: 1,
    path: '/music',
    displayName: 'Music',
    createdAt: now,
    updatedAt: now,
  );
}

Track _testTrack({
  int id = 1,
  String title = 'Test Track',
  String artist = 'Test Artist',
  bool isMissing = false,
  String? customArtworkPath,
  String? customArtworkHash,
  String? customArtworkMimeType,
}) {
  final now = DateTime(2026, 5);
  final fileName = title.toLowerCase().replaceAll(' ', '-');
  return Track(
    id: id,
    libraryFolderId: 1,
    filePath: '/music/$fileName.mp3',
    title: title,
    artist: artist,
    album: 'Test Album',
    codec: 'mp3',
    duration: const Duration(minutes: 3, seconds: 15),
    isMissing: isMissing,
    customArtworkPath: customArtworkPath,
    customArtworkHash: customArtworkHash,
    customArtworkMimeType: customArtworkMimeType,
    addedAt: now,
    updatedAt: now,
  );
}

List<Track> _largeLibraryTracks(int count) {
  return List.generate(count, (index) {
    final title = 'Track ${index.toString().padLeft(3, '0')}';
    return _testTrack(
      id: index + 1,
      title: title,
      artist: 'Artist ${index % 17}',
    );
  }, growable: false);
}

final class _FakeCustomArtworkService implements CustomArtworkService {
  _FakeCustomArtworkService({this.artwork, this.error});

  final CachedArtwork? artwork;
  final Object? error;
  var pickCount = 0;

  @override
  Future<CachedArtwork?> pickCustomArtwork() async {
    pickCount++;
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return artwork;
  }
}

final class _NoopDirectoryPickerService implements DirectoryPickerService {
  const _NoopDirectoryPickerService();

  @override
  Future<String?> pickMusicFolder() async => null;
}

final class _FakePlayerService implements PlayerService {
  final StreamController<PlayerState> _controller =
      StreamController<PlayerState>.broadcast();
  PlayerState _state = const PlayerState.idle();
  final List<double> setVolumeCalls = [];
  int toggleMuteCalls = 0;

  @override
  PlayerState get state => _state;

  @override
  Track? get currentTrack => _state.currentTrack;

  @override
  bool get isPlaying => _state.isPlaying;

  @override
  Duration get position => _state.position;

  @override
  Duration? get duration => _state.duration;

  @override
  double get volume => _state.volume;

  @override
  Stream<PlayerState> get stateStream => _controller.stream;

  @override
  Future<void> playTrack(Track track) async {
    _emit(
      PlayerState(
        currentTrack: track,
        isPlaying: true,
        duration: track.duration,
        status: PlayerPlaybackStatus.playing,
      ),
    );
  }

  @override
  Future<void> play() async {
    final track = _state.currentTrack;
    if (track == null) {
      return;
    }
    _emit(
      _state.copyWith(
        isPlaying: true,
        status: PlayerPlaybackStatus.playing,
      ),
    );
  }

  @override
  Future<void> pause() async {
    _emit(
      _state.copyWith(
        isPlaying: false,
        status: PlayerPlaybackStatus.paused,
      ),
    );
  }

  @override
  Future<void> stop() async {
    _emit(const PlayerState.idle().copyWith(
      status: PlayerPlaybackStatus.stopped,
    ));
  }

  @override
  Future<void> seek(Duration position) async {
    _emit(_state.copyWith(position: position));
  }

  @override
  Future<void> setVolume(double volume) async {
    setVolumeCalls.add(volume);
    _emit(_state.copyWith(volume: volume));
  }

  @override
  Future<void> increaseVolume() async {
    await setVolume((_state.volume + 0.05).clamp(0.0, 1.0).toDouble());
  }

  @override
  Future<void> decreaseVolume() async {
    await setVolume((_state.volume - 0.05).clamp(0.0, 1.0).toDouble());
  }

  @override
  Future<void> toggleMute() async {
    toggleMuteCalls += 1;
    await setVolume(_state.volume > 0 ? 0 : 1);
  }

  void emitPositionTick(Duration position) {
    _emit(_state.copyWith(position: position));
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void _emit(PlayerState state) {
    _state = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }
}

class _GatedDirectoryPicker implements DirectoryPickerService {
  final result = Completer<String?>();
  int calls = 0;
  @override
  Future<String?> pickMusicFolder() {
    calls++;
    return result.future;
  }
}

LibraryScanResult _controlledScanResult() => const LibraryScanResult(
    folderPath: '/music',
    scannedFiles: 3,
    addedTracks: 0,
    updatedTracks: 3,
    missingTracks: 0,
    errors: []);
