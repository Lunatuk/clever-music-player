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

const double _cardRadius = 24;
const double _controlRadius = 18;

final class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _searchController;
  LibraryScanResult? _lastScanResult;
  Object? _lastError;
  int _selectedPageIndex = 0;
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: _BottomPlayerBar(
          playerService: dependencies.playerService,
          queueService: dependencies.playbackQueue,
          tracksStream: dependencies.repositories.tracks.watchAllTracks(
            includeMissing: true,
          ),
          onOpenSettings: () {
            setState(() {
              _selectedPageIndex = 2;
            });
          },
        ),
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
    final visibleTracks = buildVisibleLibraryTracks(
      tracks: activeTracks,
      searchQuery: _searchQuery,
      showMissingTracks: _showMissingTracks,
      sortOption: _sortOption,
      userStates: userStates,
    );
    final missingCount = activeTracks.where((track) => track.isMissing).length;

    return switch (_selectedPageIndex) {
      0 => _HomeWavePage(
          playerState: playerState,
          playerService: dependencies.playerService,
          queueService: dependencies.playbackQueue,
          scanResult: _lastScanResult,
          scanError: _lastError,
          isScanning: _isScanning,
          onPageSelected: _selectPage,
          onAddFolder: () => _addMusicFolder(dependencies),
          onRescanLibrary: () => _rescanLibrary(dependencies),
        ),
      1 => _MyMusicPage(
          selectedPageIndex: _selectedPageIndex,
          playerState: playerState,
          queueService: dependencies.playbackQueue,
          activeTracks: activeTracks,
          visibleTracks: visibleTracks,
          totalIndexedTracks: totalIndexedTracks,
          missingCount: missingCount,
          userStates: userStates,
          folderCount: folders.length,
          trackLoadError: trackLoadError,
          searchController: _searchController,
          searchQuery: _searchQuery,
          sortOption: _sortOption,
          showMissingTracks: _showMissingTracks,
          onPageSelected: _selectPage,
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
      _ => _SettingsPage(
          selectedPageIndex: _selectedPageIndex,
          folders: folders,
          folderLoadError: folderLoadError,
          scanResult: _lastScanResult,
          scanError: _lastError,
          isScanning: _isScanning,
          queueService: dependencies.playbackQueue,
          onPageSelected: _selectPage,
          onAddFolder: () => _addMusicFolder(dependencies),
          onRescanLibrary: () => _rescanLibrary(dependencies),
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
    };
  }

  void _selectPage(int pageIndex) {
    if (_selectedPageIndex == pageIndex) {
      return;
    }
    setState(() {
      _selectedPageIndex = pageIndex;
    });
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

final class _HomeWavePage extends StatelessWidget {
  const _HomeWavePage({
    required this.playerState,
    required this.playerService,
    required this.queueService,
    required this.scanResult,
    required this.scanError,
    required this.isScanning,
    required this.onPageSelected,
    required this.onAddFolder,
    required this.onRescanLibrary,
  });

  final PlayerState playerState;
  final PlayerService playerService;
  final PlaybackQueueService queueService;
  final LibraryScanResult? scanResult;
  final Object? scanError;
  final bool isScanning;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onAddFolder;
  final VoidCallback onRescanLibrary;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                _WaveHomePanel(
                  playerState: playerState,
                  playerService: playerService,
                  queueService: queueService,
                ),
                const SizedBox(height: 20),
                _HomeQuickActions(
                  isScanning: isScanning,
                  onAddFolder: onAddFolder,
                  onRescanLibrary: onRescanLibrary,
                  onOpenLibrary: () => onPageSelected(1),
                ),
                const SizedBox(height: 14),
                Center(
                  child: _ScanStatus(
                    result: scanResult,
                    error: scanError,
                    isScanning: isScanning,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 56)),
      ],
    );
  }
}

