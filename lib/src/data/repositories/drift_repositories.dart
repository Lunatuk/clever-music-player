import 'package:drift/drift.dart';

import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../drift/app_database.dart';
import '../drift/drift_mappers.dart';
import 'drift_external_track_repository.dart';
import 'drift_downloaded_asset_repository.dart';
import 'drift_remote_library_repository.dart';
import 'drift_download_job_repository.dart';

final class DriftRepositories implements AppRepositories {
  DriftRepositories(AppDatabase database)
      : _database = database,
        libraryFolders = DriftLibraryRepository(database),
        tracks = DriftTrackRepository(database),
        externalTracks = DriftExternalTrackRepository(database),
        downloadedAssets = DriftDownloadedAssetRepository(database),
        remoteLibrary = DriftRemoteLibraryRepository(database),
        downloadJobs = DriftDownloadJobRepository(database),
        playlists = DriftPlaylistRepository(database),
        playbackEvents = DriftPlaybackEventRepository(database),
        trackUserState = DriftTrackUserStateRepository(database),
        settings = DriftSettingsRepository(database);

  final AppDatabase _database;

  @override
  final LibraryRepository libraryFolders;

  @override
  final TrackRepository tracks;

  @override
  final ExternalTrackRepository externalTracks;

  @override
  final DownloadedAssetRepository downloadedAssets;

  @override
  final RemoteLibraryRepository remoteLibrary;

  @override
  final DownloadJobRepository downloadJobs;

  @override
  final PlaylistRepository playlists;

  @override
  final PlaybackEventRepository playbackEvents;

  @override
  final TrackUserStateRepository trackUserState;

  @override
  final SettingsRepository settings;

  @override
  Future<void> resetLearningState() {
    return _database.transaction(() async {
      await _database.delete(_database.playbackEvents).go();
      await _database.delete(_database.trackUserStates).go();
    });
  }
}

final class DriftLibraryRepository
    implements LibraryRepository, LibraryFolderRemovalRepository {
  const DriftLibraryRepository(this._database);

  final AppDatabase _database;

  @override
  Future<int> upsertFolder(LibraryFolder folder) {
    return _database.transaction(() async {
      final previous = await findFolderByPath(folder.path);
      final id = await _database
          .into(_database.libraryFolders)
          .insertOnConflictUpdate(libraryFolderToCompanion(folder));
      final saved = (await findFolderByPath(folder.path))!;
      if (!saved.isEnabled || (folder.id != null && previous == null)) {
        await invalidateDownloadJobs(_database,
            folderId: saved.id!, reason: DownloadFailure.destinationDisabled);
      }
      return id;
    });
  }

  @override
  Future<LibraryFolder?> findFolderByPath(String path) async {
    final row = await (_database.select(_database.libraryFolders)
          ..where((table) => table.path.equals(path)))
        .getSingleOrNull();

    return row == null ? null : libraryFolderFromRow(row);
  }

  @override
  Future<List<LibraryFolder>> listFolders({bool includeDisabled = true}) {
    final query = _database.select(_database.libraryFolders);
    if (!includeDisabled) {
      query.where((table) => table.isEnabled.equals(true));
    }
    query.orderBy([
      (table) => OrderingTerm(expression: table.path),
    ]);
    return query.get().then((rows) => rows.map(libraryFolderFromRow).toList());
  }

  @override
  Stream<List<LibraryFolder>> watchFolders({bool includeDisabled = true}) {
    final query = _database.select(_database.libraryFolders);
    if (!includeDisabled) {
      query.where((table) => table.isEnabled.equals(true));
    }
    query.orderBy([
      (table) => OrderingTerm(expression: table.path),
    ]);
    return query.watch().map((rows) => rows.map(libraryFolderFromRow).toList());
  }

  @override
  Future<void> setFolderEnabled(
    int id, {
    required bool isEnabled,
    required DateTime updatedAt,
  }) =>
      _database.transaction(() async {
        await (_database.update(_database.libraryFolders)
              ..where((table) => table.id.equals(id)))
            .write(
          LibraryFoldersCompanion(
            isEnabled: Value(isEnabled),
            updatedAt: Value(updatedAt),
          ),
        );
        if (!isEnabled) {
          await invalidateDownloadJobs(_database,
              folderId: id, reason: DownloadFailure.destinationDisabled);
        }
      });

  @override
  Future<void> deleteFolder(int id) => _database.transaction(() async {
        await deleteDownloadJobsForFolder(_database, id);
        await (_database.delete(_database.libraryFolders)
              ..where((table) => table.id.equals(id)))
            .go();
      });

  @override
  Future<void> removeDisabledFolder(int id) => _database.transaction(() async {
        final current = await (_database.select(_database.libraryFolders)
              ..where((table) => table.id.equals(id)))
            .getSingleOrNull();
        if (current == null) return;
        if (current.isEnabled) {
          throw StateError('Отключите папку перед удалением из библиотеки.');
        }
        await DriftTrackRepository(_database).deleteTracksByLibraryFolder(id);
        await deleteDownloadJobsForFolder(_database, id);
        final removed = await (_database.delete(_database.libraryFolders)
              ..where((table) =>
                  table.id.equals(id) & table.isEnabled.equals(false)))
            .go();
        if (removed != 1) {
          throw StateError('Не удалось удалить папку из библиотеки.');
        }
      });
}

