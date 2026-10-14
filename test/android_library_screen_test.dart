import 'package:clever_music_player/src/android/android_import_controller.dart';
import 'package:clever_music_player/src/android/android_preview_app.dart';
import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/track_repository.dart';
import 'package:clever_music_player/src/library/artwork_cache_service.dart';
import 'package:clever_music_player/src/player/just_audio_player_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_audio_engine.dart';

void main() {
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
}

final class _Fixture {
  _Fixture() {
    importer = AndroidImportController(
        documents: const _Documents(),
        imports: DriftRepositories(database).tracks as TrackImportRepository,
        artworkCache: const NoopArtworkCacheService());
    player = JustAudioPlayerService(
        audioEngine: engine,
        isWindows: false,
        playbackEvents: DriftRepositories(database).playbackEvents);
  }
  final database = AppDatabase(NativeDatabase.memory());
  final engine = TestAudioEngine();
  late final AndroidImportController importer;
  late final JustAudioPlayerService player;
  int selections = 0, nextCalls = 0, stopCalls = 0;
  final track = Track.fromSource(
      source: ContentUriAudioSource('content://music.test/song'),
      title: 'Тестовый трек',
      artist: 'Исполнитель',
      duration: const Duration(minutes: 1),
      addedAt: DateTime(2026),
      updatedAt: DateTime(2026));
  Widget app({double textScale = 1}) => MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: AndroidLibraryScreen(
            importer: importer,
            tracks: Stream.value([track]),
            player: player,
            playTrack: (track, tracks) async {
              selections++;
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

final class _Documents implements AudioDocuments {
  const _Documents();
  @override
  Future<AudioDocumentSelection?> pickAudio() async => null;
  @override
  Future<AudioDocumentMetadata> readAudio(ContentUriAudioSource source) async =>
      const AudioDocumentMetadata();
}