final class _MyMusicPage extends StatelessWidget {
  const _MyMusicPage({
    required this.selectedPageIndex,
    required this.playerState,
    required this.queueService,
    required this.activeTracks,
    required this.visibleTracks,
    required this.totalIndexedTracks,
    required this.missingCount,
    required this.userStates,
    required this.folderCount,
    required this.trackLoadError,
    required this.searchController,
    required this.searchQuery,
    required this.sortOption,
    required this.showMissingTracks,
    required this.onPageSelected,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSortChanged,
    required this.onShowMissingChanged,
    required this.onPlayTrack,
    required this.onLikeTrack,
    required this.onDislikeTrack,
    required this.onAddToQueue,
    required this.onEditTrack,
  });

  final int selectedPageIndex;
  final PlayerState playerState;
  final PlaybackQueueService queueService;
  final List<Track> activeTracks;
  final List<Track> visibleTracks;
  final int totalIndexedTracks;
  final int missingCount;
  final Map<int, TrackUserState> userStates;
  final int folderCount;
  final Object? trackLoadError;
  final TextEditingController searchController;
  final String searchQuery;
  final LibraryTrackSortOption sortOption;
  final bool showMissingTracks;
  final ValueChanged<int> onPageSelected;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<LibraryTrackSortOption> onSortChanged;
  final ValueChanged<bool> onShowMissingChanged;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track> onLikeTrack;
  final ValueChanged<Track> onDislikeTrack;
  final ValueChanged<Track> onAddToQueue;
  final ValueChanged<Track> onEditTrack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                _ShellHeader(
                  title: 'Моя музыка',
                  subtitle: 'Search, sort, queue, and edit local tracks',
                  selectedPageIndex: selectedPageIndex,
                  onPageSelected: onPageSelected,
                ),
                const SizedBox(height: 22),
                Text('Track library', style: textTheme.headlineSmall),
                const SizedBox(height: 12),
                const _LibraryTabsPlaceholder(),
                const SizedBox(height: 12),
                _TrackListControls(
                  searchController: searchController,
                  searchQuery: searchQuery,
                  sortOption: sortOption,
                  showMissingTracks: showMissingTracks,
                  onSearchChanged: onSearchChanged,
                  onClearSearch: onClearSearch,
                  onSortChanged: onSortChanged,
                  onShowMissingChanged: onShowMissingChanged,
                ),
                const SizedBox(height: 8),
                _LibraryStats(
                  visibleTracks: visibleTracks.length,
                  totalIndexedTracks: totalIndexedTracks,
                  missingTracks: missingCount,
                  folderCount: folderCount,
                ),
                StreamBuilder<QueueState>(
                  stream: queueService.stateStream,
                  initialData: queueService.state,
                  builder: (context, snapshot) {
                    final queueState = snapshot.data ?? QueueState();
                    if (queueState.manualQueue.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: _QueuePanel(
                        queueState: queueState,
                        onRemoveQueuedTrack: queueService.removeQueuedTrack,
                        onClearQueue: queueService.clearQueue,
                        onPlayQueuedTrackNow: (index) {
                          unawaited(queueService.playQueuedTrackNow(index));
                        },
                      ),
                    );
                  },
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
                    message: 'No active tracks indexed yet.',
                  ),
                ] else if (visibleTracks.isEmpty) ...[
                  const SizedBox(height: 24),
                  const _InlineMessage(
                    message: 'No tracks match these filters.',
                  ),
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
            onPlayTrack: onPlayTrack,
            onLikeTrack: onLikeTrack,
            onDislikeTrack: onDislikeTrack,
            onAddToQueue: onAddToQueue,
            onEditTrack: onEditTrack,
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 56)),
      ],
    );
  }
}

