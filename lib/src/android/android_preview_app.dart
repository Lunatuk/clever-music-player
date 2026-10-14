import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import '../core/async_lifecycle.dart';
import '../diagnostics/diagnostics_service.dart';
import '../domain/models/track.dart';
import '../domain/repositories/track_repository.dart';
import '../library/artwork_cache_service.dart';
import '../player/player_service.dart';
import '../player/player_state.dart';
import 'android_import_controller.dart';
import 'audio_documents.dart';
import 'android_media_controls.dart';

/// A small Android prototype using the same database, player and queue.
/// The Android application ID isolates its sandbox from the future release.
final class AndroidPreviewApp extends StatefulWidget {
  const AndroidPreviewApp({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<AndroidPreviewApp> createState() => _AndroidPreviewAppState();
}

final class _AndroidPreviewAppState extends State<AndroidPreviewApp> {
  late final AndroidImportController _importer;
  @override
  void initState() {
    super.initState();
    _importer = AndroidImportController(
        documents: const AndroidAudioDocuments(),
        imports:
            widget.dependencies.repositories.tracks as TrackImportRepository,
        artworkCache: AppSupportArtworkCacheService());
  }

  @override
  void dispose() {
    unawaited(finishCleanup([
      _importer.close,
      () async => _importer.dispose(),
      widget.dependencies.dispose,
    ]).catchError((Object error, StackTrace stack) {
      widget.dependencies.diagnostics
          .record(DiagnosticEvent.appCleanupFailed, error: error);
    }));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Clever Music Preview',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xffb7c9ad),
                brightness: Brightness.dark),
            scaffoldBackgroundColor: const Color(0xff141615)),
        home: AndroidLibraryScreen(
            importer: _importer,
            tracks: widget.dependencies.repositories.tracks.watchAllTracks(),
            player: widget.dependencies.playerService,
            playTrack: (track, visible) => widget.dependencies.playbackQueue
                .playLibraryTrack(track: track, visibleTracks: visible),
            previous: widget.dependencies.playbackQueue.previous,
            next: widget.dependencies.playbackQueue.next,
            stop:
                (widget.dependencies.smtcService as AndroidMediaControlsService)
                    .stop),
      );
}

final class AndroidLibraryScreen extends StatefulWidget {
  const AndroidLibraryScreen(
      {super.key,
      required this.importer,
      required this.tracks,
      required this.player,
      required this.playTrack,
      required this.previous,
      required this.next,
      this.stop});
  final AndroidImportController importer;
  final Stream<List<Track>> tracks;
  final PlayerService player;
  final Future<void> Function(Track, List<Track>) playTrack;
  final Future<void> Function() previous, next;
  final Future<void> Function()? stop;
  @override
  State<AndroidLibraryScreen> createState() => _AndroidLibraryScreenState();
}