final class DriftTrackRepository
    implements
        TrackRepository,
        TrackScanRepository,
        TrackContentHashRepository,
        TrackImportRepository,
        TrackLibraryCountRepository {
  const DriftTrackRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<int> watchIndexedTrackCount() {
    final count = _database.tracks.id.count();
    return (_database.selectOnly(_database.tracks)..addColumns([count]))
        .watchSingle()
        .map((row) => row.read(count) ?? 0)
        .distinct();
  }

  @override
  Future<List<int>> upsertScannedTracks(List<Track> tracks) {
    if (tracks.length > TrackImportRepository.maxBatchSize) {
      throw ArgumentError.value(tracks.length, 'tracks.length');
    }
    if (tracks.isEmpty) return Future.value(const []);
    final incoming = List<Track>.of(tracks);
    final paths = incoming.map((track) => track.filePath).toSet();
    if (paths.length != incoming.length) {
      throw ArgumentError('An import batch must contain unique file paths.');
    }
    return _database.transaction(() async {
      final rows = await (_database.select(_database.tracks)
            ..where((table) => table.filePath.isIn(paths)))
          .get();
      final existing = {for (final row in rows) row.filePath: row};
      await _database.batch((batch) {
        for (final track in incoming) {
          final current = existing[track.filePath];
          var values = trackToCompanion(track);
          if (current == null) {
            // Scanning may discover a new location, but never relocate an ID.
            batch.insert(
                _database.tracks, values.copyWith(id: const Value.absent()));
            continue;
          }
          values = values.copyWith(
            id: Value(current.id),
            libraryFolderId: Value(current.libraryFolderId),
            addedAt: Value(current.addedAt),
            customArtworkPath: Value(current.customArtworkPath),
            customArtworkHash: Value(current.customArtworkHash),
            customArtworkMimeType: Value(current.customArtworkMimeType),
          );
          if (current.metadataSource == MetadataSource.manual.storageKey) {
            values = values.copyWith(
              stableId: Value(current.stableId),
              title: Value(current.title),
              artist: Value(current.artist),
              album: Value(current.album),
              albumArtist: Value(current.albumArtist),
              genre: Value(current.genre),
              year: Value(current.year),
              trackNumber: Value(current.trackNumber),
              discNumber: Value(current.discNumber),
              metadataSource: Value(current.metadataSource),
              metadataConfidence: Value(current.metadataConfidence),
            );
          }
          // Do not move updatedAt backwards past a concurrent manual edit.
          if (current.updatedAt.isAfter(track.updatedAt)) {
            values = values.copyWith(updatedAt: Value(current.updatedAt));
          }
          batch.update(_database.tracks, values,
              where: (table) => table.id.equals(current.id));
        }
      });
      final saved = await (_database.selectOnly(_database.tracks)
            ..addColumns([_database.tracks.id, _database.tracks.filePath])
            ..where(_database.tracks.filePath.isIn(paths)))
          .get();
      final ids = {
        for (final row in saved)
          row.read(_database.tracks.filePath)!: row.read(_database.tracks.id)!
      };
      return [for (final track in incoming) ids[track.filePath]!];
    });
  }

  @override
  Future<void> updateContentHashes(Map<int, String?> hashesByTrackId) {
    return _database.batch((batch) {
      for (final entry in hashesByTrackId.entries) {
        batch.update(
          _database.tracks,
          TracksCompanion(contentHash: Value(entry.value)),
          where: (table) => table.id.equals(entry.key),
        );
      }
    });
  }

  @override
  Future<int> upsertTrack(Track track) {
    // Serialize lookup and write so concurrent scans of the same location
    // cannot both decide to insert it.
    return _database.transaction(() async {
      final existing = await _findExistingTrackForUpsert(track);
      if (existing == null) {
        return _database.into(_database.tracks).insert(trackToCompanion(track));
      }

      final id = existing.id!;
      final updatedTrack = _preserveExistingCustomArtwork(
        incoming: track,
        existing: existing,
      );
      await (_database.update(_database.tracks)
            ..where((table) => table.id.equals(id)))
          .write(trackToCompanion(updatedTrack.copyWith(id: id)));
      return id;
    });
  }

  @override
  Future<void> updateTrackMetadata(TrackMetadataUpdate metadata) async {
    final updatedRows = await (_database.update(_database.tracks)
          ..where((table) => table.id.equals(metadata.trackId)))
        .write(
      TracksCompanion(
        title: Value(metadata.title),
        artist: Value(metadata.artist),
        album: Value(metadata.album),
        albumArtist: Value(metadata.albumArtist),
        genre: Value(metadata.genre),
        year: Value(metadata.year),
        trackNumber: Value(metadata.trackNumber),
        discNumber: Value(metadata.discNumber),
        metadataSource: Value(MetadataSource.manual.storageKey),
        metadataConfidence: const Value(1.0),
        updatedAt: Value(metadata.updatedAt),
      ),
    );

    if (updatedRows == 0) {
      throw StateError('Трек ${metadata.trackId} не найден.');
    }
  }

  @override
  Future<void> updateCustomArtwork({
    required int trackId,
    required String path,
    required String hash,
    required String? mimeType,
    required DateTime updatedAt,
  }) async {
    final updatedRows = await (_database.update(_database.tracks)
          ..where((table) => table.id.equals(trackId)))
        .write(
      TracksCompanion(
        customArtworkPath: Value(path),
        customArtworkHash: Value(hash),
        customArtworkMimeType: Value(mimeType),
        updatedAt: Value(updatedAt),
      ),
    );

    if (updatedRows == 0) {
      throw StateError('Трек $trackId не найден.');
    }
  }

  @override
  Future<void> clearCustomArtwork({
    required int trackId,
    required DateTime updatedAt,
  }) async {
    final updatedRows = await (_database.update(_database.tracks)
          ..where((table) => table.id.equals(trackId)))
        .write(
      TracksCompanion(
        customArtworkPath: const Value(null),
        customArtworkHash: const Value(null),
        customArtworkMimeType: const Value(null),
        updatedAt: Value(updatedAt),
      ),
    );

    if (updatedRows == 0) {
      throw StateError('Трек $trackId не найден.');
    }
    // TODO: Delete unreferenced app-owned custom artwork files after adding
    // reference counting or a safe startup cleanup pass.
  }

  @override
  Future<Track?> findById(int id) async {
    final row = await (_database.select(_database.tracks)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();

    return row == null ? null : trackFromRow(row);
  }

  @override
  Future<Track?> findByStableId(String stableId) async {
    final rows = await (_database.select(_database.tracks)
          ..where((table) => table.stableId.equals(stableId))
          ..limit(2))
        .get();

    return rows.length == 1 ? trackFromRow(rows.single) : null;
  }

  @override
  Future<Track?> findByPath(String filePath) async {
    final row = await (_database.select(_database.tracks)
          ..where((table) => table.filePath.equals(filePath)))
        .getSingleOrNull();

    return row == null ? null : trackFromRow(row);
  }

  @override
  Future<List<Track>> listTracks({
    int limit = 100,
    int offset = 0,
    bool includeDisabledFolders = false,
  }) {
    final query = _selectTracks(
      includeMissing: false,
      includeDisabledFolders: includeDisabledFolders,
    )..limit(limit, offset: offset);

    return query.get().then(_tracksFromJoinedRows);
  }

  @override
  Future<List<Track>> listTracksByLibraryFolder(
    int libraryFolderId, {
    bool includeMissing = true,
  }) {
    final query = _database.select(_database.tracks)
      ..where((table) {
        final folderExpression = table.libraryFolderId.equals(libraryFolderId);
        if (includeMissing) {
          return folderExpression;
        }
        return folderExpression & table.isMissing.equals(false);
      })
      ..orderBy([
        (table) => OrderingTerm(expression: table.title),
        (table) => OrderingTerm(expression: table.filePath),
      ]);

    return query.get().then((rows) => rows.map(trackFromRow).toList());
  }

  @override
  Stream<List<Track>> watchAllTracks({
    bool includeMissing = false,
    bool includeDisabledFolders = false,
  }) {
    final query = _selectTracks(
      includeMissing: includeMissing,
      includeDisabledFolders: includeDisabledFolders,
    );

    return query.watch().map(_tracksFromJoinedRows);
  }

  @override
  Stream<List<Track>> watchTracks({
    int limit = 100,
    bool includeDisabledFolders = false,
  }) {
    final query = _selectTracks(
      includeMissing: false,
      includeDisabledFolders: includeDisabledFolders,
    )..limit(limit);

    return query.watch().map(_tracksFromJoinedRows);
  }

  @override
  Future<void> deleteTracksByLibraryFolder(int libraryFolderId) async {
    await _database.transaction(() async {
      final trackIds = await (_database.select(_database.tracks)
            ..where(
              (table) => table.libraryFolderId.equals(libraryFolderId),
            ))
          .map((row) => row.id)
          .get();
      if (trackIds.isEmpty) {
        return;
      }

      await (_database.delete(_database.downloadedAssets)
            ..where((table) => table.trackId.isIn(trackIds)))
          .go();
      await (_database.delete(_database.externalTrackRefs)
            ..where((table) => table.trackId.isIn(trackIds)))
          .go();

      await (_database.delete(_database.playbackEvents)
            ..where((table) => table.trackId.isIn(trackIds)))
          .go();
      await (_database.delete(_database.trackUserStates)
            ..where((table) => table.trackId.isIn(trackIds)))
          .go();
      await (_database.delete(_database.playlistTracks)
            ..where((table) => table.trackId.isIn(trackIds)))
          .go();
      await (_database.delete(_database.tracks)
            ..where((table) => table.id.isIn(trackIds)))
          .go();
    });
  }

  @override
  Future<void> deleteTrack(int id) async {
    await _database.transaction(() async {
      await (_database.delete(_database.downloadedAssets)
            ..where((table) => table.trackId.equals(id)))
          .go();
      await (_database.delete(_database.externalTrackRefs)
            ..where((table) => table.trackId.equals(id)))
          .go();
      await (_database.delete(_database.playbackEvents)
            ..where((table) => table.trackId.equals(id)))
          .go();
      await (_database.delete(_database.trackUserStates)
            ..where((table) => table.trackId.equals(id)))
          .go();
      await (_database.delete(_database.playlistTracks)
            ..where((table) => table.trackId.equals(id)))
          .go();
      await (_database.delete(_database.tracks)
            ..where((table) => table.id.equals(id)))
          .go();
    });
  }

  @override
  Future<void> markTracksSeen({
    required Iterable<int> trackIds,
    required DateTime seenAt,
  }) {
    return _updateTrackScanState(
      trackIds: trackIds,
      companion: TracksCompanion(
        lastSeenAt: Value(seenAt),
        isMissing: const Value(false),
        updatedAt: Value(seenAt),
      ),
    );
  }

  @override
  Future<void> markTracksMissing({
    required Iterable<int> trackIds,
    required DateTime updatedAt,
  }) {
    return _updateTrackScanState(
      trackIds: trackIds,
      companion: TracksCompanion(
        isMissing: const Value(true),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> _updateTrackScanState({
    required Iterable<int> trackIds,
    required TracksCompanion companion,
  }) async {
    final ids = _uniqueTrackIds(trackIds);
    if (ids.isEmpty) {
      return;
    }

    await _database.transaction(() async {
      for (final chunk in _chunks(ids, 500)) {
        await (_database.update(_database.tracks)
              ..where((table) => table.id.isIn(chunk)))
            .write(companion);
      }
    });
  }

  Future<Track?> _findExistingTrackForUpsert(Track track) async {
    if (track.id != null) {
      final byId = await findById(track.id!);
      if (byId != null) {
        return byId;
      }
    }

    final byPath = await findByPath(track.filePath);
    if (byPath != null) {
      return byPath;
    }

    // A matching signature never authorizes replacing a different file.
    return null;
  }

  Track _preserveExistingCustomArtwork({
    required Track incoming,
    required Track existing,
  }) {
    final hasIncomingCustomArtwork = incoming.customArtworkPath != null ||
        incoming.customArtworkHash != null ||
        incoming.customArtworkMimeType != null;
    if (hasIncomingCustomArtwork) {
      return incoming;
    }

    return incoming.copyWith(
      customArtworkPath: existing.customArtworkPath,
      customArtworkHash: existing.customArtworkHash,
      customArtworkMimeType: existing.customArtworkMimeType,
    );
  }

  JoinedSelectStatement<HasResultSet, dynamic> _selectTracks({
    required bool includeMissing,
    required bool includeDisabledFolders,
  }) {
    final tracks = _database.tracks;
    final folders = _database.libraryFolders;
    final query = _database.select(tracks).join([
      leftOuterJoin(
        folders,
        folders.id.equalsExp(tracks.libraryFolderId),
      ),
    ]);

    final filters = <Expression<bool>>[];
    if (!includeMissing) {
      filters.add(tracks.isMissing.equals(false));
    }
    if (!includeDisabledFolders) {
      filters.add(
        tracks.libraryFolderId.isNull() | folders.isEnabled.equals(true),
      );
    }
    for (final filter in filters) {
      query.where(filter);
    }
    query.orderBy([
      OrderingTerm(expression: tracks.title),
      OrderingTerm(expression: tracks.filePath),
    ]);
    return query;
  }

  List<Track> _tracksFromJoinedRows(List<TypedResult> rows) {
    return rows
        .map((row) => trackFromRow(row.readTable(_database.tracks)))
        .toList();
  }
}

List<int> _uniqueTrackIds(Iterable<int> trackIds) {
  return trackIds.toSet().toList(growable: false);
}

Iterable<List<int>> _chunks(List<int> values, int size) sync* {
  for (var start = 0; start < values.length; start += size) {
    final end = start + size > values.length ? values.length : start + size;
    yield values.sublist(start, end);
  }
}

final class DriftPlaylistRepository implements PlaylistRepository {
  DriftPlaylistRepository(
    this._database, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _clock;

  @override
  Stream<List<PlaylistWithCount>> watchPlaylists() {
    final countExpression = _database.playlistTracks.trackId.count();
    final query = _database.select(_database.playlists).join([
      leftOuterJoin(
        _database.playlistTracks,
        _database.playlistTracks.playlistId.equalsExp(_database.playlists.id),
      ),
    ])
      ..addColumns([countExpression])
      ..groupBy([_database.playlists.id])
      ..orderBy([
        OrderingTerm(
          expression: _database.playlists.updatedAt,
          mode: OrderingMode.desc,
        ),
        OrderingTerm(expression: _database.playlists.name),
      ]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return PlaylistWithCount(
          playlist: playlistFromRow(row.readTable(_database.playlists)),
          trackCount: row.read(countExpression) ?? 0,
        );
      }).toList(growable: false);
    });
  }

  @override
  Future<int> createPlaylist(String name, {String? description}) {
    final trimmedName = _trimRequiredName(name);
    final now = _clock();
    return _database.into(_database.playlists).insert(
          PlaylistsCompanion(
            name: Value(trimmedName),
            description: Value(_trimOptionalDescription(description)),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  @override
  Future<void> renamePlaylist(int id, String name) async {
    final updatedRows = await (_database.update(_database.playlists)
          ..where((table) => table.id.equals(id)))
        .write(
      PlaylistsCompanion(
        name: Value(_trimRequiredName(name)),
        updatedAt: Value(_clock()),
      ),
    );

    if (updatedRows == 0) {
      throw StateError('Плейлист $id не найден.');
    }
  }

  @override
  Future<void> deletePlaylist(int id) async {
    await _database.transaction(() async {
      await (_database.delete(_database.playlistTracks)
            ..where((table) => table.playlistId.equals(id)))
          .go();
      await (_database.delete(_database.playlists)
            ..where((table) => table.id.equals(id)))
          .go();
    });
  }

  @override
  Stream<List<PlaylistEntry>> watchPlaylistTracks(int playlistId) {
    final playlistTracks = _database.playlistTracks;
    final tracks = _database.tracks;
    final folders = _database.libraryFolders;
    final query = _database.select(playlistTracks).join([
      innerJoin(
        tracks,
        tracks.id.equalsExp(playlistTracks.trackId),
      ),
      leftOuterJoin(
        folders,
        folders.id.equalsExp(tracks.libraryFolderId),
      ),
    ])
      ..where(playlistTracks.playlistId.equals(playlistId))
      ..orderBy([
        OrderingTerm(expression: playlistTracks.position),
        OrderingTerm(expression: playlistTracks.addedAt),
        OrderingTerm(expression: playlistTracks.trackId),
      ]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final playlistTrack = row.readTable(playlistTracks);
        final track = trackFromRow(row.readTable(tracks));
        final folder = row.readTableOrNull(folders);
        return PlaylistEntry(
          playlistId: playlistTrack.playlistId,
          trackId: playlistTrack.trackId,
          position: playlistTrack.position,
          addedAt: playlistTrack.addedAt,
          track: track,
          unavailableReason: _unavailableReason(track, folder),
        );
      }).toList(growable: false);
    });
  }

  @override
  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    await _database.transaction(() async {
      final existing = await (_database.select(_database.playlistTracks)
            ..where(
              (table) =>
                  table.playlistId.equals(playlistId) &
                  table.trackId.equals(trackId),
            ))
          .getSingleOrNull();
      if (existing != null) {
        return;
      }

      final lastEntry = await (_database.select(_database.playlistTracks)
            ..where((table) => table.playlistId.equals(playlistId))
            ..orderBy([
              (table) => OrderingTerm(
                    expression: table.position,
                    mode: OrderingMode.desc,
                  ),
            ])
            ..limit(1))
          .getSingleOrNull();
      final now = _clock();
      await _database.into(_database.playlistTracks).insert(
            PlaylistTracksCompanion(
              playlistId: Value(playlistId),
              trackId: Value(trackId),
              position: Value((lastEntry?.position ?? -1) + 1),
              addedAt: Value(now),
            ),
          );
      await _touchPlaylist(playlistId, now);
    });
  }

  @override
  Future<void> reorderPlaylistTracks({
    required int playlistId,
    required List<int> trackIds,
  }) async {
    await _database.transaction(() async {
      final existingEntries = await (_database.select(_database.playlistTracks)
            ..where((table) => table.playlistId.equals(playlistId))
            ..orderBy([
              (table) => OrderingTerm(expression: table.position),
              (table) => OrderingTerm(expression: table.addedAt),
              (table) => OrderingTerm(expression: table.trackId),
            ]))
          .get();
      final existingTrackIds = {
        for (final entry in existingEntries) entry.trackId,
      };
      final requestedTrackIds = trackIds.toSet();

      if (requestedTrackIds.length != trackIds.length ||
          requestedTrackIds.length != existingTrackIds.length ||
          !requestedTrackIds.containsAll(existingTrackIds)) {
        throw ArgumentError.value(
          trackIds,
          'trackIds',
          'Список для изменения порядка должен содержать каждый трек '
              'плейлиста ровно один раз.',
        );
      }

      for (var index = 0; index < trackIds.length; index++) {
        await (_database.update(_database.playlistTracks)
              ..where(
                (table) =>
                    table.playlistId.equals(playlistId) &
                    table.trackId.equals(trackIds[index]),
              ))
            .write(PlaylistTracksCompanion(position: Value(index)));
      }

      await _touchPlaylist(playlistId, _clock());
    });
  }

  @override
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    final removedRows = await (_database.delete(_database.playlistTracks)
          ..where(
            (table) =>
                table.playlistId.equals(playlistId) &
                table.trackId.equals(trackId),
          ))
        .go();
    if (removedRows > 0) {
      await _touchPlaylist(playlistId, _clock());
    }
  }

  Future<void> _touchPlaylist(int playlistId, DateTime updatedAt) async {
    await (_database.update(_database.playlists)
          ..where((table) => table.id.equals(playlistId)))
        .write(PlaylistsCompanion(updatedAt: Value(updatedAt)));
  }

  static String _trimRequiredName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
          name, 'name', 'Название плейлиста обязательно.');
    }
    return trimmed;
  }

  static String? _trimOptionalDescription(String? description) {
    final trimmed = description?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static String? _unavailableReason(
    Track track,
    LibraryFolderRow? folder,
  ) {
    if (track.isMissing) {
      return 'Отсутствует';
    }
    if (folder?.isEnabled == false) {
      return 'Папка отключена';
    }
    return null;
  }
}