final class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.selectedPageIndex,
    required this.folders,
    required this.folderLoadError,
    required this.scanResult,
    required this.scanError,
    required this.isScanning,
    required this.queueService,
    required this.onPageSelected,
    required this.onAddFolder,
    required this.onRescanLibrary,
    required this.onRescanFolder,
    required this.onToggleEnabled,
    required this.onRemoveFolder,
  });

  final int selectedPageIndex;
  final List<LibraryFolder> folders;
  final Object? folderLoadError;
  final LibraryScanResult? scanResult;
  final Object? scanError;
  final bool isScanning;
  final PlaybackQueueService queueService;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onAddFolder;
  final VoidCallback onRescanLibrary;
  final ValueChanged<LibraryFolder> onRescanFolder;
  final ValueChanged<LibraryFolder> onToggleEnabled;
  final ValueChanged<LibraryFolder> onRemoveFolder;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                _ShellHeader(
                  title: 'Settings',
                  subtitle: 'Library management and development tools',
                  selectedPageIndex: selectedPageIndex,
                  onPageSelected: onPageSelected,
                ),
                const SizedBox(height: 22),
                _SettingsSection(
                  title: 'Library management',
                  child: _LibraryActions(
                    isScanning: isScanning,
                    onAddFolder: onAddFolder,
                    onRescanLibrary: onRescanLibrary,
                  ),
                ),
                const SizedBox(height: 16),
                _LibraryFoldersPanel(
                  folders: folders,
                  error: folderLoadError,
                  isScanning: isScanning,
                  onRescanFolder: onRescanFolder,
                  onToggleEnabled: onToggleEnabled,
                  onRemoveFolder: onRemoveFolder,
                ),
                const SizedBox(height: 16),
                _SettingsSection(
                  title: 'Scan status',
                  child: _ScanStatus(
                    result: scanResult,
                    error: scanError,
                    isScanning: isScanning,
                  ),
                ),
                const SizedBox(height: 16),
                StreamBuilder<QueueState>(
                  stream: queueService.stateStream,
                  initialData: queueService.state,
                  builder: (context, snapshot) {
                    final queueState = snapshot.data ?? QueueState();
                    return _RecommendationDebugPanel(
                      result: queueState.lastRecommendationResult,
                      candidates: queueState.recommendationCandidates,
                      repeatGuardMessage: queueState.repeatGuardMessage,
                      selectionPoolMessage: queueState.selectionPoolMessage,
                    );
                  },
                ),
                const SizedBox(height: 16),
                const _DevInfoPanel(),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 56)),
      ],
    );
  }
}

final class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.title,
    required this.subtitle,
    required this.selectedPageIndex,
    required this.onPageSelected,
  });

  final String title;
  final String subtitle;
  final int selectedPageIndex;
  final ValueChanged<int> onPageSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _ShellIconButton(
          tooltip: 'Go to wave page',
          icon: Icons.waves_outlined,
          selected: selectedPageIndex == 0,
          onPressed: () => onPageSelected(0),
        ),
        const SizedBox(width: 4),
        _ShellIconButton(
          tooltip: 'Go to My Music page',
          icon: Icons.library_music_outlined,
          selected: selectedPageIndex == 1,
          onPressed: () => onPageSelected(1),
        ),
      ],
    );
  }
}

final class _ShellIconButton extends StatelessWidget {
  const _ShellIconButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      );
    }
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

