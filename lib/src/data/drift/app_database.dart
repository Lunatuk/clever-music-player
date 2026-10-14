import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../diagnostics/diagnostics_service.dart';

part 'app_database.g.dart';

@DataClassName('LibraryFolderRow')
class LibraryFolders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  TextColumn get displayName => text().nullable()();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get isRecursive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastScannedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DataClassName('TrackRow')
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get libraryFolderId => integer()
      .nullable()
      .references(LibraryFolders, #id, onDelete: KeyAction.setNull)();
  TextColumn get stableId => text().nullable()();
  TextColumn get filePath => text().unique()();
  TextColumn get contentHash => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  TextColumn get albumArtist => text().nullable()();
  TextColumn get genre => text().nullable()();
  TextColumn get artworkPath => text().nullable()();
  TextColumn get artworkHash => text().nullable()();
  TextColumn get artworkMimeType => text().nullable()();
  TextColumn get customArtworkPath => text().nullable()();
  TextColumn get customArtworkHash => text().nullable()();
  TextColumn get customArtworkMimeType => text().nullable()();
  TextColumn get codec => text().nullable()();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get metadataSource => text().nullable()();
  RealColumn get metadataConfidence => real().nullable()();
  IntColumn get fileSizeBytes => integer().nullable()();
  DateTimeColumn get modifiedAt => dateTime().nullable()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  BoolColumn get isMissing => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DataClassName('PlaylistRow')
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DataClassName('PlaylistTrackRow')
class PlaylistTracks extends Table {
  IntColumn get playlistId =>
      integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {playlistId, trackId};
}

@DataClassName('PlaybackEventRow')
class PlaybackEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get operationId => text().nullable()();
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  TextColumn get eventType => text()();
  DateTimeColumn get occurredAt => dateTime()();
  IntColumn get positionMs => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get waveMode => text().nullable()();
  TextColumn get metadataJson => text().nullable()();
}

@DataClassName('TrackUserStateRow')
class TrackUserStates extends Table {
  @override
  String get tableName => 'track_user_state';

  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
  IntColumn get rating => integer().nullable()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get completeCount => integer().withDefault(const Constant(0))();
  IntColumn get skipCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();
  DateTimeColumn get lastSkippedAt => dateTime().nullable()();
  DateTimeColumn get lastCompletedAt => dateTime().nullable()();
  RealColumn get userScoreBoost => real().withDefault(const Constant(0))();
  TextColumn get preferredWaveMode => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {trackId};
}

@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('ExternalTrackRefRow')
class ExternalTrackRefs extends Table {
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  TextColumn get provider => text()();
  TextColumn get externalId => text()();
  TextColumn get variantKey => text().withDefault(const Constant(''))();
  TextColumn get origin => text()();
  DateTimeColumn get linkedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {trackId, provider, externalId, variantKey};
}

