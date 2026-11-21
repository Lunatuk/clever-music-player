import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/models.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../library/audio_comparison.dart';
import '../../library/library_track_variants.dart';
import '../drift/app_database.dart';
import '../drift/drift_mappers.dart';

typedef _StoredMatch = ({int id, String path, String key, String revision});
typedef _CheckedMatch = ({
  _StoredMatch match,
  int? lastSeen,
  String? fileHash,
  bool valid
});

final class DriftLibraryVariantRepository
    implements LibraryVariantRepository, AudioMatchRepository {
  const DriftLibraryVariantRepository(this._database, this._settings,
      {this.revisionReader});

  static const _preferencePrefix = 'library.preferred-version.v1.';
  static const _audioPreferencePrefix = '${_preferencePrefix}local_pcm.';
  final AppDatabase _database;
  final SettingsRepository _settings;
  final AudioRevisionReader? revisionReader;

  Selectable<QueryRow> _evidence() => _database.customSelect(
        '''
        SELECT e.track_id, e.external_id, e.variant_key,
               s.value AS preferred, a.codec, a.actual_quality,
               NULL AS match_value, NULL AS source, NULL AS last_seen, NULL AS file_hash
          FROM external_track_refs e
          JOIN tracks t ON t.id = e.track_id
          LEFT JOIN library_folders f ON f.id = t.library_folder_id
          LEFT JOIN downloaded_assets a
            ON a.track_id = e.track_id AND a.state = 'verified'
           AND a.source = t.file_path AND a.file_size_bytes = t.file_size_bytes
           AND t.content_hash =
               '${FileContentIdentity.keyPrefix}' || a.file_size_bytes || ':' || a.content_hash
          LEFT JOIN app_settings s
            ON s.key = '$_preferencePrefix' || e.external_id || '.' || e.variant_key
         WHERE e.provider = 'yandex_music'
           AND (t.library_folder_id IS NULL OR f.is_enabled = 1)
           AND (e.origin IN ('embeddedTag', 'manual')
                OR (e.origin = 'providerResponse'
                    AND a.provider = e.provider AND a.external_id = e.external_id
                    AND a.variant_key = e.variant_key))
        UNION ALL
        SELECT t.id, NULL, NULL, s.value, NULL, NULL,
               m.value, t.file_path, t.last_seen_at, t.content_hash
          FROM app_settings m
          JOIN tracks t ON m.key = '$audioMatchSettingPrefix' || t.id
          LEFT JOIN library_folders f ON f.id = t.library_folder_id
          LEFT JOIN app_settings s ON s.key = '$_audioPreferencePrefix' ||
               substr(m.value, 1, instr(m.value, '|') - 1)
         WHERE t.is_missing = 0
           AND (t.library_folder_id IS NULL OR f.is_enabled = 1)
         ORDER BY 1, 2, 3
        ''',
        readsFrom: {
          _database.tracks,
          _database.libraryFolders,
          _database.externalTrackRefs,
          _database.downloadedAssets,
          _database.appSettings,
        },
      );

  @override
  Stream<LibraryVariantEvidence> watchEvidence() {
    final checked = <int, _CheckedMatch>{};
    return _evidence()
        .watch()
        // Unrelated settings (such as volume changes) must not rebuild the list.
        .distinct((left, right) =>
            left.length == right.length &&
            Iterable<int>.generate(left.length).every(
                (index) => mapEquals(left[index].data, right[index].data)))
        .asyncMap((rows) async {
      final current = {
        for (final row in rows)
          if (_storedMatch(row) case final match?) match: row,
      };
      checked.removeWhere((_, cached) => !current.containsKey(cached.match));
      for (final entry in current.entries) {
        final match = entry.key;
        final lastSeen = entry.value.readNullable<int>('last_seen');
        final fileHash = entry.value.readNullable<String>('file_hash');
        final previous = checked[match.id];
        if (previous?.match == match &&
            previous?.lastSeen == lastSeen &&
            previous?.fileHash == fileHash) {
          continue;
        }
        final revision = await _readRevision(match.path);
        checked[match.id] = (
          match: match,
          lastSeen: lastSeen,
          fileHash: fileHash,
          valid: revision == match.revision
        );
      }
      return _fromRows(rows, {
        for (final proof in checked.values)
          if (proof.valid) proof.match,
      });
    });
  }

  LibraryVariantEvidence _fromRows(
      List<QueryRow> rows, Set<_StoredMatch> valid) {
    final identities = <int, Set<ExternalTrackIdentity>>{};
    final preferred = <ExternalTrackIdentity, int>{};
    final quality = <int, LibraryVariantQuality>{};
    final matches = <int, String>{};
    for (final row in rows) {
      final trackId = row.read<int>('track_id');
      final preferredId =
          int.tryParse(row.readNullable<String>('preferred') ?? '');
      if (row.readNullable<String>('external_id') == null) {
        final match = _storedMatch(row);
        if (match != null && valid.contains(match)) {
          matches[trackId] = match.key;
          if (preferredId != null) {
            preferred[audioVariantIdentity(match.key)] = preferredId;
          }
        }
        continue;
      }
      final identity = ExternalTrackIdentity(
          provider: 'yandex_music',
          externalId: row.read<String>('external_id'),
          variantKey: row.read<String>('variant_key'));
      (identities[trackId] ??= {}).add(identity);
      if (preferredId != null) preferred[identity] = preferredId;
      final codec = row.readNullable<String>('codec');
      final profile = row.readNullable<String>('actual_quality');
      if (codec != null && profile != null) {
        quality[trackId] = (codec: codec, profile: profile);
      }
    }
    return LibraryVariantEvidence(
        identities: identities,
        preferred: preferred,
        quality: quality,
        audioMatches: matches);
  }

  _StoredMatch? _storedMatch(QueryRow row) {
    final value = row.readNullable<String>('match_value');
    final path = row.readNullable<String>('source');
    if (value == null || path == null || value.length > 160) return null;
    final parts = value.split('|');
    if (parts.length != 2 ||
        !isAudioMatchKey(parts[0]) ||
        !isAudioRevisionKey(parts[1])) {
      return null;
    }
    return (
      id: row.read<int>('track_id'),
      path: path,
      key: parts[0],
      revision: parts[1]
    );
  }

  Future<String?> _readRevision(String path) async {
    try {
      return await tryAudioRevision(
          revisionReader, AudioSourceReference.fromStorage(path));
    } on Object {
      return null;
    }
  }

  @override
  Future<AudioMatchSaveResult> rememberAudioMatch(AudioMatchProof proof) async {
    final firstId = proof.first.id!, secondId = proof.second.id!;
    final validated = <_StoredMatch>{};
    for (final row in await _evidence().get()) {
      final match = _storedMatch(row);
      if (match != null &&
          match.key == proof.key &&
          await _readRevision(match.path) == match.revision) {
        validated.add(match);
      }
    }
    if (await _readRevision(proof.first.filePath) != proof.firstRevision ||
        await _readRevision(proof.second.filePath) != proof.secondRevision) {
      return AudioMatchSaveResult.changed;
    }
    return _database.transaction(() async {
      final tracks = _database.tracks;
      final folders = _database.libraryFolders;
      final query = _database.select(tracks).join([
        leftOuterJoin(folders, folders.id.equalsExp(tracks.libraryFolderId),
            useColumns: false),
      ])
        ..where(tracks.isMissing.equals(false) &
            (tracks.libraryFolderId.isNull() | folders.isEnabled.equals(true)));
      final active =
          await query.map((row) => trackFromRow(row.readTable(tracks))).get();
      if (!active.any((track) =>
              track.id == firstId && track.filePath == proof.first.filePath) ||
          !active.any((track) =>
              track.id == secondId &&
              track.filePath == proof.second.filePath)) {
        return AudioMatchSaveResult.changed;
      }
      final evidence = _fromRows(await _evidence().get(), validated);
      final merged = LibraryVariantEvidence(
        identities: evidence.identities,
        audioMatches: {
          ...evidence.audioMatches,
          firstId: proof.key,
          secondId: proof.key
        },
      );
      if (!libraryAudioMatchFitsCatalogue(active, merged, firstId, secondId)) {
        return AudioMatchSaveResult.releaseConflict;
      }
      await _database.batch((batch) {
        batch.insertAllOnConflictUpdate(_database.appSettings, [
          AppSettingsCompanion.insert(
              key: audioMatchSettingKey(firstId),
              value: '${proof.key}|${proof.firstRevision}',
              updatedAt: DateTime.now()),
          AppSettingsCompanion.insert(
              key: audioMatchSettingKey(secondId),
              value: '${proof.key}|${proof.secondRevision}',
              updatedAt: DateTime.now()),
        ]);
      });
      return AudioMatchSaveResult.saved;
    });
  }

  @override
  Future<void> forgetAudioMatches(Map<int, String> matches) =>
      _database.batch((batch) {
        for (final entry in matches.entries) {
          if (!isAudioMatchKey(entry.value)) continue;
          batch.deleteWhere(
              _database.appSettings,
              (table) =>
                  table.key.equals(audioMatchSettingKey(entry.key)) &
                  table.value.like('${entry.value}|%'));
        }
      });

  @override
  Future<void> setPreferred(ExternalTrackIdentity identity, int? trackId) {
    final audio = identity.provider == 'local_pcm' &&
        identity.variantKey.isEmpty &&
        isAudioMatchKey(identity.externalId);
    if ((!isLibraryVariantIdentity(identity) && !audio) ||
        (trackId != null && trackId <= 0)) {
      throw ArgumentError('Некорректная версия трека.');
    }
    final key = audio
        ? '$_audioPreferencePrefix${identity.externalId}'
        : '$_preferencePrefix${identity.externalId}.${identity.variantKey}';
    return trackId == null
        ? _settings.delete(key)
        : _settings.writeString(key, trackId.toString());
  }
}
