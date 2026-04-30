import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  TextColumn get codec => text().nullable()();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get fileSizeBytes => integer().nullable()();
  DateTimeColumn get modifiedAt => dateTime().nullable()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  BoolColumn get isMissing => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DataClassName('PlaybackEventRow')
class PlaybackEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
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

@DriftDatabase(
  tables: [
    LibraryFolders,
    Tracks,
    PlaybackEvents,
    TrackUserStates,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open() => AppDatabase(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
          await _createIndexes();
        },
        onUpgrade: (migrator, from, to) async {
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
          await _createIndexes();
        },
      );

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tracks_library_folder '
      'ON tracks(library_folder_id);',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_tracks_stable_id '
      'ON tracks(stable_id) WHERE stable_id IS NOT NULL;',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tracks_last_seen '
      'ON tracks(last_seen_at);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_playback_events_track_time '
      'ON playback_events(track_id, occurred_at);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_track_user_state_updated '
      'ON track_user_state(updated_at);',
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final databaseDirectory = Directory(
      p.join(supportDirectory.path, 'CleverMusicPlayer'),
    );

    await databaseDirectory.create(recursive: true);

    final databaseFile = File(
      p.join(databaseDirectory.path, 'clever_music_player.sqlite'),
    );

    return NativeDatabase.createInBackground(databaseFile);
  });
}