final class _AndroidLibraryScreenState extends State<AndroidLibraryScreen> {
  Future<void> _command(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Не удалось выполнить действие. Попробуйте ещё раз.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Моя музыка'), actions: [
          IconButton(
              tooltip: 'О версии',
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                        title: const Text('Clever Music Preview'),
                        content: const SingleChildScrollView(
                            child: Text(
                                'Первая версия для проверки музыки на телефоне. '
                                'Можно выбирать отдельные файлы или папку с музыкой и вложенными каталогами. '
                                'Импорт можно остановить; уже добавленные треки сохранятся.\n\n'
                                'Музыка продолжает играть при блокировке экрана. '
                                'Управление доступно в уведомлении и на экране блокировки.\n\n'
                                'После прерывания или отключения наушников музыка ставится на паузу. '
                                'Нажми Play, чтобы продолжить.')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Понятно'))
                        ],
                      ))),
          ListenableBuilder(
              listenable: widget.importer,
              builder: (context, _) =>
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (widget.importer.supportsFolders)
                      IconButton(
                          tooltip: 'Добавить папку',
                          onPressed: widget.importer.busy
                              ? null
                              : () => _command(widget.importer.importFolder),
                          icon: const Icon(Icons.create_new_folder_outlined)),
                    IconButton(
                        tooltip: 'Добавить музыку',
                        onPressed: widget.importer.busy
                            ? null
                            : () => _command(widget.importer.importSelection),
                        icon: const Icon(Icons.add_rounded)),
                  ])),
        ]),
        body: SafeArea(
            top: false,
            child: Column(children: [
              ListenableBuilder(
                  listenable: widget.importer,
                  builder: (context, _) {
                    final importer = widget.importer;
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      if (importer.busy)
                        LinearProgressIndicator(
                            value: importer.folderImport || importer.total == 0
                                ? null
                                : importer.processed / importer.total),
                      if (importer.busy)
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                children: [
                                  Text(
                                      importer.cancelling
                                          ? 'Остановка импорта…'
                                          : importer.folderImport
                                              ? 'Найдено: ${importer.total} · Обработано: ${importer.processed}'
                                              : 'Обработано: ${importer.processed} / ${importer.total}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                  TextButton(
                                      onPressed: importer.canCancel
                                          ? () => _command(importer.cancel)
                                          : null,
                                      child: const Text('Остановить импорт')),
                                ])),
                      if (importer.message != null)
                        Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                            child: Text(importer.message!,
                                style: Theme.of(context).textTheme.bodySmall)),
                    ]);
                  }),
              Expanded(
                  child: StreamBuilder<List<Track>>(
                      stream: widget.tracks,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(
                              child: Text('Не удалось открыть библиотеку.'));
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final tracks = snapshot.data!;
                        if (tracks.isEmpty) {
                          return Center(
                              child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(28),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.library_music_outlined,
                                            size: 64),
                                        const SizedBox(height: 20),
                                        Text('Музыка с твоего телефона',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge,
                                            textAlign: TextAlign.center),
                                        const SizedBox(height: 12),
                                        const Text(
                                            'Добавь папку с музыкой или выбери отдельные файлы через +. Доступ сохранится после перезапуска.',
                                            textAlign: TextAlign.center),
                                      ])));
                        }
                        return ListView.builder(
                            itemCount: tracks.length,
                            itemBuilder: (context, index) {
                              final track = tracks[index];
                              return ListTile(
                                  leading: _Cover(track: track),
                                  title: Text(track.displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                      track.artist ?? 'Неизвестный исполнитель',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  onTap: () => _command(
                                      () => widget.playTrack(track, tracks)));
                            });
                      })),
              StreamBuilder<PlayerState>(
                  stream: widget.player.stateStream,
                  initialData: widget.player.state,
                  builder: (context, snapshot) {
                    final state = snapshot.data ?? widget.player.state;
                    final track = state.currentTrack;
                    if (track == null) return const SizedBox.shrink();
                    final total =
                        (state.duration ?? track.duration ?? Duration.zero)
                            .inMilliseconds;
                    final position = state.position.inMilliseconds
                        .clamp(0, total > 0 ? total : 0);
                    return Material(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(children: [
                                    _Cover(track: track, size: 40),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Text(track.displayTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis)),
                                    if (state.status ==
                                        PlayerPlaybackStatus.loading)
                                      const Padding(
                                          padding: EdgeInsets.all(8),
                                          child: SizedBox.square(
                                              dimension: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))),
                                  ]),
                                  if (state.hasError)
                                    const Text(
                                        'Не удалось открыть трек. Выберите файл заново через +.',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                  Slider(
                                      value: position.toDouble(),
                                      max: total > 0 ? total.toDouble() : 1,
                                      onChanged: total <= 0
                                          ? null
                                          : (value) => _command(() =>
                                              widget.player.seek(Duration(
                                                  milliseconds:
                                                      value.round())))),
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                            tooltip: 'Предыдущий трек',
                                            onPressed: () =>
                                                _command(widget.previous),
                                            icon: const Icon(
                                                Icons.skip_previous_rounded)),
                                        IconButton.filled(
                                            tooltip: state.isPlaying
                                                ? 'Пауза'
                                                : 'Воспроизвести',
                                            onPressed: () => _command(
                                                state.isPlaying
                                                    ? widget.player.pause
                                                    : widget.player.play),
                                            icon: Icon(state.isPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded)),
                                        IconButton(
                                            tooltip: 'Следующий трек',
                                            onPressed: () =>
                                                _command(widget.next),
                                            icon: const Icon(
                                                Icons.skip_next_rounded)),
                                        if (widget.stop != null)
                                          IconButton(
                                              tooltip: 'Остановить',
                                              onPressed: () =>
                                                  _command(widget.stop!),
                                              icon: const Icon(
                                                  Icons.stop_rounded)),
                                      ]),
                                ])));
                  }),
            ])),
      );
}

final class _Cover extends StatelessWidget {
  const _Cover({required this.track, this.size = 52});
  final Track track;
  final double size;
  @override
  Widget build(BuildContext context) {
    final path = track.customArtworkPath ?? track.artworkPath;
    Widget fallback() => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.music_note_rounded)));
    return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
            dimension: size,
            child: path == null
                ? fallback()
                : Image.file(File(path),
                    width: size,
                    height: size,
                    cacheWidth: 156,
                    cacheHeight: 156,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => fallback())));
  }
}
