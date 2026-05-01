import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/dependency_scope.dart';
import '../../domain/models/models.dart';
import '../../library/library_scanner_service.dart';
import '../../player/player_progress.dart';
import '../../player/player_service.dart';
import '../../player/player_state.dart';
import '../../queue/playback_queue_service.dart';
import '../../queue/queue_state.dart';

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
              _PlayerControls(
                playerService: dependencies.playerService,
                queueService: dependencies.playbackQueue,
              ),
              const SizedBox(height: 24),
              Text('Tracks', style: textTheme.titleLarge),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<PlayerState>(
                  stream: dependencies.playerService.stateStream,
                  initialData: dependencies.playerService.state,
                  builder: (context, playerSnapshot) {
                    final currentTrack = playerSnapshot.data?.currentTrack;

                    return StreamBuilder<List<Track>>(
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

                        final trackIds =
                            tracks.map((track) => track.id).whereType<int>();
                        return StreamBuilder<Map<int, TrackUserState>>(
                          stream: dependencies.repositories.trackUserState
                              .watchTrackStatesByTrackIds(trackIds),
                          initialData: const {},
                          builder: (context, stateSnapshot) {
                            final userStates = stateSnapshot.data ??
                                const <int, TrackUserState>{};
                            return ListView.separated(
                              itemCount: tracks.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final track = tracks[index];
                                return _TrackListTile(
                                  track: track,
                                  userState: track.id == null
                                      ? null
                                      : userStates[track.id],
                                  isCurrent: _isSameTrack(track, currentTrack),
                                  onTap: () {
                                    unawaited(
                                      dependencies.playbackQueue
                                          .playTrackManually(track),
                                    );
                                  },
                                  onLike: () {
                                    unawaited(
                                      dependencies.playbackQueue
                                          .toggleLike(track),
                                    );
                                  },
                                  onDislike: () {
                                    unawaited(
                                      dependencies.playbackQueue
                                          .toggleDislike(track),
                                    );
                                  },
                                );
                              },
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

  bool _isSameTrack(Track track, Track? other) {
    if (other == null) {
      return false;
    }
    if (track.id != null && other.id != null) {
      return track.id == other.id;
    }
    return track.filePath == other.filePath;
  }
}

final class _PlayerControls extends StatefulWidget {
  const _PlayerControls({
    required this.playerService,
    required this.queueService,
  });

  final PlayerService playerService;
  final PlaybackQueueService queueService;

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

    return StreamBuilder<QueueState>(
      stream: widget.queueService.stateStream,
      initialData: widget.queueService.state,
      builder: (context, queueSnapshot) {
        final queueState = queueSnapshot.data ?? QueueState();

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
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          tooltip: 'Next',
                          onPressed: queueState.isChoosingNext || track == null
                              ? null
                              : () {
                                  unawaited(widget.queueService.next());
                                },
                          icon: const Icon(Icons.skip_next_outlined),
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
                                    final target =
                                        PlayerProgress.fromSliderValue(
                                      value,
                                      duration!,
                                    );
                                    unawaited(
                                      widget.playerService.seek(target),
                                    );
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
                    if (state.status == PlayerPlaybackStatus.loading ||
                        queueState.isChoosingNext)
                      const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    _WaveControls(
                      queueState: queueState,
                      onSmartNext: queueState.isChoosingNext
                          ? null
                          : () {
                              unawaited(widget.queueService.playSmartNext());
                            },
                      onModeChanged: widget.queueService.setWaveMode,
                      onWaveToggle: queueState.isWaveEnabled
                          ? widget.queueService.disableWave
                          : widget.queueService.enableWave,
                    ),
                    const SizedBox(height: 8),
                    _FeedbackControls(
                      hasTrack: track != null,
                      isLiked: queueState.isCurrentTrackLiked,
                      isDisliked: queueState.isCurrentTrackDisliked,
                      onLike: () {
                        unawaited(widget.queueService.likeCurrentTrack());
                      },
                      onDislike: () {
                        unawaited(widget.queueService.dislikeCurrentTrack());
                      },
                    ),
                    if (state.hasError || queueState.lastError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        state.errorMessage ??
                            queueState.lastError ??
                            'Playback failed.',
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ],
                    _RecommendationDebugPanel(
                      result: queueState.lastRecommendationResult,
                      candidates: queueState.recommendationCandidates,
                      repeatGuardMessage: queueState.repeatGuardMessage,
                    ),
                  ],
                ),
              ),
            );
          },
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

final class _WaveControls extends StatelessWidget {
  const _WaveControls({
    required this.queueState,
    required this.onSmartNext,
    required this.onModeChanged,
    required this.onWaveToggle,
  });

  final QueueState queueState;
  final VoidCallback? onSmartNext;
  final ValueChanged<WaveMode> onModeChanged;
  final VoidCallback onWaveToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: onSmartNext,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(queueState.isWaveEnabled ? 'Smart Next' : 'Start Wave'),
        ),
        if (queueState.isWaveEnabled)
          OutlinedButton.icon(
            onPressed: onWaveToggle,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop Wave'),
          ),
        DropdownButton<WaveMode>(
          value: queueState.selectedWaveMode,
          onChanged: queueState.isChoosingNext
              ? null
              : (mode) {
                  if (mode != null) {
                    onModeChanged(mode);
                  }
                },
          items: [
            for (final mode in WaveMode.values)
              DropdownMenuItem(
                value: mode,
                child: Text(mode.label),
              ),
          ],
        ),
      ],
    );
  }
}

