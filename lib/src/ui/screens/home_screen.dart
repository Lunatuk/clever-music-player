import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/dependency_scope.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../../library/library_management_service.dart';
import '../../library/library_scanner_service.dart';
import '../../library/library_track_list.dart';
import '../../player/player_progress.dart';
import '../../player/player_service.dart';
import '../../player/player_state.dart';
import '../../queue/playlist_queue_actions.dart';
import '../../queue/playback_queue_service.dart';
import '../../queue/queue_state.dart';
import '../track_metadata_subtitle.dart';
import '../track_metadata_edit_dialog.dart';
import '../track_artwork.dart';

const double _cardRadius = 24;
const double _controlRadius = 18;
const double _bottomPlayerBarBackgroundOpacity = 0.48;
const double _bottomPlayerBarBlurSigma = 18;
const double _bottomPlayerBarScrollPadding = 152;

const int _wavePageIndex = 0;
const int _myMusicPageIndex = 1;
const int _playlistsPageIndex = 2;
const int _settingsPageIndex = 3;

final class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _searchController;
  AppDependencies? _streamDependencies;
  Stream<List<Track>>? _activeTracksStream;
  Stream<List<Track>>? _indexedTracksStream;
  Stream<List<LibraryFolder>>? _foldersStream;
  Stream<PlayerState>? _pagePlayerStateStream;
  Stream<Map<int, TrackUserState>>? _userStatesStream;
  List<int> _userStateTrackIds = const [];
  List<Track>? _visibleTracksInput;
  Map<int, TrackUserState>? _visibleTracksUserStatesInput;
  String? _visibleTracksSearchQueryInput;
  LibraryTrackSortOption? _visibleTracksSortOptionInput;
  bool? _visibleTracksShowMissingInput;
  List<Track>? _cachedVisibleTracks;
  List<Track>? _missingCountInput;
  int? _cachedMissingCount;
  LibraryScanResult? _lastScanResult;
  Object? _lastError;
  int _selectedPageIndex = _wavePageIndex;
  String _searchQuery = '';
  LibraryTrackSortOption _sortOption = LibraryTrackSortOption.title;
  bool _showMissingTracks = false;
  int? _selectedPlaylistId;
  bool _isScanning = false;
  bool _isResettingLearningState = false;
  bool _isSidebarCollapsed = false;

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
    _ensureStreams(dependencies);

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: SafeArea(
        top: false,
        child: _BottomPlayerBar(
          playerService: dependencies.playerService,
          queueService: dependencies.playbackQueue,
          tracksStream: _activeTracksStream!,
          onOpenSettings: () {
            setState(() {
              _selectedPageIndex = _settingsPageIndex;
            });
          },
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<Track>>(
          stream: _activeTracksStream,
          initialData: const [],
          builder: (context, trackSnapshot) {
            final activeTracks = trackSnapshot.data ?? const <Track>[];
            final trackIds = _trackIds(activeTracks);
            final userStatesStream =
                _watchUserStatesFor(dependencies, trackIds);

            return StreamBuilder<Map<int, TrackUserState>>(
              stream: userStatesStream,
              initialData: const {},
              builder: (context, stateSnapshot) {
                final userStates =
                    stateSnapshot.data ?? const <int, TrackUserState>{};

                return StreamBuilder<List<Track>>(
                  stream: _indexedTracksStream,
                  initialData: const [],
                  builder: (context, indexedSnapshot) {
                    return StreamBuilder<List<LibraryFolder>>(
                      stream: _foldersStream,
                      initialData: const [],
                      builder: (context, folderSnapshot) {
                        return StreamBuilder<PlayerState>(
                          stream: _pagePlayerStateStream,
                          initialData: dependencies.playerService.state,
                          builder: (context, playerSnapshot) {
                            final playerState =
                                playerSnapshot.data ?? const PlayerState.idle();

                            return _NavigationShell(
                              selectedPageIndex: _selectedPageIndex,
                              isSidebarCollapsed: _isSidebarCollapsed,
                              onPageSelected: _selectPage,
                              onToggleSidebarCollapsed: () {
                                setState(() {
                                  _isSidebarCollapsed = !_isSidebarCollapsed;
                                });
                              },
                              child: _buildHomeContent(
                                context,
                                dependencies,
                                playerState: playerState,
                                activeTracks: activeTracks,
                                totalIndexedTracks:
                                    indexedSnapshot.data?.length ?? 0,
                                userStates: userStates,
                                folders: folderSnapshot.data ?? const [],
                                trackLoadError: trackSnapshot.error ??
                                    indexedSnapshot.error,
                                folderLoadError: folderSnapshot.error,
                              ),
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

  void _ensureStreams(AppDependencies dependencies) {
    if (identical(_streamDependencies, dependencies)) {
      return;
    }

    _streamDependencies = dependencies;
    _activeTracksStream = dependencies.repositories.tracks
        .watchAllTracks(includeMissing: true)
        .asBroadcastStream();
    _indexedTracksStream = dependencies.repositories.tracks
        .watchAllTracks(
          includeMissing: true,
          includeDisabledFolders: true,
        )
        .asBroadcastStream();
    _foldersStream = dependencies.repositories.libraryFolders
        .watchFolders()
        .asBroadcastStream();
    _pagePlayerStateStream = dependencies.playerService.stateStream
        .distinct(_isSamePagePlayerState)
        .asBroadcastStream();
    _userStatesStream = null;
    _userStateTrackIds = const [];
    _clearVisibleTracksCache();
  }

  Stream<Map<int, TrackUserState>> _watchUserStatesFor(
    AppDependencies dependencies,
    List<int> trackIds,
  ) {
    if (_userStatesStream == null ||
        !_intListsEqual(_userStateTrackIds, trackIds)) {
      _userStateTrackIds = List.unmodifiable(trackIds);
      _userStatesStream = dependencies.repositories.trackUserState
          .watchTrackStatesByTrackIds(_userStateTrackIds);
    }
    return _userStatesStream!;
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
    switch (_selectedPageIndex) {
      case _wavePageIndex:
        return _HomeWavePage(
          playerState: playerState,
          playerService: dependencies.playerService,
          queueService: dependencies.playbackQueue,
          scanResult: _lastScanResult,
          scanError: _lastError,
          isScanning: _isScanning,
          onPageSelected: _selectPage,
          onAddFolder: () => _addMusicFolder(dependencies),
          onRescanLibrary: () => _rescanLibrary(dependencies),
        );
      case _myMusicPageIndex:
        final visibleTracks = _visibleTracksFor(
          activeTracks: activeTracks,
          userStates: userStates,
        );
        final missingCount = _missingCountFor(activeTracks);
        return _MyMusicPage(
          playerState: playerState,
          queueService: dependencies.playbackQueue,
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
            unawaited(
              dependencies.playbackQueue.playLibraryTrack(
                track: track,
                visibleTracks: visibleTracks,
              ),
            );
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
          onAddToPlaylist: (track) {
            unawaited(_addTrackToPlaylist(dependencies, track));
          },
          onEditTrack: (track) {
            unawaited(_editTrackMetadata(dependencies, track));
          },
          onSetCustomCover: (track) {
            unawaited(_setTrackCustomCover(dependencies, track));
          },
          onRemoveCustomCover: (track) {
            unawaited(_removeTrackCustomCover(dependencies, track));
          },
        );
      case _playlistsPageIndex:
        return _PlaylistsPage(
          playerState: playerState,
          queueService: dependencies.playbackQueue,
          playlistRepository: dependencies.repositories.playlists,
          activeTracks: activeTracks,
          selectedPlaylistId: _selectedPlaylistId,
          onSelectedPlaylistChanged: (playlistId) {
            setState(() {
              _selectedPlaylistId = playlistId;
            });
          },
          onAddToQueue: (track) {
            unawaited(dependencies.playbackQueue.addToQueue(track));
          },
        );
      default:
        return _SettingsPage(
          folders: folders,
          folderLoadError: folderLoadError,
          scanResult: _lastScanResult,
          scanError: _lastError,
          isScanning: _isScanning,
          isResettingLearningState: _isResettingLearningState,
          queueService: dependencies.playbackQueue,
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
          onResetLearningState: () {
            unawaited(_confirmAndResetLearningState(dependencies));
          },
        );
    }
  }

  List<Track> _visibleTracksFor({
    required List<Track> activeTracks,
    required Map<int, TrackUserState> userStates,
  }) {
    if (identical(_visibleTracksInput, activeTracks) &&
        identical(_visibleTracksUserStatesInput, userStates) &&
        _visibleTracksSearchQueryInput == _searchQuery &&
        _visibleTracksSortOptionInput == _sortOption &&
        _visibleTracksShowMissingInput == _showMissingTracks) {
      return _cachedVisibleTracks!;
    }

    final visibleTracks = buildVisibleLibraryTracks(
      tracks: activeTracks,
      searchQuery: _searchQuery,
      showMissingTracks: _showMissingTracks,
      sortOption: _sortOption,
      userStates: userStates,
    );
    _visibleTracksInput = activeTracks;
    _visibleTracksUserStatesInput = userStates;
    _visibleTracksSearchQueryInput = _searchQuery;
    _visibleTracksSortOptionInput = _sortOption;
    _visibleTracksShowMissingInput = _showMissingTracks;
    _cachedVisibleTracks = visibleTracks;
    return visibleTracks;
  }

  int _missingCountFor(List<Track> activeTracks) {
    if (identical(_missingCountInput, activeTracks) &&
        _cachedMissingCount != null) {
      return _cachedMissingCount!;
    }
    final missingCount = activeTracks.where((track) => track.isMissing).length;
    _missingCountInput = activeTracks;
    _cachedMissingCount = missingCount;
    return missingCount;
  }

  void _clearVisibleTracksCache() {
    _visibleTracksInput = null;
    _visibleTracksUserStatesInput = null;
    _visibleTracksSearchQueryInput = null;
    _visibleTracksSortOptionInput = null;
    _visibleTracksShowMissingInput = null;
    _cachedVisibleTracks = null;
    _missingCountInput = null;
    _cachedMissingCount = null;
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

  Future<void> _confirmAndResetLearningState(
    AppDependencies dependencies,
  ) async {
    if (_isResettingLearningState) {
      return;
    }

    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Сбросить историю и рекомендации?'),
          content: const Text(
            'Будут сброшены история прослушивания, лайки, дизлайки, пропуски, '
            'счетчики воспроизведений и веса рекомендаций.\n\n'
            'Треки, плейлисты, папки, обложки и аудиофайлы останутся на месте.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Сбросить'),
            ),
          ],
        );
      },
    );
    if (shouldReset != true || !mounted) {
      return;
    }

    setState(() {
      _isResettingLearningState = true;
    });

    try {
      await dependencies.repositories.resetLearningState();
      dependencies.playbackQueue.clearLearningStateSnapshot();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('История и рекомендации сброшены.')),
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnack(
        context,
        'Could not reset history and recommendations: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResettingLearningState = false;
        });
      }
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

  Future<void> _setTrackCustomCover(
    AppDependencies dependencies,
    Track track,
  ) async {
    final trackId = track.id;
    if (trackId == null) {
      return;
    }

    try {
      final artwork = await dependencies.customArtwork.pickCustomArtwork();
      if (artwork == null) {
        return;
      }
      await dependencies.repositories.tracks.updateCustomArtwork(
        trackId: trackId,
        path: artwork.path,
        hash: artwork.hash,
        mimeType: artwork.mimeType,
        updatedAt: DateTime.now(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated cover for "${track.displayTitle}".')),
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = error;
      });
      _showErrorSnack(context, 'Could not set cover: $error');
    }
  }

  Future<void> _removeTrackCustomCover(
    AppDependencies dependencies,
    Track track,
  ) async {
    final trackId = track.id;
    if (trackId == null) {
      return;
    }

    try {
      await dependencies.repositories.tracks.clearCustomArtwork(
        trackId: trackId,
        updatedAt: DateTime.now(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed custom cover for "${track.displayTitle}".'),
        ),
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = error;
      });
      _showErrorSnack(context, 'Could not remove custom cover: $error');
    }
  }

  Future<void> _addTrackToPlaylist(
    AppDependencies dependencies,
    Track track,
  ) async {
    final trackId = track.id;
    if (trackId == null) {
      return;
    }

    final selection = await showDialog<_AddTrackToPlaylistSelection>(
      context: context,
      builder: (context) => _AddTrackToPlaylistDialog(
        track: track,
        playlistRepository: dependencies.repositories.playlists,
      ),
    );
    if (selection == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    try {
      var playlistId = selection.playlistId;
      if (selection.createNew) {
        final data = await showDialog<_PlaylistFormData>(
          context: context,
          builder: (context) => const _PlaylistFormDialog.create(),
        );
        if (data == null) {
          return;
        }
        playlistId = await dependencies.repositories.playlists.createPlaylist(
          data.name,
          description: data.description,
        );
      }

      if (playlistId == null) {
        return;
      }

      await dependencies.repositories.playlists.addTrackToPlaylist(
        playlistId,
        trackId,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "${track.displayTitle}" to playlist.')),
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = error;
      });
      _showErrorSnack(context, 'Could not add track to playlist: $error');
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

final class _NavigationShell extends StatelessWidget {
  const _NavigationShell({
    required this.selectedPageIndex,
    required this.isSidebarCollapsed,
    required this.onPageSelected,
    required this.onToggleSidebarCollapsed,
    required this.child,
  });

  final int selectedPageIndex;
  final bool isSidebarCollapsed;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onToggleSidebarCollapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final forceCompact = constraints.maxWidth < 820;
        final isCompact = forceCompact || isSidebarCollapsed;
        return Row(
          children: [
            _NavigationSidebar(
              isCompact: isCompact,
              showCollapseToggle: !forceCompact,
              selectedPageIndex: selectedPageIndex,
              onToggleCollapsed: onToggleSidebarCollapsed,
              onPageSelected: onPageSelected,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                reverseDuration: const Duration(milliseconds: 140),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(0, 0.015),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: offset,
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey('page-$selectedPageIndex'),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

final class _NavigationSidebar extends StatelessWidget {
  const _NavigationSidebar({
    required this.isCompact,
    required this.showCollapseToggle,
    required this.selectedPageIndex,
    required this.onToggleCollapsed,
    required this.onPageSelected,
  });

  final bool isCompact;
  final bool showCollapseToggle;
  final int selectedPageIndex;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<int> onPageSelected;

  static const _destinations = [
    _NavigationDestinationData(
      id: 'wave',
      pageIndex: _wavePageIndex,
      label: 'Волна',
      icon: Icons.graphic_eq_outlined,
    ),
    _NavigationDestinationData(
      id: 'music',
      pageIndex: _myMusicPageIndex,
      label: 'Моя музыка',
      icon: Icons.library_music_outlined,
    ),
    _NavigationDestinationData(
      id: 'playlists',
      pageIndex: _playlistsPageIndex,
      label: 'Плейлисты',
      icon: Icons.queue_music_outlined,
    ),
    _NavigationDestinationData(
      id: 'settings',
      pageIndex: _settingsPageIndex,
      label: 'Настройки',
      icon: Icons.settings_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final width = isCompact ? 72.0 : 208.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: width,
      child: Material(
        color: colorScheme.surfaceContainerLowest,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 8 : 12,
                16,
                isCompact ? 8 : 12,
                16,
              ),
              child: Column(
                crossAxisAlignment: isCompact
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.stretch,
                children: [
                  if (showCollapseToggle) ...[
                    Align(
                      alignment:
                          isCompact ? Alignment.center : Alignment.centerRight,
                      child: Semantics(
                        label:
                            isCompact ? 'Expand sidebar' : 'Collapse sidebar',
                        button: true,
                        child: IconButton(
                          key: const ValueKey('sidebar-collapse-toggle'),
                          onPressed: onToggleCollapsed,
                          icon: Icon(
                            isCompact
                                ? Icons.keyboard_double_arrow_right_outlined
                                : Icons.keyboard_double_arrow_left_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final destination in _destinations) ...[
                    _NavigationSidebarItem(
                      destination: destination,
                      isCompact: isCompact,
                      selected: destination.pageIndex == selectedPageIndex,
                      onPressed: () => onPageSelected(destination.pageIndex),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _NavigationSidebarItem extends StatelessWidget {
  const _NavigationSidebarItem({
    required this.destination,
    required this.isCompact,
    required this.selected,
    required this.onPressed,
  });

  final _NavigationDestinationData destination;
  final bool isCompact;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final background = selected
        ? colorScheme.primaryContainer.withValues(alpha: 0.82)
        : Colors.transparent;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.38)
              : Colors.transparent,
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 0 : 12,
        vertical: 10,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showLabel = !isCompact && constraints.maxWidth >= 56;
          return Row(
            mainAxisAlignment:
                showLabel ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              if (selected)
                SizedBox(
                  key: ValueKey('active-nav-${destination.id}'),
                  width: 4,
                  height: 24,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              if (selected && showLabel) const SizedBox(width: 10),
              Icon(destination.icon, color: foreground),
              if (showLabel) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('nav-${destination.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: content,
        ),
      ),
    );
  }
}

final class _NavigationDestinationData {
  const _NavigationDestinationData({
    required this.id,
    required this.pageIndex,
    required this.label,
    required this.icon,
  });

  final String id;
  final int pageIndex;
  final String label;
  final IconData icon;
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
                  onOpenLibrary: () => onPageSelected(_myMusicPageIndex),
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
        const SliverToBoxAdapter(
          child: SizedBox(height: _bottomPlayerBarScrollPadding),
        ),
      ],
    );
  }
}

final class _MyMusicPage extends StatelessWidget {
  const _MyMusicPage({
    required this.playerState,
    required this.queueService,
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
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSortChanged,
    required this.onShowMissingChanged,
    required this.onPlayTrack,
    required this.onLikeTrack,
    required this.onDislikeTrack,
    required this.onAddToQueue,
    required this.onAddToPlaylist,
    required this.onEditTrack,
    required this.onSetCustomCover,
    required this.onRemoveCustomCover,
  });

  final PlayerState playerState;
  final PlaybackQueueService queueService;
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
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<LibraryTrackSortOption> onSortChanged;
  final ValueChanged<bool> onShowMissingChanged;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track> onLikeTrack;
  final ValueChanged<Track> onDislikeTrack;
  final ValueChanged<Track> onAddToQueue;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onEditTrack;
  final ValueChanged<Track> onSetCustomCover;
  final ValueChanged<Track> onRemoveCustomCover;

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
                ),
                const SizedBox(height: 22),
                Text(
                  'Track library',
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
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
                if (trackLoadError != null) ...[
                  const SizedBox(height: 24),
                  _InlineMessage(
                    message: 'Could not load tracks: $trackLoadError',
                    isError: true,
                  ),
                ] else if (visibleTracks.isEmpty && searchQuery.isEmpty) ...[
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
            onAddToPlaylist: onAddToPlaylist,
            onEditTrack: onEditTrack,
            onSetCustomCover: onSetCustomCover,
            onRemoveCustomCover: onRemoveCustomCover,
          ),
        const SliverToBoxAdapter(
          child: SizedBox(height: _bottomPlayerBarScrollPadding),
        ),
      ],
    );
  }
}

final class _PlaylistsPage extends StatelessWidget {
  const _PlaylistsPage({
    required this.playerState,
    required this.queueService,
    required this.playlistRepository,
    required this.activeTracks,
    required this.selectedPlaylistId,
    required this.onSelectedPlaylistChanged,
    required this.onAddToQueue,
  });

  final PlayerState playerState;
  final PlaybackQueueService queueService;
  final PlaylistRepository playlistRepository;
  final List<Track> activeTracks;
  final int? selectedPlaylistId;
  final ValueChanged<int?> onSelectedPlaylistChanged;
  final ValueChanged<Track> onAddToQueue;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                const _ShellHeader(
                  title: 'Плейлисты',
                  subtitle: 'Create, reorder, and play local playlists',
                ),
                const SizedBox(height: 22),
                StreamBuilder<QueueState>(
                  stream: queueService.stateStream,
                  initialData: queueService.state,
                  builder: (context, snapshot) {
                    final queueState = snapshot.data ?? QueueState();
                    if (queueState.manualQueue.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 18),
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
                _PlaylistsContent(
                  playlistRepository: playlistRepository,
                  queueService: queueService,
                  selectedPlaylistId: selectedPlaylistId,
                  activeTracks: activeTracks,
                  currentTrack: playerState.currentTrack,
                  onSelectedPlaylistChanged: onSelectedPlaylistChanged,
                  onAddToQueue: onAddToQueue,
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: _bottomPlayerBarScrollPadding),
        ),
      ],
    );
  }
}

final class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.folders,
    required this.folderLoadError,
    required this.scanResult,
    required this.scanError,
    required this.isScanning,
    required this.isResettingLearningState,
    required this.queueService,
    required this.onAddFolder,
    required this.onRescanLibrary,
    required this.onRescanFolder,
    required this.onToggleEnabled,
    required this.onRemoveFolder,
    required this.onResetLearningState,
  });

  final List<LibraryFolder> folders;
  final Object? folderLoadError;
  final LibraryScanResult? scanResult;
  final Object? scanError;
  final bool isScanning;
  final bool isResettingLearningState;
  final PlaybackQueueService queueService;
  final VoidCallback onAddFolder;
  final VoidCallback onRescanLibrary;
  final ValueChanged<LibraryFolder> onRescanFolder;
  final ValueChanged<LibraryFolder> onToggleEnabled;
  final ValueChanged<LibraryFolder> onRemoveFolder;
  final VoidCallback onResetLearningState;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                const _ShellHeader(
                  title: 'Настройки',
                  subtitle: 'Library management and development tools',
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
                _SettingsSection(
                  title: 'Reset',
                  child: _ResetActions(
                    isResettingLearningState: isResettingLearningState,
                    onResetLearningState: onResetLearningState,
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
        const SliverToBoxAdapter(
          child: SizedBox(height: _bottomPlayerBarScrollPadding),
        ),
      ],
    );
  }
}

final class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

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
      ],
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
              'Liquid Wave UI v1. Custom backgrounds, GIFs, previous-track '
              'history, playlist import/export, and server sync are '
              'intentionally not implemented in this iteration.',
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

final class _ResetActions extends StatelessWidget {
  const _ResetActions({
    required this.isResettingLearningState,
    required this.onResetLearningState,
  });

  final bool isResettingLearningState;
  final VoidCallback onResetLearningState;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Сбрасывает только историю, лайки, дизлайки и локальные веса '
          'рекомендаций. Музыка, папки и плейлисты не удаляются.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: isResettingLearningState ? null : onResetLearningState,
              icon: const Icon(Icons.restart_alt_outlined),
              label: const Text('Сбросить историю и рекомендации'),
            ),
            if (isResettingLearningState)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        // TODO: Add a stronger full library database reset flow separately.
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

final class _PlaylistsContent extends StatelessWidget {
  const _PlaylistsContent({
    required this.playlistRepository,
    required this.queueService,
    required this.selectedPlaylistId,
    required this.activeTracks,
    required this.currentTrack,
    required this.onSelectedPlaylistChanged,
    required this.onAddToQueue,
  });

  final PlaylistRepository playlistRepository;
  final PlaybackQueueService queueService;
  final int? selectedPlaylistId;
  final List<Track> activeTracks;
  final Track? currentTrack;
  final ValueChanged<int?> onSelectedPlaylistChanged;
  final ValueChanged<Track> onAddToQueue;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PlaylistWithCount>>(
      stream: playlistRepository.watchPlaylists(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InlineMessage(
            message: 'Could not load playlists: ${snapshot.error}',
            isError: true,
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final playlists = snapshot.data!;
        final playlistId = selectedPlaylistId;
        if (playlistId == null) {
          return _PlaylistListView(
            playlists: playlists,
            playlistRepository: playlistRepository,
            onOpenPlaylist: onSelectedPlaylistChanged,
          );
        }

        final selected = _findPlaylist(playlists, playlistId);
        if (selected == null) {
          return _PlaylistNotFoundCard(
            onBack: () => onSelectedPlaylistChanged(null),
          );
        }

        return StreamBuilder<List<PlaylistEntry>>(
          stream: playlistRepository.watchPlaylistTracks(playlistId),
          initialData: const [],
          builder: (context, entrySnapshot) {
            if (entrySnapshot.hasError) {
              return _InlineMessage(
                message: 'Could not load playlist tracks: '
                    '${entrySnapshot.error}',
                isError: true,
              );
            }

            return _PlaylistDetailsView(
              playlist: selected.playlist,
              entries: entrySnapshot.data ?? const [],
              playlistRepository: playlistRepository,
              queueService: queueService,
              activeTracks: activeTracks,
              currentTrack: currentTrack,
              onBack: () => onSelectedPlaylistChanged(null),
              onAddToQueue: onAddToQueue,
            );
          },
        );
      },
    );
  }

  static PlaylistWithCount? _findPlaylist(
    List<PlaylistWithCount> playlists,
    int playlistId,
  ) {
    for (final playlist in playlists) {
      if (playlist.id == playlistId) {
        return playlist;
      }
    }
    return null;
  }
}

final class _PlaylistListView extends StatelessWidget {
  const _PlaylistListView({
    required this.playlists,
    required this.playlistRepository,
    required this.onOpenPlaylist,
  });

  final List<PlaylistWithCount> playlists;
  final PlaylistRepository playlistRepository;
  final ValueChanged<int?> onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () {
              unawaited(_createPlaylist(context, playlistRepository));
            },
            icon: const Icon(Icons.playlist_add_outlined),
            label: const Text('Создать плейлист'),
          ),
        ),
        const SizedBox(height: 14),
        if (playlists.isEmpty)
          const _InlineMessage(message: 'No playlists yet.')
        else
          for (final playlist in playlists) ...[
            _PlaylistListRow(
              playlist: playlist,
              playlistRepository: playlistRepository,
              onOpen: () => onOpenPlaylist(playlist.id),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

final class _PlaylistListRow extends StatelessWidget {
  const _PlaylistListRow({
    required this.playlist,
    required this.playlistRepository,
    required this.onOpen,
  });

  final PlaylistWithCount playlist;
  final PlaylistRepository playlistRepository;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final description = playlist.description?.trim();
    final dateLabel = _shortDateTimeLabel(playlist.updatedAt);

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SizedBox.square(
                  dimension: 44,
                  child: Icon(
                    Icons.queue_music_outlined,
                    color: colorScheme.primary,
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
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        _trackCountLabel(playlist.trackCount),
                        'Updated $dateLabel',
                        if (description != null && description.isNotEmpty)
                          description,
                      ].join(' · '),
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
              IconButton(
                tooltip: 'Open playlist',
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new_outlined),
              ),
              PopupMenuButton<_PlaylistListAction>(
                tooltip: 'Playlist actions',
                onSelected: (action) {
                  switch (action) {
                    case _PlaylistListAction.rename:
                      unawaited(_renamePlaylist(context, playlistRepository));
                    case _PlaylistListAction.delete:
                      unawaited(_deletePlaylist(context, playlistRepository));
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _PlaylistListAction.rename,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Rename'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _PlaylistListAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renamePlaylist(
    BuildContext context,
    PlaylistRepository repository,
  ) async {
    final playlistId = playlist.id;
    if (playlistId == null) {
      return;
    }

    final data = await showDialog<_PlaylistFormData>(
      context: context,
      builder: (context) => _PlaylistFormDialog.rename(
        initialName: playlist.name,
      ),
    );
    if (data == null) {
      return;
    }

    try {
      await repository.renamePlaylist(playlistId, data.name);
    } on Object catch (error) {
      if (context.mounted) {
        _showErrorSnack(context, 'Could not rename playlist: $error');
      }
    }
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    PlaylistRepository repository,
  ) async {
    final playlistId = playlist.id;
    if (playlistId == null) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete playlist?'),
          content: const Text(
            'This removes only the local playlist. Tracks and audio files stay '
            'in your library and on disk.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) {
      return;
    }

    try {
      await repository.deletePlaylist(playlistId);
    } on Object catch (error) {
      if (context.mounted) {
        _showErrorSnack(context, 'Could not delete playlist: $error');
      }
    }
  }
}

final class _PlaylistDetailsView extends StatelessWidget {
  const _PlaylistDetailsView({
    required this.playlist,
    required this.entries,
    required this.playlistRepository,
    required this.queueService,
    required this.activeTracks,
    required this.currentTrack,
    required this.onBack,
    required this.onAddToQueue,
  });

  final Playlist playlist;
  final List<PlaylistEntry> entries;
  final PlaylistRepository playlistRepository;
  final PlaybackQueueService queueService;
  final List<Track> activeTracks;
  final Track? currentTrack;
  final VoidCallback onBack;
  final ValueChanged<Track> onAddToQueue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final playableCount = entries.where((entry) => entry.isPlayable).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_outlined),
            label: const Text('Back to playlists'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          '${_trackCountLabel(entries.length)} · $playableCount playable',
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: playlist.id == null
                  ? null
                  : () {
                      unawaited(_showAddTracksDialog(context));
                    },
              icon: const Icon(Icons.playlist_add_outlined),
              label: const Text('Add tracks'),
            ),
            FilledButton.icon(
              onPressed: playableCount == 0
                  ? null
                  : () {
                      unawaited(_addPlaylistToQueue(context));
                    },
              icon: const Icon(Icons.queue_music_outlined),
              label: const Text('Добавить в очередь'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (entries.isEmpty)
          const _InlineMessage(message: 'This playlist is empty.')
        else
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final elevation =
                      Tween<double>(begin: 0, end: 8).evaluate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ));
                  return Material(
                    color: Colors.transparent,
                    elevation: elevation,
                    borderRadius: BorderRadius.circular(20),
                    child: child,
                  );
                },
                child: child,
              );
            },
            onReorder: (oldIndex, newIndex) {
              unawaited(_reorderPlaylistEntry(context, oldIndex, newIndex));
            },
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Padding(
                key: ValueKey('playlist-entry-${entry.playlistId}-'
                    '${entry.trackId}'),
                padding: const EdgeInsets.only(bottom: 8),
                child: _PlaylistEntryTile(
                  entry: entry,
                  isCurrent: _isSameTrack(entry.track, currentTrack),
                  dragHandle: ReorderableDragStartListener(
                    index: index,
                    child: const Tooltip(
                      message: 'Reorder track',
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.drag_handle_outlined),
                      ),
                    ),
                  ),
                  onPlay: entry.isPlayable
                      ? () {
                          unawaited(_playPlaylistFromEntry(entry));
                        }
                      : null,
                  onAddToQueue:
                      entry.isPlayable ? () => onAddToQueue(entry.track) : null,
                  onRemove: () {
                    unawaited(
                      playlistRepository.removeTrackFromPlaylist(
                        entry.playlistId,
                        entry.trackId,
                      ),
                    );
                  },
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _reorderPlaylistEntry(
    BuildContext context,
    int oldIndex,
    int newIndex,
  ) async {
    final playlistId = playlist.id;
    if (playlistId == null || oldIndex < 0 || oldIndex >= entries.length) {
      return;
    }

    final adjustedNewIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;
    if (adjustedNewIndex < 0 ||
        adjustedNewIndex >= entries.length ||
        adjustedNewIndex == oldIndex) {
      return;
    }

    final reorderedEntries = entries.toList(growable: true);
    final moved = reorderedEntries.removeAt(oldIndex);
    reorderedEntries.insert(adjustedNewIndex, moved);
    final updatedEntries = [
      for (var index = 0; index < reorderedEntries.length; index++)
        _withPlaylistPosition(reorderedEntries[index], index),
    ];

    try {
      await playlistRepository.reorderPlaylistTracks(
        playlistId: playlistId,
        trackIds: [
          for (final entry in updatedEntries) entry.trackId,
        ],
      );
      await queueService.refreshPlaylistContextOrder(
        playlistId: playlistId,
        entries: updatedEntries,
      );
    } on Object catch (error) {
      if (context.mounted) {
        _showErrorSnack(context, 'Could not reorder playlist: $error');
      }
    }
  }

  PlaylistEntry _withPlaylistPosition(PlaylistEntry entry, int position) {
    return PlaylistEntry(
      playlistId: entry.playlistId,
      trackId: entry.trackId,
      position: position,
      addedAt: entry.addedAt,
      track: entry.track,
      unavailableReason: entry.unavailableReason,
    );
  }

  Future<void> _playPlaylistFromEntry(PlaylistEntry entry) async {
    final playlistId = playlist.id;
    if (playlistId == null) {
      return;
    }

    await queueService.playPlaylist(
      playlistId: playlistId,
      playlistName: playlist.name,
      entries: entries,
      startTrackId: entry.trackId,
    );
  }

  Future<void> _showAddTracksDialog(BuildContext context) async {
    final playlistId = playlist.id;
    if (playlistId == null) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => _AddTracksToPlaylistDialog(
        playlistId: playlistId,
        playlistRepository: playlistRepository,
        tracks: activeTracks,
        existingTrackIds: {
          for (final entry in entries) entry.trackId,
        },
      ),
    );
  }

  Future<void> _addPlaylistToQueue(BuildContext context) async {
    final queuedCount = await addPlaylistEntriesToQueue(
      entries: entries,
      addToQueue: queueService.addToQueue,
    );
    if (!context.mounted) {
      return;
    }

    final message = queuedCount == 0
        ? 'No playable tracks in this playlist.'
        : 'Added $queuedCount tracks to queue.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

final class _PlaylistEntryTile extends StatelessWidget {
  const _PlaylistEntryTile({
    required this.entry,
    required this.isCurrent,
    required this.dragHandle,
    required this.onPlay,
    required this.onAddToQueue,
    required this.onRemove,
  });

  final PlaylistEntry entry;
  final bool isCurrent;
  final Widget dragHandle;
  final VoidCallback? onPlay;
  final VoidCallback? onAddToQueue;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final unavailableReason = entry.unavailableReason;
    final isUnavailable = unavailableReason != null;
    final subtitle = isUnavailable
        ? '$unavailableReason - ${buildTrackMetadataSubtitle(entry.track)}'
        : buildTrackMetadataSubtitle(entry.track);
    final rowColor = isCurrent
        ? Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.16),
            colorScheme.surfaceContainer,
          )
        : colorScheme.surfaceContainerLow;
    final leadingColor = isUnavailable
        ? colorScheme.error
        : isCurrent
            ? colorScheme.tertiary
            : colorScheme.onSurfaceVariant;

    return Material(
      color: rowColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  TrackArtwork(
                    track: entry.track,
                    size: 44,
                    borderRadius: 14,
                  ),
                  if (isUnavailable || isCurrent)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.42),
                        child: SizedBox.square(
                          dimension: 44,
                          child: Icon(
                            isUnavailable
                                ? Icons.report_problem_outlined
                                : Icons.graphic_eq_outlined,
                            size: 22,
                            color: leadingColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.track.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: isUnavailable ? colorScheme.error : null,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: isUnavailable
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              dragHandle,
              const SizedBox(width: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Add to queue',
                      onPressed: onAddToQueue,
                      icon: const Icon(Icons.queue_music_outlined),
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      tooltip: 'Remove from playlist',
                      onPressed: onRemove,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      tooltip: isCurrent ? 'Playing' : 'Play',
                      onPressed: onPlay,
                      icon: Icon(
                        isCurrent
                            ? Icons.graphic_eq_outlined
                            : Icons.play_arrow_outlined,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _PlaylistNotFoundCard extends StatelessWidget {
  const _PlaylistNotFoundCard({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Playlist not found.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_outlined),
              label: const Text('Back to playlists'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PlaylistListAction { rename, delete }

Future<void> _createPlaylist(
  BuildContext context,
  PlaylistRepository repository,
) async {
  final data = await showDialog<_PlaylistFormData>(
    context: context,
    builder: (context) => const _PlaylistFormDialog.create(),
  );
  if (data == null) {
    return;
  }

  try {
    await repository.createPlaylist(
      data.name,
      description: data.description,
    );
  } on Object catch (error) {
    if (context.mounted) {
      _showErrorSnack(context, 'Could not create playlist: $error');
    }
  }
}

final class _AddTrackToPlaylistSelection {
  const _AddTrackToPlaylistSelection.playlist(this.playlistId)
      : createNew = false;

  const _AddTrackToPlaylistSelection.createNew()
      : playlistId = null,
        createNew = true;

  final int? playlistId;
  final bool createNew;
}

final class _AddTrackToPlaylistDialog extends StatelessWidget {
  const _AddTrackToPlaylistDialog({
    required this.track,
    required this.playlistRepository,
  });

  final Track track;
  final PlaylistRepository playlistRepository;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add to playlist'),
      content: SizedBox(
        width: 420,
        child: StreamBuilder<List<PlaylistWithCount>>(
          stream: playlistRepository.watchPlaylists(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Could not load playlists: ${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final playlists = snapshot.data!;
            if (playlists.isEmpty) {
              return Text(
                'No playlists yet. Create one for "${track.displayTitle}".',
              );
            }

            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return ListTile(
                    leading: const Icon(Icons.queue_music_outlined),
                    title: Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_trackCountLabel(playlist.trackCount)),
                    onTap: playlist.id == null
                        ? null
                        : () {
                            Navigator.of(context).pop(
                              _AddTrackToPlaylistSelection.playlist(
                                playlist.id!,
                              ),
                            );
                          },
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop(
              const _AddTrackToPlaylistSelection.createNew(),
            );
          },
          icon: const Icon(Icons.playlist_add_outlined),
          label: const Text('Create new'),
        ),
      ],
    );
  }
}

final class _AddTracksToPlaylistDialog extends StatefulWidget {
  const _AddTracksToPlaylistDialog({
    required this.playlistId,
    required this.playlistRepository,
    required this.tracks,
    required this.existingTrackIds,
  });

  final int playlistId;
  final PlaylistRepository playlistRepository;
  final List<Track> tracks;
  final Set<int> existingTrackIds;

  @override
  State<_AddTracksToPlaylistDialog> createState() =>
      _AddTracksToPlaylistDialogState();
}

final class _AddTracksToPlaylistDialogState
    extends State<_AddTracksToPlaylistDialog> {
  late final TextEditingController _searchController;
  late final Set<int> _addedTrackIds;
  final Set<int> _savingTrackIds = {};
  String _searchQuery = '';
  Object? _error;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _addedTrackIds = {...widget.existingTrackIds};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredTracks = _filteredTracks();

    return AlertDialog(
      title: const Text('Add tracks'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search tracks',
                prefixIcon: const Icon(Icons.search_outlined),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        icon: const Icon(Icons.close_outlined),
                      ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              _InlineMessage(
                message: 'Could not add track: $_error',
                isError: true,
              ),
            ],
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: filteredTracks.isEmpty
                  ? const _InlineMessage(message: 'No tracks match.')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredTracks.length,
                      itemBuilder: (context, index) {
                        final track = filteredTracks[index];
                        final trackId = track.id!;
                        final isAdded = _addedTrackIds.contains(trackId);
                        final isSaving = _savingTrackIds.contains(trackId);
                        return ListTile(
                          leading: Stack(
                            alignment: Alignment.center,
                            children: [
                              TrackArtwork(
                                track: track,
                                size: 40,
                                borderRadius: 12,
                              ),
                              if (isAdded)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: ColoredBox(
                                    color: Colors.black.withValues(alpha: 0.42),
                                    child: const SizedBox.square(
                                      dimension: 40,
                                      child: Icon(Icons.check_circle_outline),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            track.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            buildTrackMetadataSubtitle(track),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: TextButton(
                            onPressed: isAdded || isSaving
                                ? null
                                : () {
                                    unawaited(_addTrack(trackId));
                                  },
                            child: Text(isAdded ? 'Added' : 'Add'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  List<Track> _filteredTracks() {
    final query = _searchQuery.trim().toLowerCase();
    final tracks = widget.tracks
        .where((track) => track.id != null && !track.isMissing)
        .where((track) {
      if (query.isEmpty) {
        return true;
      }
      return track.displayTitle.toLowerCase().contains(query) ||
          (track.artist ?? '').toLowerCase().contains(query);
    }).toList(growable: false);
    return tracks;
  }

  Future<void> _addTrack(int trackId) async {
    setState(() {
      _savingTrackIds.add(trackId);
      _error = null;
    });
    try {
      await widget.playlistRepository.addTrackToPlaylist(
        widget.playlistId,
        trackId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _addedTrackIds.add(trackId);
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _savingTrackIds.remove(trackId);
        });
      }
    }
  }
}

final class _PlaylistFormData {
  const _PlaylistFormData({
    required this.name,
    this.description,
  });

  final String name;
  final String? description;
}

final class _PlaylistFormDialog extends StatefulWidget {
  const _PlaylistFormDialog.create()
      : title = 'Создать плейлист',
        submitLabel = 'Create',
        initialName = '',
        initialDescription = '',
        allowDescription = true;

  const _PlaylistFormDialog.rename({
    required this.initialName,
  })  : title = 'Rename playlist',
        submitLabel = 'Rename',
        initialDescription = '',
        allowDescription = false;

  final String title;
  final String submitLabel;
  final String initialName;
  final String initialDescription;
  final bool allowDescription;

  @override
  State<_PlaylistFormDialog> createState() => _PlaylistFormDialogState();
}

final class _PlaylistFormDialogState extends State<_PlaylistFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (widget.allowDescription) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _error = 'Name is required';
      });
      return;
    }

    final description = _descriptionController.text.trim();
    Navigator.of(context).pop(
      _PlaylistFormData(
        name: name,
        description: description.isEmpty ? null : description,
      ),
    );
  }
}

String _trackCountLabel(int count) {
  return count == 1 ? '1 track' : '$count tracks';
}

String _shortDateTimeLabel(DateTime value) {
  return value.toLocal().toString().split('.').first;
}

void _showErrorSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
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
    required this.onAddToPlaylist,
    required this.onEditTrack,
    required this.onSetCustomCover,
    required this.onRemoveCustomCover,
  });

  final List<Track> tracks;
  final Map<int, TrackUserState> userStates;
  final Track? currentTrack;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track> onLikeTrack;
  final ValueChanged<Track> onDislikeTrack;
  final ValueChanged<Track> onAddToQueue;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onEditTrack;
  final ValueChanged<Track> onSetCustomCover;
  final ValueChanged<Track> onRemoveCustomCover;

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
                onAddToPlaylist:
                    track.id == null ? null : () => onAddToPlaylist(track),
                onEdit: () => onEditTrack(track),
                onSetCustomCover:
                    track.id == null ? null : () => onSetCustomCover(track),
                onRemoveCustomCover: track.id == null || !track.hasCustomArtwork
                    ? null
                    : () => onRemoveCustomCover(track),
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

bool _isSameNullableTrack(Track? left, Track? right) {
  if (left == null || right == null) {
    return left == right;
  }
  return _isSameTrack(left, right);
}

bool _isSamePagePlayerState(PlayerState left, PlayerState right) {
  return _isSameNullableTrack(left.currentTrack, right.currentTrack) &&
      left.isPlaying == right.isPlaying &&
      left.status == right.status &&
      left.errorMessage == right.errorMessage;
}

List<int> _trackIds(List<Track> tracks) {
  return [
    for (final track in tracks)
      if (track.id != null) track.id!,
  ];
}

bool _intListsEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
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
                      final waveTrack =
                          playerState.currentTrack ?? queueState.currentTrack;
                      if (!queueState.isWaveCurrentSource) {
                        unawaited(queueService.playSmartNext());
                        return;
                      }
                      if (playerState.isPlaying) {
                        unawaited(playerService.pause());
                        return;
                      }
                      if (waveTrack != null) {
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
    final track = queueState.isWaveCurrentSource
        ? playerState.currentTrack ?? queueState.currentTrack
        : null;
    final hasTrack = track != null;
    final isBusy = queueState.isChoosingNext ||
        playerState.status == PlayerPlaybackStatus.loading;
    final launchIcon = queueState.isWaveCurrentSource && playerState.isPlaying
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
                      isWaveCurrentSource: queueState.isWaveCurrentSource,
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
    required this.isWaveCurrentSource,
    required this.isChoosingNext,
  });

  final WaveMode mode;
  final bool isWaveCurrentSource;
  final bool isChoosingNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = isChoosingNext
        ? 'Choosing'
        : isWaveCurrentSource
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
              isWaveCurrentSource
                  ? Icons.graphic_eq_outlined
                  : Icons.waves_outlined,
              size: 16,
              color: isWaveCurrentSource
                  ? colorScheme.tertiary
                  : colorScheme.primary,
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
                track?.displayTitle ?? 'No track playing',
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
            tooltip: 'Shuffle playlist',
            onPressed: canUseShuffle ? onShuffle : null,
            icon: const Icon(Icons.shuffle_outlined),
          )
        : IconButton.outlined(
            tooltip: 'Shuffle playlist',
            onPressed: canUseShuffle ? onShuffle : null,
            icon: const Icon(Icons.shuffle_outlined),
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          tooltip: 'Previous',
          onPressed: canGoPrevious ? onPrevious : null,
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
        _BottomVolumeControl(
          volume: volume,
          showSlider: showVolumeSlider,
          onToggleMute: onToggleMute,
          onChanged: onVolumeChanged,
        ),
        const SizedBox(width: 8),
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

final class _BottomVolumeControl extends StatefulWidget {
  const _BottomVolumeControl({
    required this.volume,
    required this.showSlider,
    required this.onToggleMute,
    required this.onChanged,
  });

  final double volume;
  final bool showSlider;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onChanged;

  @override
  State<_BottomVolumeControl> createState() => _BottomVolumeControlState();
}

final class _BottomVolumeControlState extends State<_BottomVolumeControl> {
  static const double _popupWidth = 44;
  static const double _popupHeight = 154;
  static const double _popupGap = 3;

  OverlayEntry? _overlayEntry;
  Timer? _hideOverlayTimer;
  Rect? _buttonOverlayRect;
  bool _isButtonHovered = false;
  bool _isPopupHovered = false;
  bool _isPopupDragging = false;

  @override
  void didUpdateWidget(_BottomVolumeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showSlider) {
      _hideOverlayNow();
      return;
    }
    _scheduleOverlayRebuild();
  }

  @override
  void dispose() {
    _hideOverlayTimer?.cancel();
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedVolume = _normalizedVolumeForDisplay(widget.volume);
    final volumeIcon = _volumeIcon(normalizedVolume);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => _handleButtonHoverChanged(isHovered: true),
          onExit: (_) => _handleButtonHoverChanged(isHovered: false),
          child: IconButton(
            key: const ValueKey('bottom-player-volume-button'),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            tooltip: widget.showSlider
                ? (normalizedVolume <= 0 ? 'Unmute' : 'Mute')
                : null,
            onPressed: widget.onToggleMute,
            icon: Icon(volumeIcon, size: 20),
          ),
        ),
        if (widget.showSlider) ...[
          const SizedBox(width: 4),
          SizedBox(
            width: 140,
            child: _VolumeSliderTheme(
              child: Slider(
                key: const ValueKey('bottom-player-volume-slider'),
                value: normalizedVolume,
                min: 0,
                max: 1,
                onChanged: widget.onChanged,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _handleButtonHoverChanged({required bool isHovered}) {
    _isButtonHovered = isHovered;
    if (isHovered) {
      _hideOverlayTimer?.cancel();
      _showOverlay();
      return;
    }

    _scheduleOverlayHide();
  }

  void _handlePopupHoverChanged({required bool isHovered}) {
    _isPopupHovered = isHovered;
    if (isHovered) {
      _hideOverlayTimer?.cancel();
      return;
    }

    _scheduleOverlayHide();
  }

  void _showOverlay() {
    if (widget.showSlider || _overlayEntry != null) {
      return;
    }
    if (!_updateButtonOverlayRect()) {
      return;
    }

    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(builder: _buildOverlay);
    overlay.insert(_overlayEntry!);
  }

  Widget _buildOverlay(BuildContext context) {
    final normalizedVolume = _normalizedVolumeForDisplay(widget.volume);
    final overlaySize = MediaQuery.sizeOf(context);
    final buttonRect = _buttonOverlayRect;
    if (buttonRect == null) {
      return const SizedBox.shrink();
    }

    final left = (buttonRect.center.dx - (_popupWidth / 2))
        .clamp(8.0, overlaySize.width - _popupWidth - 8)
        .toDouble();
    final top = (buttonRect.top - _popupHeight - _popupGap)
        .clamp(8.0, overlaySize.height - _popupHeight - 8)
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      child: SizedBox(
        width: _popupWidth,
        height: _popupHeight,
        child: MouseRegion(
          onEnter: (_) => _handlePopupHoverChanged(isHovered: true),
          onExit: (_) => _handlePopupHoverChanged(isHovered: false),
          child: _VolumePopupSlider(
            value: normalizedVolume,
            onChanged: widget.onChanged,
            onChangeStart: (_) {
              _isPopupDragging = true;
              _hideOverlayTimer?.cancel();
            },
            onChangeEnd: (_) {
              _isPopupDragging = false;
              _scheduleOverlayHide();
            },
          ),
        ),
      ),
    );
  }

  void _scheduleOverlayHide() {
    _hideOverlayTimer?.cancel();
    _hideOverlayTimer = Timer(const Duration(milliseconds: 140), () {
      if (_isButtonHovered || _isPopupHovered || _isPopupDragging) {
        return;
      }
      _hideOverlayNow();
    });
  }

  void _hideOverlayNow() {
    _hideOverlayTimer?.cancel();
    _hideOverlayTimer = null;
    _isPopupHovered = false;
    _isPopupDragging = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _scheduleOverlayRebuild() {
    if (_overlayEntry == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _updateButtonOverlayRect();
      _overlayEntry?.markNeedsBuild();
    });
  }

  bool _updateButtonOverlayRect() {
    final renderBox = context.findRenderObject();
    final overlayRenderBox = Overlay.of(context).context.findRenderObject();
    if (renderBox is! RenderBox ||
        overlayRenderBox is! RenderBox ||
        !renderBox.attached ||
        !overlayRenderBox.attached) {
      return false;
    }

    final topLeft = renderBox.localToGlobal(
      Offset.zero,
      ancestor: overlayRenderBox,
    );
    _buttonOverlayRect = topLeft & renderBox.size;
    return true;
  }
}

final class _VolumePopupSlider extends StatelessWidget {
  const _VolumePopupSlider({
    required this.value,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Material(
        key: const ValueKey('bottom-player-volume-popup'),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.94),
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.32),
            ),
          ),
          child: SizedBox(
            width: 36,
            height: 144,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: RotatedBox(
                quarterTurns: -1,
                child: _VolumeSliderTheme(
                  child: Slider(
                    key: const ValueKey('bottom-player-volume-popup-slider'),
                    value: value,
                    min: 0,
                    max: 1,
                    onChanged: onChanged,
                    onChangeStart: onChangeStart,
                    onChangeEnd: onChangeEnd,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _VolumeSliderTheme extends StatelessWidget {
  const _VolumeSliderTheme({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2.5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      ),
      child: child,
    );
  }
}

String _summarySubtitle(Track? track, PlaybackContext? playbackContext) {
  if (playbackContext != null && playbackContext.isPlaylist) {
    final name = playbackContext.playlistName?.trim();
    if (name != null && name.isNotEmpty) {
      return 'Playing from: $name';
    }
  }
  if (playbackContext != null && playbackContext.isLibrary) {
    return 'Playing from: All Tracks';
  }
  return _artistLabel(track);
}

String _repeatTooltip(PlaybackRepeatMode mode, PlaybackSource source) {
  final listName = source == PlaybackSource.library ? 'library' : 'playlist';
  return switch (mode) {
    PlaybackRepeatMode.none => 'No repeat',
    PlaybackRepeatMode.playlist => 'Repeat $listName',
    PlaybackRepeatMode.track => 'Repeat track',
  };
}

IconData _repeatIcon(PlaybackRepeatMode mode) {
  return switch (mode) {
    PlaybackRepeatMode.none => Icons.repeat,
    PlaybackRepeatMode.playlist => Icons.repeat,
    PlaybackRepeatMode.track => Icons.repeat_one,
  };
}

IconData _volumeIcon(double volume) {
  if (volume <= 0) {
    return Icons.volume_off_outlined;
  }
  if (volume < 0.5) {
    return Icons.volume_down_outlined;
  }
  return Icons.volume_up_outlined;
}

double _normalizedVolumeForDisplay(double volume) {
  if (volume.isNaN) {
    return 1;
  }
  if (volume == double.infinity) {
    return 1;
  }
  if (volume == double.negativeInfinity) {
    return 0;
  }
  return volume.clamp(0.0, 1.0).toDouble();
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

enum _TrackRowAction { setCover, removeCustomCover }

final class _TrackListTile extends StatelessWidget {
  const _TrackListTile({
    required this.track,
    required this.userState,
    required this.isCurrent,
    required this.onTap,
    required this.onLike,
    required this.onDislike,
    required this.onAddToQueue,
    required this.onAddToPlaylist,
    required this.onEdit,
    required this.onSetCustomCover,
    required this.onRemoveCustomCover,
  });

  final Track track;
  final TrackUserState? userState;
  final bool isCurrent;
  final VoidCallback? onTap;
  final VoidCallback onLike;
  final VoidCallback onDislike;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback onEdit;
  final VoidCallback? onSetCustomCover;
  final VoidCallback? onRemoveCustomCover;

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
            tooltip: 'Add to playlist',
            onPressed: onAddToPlaylist,
            icon: const Icon(Icons.playlist_add_outlined),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: 'Edit metadata',
            onPressed: track.id == null ? null : onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          const SizedBox(width: 2),
          PopupMenuButton<_TrackRowAction>(
            tooltip: 'Track actions',
            enabled: track.id != null,
            icon: const Icon(Icons.more_horiz_outlined),
            onSelected: (action) {
              switch (action) {
                case _TrackRowAction.setCover:
                  onSetCustomCover?.call();
                case _TrackRowAction.removeCustomCover:
                  onRemoveCustomCover?.call();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _TrackRowAction.setCover,
                child: ListTile(
                  leading: Icon(Icons.image_outlined),
                  title: Text('Set cover'),
                ),
              ),
              if (track.hasCustomArtwork)
                const PopupMenuItem(
                  value: _TrackRowAction.removeCustomCover,
                  child: ListTile(
                    leading: Icon(Icons.hide_image_outlined),
                    title: Text('Remove custom cover'),
                  ),
                ),
            ],
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
              Stack(
                alignment: Alignment.center,
                children: [
                  TrackArtwork(
                    track: track,
                    size: 44,
                    borderRadius: 14,
                  ),
                  if (isMissing || isCurrent)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.42),
                        child: SizedBox.square(
                          dimension: 44,
                          child: Icon(
                            isMissing
                                ? Icons.report_problem_outlined
                                : Icons.graphic_eq_outlined,
                            size: 22,
                            color: leadingColor,
                          ),
                        ),
                      ),
                    ),
                ],
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
