import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/dependency_scope.dart';
import '../../domain/models/models.dart';
import '../../library/library_management_service.dart';
import '../../library/library_scanner_service.dart';
import '../../library/library_track_list.dart';
import '../../player/player_progress.dart';
import '../../player/player_service.dart';
import '../../player/player_state.dart';
import '../../queue/playback_queue_service.dart';
import '../../queue/queue_state.dart';
import '../track_metadata_subtitle.dart';
import '../track_metadata_edit_dialog.dart';

final class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _searchController;
  LibraryScanResult? _lastScanResult;
  Object? _lastError;
  String _searchQuery = '';
  LibraryTrackSortOption _sortOption = LibraryTrackSortOption.title;
  bool _showMissingTracks = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = AppDependenciesScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clever Music Player'),
      ),
      body: SafeArea(
        child: StreamBuilder<PlayerState>(
          stream: dependencies.playerService.stateStream,
          initialData: dependencies.playerService.state,
          builder: (context, playerSnapshot) {
            final playerState = playerSnapshot.data ?? const PlayerState.idle();

            return StreamBuilder<List<Track>>(
              stream: dependencies.repositories.tracks.watchAllTracks(
                includeMissing: true,
              ),
              builder: (context, trackSnapshot) {
                final activeTracks = trackSnapshot.data ?? const <Track>[];
                final trackIds =
                    activeTracks.map((track) => track.id).whereType<int>();

                return StreamBuilder<Map<int, TrackUserState>>(
                  stream: dependencies.repositories.trackUserState
                      .watchTrackStatesByTrackIds(trackIds),
                  initialData: const {},
                  builder: (context, stateSnapshot) {
                    final userStates =
                        stateSnapshot.data ?? const <int, TrackUserState>{};

                    return StreamBuilder<List<Track>>(
                      stream: dependencies.repositories.tracks.watchAllTracks(
                        includeMissing: true,
                        includeDisabledFolders: true,
                      ),
                      initialData: const [],
                      builder: (context, indexedSnapshot) {
                        return StreamBuilder<List<LibraryFolder>>(
                          stream: dependencies.repositories.libraryFolders
                              .watchFolders(),
                          initialData: const [],
                          builder: (context, folderSnapshot) {
                            return _buildHomeContent(
                              context,
                              dependencies,
                              playerState: playerState,
                              activeTracks: activeTracks,
                              totalIndexedTracks:
                                  indexedSnapshot.data?.length ?? 0,
                              userStates: userStates,
                              folders: folderSnapshot.data ?? const [],
                              trackLoadError:
                                  trackSnapshot.error ?? indexedSnapshot.error,
                              folderLoadError: folderSnapshot.error,
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
    );
  }

  Widget _buildHomeContent(
    BuildContext context,
    AppDependencies dependencies, {
    required PlayerState playerState,
    required List<Track> activeTracks,
    required int totalIndexedTracks,
    required Map<int, TrackUserState> userStates,
    required List<LibraryFolder> folders,
    required Object? trackLoadError,
    required Object? folderLoadError,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final visibleTracks = buildVisibleLibraryTracks(
      tracks: activeTracks,
      searchQuery: _searchQuery,
      showMissingTracks: _showMissingTracks,
      sortOption: _sortOption,
      userStates: userStates,
    );
    final missingCount = activeTracks.where((track) => track.isMissing).length;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                Text(
                  'Local-first music library',
                  style: textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a folder, scan local audio files, and persist them '
                  'in the on-device SQLite library.',
                  style: textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                _LibraryActions(
                  isScanning: _isScanning,
                  onAddFolder: () => _addMusicFolder(dependencies),
                  onRescanLibrary: () => _rescanLibrary(dependencies),
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
                  libraryTracks: activeTracks,
                ),
                const SizedBox(height: 24),
                _LibraryFoldersPanel(
                  folders: folders,
                  error: folderLoadError,
                  isScanning: _isScanning,
                  onRescanFolder: (folder) {
                    unawaited(_rescanFolder(dependencies, folder));
                  },
                  onToggleEnabled: (folder) {
                    unawaited(_toggleFolderEnabled(dependencies, folder));
                  },
                  onRemoveFolder: (folder) {
                    unawaited(_confirmAndRemoveFolder(dependencies, folder));
                  },
                ),
                const SizedBox(height: 24),
                Text('Tracks', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                _TrackListControls(
                  searchController: _searchController,
                  searchQuery: _searchQuery,
                  sortOption: _sortOption,
                  showMissingTracks: _showMissingTracks,
                  onSearchChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  onClearSearch: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  onSortChanged: (option) {
                    setState(() {
                      _sortOption = option;
                    });
                  },
                  onShowMissingChanged: (value) {
                    setState(() {
                      _showMissingTracks = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                _LibraryStats(
                  visibleTracks: visibleTracks.length,
                  totalIndexedTracks: totalIndexedTracks,
                  missingTracks: missingCount,
                  folderCount: folders.length,
                ),
                if (trackLoadError != null) ...[
                  const SizedBox(height: 24),
                  _InlineMessage(
                    message: 'Could not load tracks: $trackLoadError',
                    isError: true,
                  ),
                ] else if (activeTracks.isEmpty) ...[
                  const SizedBox(height: 24),
                  const _InlineMessage(
                      message: 'No active tracks indexed yet.'),
                ] else if (visibleTracks.isEmpty) ...[
                  const SizedBox(height: 24),
                  const _InlineMessage(
                      message: 'No tracks match these filters.'),
                ],
              ],
            ),
          ),
        ),
        if (trackLoadError == null && visibleTracks.isNotEmpty)
          _TrackListSliver(
            tracks: visibleTracks,
            userStates: userStates,
            currentTrack: playerState.currentTrack,
            onPlayTrack: (track) {
              unawaited(dependencies.playbackQueue.playTrackManually(track));
            },
            onLikeTrack: (track) {
              unawaited(dependencies.playbackQueue.toggleLike(track));
            },
            onDislikeTrack: (track) {
              unawaited(dependencies.playbackQueue.toggleDislike(track));
            },
            onAddToQueue: (track) {
              unawaited(dependencies.playbackQueue.addToQueue(track));
            },
            onEditTrack: (track) {
              unawaited(_editTrackMetadata(dependencies, track));
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Future<void> _addMusicFolder(AppDependencies dependencies) async {
    final folderPath = await dependencies.directoryPicker.pickMusicFolder();
    if (folderPath == null || folderPath.isEmpty) {
      return;
    }

    await _runScan(
      () => dependencies.libraryScanner.scanFolder(folderPath),
    );
  }

  Future<void> _rescanLibrary(AppDependencies dependencies) async {
    await _runScan(
      () => _libraryManagement(dependencies).rescanEnabledFolders(),
    );
  }

  Future<void> _rescanFolder(
    AppDependencies dependencies,
    LibraryFolder folder,
  ) async {
    await _runScan(
      () => _libraryManagement(dependencies).rescanFolder(folder),
    );
  }

  Future<void> _toggleFolderEnabled(
    AppDependencies dependencies,
    LibraryFolder folder,
  ) async {
    try {
      await _libraryManagement(dependencies).setFolderEnabled(
        folder,
        isEnabled: !folder.isEnabled,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = error;
      });
    }
  }

  Future<void> _confirmAndRemoveFolder(
    AppDependencies dependencies,
    LibraryFolder folder,
  ) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove folder from library?'),
          content: const Text(
            'This will remove the folder and its imported tracks from the app '
            'database only.\n\n'
            'Your audio files on disk will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove from library'),
            ),
          ],
        );
      },
    );
    if (shouldRemove != true) {
      return;
    }

    try {
      await _libraryManagement(dependencies).removeFolderFromLibrary(folder);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = error;
      });
    }
  }

  Future<void> _editTrackMetadata(
    AppDependencies dependencies,
    Track track,
  ) async {
    final metadata = await showDialog<TrackMetadataUpdate>(
      context: context,
      builder: (context) => TrackMetadataEditDialog(track: track),
    );
    if (metadata == null) {
      return;
    }

    try {
      await dependencies.repositories.tracks.updateTrackMetadata(metadata);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = error;
      });
    }
  }

  Future<void> _runScan(
    Future<LibraryScanResult> Function() scan,
  ) async {
    setState(() {
      _isScanning = true;
      _lastError = null;
    });

    try {
      final result = await scan();

      if (!mounted) {
        return;
      }
      setState(() {
        _lastScanResult = result;
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

  LibraryManagementService _libraryManagement(AppDependencies dependencies) {
    return LibraryManagementService(
      libraryRepository: dependencies.repositories.libraryFolders,
      trackRepository: dependencies.repositories.tracks,
      scanFolder: dependencies.libraryScanner.scanFolder,
    );
  }
}

final class _LibraryActions extends StatelessWidget {
  const _LibraryActions({
    required this.isScanning,
    required this.onAddFolder,
    required this.onRescanLibrary,
  });

  final bool isScanning;
  final VoidCallback onAddFolder;
  final VoidCallback onRescanLibrary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: isScanning ? null : onAddFolder,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Add music folder'),
        ),
        OutlinedButton.icon(
          onPressed: isScanning ? null : onRescanLibrary,
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('Rescan library'),
        ),
        if (isScanning)
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }
}

final class _TrackListControls extends StatelessWidget {
  const _TrackListControls({
    required this.searchController,
    required this.searchQuery,
    required this.sortOption,
    required this.showMissingTracks,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSortChanged,
    required this.onShowMissingChanged,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final LibraryTrackSortOption sortOption;
  final bool showMissingTracks;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<LibraryTrackSortOption> onSortChanged;
  final ValueChanged<bool> onShowMissingChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 720.0;
        final searchWidth = _searchControlWidth(maxWidth);
        final sortWidth = _boundedControlWidth(maxWidth, 220);
        final toggleWidth = _boundedControlWidth(maxWidth, 210);
        final sortDropdown = DropdownButtonFormField<LibraryTrackSortOption>(
          initialValue: sortOption,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Sort by',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final option in LibraryTrackSortOption.values)
              DropdownMenuItem(
                value: option,
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          selectedItemBuilder: (context) {
            return [
              for (final option in LibraryTrackSortOption.values)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ];
          },
          onChanged: (option) {
            if (option != null) {
              onSortChanged(option);
            }
          },
        );
        final missingToggle = SizedBox(
          width: toggleWidth,
          child: Row(
            children: [
              Switch(
                value: showMissingTracks,
                onChanged: onShowMissingChanged,
              ),
              const Expanded(
                child: Text(
                  'Show missing tracks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: searchWidth,
              child: _SearchField(
                controller: searchController,
                searchQuery: searchQuery,
                onChanged: onSearchChanged,
                onClear: onClearSearch,
              ),
            ),
            SizedBox(
              width: sortWidth,
              child: sortDropdown,
            ),
            missingToggle,
          ],
        );
      },
    );
  }

  static double _searchControlWidth(double maxWidth) {
    if (maxWidth < 760) {
      return maxWidth;
    }

    return maxWidth - 220 - 210 - 24;
  }

  static double _boundedControlWidth(double maxWidth, double preferredWidth) {
    if (maxWidth < preferredWidth) {
      return maxWidth;
    }
    return preferredWidth;
  }
}

final class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.searchQuery,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String searchQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: 'Search tracks',
        prefixIcon: const Icon(Icons.search_outlined),
        suffixIcon: searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: onClear,
                icon: const Icon(Icons.close_outlined),
              ),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

final class _LibraryStats extends StatelessWidget {
  const _LibraryStats({
    required this.visibleTracks,
    required this.totalIndexedTracks,
    required this.missingTracks,
    required this.folderCount,
  });

  final int visibleTracks;
  final int totalIndexedTracks;
  final int missingTracks;
  final int folderCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Text(
      'Visible tracks: $visibleTracks | Indexed tracks: $totalIndexedTracks | '
      'Missing: $missingTracks | Folders: $folderCount',
      style: textTheme.bodySmall,
    );
  }
}

final class _LibraryFoldersPanel extends StatelessWidget {
  const _LibraryFoldersPanel({
    required this.folders,
    required this.error,
    required this.isScanning,
    required this.onRescanFolder,
    required this.onToggleEnabled,
    required this.onRemoveFolder,
  });

  final List<LibraryFolder> folders;
  final Object? error;
  final bool isScanning;
  final ValueChanged<LibraryFolder> onRescanFolder;
  final ValueChanged<LibraryFolder> onToggleEnabled;
  final ValueChanged<LibraryFolder> onRemoveFolder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
            Text('Library folders', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            if (error != null)
              Text(
                'Could not load library folders: $error',
                style: TextStyle(color: colorScheme.error),
              )
            else if (folders.isEmpty)
              const Text('No library folders added.')
            else
              for (var index = 0; index < folders.length; index++) ...[
                if (index > 0) const Divider(height: 24),
                _LibraryFolderRow(
                  folder: folders[index],
                  isScanning: isScanning,
                  onRescanFolder: onRescanFolder,
                  onToggleEnabled: onToggleEnabled,
                  onRemoveFolder: onRemoveFolder,
                ),
              ],
          ],
        ),
      ),
    );
  }
}

final class _LibraryFolderRow extends StatelessWidget {
  const _LibraryFolderRow({
    required this.folder,
    required this.isScanning,
    required this.onRescanFolder,
    required this.onToggleEnabled,
    required this.onRemoveFolder,
  });

  final LibraryFolder folder;
  final bool isScanning;
  final ValueChanged<LibraryFolder> onRescanFolder;
  final ValueChanged<LibraryFolder> onToggleEnabled;
  final ValueChanged<LibraryFolder> onRemoveFolder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final statusColor =
        folder.isEnabled ? colorScheme.primary : colorScheme.outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _folderDisplayName(folder),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              folder.isEnabled
                  ? Icons.check_circle_outline
                  : Icons.pause_circle_outline,
              size: 18,
              color: statusColor,
            ),
            const SizedBox(width: 4),
            Text(
              folder.isEnabled ? 'Enabled' : 'Disabled',
              style: textTheme.bodySmall?.copyWith(color: statusColor),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          folder.path,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          _lastScannedLabel(folder.lastScannedAt),
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (folder.isEnabled)
              OutlinedButton.icon(
                onPressed: isScanning ? null : () => onRescanFolder(folder),
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Rescan this folder'),
              ),
            TextButton.icon(
              onPressed: folder.id == null || isScanning
                  ? null
                  : () => onToggleEnabled(folder),
              icon: Icon(
                folder.isEnabled
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
              ),
              label:
                  Text(folder.isEnabled ? 'Disable folder' : 'Enable folder'),
            ),
            if (!folder.isEnabled)
              TextButton.icon(
                onPressed: folder.id == null || isScanning
                    ? null
                    : () => onRemoveFolder(folder),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove folder'),
              ),
          ],
        ),
      ],
    );
  }

  static String _folderDisplayName(LibraryFolder folder) {
    final displayName = folder.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    return folder.path;
  }

  static String _lastScannedLabel(DateTime? lastScannedAt) {
    if (lastScannedAt == null) {
      return 'Last scanned: never';
    }
    return 'Last scanned: ${lastScannedAt.toLocal().toString().split('.').first}';
  }
}