final class _FeedbackControls extends StatelessWidget {
  const _FeedbackControls({
    required this.hasTrack,
    required this.isLiked,
    required this.isDisliked,
    required this.onLike,
    required this.onDislike,
  });

  final bool hasTrack;
  final bool isLiked;
  final bool isDisliked;
  final VoidCallback onLike;
  final VoidCallback onDislike;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FeedbackButton(
          isActive: isLiked,
          onPressed: hasTrack ? onLike : null,
          icon: Icons.thumb_up_outlined,
          label: 'Like',
        ),
        _FeedbackButton(
          isActive: isDisliked,
          onPressed: hasTrack ? onDislike : null,
          icon: Icons.thumb_down_outlined,
          label: 'Dislike',
        ),
      ],
    );
  }
}

final class _FeedbackButton extends StatelessWidget {
  const _FeedbackButton({
    required this.isActive,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final bool isActive;
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (isActive) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

final class _RecommendationDebugPanel extends StatelessWidget {
  const _RecommendationDebugPanel({
    required this.result,
    required this.candidates,
    required this.repeatGuardMessage,
  });

  final RecommendationResult? result;
  final List<RecommendationResult> candidates;
  final String? repeatGuardMessage;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    if (result == null) {
      return const SizedBox.shrink();
    }

    final textTheme = Theme.of(context).textTheme;
    final candidateWeights = selectionWeightsForRecommendations(candidates);
    final weightedCandidates = [
      for (var index = 0; index < candidates.length; index++)
        _WeightedRecommendationCandidate(
          result: candidates[index],
          weight: candidateWeights[index],
        ),
    ];
    final topCandidates = _debugCandidates(weightedCandidates, result);
    final meaningfulReasons = result.reasons
        .where((reason) => reason.code != 'technical_base_score')
        .take(5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text('Recommendation', style: textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          '${result.selectedTrack.displayTitle} - '
          'score ${result.finalScore.toStringAsFixed(1)} '
          'from ${result.candidatesConsidered} candidates',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        for (final reason in meaningfulReasons)
          Text(
            '- ${reason.message} (${_formatWeight(reason.weight)})',
            style: textTheme.bodySmall,
          ),
        if (repeatGuardMessage != null) ...[
          const SizedBox(height: 8),
          Text(repeatGuardMessage!, style: textTheme.bodySmall),
        ],
        if (topCandidates.length > 1) ...[
          const SizedBox(height: 8),
          Text('Top candidates', style: textTheme.labelLarge),
          const SizedBox(height: 4),
          for (final candidate in topCandidates)
            Text(
              '${_isSelected(candidate.result, result) ? '(selected) ' : ''}'
              '${candidate.result.track.displayTitle}: '
              'score ${candidate.result.score.toStringAsFixed(1)}, '
              'weight ${candidate.weight.toStringAsFixed(1)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall,
            ),
        ],
      ],
    );
  }

  static String _formatWeight(double weight) {
    final prefix = weight >= 0 ? '+' : '';
    return '$prefix${weight.toStringAsFixed(1)}';
  }

  static List<_WeightedRecommendationCandidate> _debugCandidates(
    List<_WeightedRecommendationCandidate> candidates,
    RecommendationResult selected,
  ) {
    final topCandidates = candidates.take(5).toList(growable: true);
    if (topCandidates.any(
      (candidate) => _isSelected(candidate.result, selected),
    )) {
      return topCandidates;
    }

    for (final candidate in candidates.skip(5)) {
      if (!_isSelected(candidate.result, selected)) {
        continue;
      }
      if (topCandidates.length >= 5) {
        topCandidates.removeLast();
      }
      topCandidates.add(candidate);
      break;
    }

    return topCandidates;
  }

  static bool _isSelected(
    RecommendationResult candidate,
    RecommendationResult selected,
  ) {
    final candidateTrack = candidate.track;
    final selectedTrack = selected.track;
    if (candidateTrack.id != null && selectedTrack.id != null) {
      return candidateTrack.id == selectedTrack.id;
    }
    return candidateTrack.filePath == selectedTrack.filePath;
  }
}

final class _WeightedRecommendationCandidate {
  const _WeightedRecommendationCandidate({
    required this.result,
    required this.weight,
  });

  final RecommendationResult result;
  final double weight;
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
    required this.userState,
    required this.isCurrent,
    required this.onTap,
    required this.onLike,
    required this.onDislike,
  });

