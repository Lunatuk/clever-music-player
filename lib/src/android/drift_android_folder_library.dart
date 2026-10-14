import 'package:drift/drift.dart';

import '../data/drift/app_database.dart';
import '../data/repositories/drift_repositories.dart';
import '../domain/models/audio_source_reference.dart';
import 'android_folder_bookmarks.dart';
import 'audio_documents.dart';

typedef _TreeIdentity = (String authority, String treeId);

_TreeIdentity _identity(ContentUriAudioSource root) =>
    (root.uri.authority, root.uri.pathSegments[1]);

ContentUriAudioSource? _root(String value, {required bool document}) {
  try {
    final source = ContentUriAudioSource(value);
    if (!document) return isAudioFolderUri(source) ? source : null;
    final parts = source.uri.pathSegments;
    if (parts.length != 4 ||
        parts[0] != 'tree' ||
        parts[1].isEmpty ||
        parts[2] != 'document' ||
        parts[3].isEmpty) {
      return null;
    }
    return ContentUriAudioSource(
        source.uri.replace(pathSegments: parts.take(2)).toString());
  } on FormatException {
    return null;
  }
}

/// Android adapter over the shared desktop folder visibility model. No file IO,
/// metadata matching, grant revocation or track deletion belongs here.
final class DriftAndroidFolderLibrary implements AndroidFolderLibraryStorage {
  const DriftAndroidFolderLibrary(this.database);
  final AppDatabase database;

  @override
  Future<Map<String, int>> synchronize(
          List<SavedAudioFolder> folders, String encoded) =>
      database.transaction(() async {
        final table = database.libraryFolders;
        final existing = await database.select(table).get();
        final byIdentity = {
          for (final row in existing)
            if (_root(row.path, document: false) case final root?)
              _identity(root): row,
        };
        final active = {
          for (final folder in folders) _identity(folder.source): folder,
        };
        final roots = {
          for (final entry in byIdentity.entries)
            entry.key: ContentUriAudioSource(entry.value.path),
          for (final folder in folders) _identity(folder.source): folder.source,
        };
        // Older Android versions stored tree documents with a null owner.
        // Recover roots even if they were already forgotten in package 21.
        // Separate /document/... imports and desktop files stay independent.
        final tracks = database.tracks;
        final unowned = await (database.selectOnly(tracks)
              ..addColumns([tracks.id, tracks.filePath])
              ..where(tracks.libraryFolderId.isNull() &
                  tracks.filePath.like('content://%')))
            .get();
        final adopt = <int, _TreeIdentity>{};
        for (final row in unowned) {
          final root = _root(row.read(tracks.filePath)!, document: true);
          if (root == null) continue;
          final key = _identity(root);
          roots.putIfAbsent(key, () => root);
          adopt[row.read(tracks.id)!] = key;
        }
        final now = DateTime.now();
        final ids = <_TreeIdentity, int>{};
        for (final entry in roots.entries) {
          final current = byIdentity[entry.key];
          final saved = active[entry.key];
          final enabled = saved != null;
          final name = saved?.name ?? current?.displayName;
          final scanned = saved?.lastCompletedAt ?? current?.lastScannedAt;
          if (current == null) {
            ids[entry.key] = await database.into(table).insert(
                LibraryFoldersCompanion.insert(
                    path: entry.value.storageValue,
                    displayName: Value(name),
                    isEnabled: Value(enabled),
                    lastScannedAt: Value(scanned),
                    createdAt: now,
                    updatedAt: now));
          } else {
            ids[entry.key] = current.id;
            if (current.isEnabled != enabled ||
                current.displayName != name ||
                current.lastScannedAt != scanned) {
              await (database.update(table)
                    ..where((t) => t.id.equals(current.id)))
                  .write(LibraryFoldersCompanion(
                      isEnabled: Value(enabled),
                      displayName: Value(name),
                      lastScannedAt: Value(scanned),
                      updatedAt: Value(now)));
            }
          }
        }
        await database.batch((batch) {
          for (final entry in adopt.entries) {
            batch.update(tracks,
                TracksCompanion(libraryFolderId: Value(ids[entry.value]!)),
                where: (t) =>
                    t.id.equals(entry.key) & t.libraryFolderId.isNull());
          }
        });
        await DriftSettingsRepository(database)
            .writeString(AndroidFolderBookmarks.settingKey, encoded);
        return {
          for (final folder in folders)
            folder.source.storageValue: ids[_identity(folder.source)]!,
        };
      });
}