final class _TrackListSliver extends StatelessWidget {
  const _TrackListSliver({
    required this.tracks,
    required this.userStates,
    required this.currentTrack,
    required this.onPlayTrack,
    required this.onLikeTrack,
    required this.onDislikeTrack,
    required this.onAddToQueue,
    required this.onEditTrack,
  });

  final List<Track> tracks;
  final Map<int, TrackUserState> userStates;
  final Track? currentTrack;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track> onLikeTrack;
  final ValueChanged<Track> onDislikeTrack;
  final ValueChanged<Track> onAddToQueue;
  final ValueChanged<Track> onEditTrack;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index.isOdd) {
              return const Divider(height: 1);
            }

            final track = tracks[index ~/ 2];
            return _TrackListTile(
              track: track,
              userState: track.id == null ? null : userStates[track.id],
              isCurrent: _isSameTrack(track, currentTrack),
              onTap: track.isMissing ? null : () => onPlayTrack(track),
              onLike: () => onLikeTrack(track),
              onDislike: () => onDislikeTrack(track),
              onAddToQueue: track.isMissing ? null : () => onAddToQueue(track),
              onEdit: () => onEditTrack(track),
            );
          },
          childCount: tracks.length * 2 - 1,
        ),
      ),
    );
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

final class _PlayerControls extends StatefulWidget {
  const _PlayerControls({
    required this.playerService,
    required this.queueService,
    required this.libraryTracks,
  });

