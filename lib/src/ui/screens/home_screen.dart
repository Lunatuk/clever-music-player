import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/dependency_scope.dart';
import '../../domain/models/models.dart';
import '../../library/library_scanner_service.dart';
import '../../player/player_progress.dart';
import '../../player/player_service.dart';
import '../../player/player_state.dart';

final class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final class _HomeScreenState extends State<HomeScreen> {
  LibraryScanResult? _lastScanResult;
  Object? _lastError;
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    final dependencies = AppDependenciesScope.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clever Music Player'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Local-first music library',
                style: textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a folder, scan local audio files, and persist them in '
                'the on-device SQLite library.',
                style: textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _isScanning
                        ? null
                        : () => _addMusicFolder(dependencies),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Add music folder'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _isScanning ? null : () => _rescanLibrary(dependencies),
                    icon: const Icon(Icons.refresh_outlined),
                    label: const Text('Rescan library'),
                  ),
                  if (_isScanning)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _ScanStatus(
                result: _lastScanResult,
                error: _lastError,
                isScanning: _isScanning,
              ),
              const SizedBox(height: 24),
              _PlayerControls(playerService: dependencies.playerService),
              const SizedBox(height: 24),
              Text('Tracks', style: textTheme.titleLarge),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<List<Track>>(
                  stream: dependencies.repositories.tracks.watchAllTracks(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _EmptyState(
                        message: 'Could not load tracks: ${snapshot.error}',
                      );
                    }

                    final tracks = snapshot.data ?? const <Track>[];
                    if (tracks.isEmpty) {
                      return const _EmptyState(
                        message: 'No tracks indexed yet.',
                      );
                    }

                    return ListView.separated(
                      itemCount: tracks.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        return _TrackListTile(
                          track: track,
                          onTap: () {
                            unawaited(
                              dependencies.playerService.playTrack(track),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addMusicFolder(AppDependencies dependencies) async {
    final folderPath = await dependencies.directoryPicker.pickMusicFolder();
    if (folderPath == null || folderPath.isEmpty) {
      return;
    }

    await _scanFolders(dependencies, [folderPath]);
  }

  Future<void> _rescanLibrary(AppDependencies dependencies) async {
    final folders = await dependencies.repositories.libraryFolders.listFolders(
      includeDisabled: false,
    );
    if (folders.isEmpty) {
      setState(() {
        _lastScanResult = null;
        _lastError = 'No music folders have been added yet.';
      });
      return;
    }

    await _scanFolders(
      dependencies,
      folders.map((folder) => folder.path).toList(growable: false),
    );
  }

  Future<void> _scanFolders(
    AppDependencies dependencies,
    List<String> folderPaths,
  ) async {
    setState(() {
      _isScanning = true;
      _lastError = null;
    });

    try {
      final results = <LibraryScanResult>[];
      for (final folderPath in folderPaths) {
        results.add(await dependencies.libraryScanner.scanFolder(folderPath));
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _lastScanResult = LibraryScanResult.combine(results);
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }
}

final class _PlayerControls extends StatefulWidget {
  const _PlayerControls({required this.playerService});

  final PlayerService playerService;

  @override
  State<_PlayerControls> createState() => _PlayerControlsState();
}

final class _PlayerControlsState extends State<_PlayerControls> {
  Duration? _dragPosition;
  Object? _dragTrackKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return StreamBuilder<PlayerState>(
      stream: widget.playerService.stateStream,
      initialData: widget.playerService.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const PlayerState.idle();
        final track = state.currentTrack;
        final duration = state.duration;
        final trackKey = _trackKey(track);
        final activeDragPosition =
            _dragTrackKey == trackKey ? _dragPosition : null;
        final progress = PlayerProgress(
          position: state.position,
          duration: duration,
          dragPosition: activeDragPosition,
        );
        final canSeek = track != null &&
            progress.canSeek &&
            state.status != PlayerPlaybackStatus.loading;

        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      state.isPlaying
                          ? Icons.graphic_eq_outlined
                          : Icons.music_note_outlined,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track?.displayTitle ?? 'No track playing',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium,
                          ),
                          Text(
                            _artistLabel(track),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      tooltip: state.isPlaying ? 'Pause' : 'Play',
                      onPressed: track == null
                          ? null
                          : () {
                              unawaited(
                                state.isPlaying
                                    ? widget.playerService.pause()
                                    : widget.playerService.play(),
                              );
                            },
                      icon: Icon(
                        state.isPlaying
                            ? Icons.pause_outlined
                            : Icons.play_arrow_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Stop',
                      onPressed: track == null
                          ? null
                          : () {
                              unawaited(widget.playerService.stop());
                            },
                      icon: const Icon(Icons.stop_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(PlayerProgress.formatDuration(
                      progress.displayPosition,
                    )),
                    Expanded(
                      child: Slider(
                        value: progress.valueMilliseconds,
                        min: 0,
                        max: progress.maxMilliseconds,
                        onChanged: canSeek
                            ? (value) {
                                setState(() {
                                  _dragTrackKey = trackKey;
                                  _dragPosition =
                                      PlayerProgress.fromSliderValue(
                                    value,
                                    duration!,
                                  );
                                });
                              }
                            : null,
                        onChangeEnd: canSeek
                            ? (value) {
                                final target = PlayerProgress.fromSliderValue(
                                  value,
                                  duration!,
                                );
                                unawaited(widget.playerService.seek(target));
                                setState(() {
                                  _dragPosition = null;
                                  _dragTrackKey = null;
                                });
                              }
                            : null,
                      ),
                    ),
                    Text(PlayerProgress.formatDuration(
                      progress.displayDuration,
                    )),
                  ],
                ),
                if (state.status == PlayerPlaybackStatus.loading)
                  const LinearProgressIndicator(),
                if (state.hasError) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.errorMessage!,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static String _artistLabel(Track? track) {
    final artist = track?.artist?.trim();
    if (artist != null && artist.isNotEmpty) {
      return artist;
    }
    return track == null
        ? 'Select a local track to start playback'
        : 'Unknown artist';
  }

  static Object? _trackKey(Track? track) {
    return track?.id ?? track?.filePath;
  }
}

final class _ScanStatus extends StatelessWidget {
  const _ScanStatus({
    required this.result,
    required this.error,
    required this.isScanning,
  });

  final LibraryScanResult? result;
  final Object? error;
  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (isScanning) {
      return const Text('Scanning local folders...');
    }

    if (error != null) {
      return Text(
        error.toString(),
        style: TextStyle(color: colorScheme.error),
      );
    }

    final result = this.result;
    if (result == null) {
      return const Text('No scan has run yet.');
    }

    final errorSuffix = result.hasErrors
        ? ' ${result.errors.length} file errors were recorded.'
        : '';
    return Text('${result.summary}$errorSuffix');
  }
}

final class _TrackListTile extends StatelessWidget {
  const _TrackListTile({
    required this.track,
    required this.onTap,
  });

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      track.artist,
      track.album,
      track.codec?.toUpperCase(),
    ].where((value) => value != null && value.trim().isNotEmpty).join(' - ');
    final subtitle = metadata.isEmpty ? track.filePath : metadata;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(
        track.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.play_arrow_outlined),
    );
  }
}

final class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
      ),
    );
  }
}