final class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({
    required this.isScanning,
    required this.onAddFolder,
    required this.onRescanLibrary,
    required this.onOpenLibrary,
  });

  final bool isScanning;
  final VoidCallback onAddFolder;
  final VoidCallback onRescanLibrary;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: isScanning ? null : onAddFolder,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Добавить папку'),
        ),
        OutlinedButton.icon(
          onPressed: isScanning ? null : onRescanLibrary,
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('Еще раз'),
        ),
        OutlinedButton.icon(
          onPressed: onOpenLibrary,
          icon: const Icon(Icons.library_music_outlined),
          label: const Text('Моя музыка'),
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

final class _LibraryTabsPlaceholder extends StatelessWidget {
  const _LibraryTabsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          avatar: const Icon(Icons.music_note_outlined, size: 16),
          label: const Text('Все треки'),
          side: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.65),
          ),
        ),
        Chip(
          avatar: const Icon(Icons.queue_music_outlined, size: 16),
          label: const Text('Плейлисты'),
          backgroundColor: colorScheme.surfaceContainer,
          labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

final class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

final class _DevInfoPanel extends StatelessWidget {
  const _DevInfoPanel();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('App/dev info', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Liquid Wave UI v1. Playlists, custom backgrounds, GIFs, '
              'previous-track history, and server sync are intentionally '
              'not implemented in this iteration.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
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
          label: const Text('Добавить папку'),
        ),
        OutlinedButton.icon(
          onPressed: isScanning ? null : onRescanLibrary,
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('Еще раз'),
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
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 720.0;
        final controlsMaxWidth = maxWidth > 28 ? maxWidth - 28 : maxWidth;
        final searchWidth = _searchControlWidth(controlsMaxWidth);
        final sortWidth = _boundedControlWidth(controlsMaxWidth, 240);
        final toggleWidth = _boundedControlWidth(controlsMaxWidth, 230);
        final sortDropdown = DropdownButtonFormField<LibraryTrackSortOption>(
          initialValue: sortOption,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Sort by',
            prefixIcon: Icon(Icons.sort_outlined),
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
        final missingToggle = DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(_controlRadius),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: SizedBox(
            width: toggleWidth,
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Switch(
                    value: showMissingTracks,
                    onChanged: onShowMissingChanged,
                  ),
                  const Expanded(
                    child: Text(
                      'Show missing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final controls = [
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
        ];

        return Card(
          color: colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: controls,
            ),
          ),
        );
      },
    );
  }

  static double _searchControlWidth(double maxWidth) {
    if (maxWidth < 760) {
      return maxWidth;
    }

    return maxWidth - 240 - 230 - 24;
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
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        'Visible $visibleTracks / Indexed $totalIndexedTracks / '
        'Missing $missingTracks / Folders $folderCount',
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
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

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.folder_copy_outlined),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        title: const Text('Library folders'),
        subtitle: Text(_folderSummary(folders, error)),
        children: [
          if (error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Could not load library folders: $error',
                style: TextStyle(color: colorScheme.error),
              ),
            )
          else if (folders.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No library folders added.'),
            )
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
    );
  }

  static String _folderSummary(List<LibraryFolder> folders, Object? error) {
    if (error != null) {
      return 'Needs attention';
    }
    if (folders.isEmpty) {
      return 'No folders added';
    }
    final enabled = folders.where((folder) => folder.isEnabled).length;
    return '$enabled enabled / ${folders.length} total';
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
        folder.isEnabled ? colorScheme.tertiary : colorScheme.outline;

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
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _lastScannedLabel(folder.lastScannedAt),
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (folder.isEnabled)
              OutlinedButton.icon(
                onPressed: isScanning ? null : () => onRescanFolder(folder),
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Rescan'),
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
              label: Text(folder.isEnabled ? 'Disable' : 'Enable'),
            ),
            if (!folder.isEnabled)
              TextButton.icon(
                onPressed: folder.id == null || isScanning
                    ? null
                    : () => onRemoveFolder(folder),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
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
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final track = tracks[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TrackListTile(
                track: track,
                userState: track.id == null ? null : userStates[track.id],
                isCurrent: _isSameTrack(track, currentTrack),
                onTap: track.isMissing ? null : () => onPlayTrack(track),
                onLike: () => onLikeTrack(track),
                onDislike: () => onDislikeTrack(track),
                onAddToQueue:
                    track.isMissing ? null : () => onAddToQueue(track),
                onEdit: () => onEditTrack(track),
              ),
            );
          },
          childCount: tracks.length,
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

final class _WaveHomePanel extends StatelessWidget {
  const _WaveHomePanel({
    required this.playerState,
    required this.playerService,
    required this.queueService,
  });

  final PlayerState playerState;
  final PlayerService playerService;
  final PlaybackQueueService queueService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueueState>(
      stream: queueService.stateStream,
      initialData: queueService.state,
      builder: (context, snapshot) {
        final queueState = snapshot.data ?? QueueState();
        final currentTrack =
            playerState.currentTrack ?? queueState.currentTrack;
        final isBusy = queueState.isChoosingNext ||
            playerState.status == PlayerPlaybackStatus.loading;

        return Column(
          children: [
            _WaveHeroSection(
              playerState: playerState,
              queueState: queueState,
              onLaunch: isBusy
                  ? null
                  : () {
                      if (playerState.isPlaying && currentTrack != null) {
                        unawaited(playerService.pause());
                        return;
                      }
                      if (currentTrack != null && queueState.isWaveEnabled) {
                        unawaited(playerService.play());
                        return;
                      }
                      unawaited(queueService.playSmartNext());
                    },
              onConfigure: () {
                unawaited(
                  _showWaveModeSheet(
                    context: context,
                    queueState: queueState,
                    onModeChanged: queueService.setWaveMode,
                  ),
                );
              },
            ),
            if (queueState.lastError != null) ...[
              const SizedBox(height: 12),
              _InlineMessage(
                message: queueState.lastError!,
                isError: true,
              ),
            ],
          ],
        );
      },
    );
  }
}

