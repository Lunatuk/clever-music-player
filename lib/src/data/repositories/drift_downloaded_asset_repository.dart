import 'package:drift/drift.dart';

import '../../domain/models/audio_source_reference.dart';
import '../../domain/models/downloaded_asset.dart';
import '../../domain/models/external_track_ref.dart';
import '../../domain/repositories/downloaded_asset_repository.dart';
import '../drift/app_database.dart';

final class DriftDownloadedAssetRepository
    implements DownloadedAssetRepository {
  const DriftDownloadedAssetRepository(this.database);
  final AppDatabase database;

  @override
  Future<DownloadedAsset> registerVerified(
          DownloadedAssetPublication publication,
          DownloadedAssetVerification verification,
          {DownloadedAsset? replaces}) =>
      database.transaction(() async {
        if (!await _matchesCurrentTrack(publication, verification)) {
          throw StateError(
              'Источник или данные трека не соответствуют проверенному файлу.');
        }
        final refs = database.externalTrackRefs;
        final ref = await (database.select(refs)
              ..where((t) =>
                  t.trackId.equals(publication.trackId) &
                  t.provider.equals(publication.identity.provider) &
                  t.externalId.equals(publication.identity.externalId) &
                  t.variantKey.equals(publication.identity.variantKey)))
            .getSingleOrNull();
        if (ref == null) {
          throw StateError('Нет подтверждённой внешней ссылки трека.');
        }
        final current = await findForTrack(publication.trackId);
        if (current?.publication.publicationId == publication.publicationId) {
          if (current!.publication != publication ||
              !current.verification.describesSameBytes(verification)) {
            throw StateError('Повтор ID публикации с другими данными файла.');
          }
          return current;
        }
        if (current == null
            ? replaces != null
            : replaces == null ||
                !_sameRevision(current, replaces) ||
                current.publication.identity != publication.identity) {
          throw StateError(
              'Публикация уже изменена или относится к другому треку.');
        }
        final duplicate = await (database.select(database.downloadedAssets)
              ..where((t) => t.publicationId.equals(publication.publicationId)))
            .getSingleOrNull();
        if (duplicate != null) {
          throw StateError('ID публикации уже используется.');
        }
        final revision = (current?.revision ?? 0) + 1;
        final values = _values(publication, verification, revision);
        if (current == null) {
          await database.into(database.downloadedAssets).insert(values);
        } else {
          await (database.update(database.downloadedAssets)
                ..where((t) => t.trackId.equals(publication.trackId)))
              .write(values);
        }
        return DownloadedAsset(
            publication: publication,
            verification: verification,
            state: DownloadedAssetState.verified,
            revision: revision);
      });

  @override
  Future<DownloadedAsset?> findForTrack(int trackId) async {
    _validateTrackId(trackId);
    final row = await (database.select(database.downloadedAssets)
          ..where((t) => t.trackId.equals(trackId)))
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<List<DownloadedAsset>> findCandidates(ExternalTrackIdentity identity,
      {required String quality, required int? libraryFolderId}) {
    validateAssetQuality(quality);
    if (libraryFolderId != null) _validateTrackId(libraryFolderId);
    final assets = database.downloadedAssets, tracks = database.tracks;
    final folders = database.libraryFolders;
    final query = database.select(assets).join([
      innerJoin(tracks, tracks.id.equalsExp(assets.trackId)),
      leftOuterJoin(folders, folders.id.equalsExp(tracks.libraryFolderId)),
    ])
      ..where(assets.provider.equals(identity.provider) &
          assets.externalId.equals(identity.externalId) &
          assets.variantKey.equals(identity.variantKey) &
          assets.actualQuality.equals(quality) &
          assets.state.equals(DownloadedAssetState.verified.name) &
          tracks.isMissing.equals(false) &
          assets.source.equalsExp(tracks.filePath) &
          (tracks.fileSizeBytes.isNull() |
              tracks.fileSizeBytes.equalsExp(assets.fileSizeBytes)) &
          (tracks.contentHash.isNull() |
              tracks.contentHash.equalsExp(assets.contentHash)) &
          (tracks.libraryFolderId.isNull() | folders.isEnabled.equals(true)) &
          (libraryFolderId == null
              ? tracks.libraryFolderId.isNull()
              : tracks.libraryFolderId.equals(libraryFolderId)))
      ..orderBy([OrderingTerm(expression: assets.trackId)]);
    return query.get().then((rows) =>
        List.unmodifiable(rows.map((row) => _fromRow(row.readTable(assets)))));
  }

  @override
  Future<bool> invalidate(
      DownloadedAsset expected, DownloadedAssetState state) {
    if (state == DownloadedAssetState.verified) {
      throw ArgumentError('Для подтверждения файла требуется проверка.');
    }
    return database.transaction(() async {
      final current = await findForTrack(expected.publication.trackId);
      if (current == null || !_sameRevision(current, expected)) return false;
      if (current.state == state) return true;
      await (database.update(database.downloadedAssets)
            ..where((t) => t.trackId.equals(current.publication.trackId)))
          .write(DownloadedAssetsCompanion(
              state: Value(state.name), revision: Value(current.revision + 1)));
      return true;
    });
  }

  @override
  Future<bool> confirm(
          DownloadedAsset expected, DownloadedAssetVerification verification) =>
      database.transaction(() async {
        final current = await findForTrack(expected.publication.trackId);
        if (current == null ||
            !_sameRevision(current, expected) ||
            !current.verification.describesSameBytes(verification) ||
            verification.checkedAt.isBefore(current.verification.checkedAt) ||
            !await _matchesCurrentTrack(current.publication, verification)) {
          return false;
        }
        if (current.state == DownloadedAssetState.verified &&
            current.verification == verification) {
          return true;
        }
        await (database.update(database.downloadedAssets)
              ..where((t) => t.trackId.equals(current.publication.trackId)))
            .write(DownloadedAssetsCompanion(
                state: Value(DownloadedAssetState.verified.name),
                revision: Value(current.revision + 1),
                verifiedAtMicros:
                    Value(verification.checkedAt.microsecondsSinceEpoch)));
        return true;
      });

  Future<bool> _matchesCurrentTrack(DownloadedAssetPublication publication,
      DownloadedAssetVerification verification) async {
    final track = await (database.select(database.tracks)
          ..where((t) => t.id.equals(publication.trackId)))
        .getSingleOrNull();
    return track != null &&
        track.filePath == publication.source.storageValue &&
        (track.fileSizeBytes == null ||
            track.fileSizeBytes == verification.fileSizeBytes) &&
        (track.contentHash == null ||
            track.contentHash == verification.contentHash);
  }

  // Compare the complete snapshot as well: a removed/recreated slot must not
  // accept a stale operation even if a caller accidentally reuses its token.
  static bool _sameRevision(DownloadedAsset a, DownloadedAsset b) => a == b;

  static DownloadedAssetsCompanion _values(DownloadedAssetPublication p,
          DownloadedAssetVerification v, int revision) =>
      DownloadedAssetsCompanion(
          trackId: Value(p.trackId),
          provider: Value(p.identity.provider),
          externalId: Value(p.identity.externalId),
          variantKey: Value(p.identity.variantKey),
          source: Value(p.source.storageValue),
          publicationId: Value(p.publicationId),
          requestedQuality: Value(p.requestedQuality),
          actualQuality: Value(v.actualQuality),
          container: Value(v.container),
          codec: Value(v.codec),
          fileSizeBytes: Value(v.fileSizeBytes),
          durationMs: Value(v.duration.inMilliseconds),
          contentHash: Value(v.contentHash),
          verifiedAtMicros: Value(v.checkedAt.microsecondsSinceEpoch),
          state: Value(DownloadedAssetState.verified.name),
          revision: Value(revision));
  static DownloadedAsset _fromRow(DownloadedAssetRow r) => DownloadedAsset(
      publication: DownloadedAssetPublication(
          trackId: r.trackId,
          identity: ExternalTrackIdentity(
              provider: r.provider,
              externalId: r.externalId,
              variantKey: r.variantKey),
          source: AudioSourceReference.fromStorage(r.source),
          publicationId: r.publicationId,
          requestedQuality: r.requestedQuality),
      verification: DownloadedAssetVerification(
          actualQuality: r.actualQuality,
          container: r.container,
          codec: r.codec,
          fileSizeBytes: r.fileSizeBytes,
          duration: Duration(milliseconds: r.durationMs),
          contentHash: r.contentHash,
          checkedAt: DateTime.fromMicrosecondsSinceEpoch(r.verifiedAtMicros,
              isUtc: true)),
      state: DownloadedAssetState.fromStorageKey(r.state),
      revision: r.revision);
  static void _validateTrackId(int id) {
    if (id <= 0) throw ArgumentError('Требуется сохранённый ID источника.');
  }
}