  final Track track;
  final TrackUserState? userState;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onDislike;

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
      selected: isCurrent,
      leading: Icon(
        isCurrent ? Icons.graphic_eq_outlined : Icons.music_note_outlined,
      ),
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TrackFeedbackIconButton(
            isActive: (userState?.isFavorite ?? false) &&
                !(userState?.isHidden ?? false),
            onPressed: track.id == null ? null : onLike,
            activeIcon: Icons.thumb_up,
            inactiveIcon: Icons.thumb_up_outlined,
            activeTooltip: 'Unlike',
            inactiveTooltip: 'Like',
          ),
          const SizedBox(width: 4),
          _TrackFeedbackIconButton(
            isActive: userState?.isHidden ?? false,
            onPressed: track.id == null ? null : onDislike,
            activeIcon: Icons.thumb_down,
            inactiveIcon: Icons.thumb_down_outlined,
            activeTooltip: 'Undislike',
            inactiveTooltip: 'Dislike',
          ),
          const SizedBox(width: 4),
          Icon(
            isCurrent ? Icons.play_circle_outline : Icons.play_arrow_outlined,
          ),
        ],
      ),
    );
  }
}

final class _TrackFeedbackIconButton extends StatelessWidget {
  const _TrackFeedbackIconButton({
    required this.isActive,
    required this.onPressed,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.activeTooltip,
    required this.inactiveTooltip,
  });

  final bool isActive;
  final VoidCallback? onPressed;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String activeTooltip;
  final String inactiveTooltip;

  @override
  Widget build(BuildContext context) {
    if (isActive) {
      return IconButton.filledTonal(
        tooltip: activeTooltip,
        onPressed: onPressed,
        icon: Icon(activeIcon),
      );
    }

    return IconButton.outlined(
      tooltip: inactiveTooltip,
      onPressed: onPressed,
      icon: Icon(inactiveIcon),
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