final class _WaveHeroSection extends StatelessWidget {
  const _WaveHeroSection({
    required this.playerState,
    required this.queueState,
    required this.onLaunch,
    required this.onConfigure,
  });

  final PlayerState playerState;
  final QueueState queueState;
  final VoidCallback? onLaunch;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final track = playerState.currentTrack ?? queueState.currentTrack;
    final hasTrack = track != null;
    final isBusy = queueState.isChoosingNext ||
        playerState.status == PlayerPlaybackStatus.loading;
    final launchIcon = playerState.isPlaying
        ? Icons.pause_circle_filled_rounded
        : Icons.play_circle_fill_rounded;
    final heroTextStyle = textTheme.displayMedium?.copyWith(
      color: colorScheme.onSurface,
      fontWeight: FontWeight.w900,
      height: 1.05,
    );

    return SizedBox(
      height: 460,
      child: Stack(
        children: [
          const Positioned.fill(
            child: _LiquidWaveBackdrop(customBackground: null),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.82,
                  colors: [
                    Colors.transparent,
                    colorScheme.surfaceContainerLowest.withValues(alpha: 0.36),
                    colorScheme.surfaceContainerLowest.withValues(alpha: 0.96),
                  ],
                  stops: const [0.52, 0.82, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colorScheme.surfaceContainerLowest.withValues(alpha: 0.95),
                    colorScheme.surfaceContainerLowest.withValues(alpha: 0.0),
                    colorScheme.surfaceContainerLowest.withValues(alpha: 0.92),
                  ],
                  stops: const [0, 0.34, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.surfaceContainerLowest,
                    colorScheme.surfaceContainerLowest.withValues(alpha: 0.72),
                    Colors.transparent,
                    Colors.transparent,
                    colorScheme.surfaceContainerLowest.withValues(alpha: 0.72),
                    colorScheme.surfaceContainerLowest,
                  ],
                  stops: const [0, 0.16, 0.32, 0.68, 0.84, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _WaveModePill(
                      mode: queueState.selectedWaveMode,
                      isWaveEnabled: queueState.isWaveEnabled,
                      isChoosingNext: queueState.isChoosingNext,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: isBusy ? null : onLaunch,
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.onSurface,
                      disabledForegroundColor:
                          colorScheme.onSurface.withValues(alpha: 0.45),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      textStyle: heroTextStyle,
                    ),
                    icon: Icon(
                      launchIcon,
                      size: 56,
                      color: isBusy
                          ? colorScheme.onSurface.withValues(alpha: 0.45)
                          : colorScheme.tertiary,
                    ),
                    label: const Text('Пустить жидкого'),
                  ),
                  if (hasTrack) ...[
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Text(
                        '${track.displayTitle} - ${_artistLabel(track)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  OutlinedButton.icon(
                    onPressed: onConfigure,
                    icon: const Icon(Icons.tune_outlined),
                    label: const Text('Настроить'),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _WaveModePill extends StatelessWidget {
  const _WaveModePill({
    required this.mode,
    required this.isWaveEnabled,
    required this.isChoosingNext,
  });

  final WaveMode mode;
  final bool isWaveEnabled;
  final bool isChoosingNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = isChoosingNext
        ? 'Choosing'
        : isWaveEnabled
            ? 'Wave on'
            : 'Wave ready';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isWaveEnabled ? Icons.graphic_eq_outlined : Icons.waves_outlined,
              size: 16,
              color: isWaveEnabled ? colorScheme.tertiary : colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text('$label - ${_WaveModeSelector.waveModeLabel(mode)}'),
          ],
        ),
      ),
    );
  }
}

final class _LiquidWaveBackdrop extends StatelessWidget {
  const _LiquidWaveBackdrop({
    required this.customBackground,
  });

  final Widget? customBackground;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = customBackground;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (background != null)
          background
        else
          CustomPaint(
            painter: _LiquidWavePainter(colorScheme),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 0.95,
              colors: [
                colorScheme.primary.withValues(alpha: 0.20),
                colorScheme.secondary.withValues(alpha: 0.08),
                colorScheme.surfaceContainerLowest.withValues(alpha: 0.86),
              ],
              stops: const [0, 0.46, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.surfaceContainerLowest.withValues(alpha: 0.82),
                colorScheme.surfaceContainerHigh.withValues(alpha: 0.18),
                colorScheme.surfaceContainerLowest.withValues(alpha: 0.88),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

final class _LiquidWavePainter extends CustomPainter {
  const _LiquidWavePainter(this.colorScheme);

  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colorScheme.surfaceContainerLowest,
          colorScheme.surfaceContainer,
          colorScheme.surfaceContainerLowest,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    final waveColors = [
      colorScheme.primary.withValues(alpha: 0.28),
      colorScheme.tertiary.withValues(alpha: 0.22),
      colorScheme.secondary.withValues(alpha: 0.16),
    ];
    final waveStartX = size.width * 0.16;
    final waveEndX = size.width * 0.84;
    final waveRect = Rect.fromLTRB(waveStartX, 0, waveEndX, size.height);

    for (var index = 0; index < 7; index++) {
      final y = size.height * (0.22 + index * 0.095);
      final lift = size.height * (0.09 + index * 0.006);
      final color = waveColors[index % waveColors.length];
      final path = Path()
        ..moveTo(waveStartX, y)
        ..cubicTo(
          size.width * 0.30,
          y - lift,
          size.width * 0.40,
          y + lift,
          size.width * 0.50,
          y,
        )
        ..cubicTo(
          size.width * 0.60,
          y - lift,
          size.width * 0.70,
          y + lift,
          waveEndX,
          y - lift * 0.2,
        );
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2 + index * 0.55
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color,
            color,
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.18, 0.82, 1],
        ).createShader(waveRect);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidWavePainter oldDelegate) {
    return oldDelegate.colorScheme != colorScheme;
  }
}

Future<void> _showWaveModeSheet({
  required BuildContext context,
  required QueueState queueState,
  required ValueChanged<WaveMode> onModeChanged,
}) {
  var selectedMode = queueState.selectedWaveMode;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final textTheme = Theme.of(context).textTheme;
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Настроить волну', style: textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'Текущий режим: '
                  '${_WaveModeSelector.waveModeLabel(selectedMode)}',
                ),
                const SizedBox(height: 18),
                _WaveModeSelector(
                  selectedMode: selectedMode,
                  enabled: !queueState.isChoosingNext,
                  onModeChanged: (mode) {
                    setModalState(() {
                      selectedMode = mode;
                    });
                    onModeChanged(mode);
                  },
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

final class _WaveModeSelector extends StatelessWidget {
  const _WaveModeSelector({
    required this.selectedMode,
    required this.enabled,
    required this.onModeChanged,
  });

  final WaveMode selectedMode;
  final bool enabled;
  final ValueChanged<WaveMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in WaveMode.values)
          ChoiceChip(
            label: Text(waveModeLabel(mode)),
            selected: mode == selectedMode,
            showCheckmark: false,
            selectedColor: colorScheme.primary.withValues(alpha: 0.24),
            backgroundColor: colorScheme.surfaceContainerHigh,
            side: BorderSide(
              color: mode == selectedMode
                  ? colorScheme.primary.withValues(alpha: 0.75)
                  : colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
            onSelected: enabled
                ? (selected) {
                    if (selected) {
                      onModeChanged(mode);
                    }
                  }
                : null,
          ),
      ],
    );
  }

  static String waveModeLabel(WaveMode mode) {
    return switch (mode) {
      WaveMode.balanced => 'Balanced',
      WaveMode.discovery => 'Discovery',
      WaveMode.focus => 'Focus',
      WaveMode.favorites => 'Favorites',
      WaveMode.deepCuts => 'Deep Cuts',
    };
  }
}

final class _BottomPlayerBar extends StatefulWidget {
  const _BottomPlayerBar({
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
  State<_BottomPlayerBar> createState() => _BottomPlayerBarState();
}

final class _BottomPlayerBarState extends State<_BottomPlayerBar> {
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
    final canGoNext = !queueState.isChoosingNext &&
        (track != null ||
            queueState.manualQueue.isNotEmpty ||
            queueState.isWaveEnabled);
    final isBusy = playerState.status == PlayerPlaybackStatus.loading ||
        queueState.isChoosingNext;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(_cardRadius),
      ),
      child: Material(
        elevation: 18,
        color: colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useWideLayout = constraints.maxWidth >= 720;
              final sideWidth =
                  (constraints.maxWidth * 0.30).clamp(220.0, 340.0).toDouble();
              final summary = _NowPlayingSummary(
                track: track,
                queueCount: queueState.manualQueue.length,
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
                canGoNext: canGoNext,
                onPlayPause: track == null
                    ? null
                    : () {
                        unawaited(
                          playerState.isPlaying
                              ? widget.playerService.pause()
                              : widget.playerService.play(),
                        );
                      },
                onNext: canGoNext
                    ? () {
                        unawaited(widget.queueService.next());
                      }
                    : null,
                onStop: track == null
                    ? null
                    : () {
                        unawaited(widget.playerService.stop());
                      },
              );
              final rightActions = _BottomPlayerActions(
                hasTrack: track != null,
                isLiked: queueState.isCurrentTrackLiked,
                isDisliked: queueState.isCurrentTrackDisliked,
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
                  if (playerState.hasError || queueState.lastError != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        playerState.errorMessage ??
                            queueState.lastError ??
                            'Playback failed.',
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
    );
  }
}

final class _NowPlayingSummary extends StatelessWidget {
  const _NowPlayingSummary({
    required this.track,
    required this.queueCount,
  });

  final Track? track;
  final int queueCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.surfaceContainerHighest,
                colorScheme.primary.withValues(alpha: 0.24),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: SizedBox.square(
            dimension: 54,
            child: Icon(
              track == null ? Icons.album_outlined : Icons.graphic_eq_outlined,
              color: track == null
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.tertiary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track?.displayTitle ?? 'No track playing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall,
              ),
              Text(
                _artistLabel(track),
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
            message: '$queueCount tracks in manual queue',
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
    required this.canGoNext,
    required this.onPlayPause,
    required this.onNext,
    required this.onStop,
  });

  final bool isPlaying;
  final bool canGoNext;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          tooltip: 'Previous',
          onPressed: null,
          icon: const Icon(Icons.skip_previous_outlined),
        ),
        const SizedBox(width: 4),
        IconButton.filled(
          tooltip: isPlaying ? 'Pause' : 'Play',
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
          tooltip: 'Next / skip',
          onPressed: canGoNext ? onNext : null,
          icon: const Icon(Icons.skip_next_outlined),
        ),
        const SizedBox(width: 4),
        IconButton.outlined(
          tooltip: 'Stop',
          onPressed: onStop,
          icon: const Icon(Icons.stop_outlined),
        ),
      ],
    );
  }
}

