import 'package:flutter/foundation.dart';

import '../../domain/models/models.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../library/library_track_variants.dart';
import '../drift/app_database.dart';

final class DriftLibraryVariantRepository implements LibraryVariantRepository {
  const DriftLibraryVariantRepository(this._database, this._settings);

  static const _preferencePrefix = 'library.preferred-version.v1.';
  final AppDatabase _database;
  final SettingsRepository _settings;

  @override
  Stream<LibraryVariantEvidence> watchEvidence() => _database
      .customSelect(
        '''
        SELECT e.track_id, e.external_id, e.variant_key,
               s.value AS preferred, a.codec, a.actual_quality
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
         ORDER BY e.track_id, e.external_id, e.variant_key
        ''',
        readsFrom: {
          _database.tracks,
          _database.libraryFolders,
          _database.externalTrackRefs,
          _database.downloadedAssets,
          _database.appSettings,
        },
      )
      .watch()
      // Unrelated settings (such as volume changes) must not rebuild the list.
      .distinct((left, right) =>
          left.length == right.length &&
          Iterable<int>.generate(left.length)
              .every((index) => mapEquals(left[index].data, right[index].data)))
      .map((rows) {
        final identities = <int, Set<ExternalTrackIdentity>>{};
        final preferred = <ExternalTrackIdentity, int>{};
        final quality = <int, LibraryVariantQuality>{};
        for (final row in rows) {
          final trackId = row.read<int>('track_id');
          final identity = ExternalTrackIdentity(
              provider: 'yandex_music',
              externalId: row.read<String>('external_id'),
              variantKey: row.read<String>('variant_key'));
          (identities[trackId] ??= {}).add(identity);
          final preferredId =
              int.tryParse(row.readNullable<String>('preferred') ?? '');
          if (preferredId != null) preferred[identity] = preferredId;
          final codec = row.readNullable<String>('codec');
          final profile = row.readNullable<String>('actual_quality');
          if (codec != null && profile != null) {
            quality[trackId] = (codec: codec, profile: profile);
          }
        }
        return LibraryVariantEvidence(
            identities: identities, preferred: preferred, quality: quality);
      });

  @override
  Future<void> setPreferred(ExternalTrackIdentity identity, int? trackId) {
    if (!isLibraryVariantIdentity(identity) ||
        (trackId != null && trackId <= 0)) {
      throw ArgumentError('Некорректная версия трека.');
    }
    final key =
        '$_preferencePrefix${identity.externalId}.${identity.variantKey}';
    return trackId == null
        ? _settings.delete(key)
        : _settings.writeString(key, trackId.toString());
  }
}
