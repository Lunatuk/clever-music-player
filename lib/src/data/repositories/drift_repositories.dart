import 'package:drift/drift.dart';

import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../drift/app_database.dart';
import '../drift/drift_mappers.dart';

final class DriftRepositories implements AppRepositories {
  DriftRepositories(AppDatabase database)
      : _database = database,
        libraryFolders = DriftLibraryRepository(database),
        tracks = DriftTrackRepository(database),
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

final class DriftLibraryRepository implements LibraryRepository {
  const DriftLibraryRepository(this._database);

  final AppDatabase _database;

  @override
  Future<int> upsertFolder(LibraryFolder folder) {
    return _database
        .into(_database.libraryFolders)
        .insertOnConflictUpdate(libraryFolderToCompanion(folder));
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
  }) async {
    await (_database.update(_database.libraryFolders)
          ..where((table) => table.id.equals(id)))
        .write(
      LibraryFoldersCompanion(
        isEnabled: Value(isEnabled),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  @override
  Future<void> deleteFolder(int id) async {
    await (_database.delete(_database.libraryFolders)
          ..where((table) => table.id.equals(id)))
        .go();
  }
}

final class DriftTrackRepository
    implements TrackRepository, TrackScanRepository {
  const DriftTrackRepository(this._database);

  final AppDatabase _database;

  @override
  Future<int> upsertTrack(Track track) async {
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
      throw StateError('Track ${metadata.trackId} was not found.');
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
      throw StateError('Track $trackId was not found.');
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
      throw StateError('Track $trackId was not found.');
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
    final row = await (_database.select(_database.tracks)
          ..where((table) => table.stableId.equals(stableId)))
        .getSingleOrNull();

    return row == null ? null : trackFromRow(row);
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

    final stableId = track.stableId;
    if (stableId != null && stableId.isNotEmpty) {
      return findByStableId(stableId);
    }

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
      throw StateError('Playlist $id was not found.');
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
          'Reorder input must contain each target playlist track exactly once.',
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
      throw ArgumentError.value(name, 'name', 'Playlist name cannot be empty.');
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
      return 'Missing';
    }
    if (folder?.isEnabled == false) {
      return 'Folder disabled';
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