final class _BottomPlayerActions extends StatelessWidget {
  const _BottomPlayerActions({
    required this.hasTrack,
    required this.isLiked,
    required this.isDisliked,
    required this.onLike,
    required this.onDislike,
    required this.onOpenSettings,
  });

  final bool hasTrack;
  final bool isLiked;
  final bool isDisliked;
  final VoidCallback onLike;
  final VoidCallback onDislike;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TrackFeedbackIconButton(
          isActive: isLiked,
          onPressed: hasTrack ? onLike : null,
          activeIcon: Icons.thumb_up,
          inactiveIcon: Icons.thumb_up_outlined,
          activeTooltip: 'Unlike',
          inactiveTooltip: 'Like',
        ),
        const SizedBox(width: 4),
        _TrackFeedbackIconButton(
          isActive: isDisliked,
          onPressed: hasTrack ? onDislike : null,
          activeIcon: Icons.thumb_down,
          inactiveIcon: Icons.thumb_down_outlined,
          activeTooltip: 'Undislike',
          inactiveTooltip: 'Dislike',
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Settings',
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }
}

String _artistLabel(Track? track) {
  final artist = track?.artist?.trim();
  if (artist != null && artist.isNotEmpty) {
    return artist;
  }
  return track == null
      ? 'Select a local track to start playback'
      : 'Unknown artist';
}