  final PlayerService playerService;
  final PlaybackQueueService queueService;
  final List<Track> libraryTracks;

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
            final track = _latestTrackFor(
              state.currentTrack,
              widget.libraryTracks,
            );
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
                    _QueuePanel(
                      queueState: queueState,
                      onRemoveQueuedTrack:
                          widget.queueService.removeQueuedTrack,
                      onClearQueue: widget.queueService.clearQueue,
                      onPlayQueuedTrackNow: (index) {
                        unawaited(
                          widget.queueService.playQueuedTrackNow(index),
                        );
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
                      selectionPoolMessage: queueState.selectionPoolMessage,
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

  static Track? _latestTrackFor(
      Track? currentTrack, List<Track> libraryTracks) {
    if (currentTrack == null) {
      return null;
    }

    for (final track in libraryTracks) {
      if (_isSameTrack(track, currentTrack)) {
        return track;
      }
    }
    return currentTrack;
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

final class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.queueState,
    required this.onRemoveQueuedTrack,
    required this.onClearQueue,
    required this.onPlayQueuedTrackNow,
  });

  final QueueState queueState;
  final ValueChanged<int> onRemoveQueuedTrack;
  final VoidCallback onClearQueue;
  final ValueChanged<int> onPlayQueuedTrackNow;

  @override
  Widget build(BuildContext context) {
    final hasManualQueue = queueState.manualQueue.isNotEmpty;
    if (!hasManualQueue) {
      return const SizedBox.shrink();
    }

    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: Text('Queue', style: textTheme.titleSmall),
            ),
            TextButton.icon(
              onPressed: onClearQueue,
              icon: const Icon(Icons.clear_all_outlined),
              label: const Text('Clear queue'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var index = 0; index < queueState.manualQueue.length; index++) ...[
          _QueueTrackRow(
            track: queueState.manualQueue[index],
            leading: '${index + 1}',
            onPlayNow: () => onPlayQueuedTrackNow(index),
            onRemove: () => onRemoveQueuedTrack(index),
          ),
          if (index < queueState.manualQueue.length - 1)
            const Divider(height: 12),
        ],
      ],
    );
  }
}