final class DriftPlaybackEventRepository implements PlaybackEventRepository {
  const DriftPlaybackEventRepository(this._database);

  final AppDatabase _database;

  @override
  Future<int> addEvent(PlaybackEvent event) {
    return _database
        .into(_database.playbackEvents)
        .insert(playbackEventToCompanion(event));
  }

  @override
  Future<int> recordEvent(PlaybackEvent event) {
    final operationId = event.operationId;
    if (operationId == null || operationId.isEmpty || event.id != null) {
      throw ArgumentError(
          'recordEvent requires a new event with an operationId');
    }
    return _database.transaction(() async {
      final existing = await (_database.select(_database.playbackEvents)
            ..where((table) => table.operationId.equals(operationId)))
          .getSingleOrNull();
      if (existing != null) {
        if (!_matchesRecordedEvent(existing, event)) {
          throw StateError('An operationId cannot identify different events');
        }
        return existing.id;
      }

      final id = await addEvent(event);
      final columns = switch (event.type) {
        PlaybackEventType.started => ('play_count', 'last_played_at'),
        PlaybackEventType.completed => ('complete_count', 'last_completed_at'),
        PlaybackEventType.skipped => ('skip_count', 'last_skipped_at'),
        _ => null,
      };
      if (columns != null) {
        final (count, lastAt) = columns;
        // Only touch fields derived from this event. A delayed event must not
        // move the most recent timestamps backwards or replace explicit likes.
        await _database.customInsert(
          'INSERT INTO track_user_state (track_id, $count, $lastAt, updated_at) '
          'VALUES (?, 1, ?, ?) ON CONFLICT(track_id) DO UPDATE SET '
          '$count = track_user_state.$count + 1, '
          '$lastAt = MAX(COALESCE(track_user_state.$lastAt, excluded.$lastAt), '
          'excluded.$lastAt), '
          'updated_at = MAX(track_user_state.updated_at, excluded.updated_at)',
          variables: [
            Variable<int>(event.trackId),
            Variable<DateTime>(event.occurredAt),
            Variable<DateTime>(event.occurredAt),
          ],
          updates: {_database.trackUserStates},
        );
      }
      return id;
    });
  }

