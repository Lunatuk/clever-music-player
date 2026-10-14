import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../domain/models/models.dart';
import '../../player/player_progress.dart';
import '../../player/player_service.dart';
import '../../player/player_state.dart';
import '../../queue/playback_queue_service.dart';
import '../../queue/queue_state.dart';
import '../track_artwork.dart';
import '../track_display_helpers.dart';
import '../widgets/track_feedback_button.dart';
import 'player_volume_control.dart';

const double _cardRadius = 24;
const double _bottomPlayerBarBackgroundOpacity = 0.48;
const double _bottomPlayerBarBlurSigma = 18;

final class BottomPlayerBar extends StatefulWidget {
  const BottomPlayerBar({
    super.key,
    required this.playerService,
    required this.queueService,
    required this.tracksStream,
    required this.onOpenSettings,
  });

  final PlayerService playerService;
  final PlaybackQueueService queueService;
  final Stream<List<Track>> tracksStream;
  final VoidCallback onOpenSettings;

  @override
  State<BottomPlayerBar> createState() => _BottomPlayerBarState();
}

final class _BottomPlayerBarState extends State<BottomPlayerBar> {
  Duration? _dragPosition;
  Object? _dragTrackKey;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Track>>(
      stream: widget.tracksStream,
      initialData: const [],
      builder: (context, trackSnapshot) {
        final libraryTracks = trackSnapshot.data ?? const <Track>[];

        return StreamBuilder<QueueState>(
          stream: widget.queueService.stateStream,
          initialData: widget.queueService.state,
          builder: (context, queueSnapshot) {
            final queueState = queueSnapshot.data ?? QueueState();

            return StreamBuilder<PlayerState>(
              stream: widget.playerService.stateStream,
              initialData: widget.playerService.state,
              builder: (context, playerSnapshot) {
                final playerState =
                    playerSnapshot.data ?? const PlayerState.idle();
                final track = _latestTrackFor(
                  playerState.currentTrack ?? queueState.currentTrack,
                  libraryTracks,
                );

                return _buildBarContent(
                  context,
                  playerState: playerState,
                  queueState: queueState,
                  track: track,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBarContent(
    BuildContext context, {
    required PlayerState playerState,
    required QueueState queueState,
    required Track? track,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final duration = playerState.duration;
    final trackKey = _trackKey(track);
    final activeDragPosition = _dragTrackKey == trackKey ? _dragPosition : null;
    final progress = PlayerProgress(
      position: playerState.position,
      duration: duration,
      dragPosition: activeDragPosition,
    );
    final canSeek = track != null &&
        progress.canSeek &&
        playerState.status != PlayerPlaybackStatus.loading;
    final canGoNext = !queueState.isChoosingNext && queueState.canAdvance;
    final canGoPrevious = !queueState.isChoosingNext && track != null;
    final isBusy = playerState.status == PlayerPlaybackStatus.loading ||
        queueState.isChoosingNext;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(_cardRadius),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: _bottomPlayerBarBlurSigma,
          sigmaY: _bottomPlayerBarBlurSigma,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer.withValues(
              alpha: _bottomPlayerBarBackgroundOpacity,
            ),
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.22),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useWideLayout = constraints.maxWidth >= 720;
                  final sideWidth = (constraints.maxWidth * 0.30)
                      .clamp(220.0, 344.0)
                      .toDouble();
                  final summary = _NowPlayingSummary(
                    track: track,
                    queueCount: queueState.manualQueue.length,
                    playbackContext: queueState.activeSource ==
                                PlaybackSource.playlist ||
                            queueState.activeSource == PlaybackSource.library
                        ? queueState.playbackContext
                        : null,
                  );
                  final progressRow = _BottomProgressRow(
                    progress: progress,
                    canSeek: canSeek,
                    onChanged: (value) {
                      setState(() {
                        _dragTrackKey = trackKey;
                        _dragPosition = PlayerProgress.fromSliderValue(
                          value,
                          duration!,
                        );
                      });
                    },
                    onChangeEnd: (value) {
                      final target = PlayerProgress.fromSliderValue(
                        value,
                        duration!,
                      );
                      unawaited(widget.playerService.seek(target));
                      setState(() {
                        _dragPosition = null;
                        _dragTrackKey = null;
                      });
                    },
                  );
                  final controls = _BottomPlaybackButtons(
                    isPlaying: playerState.isPlaying,
                    canGoPrevious: canGoPrevious,
                    canGoNext: canGoNext,
                    repeatMode: queueState.repeatMode,
                    canUseRepeat: queueState.canUseRepeat,
                    canUseShuffle: queueState.canUseShuffle,
                    isShuffleEnabled: queueState.isPlaylistShuffleEnabled,
                    activeSource: queueState.activeSource,
                    onPlayPause: track == null
                        ? null
                        : () {
                            unawaited(
                              playerState.isPlaying
                                  ? widget.playerService.pause()
                                  : widget.playerService.play(),
                            );
                          },
                    onPrevious: canGoPrevious
                        ? () {
                            unawaited(widget.queueService.previous());
                          }
                        : null,
                    onNext: canGoNext
                        ? () {
                            unawaited(widget.queueService.next());
                          }
                        : null,
                    onRepeat: queueState.canUseRepeat
                        ? () {
                            widget.queueService.cycleRepeatMode();
                          }
                        : null,
                    onShuffle: queueState.canUseShuffle
                        ? widget.queueService.togglePlaylistShuffle
                        : null,
                  );
                  final rightActions = _BottomPlayerActions(
                    hasTrack: track != null,
                    isLiked: queueState.isCurrentTrackLiked,
                    isDisliked: queueState.isCurrentTrackDisliked,
                    volume: playerState.volume,
                    showVolumeSlider: sideWidth >= 344,
                    onToggleMute: () {
                      unawaited(widget.playerService.toggleMute());
                    },
                    onVolumeChanged: (value) {
                      unawaited(widget.playerService.setVolume(value));
                    },
                    onLike: () {
                      unawaited(widget.queueService.likeCurrentTrack());
                    },
                    onDislike: () {
                      unawaited(widget.queueService.dislikeCurrentTrack());
                    },
                    onOpenSettings: widget.onOpenSettings,
                  );

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (useWideLayout)
                        Row(
                          children: [
                            SizedBox(width: sideWidth, child: summary),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  controls,
                                  const SizedBox(height: 6),
                                  progressRow,
                                ],
                              ),
                            ),
                            const SizedBox(width: 18),
                            SizedBox(
                              width: sideWidth,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: rightActions,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        summary,
                        const SizedBox(height: 8),
                        Center(child: controls),
                        const SizedBox(height: 8),
                        progressRow,
                        const SizedBox(height: 6),
                        Center(child: rightActions),
                      ],
                      if (isBusy) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                      ],
                      if (playerState.hasError ||
                          queueState.lastError != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            playerState.errorMessage ??
                                queueState.lastError ??
                                'Воспроизведение не удалось.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colorScheme.error),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _NowPlayingSummary extends StatelessWidget {
  const _NowPlayingSummary({
    required this.track,
    required this.queueCount,
    required this.playbackContext,
  });

  final Track? track;
  final int queueCount;
  final PlaybackContext? playbackContext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: TrackArtwork(
            track: track,
            size: 54,
            borderRadius: 12,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track?.displayTitle ?? 'Трек не играет',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall,
              ),
              Text(
                _summarySubtitle(track, playbackContext),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (queueCount > 0) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: 'В ручной очереди: ${trackCountLabel(queueCount)}',
            child: Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.queue_music_outlined, size: 16),
              label: Text('$queueCount'),
            ),
          ),
        ],
      ],
    );
  }
}

final class _BottomProgressRow extends StatelessWidget {
  const _BottomProgressRow({
    required this.progress,
    required this.canSeek,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final PlayerProgress progress;
  final bool canSeek;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(
            PlayerProgress.formatDuration(progress.displayPosition),
            maxLines: 1,
            style: textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: Slider(
            value: progress.valueMilliseconds,
            min: 0,
            max: progress.maxMilliseconds,
            onChanged: canSeek ? onChanged : null,
            onChangeEnd: canSeek ? onChangeEnd : null,
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(
            PlayerProgress.formatDuration(progress.displayDuration),
            maxLines: 1,
            textAlign: TextAlign.end,
            style: textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

final class _BottomPlaybackButtons extends StatelessWidget {
  const _BottomPlaybackButtons({
    required this.isPlaying,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.repeatMode,
    required this.canUseRepeat,
    required this.canUseShuffle,
    required this.isShuffleEnabled,
    required this.activeSource,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onRepeat,
    required this.onShuffle,
  });

  final bool isPlaying;
  final bool canGoPrevious;
  final bool canGoNext;
  final PlaybackRepeatMode repeatMode;
  final bool canUseRepeat;
  final bool canUseShuffle;
  final bool isShuffleEnabled;
  final PlaybackSource activeSource;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onRepeat;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final repeatButton = repeatMode == PlaybackRepeatMode.none
        ? IconButton.outlined(
            tooltip: _repeatTooltip(repeatMode, activeSource),
            onPressed: canUseRepeat ? onRepeat : null,
            icon: Icon(_repeatIcon(repeatMode)),
          )
        : IconButton.filledTonal(
            tooltip: _repeatTooltip(repeatMode, activeSource),
            onPressed: canUseRepeat ? onRepeat : null,
            icon: Icon(_repeatIcon(repeatMode)),
          );
    final shuffleButton = isShuffleEnabled
        ? IconButton.filledTonal(
            tooltip: 'Перемешать плейлист',
            onPressed: canUseShuffle ? onShuffle : null,
            icon: const Icon(Icons.shuffle_outlined),
          )
        : IconButton.outlined(
            tooltip: 'Перемешать плейлист',
            onPressed: canUseShuffle ? onShuffle : null,
            icon: const Icon(Icons.shuffle_outlined),
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          tooltip: 'Предыдущий',
          onPressed: canGoPrevious ? onPrevious : null,
          icon: const Icon(Icons.skip_previous_outlined),
        ),
        const SizedBox(width: 4),
        IconButton.filled(
          tooltip: isPlaying ? 'Пауза' : 'Воспроизвести',
          onPressed: onPlayPause,
          style: IconButton.styleFrom(
            fixedSize: const Size(48, 48),
          ),
          icon: Icon(
            isPlaying ? Icons.pause_outlined : Icons.play_arrow_outlined,
          ),
        ),
        const SizedBox(width: 4),
        IconButton.outlined(
          tooltip: 'Следующий / пропустить',
          onPressed: canGoNext ? onNext : null,
          icon: const Icon(Icons.skip_next_outlined),
        ),
        if (canUseRepeat) ...[
          const SizedBox(width: 4),
          repeatButton,
        ],
        if (canUseShuffle) ...[
          const SizedBox(width: 4),
          shuffleButton,
        ],
      ],
    );
  }
}

final class _BottomPlayerActions extends StatelessWidget {
  const _BottomPlayerActions({
    required this.hasTrack,
    required this.isLiked,
    required this.isDisliked,
    required this.volume,
    required this.showVolumeSlider,
    required this.onToggleMute,
    required this.onVolumeChanged,
    required this.onLike,
    required this.onDislike,
    required this.onOpenSettings,
  });

  final bool hasTrack;
  final bool isLiked;
  final bool isDisliked;
  final double volume;
  final bool showVolumeSlider;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onLike;
  final VoidCallback onDislike;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerVolumeControl(
          volume: volume,
          showSlider: showVolumeSlider,
          onToggleMute: onToggleMute,
          onChanged: onVolumeChanged,
        ),
        const SizedBox(width: 8),
        TrackFeedbackIconButton(
          isActive: isLiked,
          onPressed: hasTrack ? onLike : null,
          activeIcon: Icons.thumb_up,
          inactiveIcon: Icons.thumb_up_outlined,
          activeTooltip: 'Убрать лайк',
          inactiveTooltip: 'Лайк',
        ),
        const SizedBox(width: 4),
        TrackFeedbackIconButton(
          isActive: isDisliked,
          onPressed: hasTrack ? onDislike : null,
          activeIcon: Icons.thumb_down,
          inactiveIcon: Icons.thumb_down_outlined,
          activeTooltip: 'Убрать дизлайк',
          inactiveTooltip: 'Дизлайк',
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Настройки',
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }
}

String _summarySubtitle(Track? track, PlaybackContext? playbackContext) {
  if (playbackContext != null && playbackContext.isPlaylist) {
    final name = playbackContext.playlistName?.trim();
    if (name != null && name.isNotEmpty) {
      return 'Играет из: $name';
    }
  }
  if (playbackContext != null && playbackContext.isLibrary) {
    return 'Играет из: Все треки';
  }
  return artistLabel(track);
}

String _repeatTooltip(PlaybackRepeatMode mode, PlaybackSource source) {
  final listName = source == PlaybackSource.library ? 'библиотеку' : 'плейлист';
  return switch (mode) {
    PlaybackRepeatMode.none => 'Без повтора',
    PlaybackRepeatMode.playlist => 'Повторять $listName',
    PlaybackRepeatMode.track => 'Повторять трек',
  };
}

IconData _repeatIcon(PlaybackRepeatMode mode) {
  return switch (mode) {
    PlaybackRepeatMode.none => Icons.repeat,
    PlaybackRepeatMode.playlist => Icons.repeat,
    PlaybackRepeatMode.track => Icons.repeat_one,
  };
}

Object? _trackKey(Track? track) {
  return track?.id ?? track?.filePath;
}

Track? _latestTrackFor(Track? currentTrack, List<Track> libraryTracks) {
  if (currentTrack == null) {
    return null;
  }

  for (final track in libraryTracks) {
    if (isSameTrack(track, currentTrack)) {
      return track;
    }
  }
  return currentTrack;
}
