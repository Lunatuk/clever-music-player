import 'package:drift/drift.dart';

import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../drift/app_database.dart';
import '../drift/drift_mappers.dart';

final class DriftRepositories implements AppRepositories {
  DriftRepositories(AppDatabase database)
      : libraryFolders = DriftLibraryRepository(database),
        tracks = DriftTrackRepository(database),
        playbackEvents = DriftPlaybackEventRepository(database),
        trackUserState = DriftTrackUserStateRepository(database),
        settings = DriftSettingsRepository(database);

  @override
  final LibraryRepository libraryFolders;

  @override
  final TrackRepository tracks;

  @override
  final PlaybackEventRepository playbackEvents;

  @override
  final TrackUserStateRepository trackUserState;

  @override
  final SettingsRepository settings;
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
  Future<void> deleteFolder(int id) async {
    await (_database.delete(_database.libraryFolders)
          ..where((table) => table.id.equals(id)))
        .go();
  }
}

final class DriftTrackRepository implements TrackRepository {
  const DriftTrackRepository(this._database);

  final AppDatabase _database;

  @override
  Future<int> upsertTrack(Track track) async {
    final existing = await _findExistingTrackForUpsert(track);
    if (existing == null) {
      return _database.into(_database.tracks).insert(trackToCompanion(track));
    }

    final id = existing.id!;
    await (_database.update(_database.tracks)
          ..where((table) => table.id.equals(id)))
        .write(trackToCompanion(track.copyWith(id: id)));
    return id;
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
  Future<List<Track>> listTracks({int limit = 100, int offset = 0}) {
    final query = _database.select(_database.tracks)
      ..where((table) => table.isMissing.equals(false))
      ..orderBy([
        (table) => OrderingTerm(expression: table.title),
        (table) => OrderingTerm(expression: table.filePath),
      ])
      ..limit(limit, offset: offset);

    return query.get().then((rows) => rows.map(trackFromRow).toList());
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
  Stream<List<Track>> watchAllTracks({bool includeMissing = false}) {
    final query = _database.select(_database.tracks);
    if (!includeMissing) {
      query.where((table) => table.isMissing.equals(false));
    }
    query.orderBy([
      (table) => OrderingTerm(expression: table.title),
      (table) => OrderingTerm(expression: table.filePath),
    ]);

    return query.watch().map((rows) => rows.map(trackFromRow).toList());
  }

  @override
  Stream<List<Track>> watchTracks({int limit = 100}) {
    final query = _database.select(_database.tracks)
      ..where((table) => table.isMissing.equals(false))
      ..orderBy([
        (table) => OrderingTerm(expression: table.title),
        (table) => OrderingTerm(expression: table.filePath),
      ])
      ..limit(limit);

    return query.watch().map((rows) => rows.map(trackFromRow).toList());
  }

  @override
  Future<void> deleteTrack(int id) async {
    await (_database.delete(_database.tracks)
          ..where((table) => table.id.equals(id)))
        .go();
  }

  Future<Track?> _findExistingTrackForUpsert(Track track) async {
    if (track.id != null) {
      final byId = await findById(track.id!);
      if (byId != null) {
        return byId;
      }
    }

    final stableId = track.stableId;
    if (stableId != null && stableId.isNotEmpty) {
      final byStableId = await findByStableId(stableId);
      if (byStableId != null) {
        return byStableId;
      }
    }

    return findByPath(track.filePath);
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