  bool _matchesRecordedEvent(PlaybackEventRow row, PlaybackEvent event) {
    // Drift stores timestamps as integer seconds and durations as milliseconds.
    return row.trackId == event.trackId &&
        row.eventType == event.type.storageKey &&
        row.occurredAt.millisecondsSinceEpoch ~/ 1000 ==
            event.occurredAt.millisecondsSinceEpoch ~/ 1000 &&
        row.positionMs == event.position?.inMilliseconds &&
        row.durationMs == event.trackDuration?.inMilliseconds &&
        row.waveMode == event.waveMode?.storageKey &&
        row.metadataJson == event.metadataJson;
  }

  @override
  Future<List<PlaybackEvent>> recentEvents({int limit = 100}) {
    final query = _database.select(_database.playbackEvents)
      ..orderBy([
        (table) => OrderingTerm(
              expression: table.occurredAt,
              mode: OrderingMode.desc,
            ),
      ])
      ..limit(limit);

    return query.get().then((rows) => rows.map(playbackEventFromRow).toList());
  }

  @override
  Future<List<PlaybackEvent>> recentForTrack(int trackId, {int limit = 50}) {
    final query = _database.select(_database.playbackEvents)
      ..where((table) => table.trackId.equals(trackId))
      ..orderBy([
        (table) => OrderingTerm(
              expression: table.occurredAt,
              mode: OrderingMode.desc,
            ),
      ])
      ..limit(limit);

    return query.get().then((rows) => rows.map(playbackEventFromRow).toList());
  }
}