Object? _trackKey(Track? track) {
  return track?.id ?? track?.filePath;
}

Track? _latestTrackFor(Track? currentTrack, List<Track> libraryTracks) {
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

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Manual queue', style: textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: onClearQueue,
                  icon: const Icon(Icons.clear_all_outlined),
                  label: const Text('Clear queue'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var index = 0;
                index < queueState.manualQueue.length;
                index++) ...[
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
        ),
      ),
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
                _artistLabel(track),
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
      final colorScheme = Theme.of(context).colorScheme;
      return Card(
        color: colorScheme.surfaceContainerLow,
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.psychology_alt_outlined),
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          title: const Text('Почему выбран трек'),
          subtitle: const Text('No Smart Wave recommendation yet.'),
          children: const [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Start Smart Wave to populate recommendation reasons.',
              ),
            ),
          ],
        ),
      );
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

    final colorScheme = Theme.of(context).colorScheme;
    final summary = '${result.selectedTrack.displayTitle} - '
        'score ${result.finalScore.toStringAsFixed(1)} '
        'from ${result.candidatesConsidered} candidates';

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.psychology_alt_outlined),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        title: const Text('Почему выбран трек'),
        subtitle: Text(
          summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
            ),
          ),
        ],
      ),
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
    final textTheme = Theme.of(context).textTheme;
    final subtleStyle = textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    if (isScanning) {
      return Text('Scanning local folders...', style: subtleStyle);
    }

    if (error != null) {
      return Text(
        error.toString(),
        style: TextStyle(color: colorScheme.error),
      );
    }

    final result = this.result;
    if (result == null) {
      return Text('No scan has run yet.', style: subtleStyle);
    }

    if (!result.hasErrors) {
      return Text(result.summary, style: subtleStyle);
    }

    final visibleErrors = result.errors.take(3).toList(growable: false);
    final remainingErrors = result.errors.length - visibleErrors.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(result.summary, style: subtleStyle),
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
    final textTheme = Theme.of(context).textTheme;
    final isMissing = track.isMissing;
    final subtitle = isMissing
        ? 'Missing - ${buildTrackMetadataSubtitle(track)}'
        : buildTrackMetadataSubtitle(track);
    final rowColor = isCurrent
        ? Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.16),
            colorScheme.surfaceContainer,
          )
        : colorScheme.surfaceContainerLow;
    final leadingColor = isMissing
        ? colorScheme.error
        : isCurrent
            ? colorScheme.tertiary
            : colorScheme.onSurfaceVariant;
    final actions = FittedBox(
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
          const SizedBox(width: 2),
          _TrackFeedbackIconButton(
            isActive: userState?.isHidden ?? false,
            onPressed: track.id == null ? null : onDislike,
            activeIcon: Icons.thumb_down,
            inactiveIcon: Icons.thumb_down_outlined,
            activeTooltip: 'Undislike',
            inactiveTooltip: 'Dislike',
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: 'Add to queue',
            onPressed: onAddToQueue,
            icon: const Icon(Icons.queue_music_outlined),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: 'Edit metadata',
            onPressed: track.id == null ? null : onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: isCurrent ? 'Playing' : 'Play',
            onPressed: onTap,
            icon: Icon(
              isCurrent ? Icons.graphic_eq_outlined : Icons.play_arrow_outlined,
            ),
          ),
        ],
      ),
    );

    return Material(
      color: rowColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: leadingColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SizedBox.square(
                  dimension: 44,
                  child: Icon(
                    isMissing
                        ? Icons.report_problem_outlined
                        : isCurrent
                            ? Icons.graphic_eq_outlined
                            : Icons.music_note_outlined,
                    color: leadingColor,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: isMissing ? colorScheme.error : null,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: isMissing
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: actions,
                ),
              ),
            ],
          ),
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

    return IconButton(
      tooltip: inactiveTooltip,
      onPressed: onPressed,
      icon: Icon(inactiveIcon),
    );
  }
}