final class _QueueTrackRow extends StatelessWidget {
  const _QueueTrackRow({
    required this.track,
    required this.leading,
    this.onPlayNow,
    this.onRemove,
  });

  final Track track;
  final String leading;
  final VoidCallback? onPlayNow;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            leading,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium,
              ),
              Text(
                _PlayerControlsState._artistLabel(track),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (onPlayNow != null) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Play now',
            onPressed: onPlayNow,
            icon: const Icon(Icons.play_arrow_outlined),
          ),
        ],
        if (onRemove != null) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Remove from queue',
            onPressed: onRemove,
            icon: const Icon(Icons.close_outlined),
          ),
        ],
      ],
    );
  }
}

final class _RecommendationDebugPanel extends StatelessWidget {
  const _RecommendationDebugPanel({
    required this.result,
    required this.candidates,
    required this.repeatGuardMessage,
    required this.selectionPoolMessage,
  });

  final RecommendationResult? result;
  final List<RecommendationResult> candidates;
  final String? repeatGuardMessage;
  final String? selectionPoolMessage;

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
        if (selectionPoolMessage != null) ...[
          const SizedBox(height: 8),
          Text(selectionPoolMessage!, style: textTheme.bodySmall),
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

    if (!result.hasErrors) {
      return Text(result.summary);
    }

    final visibleErrors = result.errors.take(3).toList(growable: false);
    final remainingErrors = result.errors.length - visibleErrors.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(result.summary),
        const SizedBox(height: 4),
        for (final error in visibleErrors)
          Text(
            '${error.path}: ${error.message}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colorScheme.error),
          ),
        if (remainingErrors > 0)
          Text(
            '$remainingErrors more scan errors were recorded.',
            style: TextStyle(color: colorScheme.error),
          ),
      ],
    );
  }
}