final class DriftTrackUserStateRepository implements TrackUserStateRepository {
  const DriftTrackUserStateRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> upsertState(TrackUserState state) async {
    await _database
        .into(_database.trackUserStates)
        .insertOnConflictUpdate(trackUserStateToCompanion(state));
  }

  @override
  Future<TrackUserState> toggleFeedback(
    int trackId,
    TrackFeedback feedback, {
    required DateTime updatedAt,
  }) {
    return _database.transaction(() async {
      await _database.into(_database.trackUserStates).insert(
            TrackUserStatesCompanion.insert(
              trackId: Value(trackId),
              updatedAt: updatedAt,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      final assignments = switch (feedback) {
        TrackFeedback.like =>
          'is_favorite = CASE WHEN is_favorite = 1 AND is_hidden = 0 '
              'THEN 0 ELSE 1 END, is_hidden = 0',
        TrackFeedback.dislike =>
          'is_hidden = CASE WHEN is_hidden = 1 AND is_favorite = 0 '
              'THEN 0 ELSE 1 END, is_favorite = 0',
      };
      await _database.customUpdate(
        'UPDATE track_user_state SET $assignments, rating = NULL, '
        'updated_at = MAX(updated_at, ?) WHERE track_id = ?',
        variables: [Variable<DateTime>(updatedAt), Variable<int>(trackId)],
        updates: {_database.trackUserStates},
      );
      return (await findByTrackId(trackId))!;
    });
  }

  @override
  Future<TrackUserState?> findByTrackId(int trackId) async {
    final row = await (_database.select(_database.trackUserStates)
          ..where((table) => table.trackId.equals(trackId)))
        .getSingleOrNull();

    return row == null ? null : trackUserStateFromRow(row);
  }

  @override
  Future<Map<int, TrackUserState>> findByTrackIds(
    Iterable<int> trackIds,
  ) async {
    final ids = trackIds.toSet().toList();
    if (ids.isEmpty) {
      return const {};
    }

    final rows = await (_database.select(_database.trackUserStates)
          ..where((table) => table.trackId.isIn(ids)))
        .get();

    return {
      for (final row in rows) row.trackId: trackUserStateFromRow(row),
    };
  }

  @override
  Stream<TrackUserState?> watchTrackState(int trackId) {
    final query = _database.select(_database.trackUserStates)
      ..where((table) => table.trackId.equals(trackId));

    return query
        .watchSingleOrNull()
        .map((row) => row == null ? null : trackUserStateFromRow(row));
  }

  @override
  Stream<Map<int, TrackUserState>> watchTrackStatesByTrackIds(
    Iterable<int> trackIds,
  ) {
    final ids = trackIds.toSet().toList();
    if (ids.isEmpty) {
      return Stream.value(const {});
    }

    final query = _database.select(_database.trackUserStates)
      ..where((table) => table.trackId.isIn(ids));

    return query.watch().map((rows) {
      return {
        for (final row in rows) row.trackId: trackUserStateFromRow(row),
      };
    });
  }

  @override
  Future<void> deleteState(int trackId) async {
    await (_database.delete(_database.trackUserStates)
          ..where((table) => table.trackId.equals(trackId)))
        .go();
  }
}

final class DriftSettingsRepository implements SettingsRepository {
  const DriftSettingsRepository(this._database);

  final AppDatabase _database;

  @override
  Future<AppSetting?> read(String key) async {
    final row = await (_database.select(_database.appSettings)
          ..where((table) => table.key.equals(key)))
        .getSingleOrNull();

    return row == null ? null : appSettingFromRow(row);
  }

  @override
  Future<String?> readString(String key) async {
    return (await read(key))?.value;
  }

  @override
  Future<void> writeString(String key, String value) async {
    final now = DateTime.now();
    await _database.into(_database.appSettings).insertOnConflictUpdate(
          appSettingToCompanion(
            AppSetting(key: key, value: value, updatedAt: now),
          ),
        );
  }

  @override
  Future<void> delete(String key) async {
    await (_database.delete(_database.appSettings)
          ..where((table) => table.key.equals(key)))
        .go();
  }
}