@DriftDatabase(
  tables: [
    LibraryFolders,
    Tracks,
    Playlists,
    PlaylistTracks,
    PlaybackEvents,
    TrackUserStates,
    AppSettings,
    ExternalTrackRefs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor,
      {this.diagnostics = const NoopDiagnosticsService()});

  final DiagnosticsService diagnostics;

  factory AppDatabase.open(
          {DiagnosticsService diagnostics = const NoopDiagnosticsService()}) =>
      AppDatabase(_openConnection(diagnostics), diagnostics: diagnostics);

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) => _migrate(
            0,
            schemaVersion,
            () => transaction(() async {
                  await migrator.createAll();
                  await _createIndexes();
                  await customStatement(
                      'PRAGMA user_version = $schemaVersion;');
                })),
        onUpgrade: (migrator, from, to) => _migrate(
            from,
            to,
            () => transaction(() async {
                  if (from > to) {
                    throw StateError(
                      'Медиатека создана более новой версией приложения: $from > $to.',
                    );
                  }
                  if (from < 2) {
                    await migrator.addColumn(tracks, tracks.stableId);
                    await migrator.addColumn(tracks, tracks.codec);
                    await migrator.addColumn(tracks, tracks.lastSeenAt);
                    await migrator.addColumn(tracks, tracks.isMissing);
                  }
                  if (from < 3) {
                    await migrator.addColumn(
                      trackUserStates,
                      trackUserStates.completeCount,
                    );
                  }
                  if (from < 4) {
                    await migrator.addColumn(tracks, tracks.metadataSource);
                    await migrator.addColumn(tracks, tracks.metadataConfidence);
                  }
                  if (from < 5) {
                    await migrator.createTable(playlists);
                    await migrator.createTable(playlistTracks);
                  }
                  if (from < 6) {
                    await migrator.addColumn(tracks, tracks.artworkPath);
                    await migrator.addColumn(tracks, tracks.artworkHash);
                    await migrator.addColumn(tracks, tracks.artworkMimeType);
                  }
                  if (from < 7) {
                    await migrator.addColumn(tracks, tracks.customArtworkPath);
                    await migrator.addColumn(tracks, tracks.customArtworkHash);
                    await migrator.addColumn(
                        tracks, tracks.customArtworkMimeType);
                  }
                  if (from < 8) {
                    // Metadata signatures are not unique: copies and unrelated tracks
                    // can share them. Keep all existing rows and their foreign keys.
                    await customStatement(
                        'DROP INDEX IF EXISTS idx_tracks_stable_id;');
                  }
                  if (from < 9) {
                    await migrator.addColumn(
                        playbackEvents, playbackEvents.operationId);
                  }
                  if (from < 10) {
                    await migrator.createTable(externalTrackRefs);
                  }
                  await _createIndexes();
                  // Commit the version marker with the DDL so an interruption cannot
                  // leave new columns with an old version and break the next upgrade.
                  await customStatement('PRAGMA user_version = $to;');
                })),
        beforeOpen: (details) async {
          diagnostics.record(DiagnosticEvent.databaseOpened,
              fields: {DiagnosticField.schemaTo: schemaVersion});
        },
      );

  Future<void> _migrate(
      int from, int to, Future<void> Function() operation) async {
    final timer = Stopwatch()..start();
    final fields = {
      DiagnosticField.schemaFrom: from,
      DiagnosticField.schemaTo: to
    };
    diagnostics.record(DiagnosticEvent.migrationStarted, fields: fields);
    try {
      await operation();
      diagnostics.record(DiagnosticEvent.migrationCompleted, fields: {
        ...fields,
        DiagnosticField.elapsedMs: timer.elapsedMilliseconds
      });
    } on Object catch (error) {
      diagnostics.record(DiagnosticEvent.migrationFailed,
          error: error,
          fields: {
            ...fields,
            DiagnosticField.elapsedMs: timer.elapsedMilliseconds
          });
      rethrow;
    }
  }

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_external_track_refs_identity '
      'ON external_track_refs(provider, external_id, variant_key, track_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tracks_library_folder '
      'ON tracks(library_folder_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tracks_stable_id '
      'ON tracks(stable_id) WHERE stable_id IS NOT NULL;',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tracks_last_seen '
      'ON tracks(last_seen_at);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_playlists_updated '
      'ON playlists(updated_at);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist_position '
      'ON playlist_tracks(playlist_id, position);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_playlist_tracks_track '
      'ON playlist_tracks(track_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_playback_events_track_time '
      'ON playback_events(track_id, occurred_at);',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_playback_events_operation '
      'ON playback_events(operation_id) WHERE operation_id IS NOT NULL;',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_track_user_state_updated '
      'ON track_user_state(updated_at);',
    );
  }
}

LazyDatabase _openConnection(DiagnosticsService diagnostics) {
  return LazyDatabase(() async {
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final databaseDirectory = Directory(
        p.join(supportDirectory.path, 'CleverMusicPlayer'),
      );

      await databaseDirectory.create(recursive: true);

      final databaseFile = File(
        p.join(databaseDirectory.path, 'clever_music_player.sqlite'),
      );

      return NativeDatabase.createInBackground(databaseFile);
    } on Object catch (error) {
      diagnostics.record(DiagnosticEvent.databaseFailure, error: error);
      rethrow;
    }
  });
}