final class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      message,
      textAlign: TextAlign.start,
      style: isError ? TextStyle(color: colorScheme.error) : null,
    );
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
    required this.onAddToQueue,
    required this.onEdit,
  });

  final Track track;
  final TrackUserState? userState;
  final bool isCurrent;
  final VoidCallback? onTap;
  final VoidCallback onLike;
  final VoidCallback onDislike;
  final VoidCallback? onAddToQueue;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMissing = track.isMissing;
    final subtitle = isMissing
        ? 'Missing - ${buildTrackMetadataSubtitle(track)}'
        : buildTrackMetadataSubtitle(track);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      selected: isCurrent,
      leading: Icon(
        isMissing
            ? Icons.report_problem_outlined
            : isCurrent
                ? Icons.graphic_eq_outlined
                : Icons.music_note_outlined,
        color: isMissing ? colorScheme.error : null,
      ),
      onTap: onTap,
      title: Text(
        track.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isMissing ? TextStyle(color: colorScheme.error) : null,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
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
            IconButton.outlined(
              tooltip: 'Add to queue',
              onPressed: onAddToQueue,
              icon: const Icon(Icons.queue_music_outlined),
            ),
            const SizedBox(width: 4),
            IconButton.outlined(
              tooltip: 'Edit metadata',
              onPressed: track.id == null ? null : onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            const SizedBox(width: 4),
            Icon(
              isCurrent ? Icons.play_circle_outline : Icons.play_arrow_outlined,
              color: isMissing ? colorScheme.outline : null,
            ),
          ],
        ),
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
