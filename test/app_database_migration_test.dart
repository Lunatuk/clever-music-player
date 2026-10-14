import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/track.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _tables = [
  'library_folders',
  'tracks',
  'track_user_state',
  'playback_events',
  'playlists',
  'playlist_tracks',
  'app_settings',
  'external_track_refs',
];

typedef _Snapshot = Map<String, List<Map<String, Object?>>>;

void main() {
  final schemaV7 = File('test/fixtures/schema_v7.sql').readAsStringSync();

  for (var version = 1; version <= 9; version++) {
    test('schema v$version upgrades without changing existing rows or IDs',
        () async {
      late _Snapshot before;
      final database = AppDatabase(NativeDatabase.memory(
        setup: (raw) {
          _createHistoricalSchema(raw.execute, schemaV7, version);
          _seedHistoricalData(raw.execute, version);
          before = _snapshot(
            (sql) => [
              for (final row in raw.select(sql)) Map<String, Object?>.of(row),
            ],
          );
        },
      ));
      addTearDown(database.close);

      await _verifyUpgrade(database, () => before);
      final repository = DriftTrackRepository(database);
      final original = (await repository.findById(41))!;
      final copyId = await repository.upsertTrack(
        Track(
          filePath: '/music/copy.mp3',
          stableId: original.stableId,
          title: 'Copy',
          addedAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      expect(copyId, isNot(41));
      expect((await repository.findById(41))?.filePath, '/music/original.mp3');
    });
  }

  test(
      'v9 Android ownership, URI, genre, settings and user data survive upgrade',
      () async {
    late _Snapshot before;
    final database = AppDatabase(NativeDatabase.memory(setup: (raw) {
      _createHistoricalSchema(raw.execute, schemaV7, 9);
      _seedHistoricalData(raw.execute, 9);
      raw.execute(
          'INSERT INTO library_folders (id, path, is_enabled, created_at, updated_at) '
          "VALUES (4, 'content://test.documents/tree/Music', 0, 1, 2)");
      raw.execute(
          'INSERT INTO tracks (id, library_folder_id, file_path, title, artist, genre, metadata_source, custom_artwork_path, added_at, updated_at) '
          "VALUES (42, 4, 'content://test.documents/tree/Music/document/song', 'Manual Android title', 'Artist', 'Rock / Alternative', 'manual', '/private/android-cover.webp', 1, 2)");
      raw.execute(
          'INSERT INTO track_user_state (track_id, is_favorite, play_count, updated_at) VALUES (42, 1, 3, 2)');
      raw.execute(
          "INSERT INTO playback_events (track_id, operation_id, event_type, occurred_at) VALUES (42, 'android-event', 'started', 2)");
      raw.execute(
          'INSERT INTO playlist_tracks (playlist_id, track_id, position, added_at) VALUES (5, 42, 1, 2)');
      before = _snapshot((sql) =>
          [for (final row in raw.select(sql)) Map<String, Object?>.of(row)]);
    }));
    addTearDown(database.close);
    await _verifyUpgrade(database, () => before);
    final repository = DriftRepositories(database);
    expect(
        (await repository.tracks.listTracks()).map((track) => track.id), [41]);
    final hidden = (await repository.tracks.findById(42))!;
    expect(hidden.libraryFolderId, 4);
    expect(hidden.genre, 'Rock / Alternative');
    expect(
        hidden.filePath, 'content://test.documents/tree/Music/document/song');
    expect(await repository.externalTracks.listForTrack(42), isEmpty);
  });

  for (final failurePoint in ['external-index', 'version']) {
    test('fresh schema creation rolls back after $failurePoint failure',
        () async {
      final dir =
          await Directory.systemTemp.createTemp('cmp_fresh_schema_retry_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'library.sqlite'));
      final failing = _FailingMigrationDatabase(NativeDatabase(file),
          failurePoint: failurePoint);
      try {
        await expectLater(failing.customSelect('SELECT * FROM tracks').get(),
            throwsStateError);
      } finally {
        await failing.close();
      }
      late int previousVersion;
      late bool previousTable;
      final retry = AppDatabase(NativeDatabase(file, setup: (raw) {
        previousVersion =
            raw.select('PRAGMA user_version').single['user_version'] as int;
        previousTable = raw
            .select(
                "SELECT name FROM sqlite_master WHERE name='external_track_refs'")
            .isNotEmpty;
      }));
      addTearDown(retry.close);
      expect(await DriftRepositories(retry).tracks.listTracks(), isEmpty);
      expect(previousVersion, 0);
      expect(previousTable, isFalse);
      expect(
          (await retry.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          10);
    });
  }

  test('schema v10 remains valid after closing and reopening a migrated file',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('clever_schema_reopen_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'library.sqlite'));
    final oldDatabase = AppDatabase(NativeDatabase(
      file,
      setup: (raw) {
        _createHistoricalSchema(raw.execute, schemaV7, 7);
        _seedHistoricalData(raw.execute, 7);
      },
    ));
    try {
      expect((await DriftTrackRepository(oldDatabase).findById(41))?.title,
          'Original');
    } finally {
      await oldDatabase.close();
    }

    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    expect(
        (await reopened.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        10);
    final repositories = DriftRepositories(reopened);
    final original = (await repositories.tracks.findById(41))!;
    await repositories.tracks.upsertTrack(
      Track(
        filePath: '/music/copy.mp3',
        stableId: original.stableId,
        addedAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    expect(await repositories.tracks.listTracks(), hasLength(2));
    expect((await repositories.trackUserState.findByTrackId(41))?.isFavorite,
        isTrue);
    expect(await repositories.playlists.watchPlaylistTracks(5).first,
        hasLength(1));
  });

  for (final version in [1, 7, 8, 9]) {
    for (final failurePoint in [
      'index',
      'operation-index',
      'external-index',
      'version'
    ]) {
      test(
          'v$version upgrade rolls back after $failurePoint failure and retries',
          () async {
        final directory =
            await Directory.systemTemp.createTemp('clever_schema_retry_');
        addTearDown(() => directory.delete(recursive: true));
        final file = File(p.join(directory.path, 'library.sqlite'));
        final failing = _FailingMigrationDatabase(
            NativeDatabase(
              file,
              setup: (raw) {
                _createHistoricalSchema(raw.execute, schemaV7, version);
                _seedHistoricalData(raw.execute, version);
              },
            ),
            failurePoint: failurePoint);
        try {
          await expectLater(
            failing.customSelect('SELECT * FROM tracks').get(),
            throwsStateError,
          );
        } finally {
          await failing.close();
        }

        late int versionAfterFailure;
        int? uniqueAfterFailure;
        late bool hasStableIdAfterFailure;
        late bool hasOperationIdAfterFailure;
        late bool hasExternalRefsAfterFailure;
        final retry = AppDatabase(NativeDatabase(
          file,
          setup: (raw) {
            versionAfterFailure =
                raw.select('PRAGMA user_version').single['user_version'] as int;
            final indexes = raw
                .select("PRAGMA index_list('tracks')")
                .where((row) => row['name'] == 'idx_tracks_stable_id');
            uniqueAfterFailure =
                indexes.isEmpty ? null : indexes.single['unique'] as int;
            hasStableIdAfterFailure = raw
                .select("PRAGMA table_info('tracks')")
                .any((row) => row['name'] == 'stable_id');
            hasOperationIdAfterFailure = raw
                .select("PRAGMA table_info('playback_events')")
                .any((row) => row['name'] == 'operation_id');
            hasExternalRefsAfterFailure = raw
                .select(
                    "SELECT name FROM sqlite_master WHERE name = 'external_track_refs'")
                .isNotEmpty;
          },
        ));
        addTearDown(retry.close);
        expect((await DriftTrackRepository(retry).findById(41))?.title,
            'Original');
        expect(versionAfterFailure, version);
        expect(
            uniqueAfterFailure, version == 1 ? isNull : (version < 8 ? 1 : 0));
        expect(hasStableIdAfterFailure, version >= 2);
        expect(hasOperationIdAfterFailure, version >= 9);
        expect(hasExternalRefsAfterFailure, isFalse);
        expect(
            (await retry.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version'),
            10);
      });
    }
  }

  // Optional developer check: always migrates a temporary COPY, never the input.
  // The normal suite uses the frozen schema above and requires no personal data.
  final suppliedSnapshot = Platform.environment['CLEVER_MIGRATION_SNAPSHOT'];
  if (suppliedSnapshot != null) {
    test('a supplied real library snapshot upgrades without changing its data',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('clever_real_schema_upgrade_');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(suppliedSnapshot)
          .copy(p.join(directory.path, 'library.sqlite'));
      late _Snapshot before;
      final database = AppDatabase(NativeDatabase(
        file,
        setup: (raw) {
          before = _snapshot(
            (sql) => [
              for (final row in raw.select(sql)) Map<String, Object?>.of(row),
            ],
          );
        },
      ));
      addTearDown(database.close);

      await _verifyUpgrade(database, () => before);
    });
  }
}

class _FailingMigrationDatabase extends AppDatabase {
  _FailingMigrationDatabase(super.executor, {required this.failurePoint});

  final String failurePoint;

  @override
  Future<void> customStatement(String statement, [List<dynamic>? args]) async {
    if (failurePoint == 'index' &&
        statement
            .startsWith('CREATE INDEX IF NOT EXISTS idx_tracks_stable_id ')) {
      throw StateError('Simulated interruption after dropping the old index');
    }
    if (failurePoint == 'operation-index' &&
        statement.startsWith(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_playback_events_operation ')) {
      throw StateError('Simulated interruption after adding operation_id');
    }
    await super.customStatement(statement, args);
    if (failurePoint == 'external-index' &&
        statement.startsWith(
            'CREATE INDEX IF NOT EXISTS idx_external_track_refs_identity ')) {
      throw StateError(
          'Simulated interruption after adding external identities');
    }
    if (failurePoint == 'version' &&
        statement.startsWith('PRAGMA user_version = ')) {
      throw StateError('Simulated interruption after updating the version');
    }
  }
}

_Snapshot _snapshot(List<Map<String, Object?>> Function(String) select) {
  final available = select("SELECT name FROM sqlite_master WHERE type='table'")
      .map((row) => row['name'])
      .toSet();
  return {
    for (final table in _tables)
      if (available.contains(table)) table: select('SELECT * FROM $table'),
  };
}

Future<void> _verifyUpgrade(
  AppDatabase database,
  _Snapshot Function() getBefore,
) async {
  // The first query opens Drift and runs its production migration.
  expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      10);
  for (final entry in getBefore().entries) {
    final table = entry.key;
    final oldRows = entry.value;
    final rows = await database.customSelect('SELECT * FROM $table').get();
    expect(rows, hasLength(oldRows.length), reason: '$table row count');
    if (oldRows.isEmpty) {
      continue;
    }
    final columns = oldRows.first.keys.toList();
    final actual = [
      for (final row in rows)
        {for (final column in columns) column: row.data[column]},
    ];
    expect(actual, unorderedEquals(oldRows), reason: '$table existing values');
  }
  final indexes =
      await database.customSelect("PRAGMA index_list('tracks')").get();
  expect(
      indexes
          .singleWhere(
              (row) => row.read<String>('name') == 'idx_tracks_stable_id')
          .read<int>('unique'),
      0);
  expect(
    (await database.customSelect("PRAGMA index_list('playback_events')").get())
        .singleWhere((row) =>
            row.read<String>('name') == 'idx_playback_events_operation')
        .read<int>('unique'),
    1,
  );
  expect(
      await database
          .customSelect('PRAGMA integrity_check')
          .getSingle()
          .then((row) => row.read<String>('integrity_check')),
      'ok');
  expect(
      await database.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
}

void _createHistoricalSchema(
  void Function(String) execute,
  String schemaV7,
  int version,
) {
  final schema = version == 9
      ? File('test/fixtures/schema_v9.sql').readAsStringSync()
      : schemaV7;
  for (final sql in schema.split(';')) {
    if (sql.trim().isNotEmpty) {
      execute(sql);
    }
  }
  if (version == 8) {
    execute('DROP INDEX idx_tracks_stable_id');
    execute('CREATE INDEX idx_tracks_stable_id ON tracks(stable_id) '
        'WHERE stable_id IS NOT NULL');
  }
  // Schemas 1-6 are reconstructed from the frozen v7 DDL and the application's
  // historical migrations. They do not depend on the current target schema.
  if (version < 7) {
    for (final column in [
      'custom_artwork_path',
      'custom_artwork_hash',
      'custom_artwork_mime_type',
    ]) {
      execute('ALTER TABLE tracks DROP COLUMN $column');
    }
  }
  if (version < 6) {
    for (final column in [
      'artwork_path',
      'artwork_hash',
      'artwork_mime_type'
    ]) {
      execute('ALTER TABLE tracks DROP COLUMN $column');
    }
  }
  if (version < 5) {
    execute('DROP TABLE playlist_tracks');
    execute('DROP TABLE playlists');
  }
  if (version < 4) {
    execute('ALTER TABLE tracks DROP COLUMN metadata_source');
    execute('ALTER TABLE tracks DROP COLUMN metadata_confidence');
  }
  if (version < 3) {
    execute('ALTER TABLE track_user_state DROP COLUMN complete_count');
  }
  if (version < 2) {
    execute('DROP INDEX idx_tracks_stable_id');
    execute('DROP INDEX idx_tracks_last_seen');
    for (final column in ['stable_id', 'codec', 'last_seen_at', 'is_missing']) {
      execute('ALTER TABLE tracks DROP COLUMN $column');
    }
  }
  execute('PRAGMA user_version = $version');
}

void _seedHistoricalData(void Function(String) execute, int version) {
  execute('INSERT INTO library_folders (id, path, created_at, updated_at) '
      "VALUES (3, '/music', 1, 2)");
  execute('INSERT INTO tracks (id, library_folder_id, file_path, title, '
      'content_hash, added_at, updated_at) '
      "VALUES (41, 3, '/music/original.mp3', 'Original', 'audio-hash', 1, 2)");
  execute('INSERT INTO track_user_state '
      '(track_id, is_favorite, play_count, updated_at) VALUES (41, 1, 7, 2)');
  execute('INSERT INTO playback_events '
      "(id, track_id, event_type, occurred_at) VALUES (9, 41, 'started', 2)");
  execute('INSERT INTO app_settings (key, value, updated_at) '
      "VALUES ('kept-setting', 'kept-value', 2)");
  if (version >= 2) {
    execute("UPDATE tracks SET stable_id = 'legacy-signature', codec = 'mp3'");
  }
  if (version >= 3) {
    execute('UPDATE track_user_state SET complete_count = 4');
  }
  if (version >= 4) {
    execute("UPDATE tracks SET metadata_source = 'manual', "
        'metadata_confidence = 1');
  }
  if (version >= 5) {
    execute('INSERT INTO playlists (id, name, created_at, updated_at) '
        "VALUES (5, 'Keep', 1, 2)");
    execute('INSERT INTO playlist_tracks '
        '(playlist_id, track_id, position, added_at) VALUES (5, 41, 0, 2)');
  }
  if (version >= 6) {
    execute("UPDATE tracks SET artwork_path = '/app/artwork/cover.png', "
        "artwork_hash = 'embedded-hash', artwork_mime_type = 'image/png'");
  }
  if (version >= 9) {
    execute("UPDATE playback_events SET operation_id = 'legacy-event-9'");
    execute("UPDATE tracks SET genre = 'Progressive Metal; Rock'");
    execute(
        "INSERT INTO app_settings (key, value, updated_at) VALUES ('android.audio_folder_bookmarks.v1', '{\"version\":1,\"folders\":[]}', 2)");
  }
  if (version >= 7) {
    execute("UPDATE tracks SET custom_artwork_path = '/app/custom/cover.png', "
        "custom_artwork_hash = 'custom-hash', custom_artwork_mime_type = 'image/png'");
  }
}
