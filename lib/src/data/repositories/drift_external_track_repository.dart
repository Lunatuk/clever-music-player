import 'package:drift/drift.dart';

import '../../domain/models/external_track_ref.dart';
import '../../domain/repositories/external_track_repository.dart';
import '../drift/app_database.dart';

typedef _RefKey = (int, String, String, String);
_RefKey _key(ExternalTrackRef ref) => (
      ref.trackId,
      ref.identity.provider,
      ref.identity.externalId,
      ref.identity.variantKey
    );

final class DriftExternalTrackRepository implements ExternalTrackRepository {
  const DriftExternalTrackRepository(this.database);
  final AppDatabase database;

  @override
  Future<void> linkAll(List<ExternalTrackRef> refs) {
    if (refs.length > ExternalTrackRepository.maxBatchSize) {
      throw ArgumentError('Слишком большой пакет внешних ссылок.');
    }
    if (refs.isEmpty) return Future.value();
    final unique = <_RefKey, ExternalTrackRef>{};
    for (final ref in refs) {
      final previous = unique[_key(ref)];
      unique[_key(ref)] = previous == null
          ? ref
          : ExternalTrackRef(
              trackId: ref.trackId,
              identity: ref.identity,
              origin: ref.origin.priority > previous.origin.priority
                  ? ref.origin
                  : previous.origin,
              linkedAt: previous.linkedAt);
    }
    return database.transaction(() async {
      final trackIds = unique.values.map((ref) => ref.trackId).toSet();
      final existingTracks = await (database.selectOnly(database.tracks)
            ..addColumns([database.tracks.id])
            ..where(database.tracks.id.isIn(trackIds)))
          .get();
      if (existingTracks.length != trackIds.length) {
        throw StateError(
            'Внешнюю ссылку можно связать только с существующим треком.');
      }
      final table = database.externalTrackRefs;
      final rows = await (database.select(table)
            ..where((t) => unique.values
                .map((ref) => _matches(t, ref.trackId, ref.identity))
                .reduce((a, b) => a | b)))
          .get();
      final existing = {for (final row in rows) _key(_fromRow(row)): row};
      await database.batch((batch) {
        for (final entry in unique.entries) {
          final ref = entry.value;
          final current = existing[entry.key];
          if (current == null) {
            batch.insert(
                table,
                ExternalTrackRefsCompanion.insert(
                    trackId: ref.trackId,
                    provider: ref.identity.provider,
                    externalId: ref.identity.externalId,
                    variantKey: Value(ref.identity.variantKey),
                    origin: ref.origin.storageKey,
                    linkedAt: ref.linkedAt));
          } else if (ref.origin.priority >
              ExternalTrackRefOrigin.fromStorageKey(current.origin).priority) {
            batch.update(
                table,
                ExternalTrackRefsCompanion(
                    origin: Value(ref.origin.storageKey)),
                where: (t) => _matches(t, ref.trackId, ref.identity));
          }
        }
      });
    });
  }

  @override
  Future<List<ExternalTrackRef>> listForTrack(int trackId) {
    _validateTrackId(trackId);
    final query = database.select(database.externalTrackRefs)
      ..where((t) => t.trackId.equals(trackId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.provider),
        (t) => OrderingTerm(expression: t.externalId),
        (t) => OrderingTerm(expression: t.variantKey)
      ]);
    return query.get().then((rows) => List.unmodifiable(rows.map(_fromRow)));
  }

  @override
  Future<List<ExternalTrackRef>> findRefs(ExternalTrackIdentity identity) {
    final query = database.select(database.externalTrackRefs)
      ..where((t) => _identityMatches(t, identity))
      ..orderBy([(t) => OrderingTerm(expression: t.trackId)]);
    return query.get().then((rows) => List.unmodifiable(rows.map(_fromRow)));
  }

  @override
  Future<void> unlink(int trackId, ExternalTrackIdentity identity) async {
    _validateTrackId(trackId);
    await database.transaction(() async {
      await (database.delete(database.downloadedAssets)
            ..where((t) =>
                t.trackId.equals(trackId) &
                t.provider.equals(identity.provider) &
                t.externalId.equals(identity.externalId) &
                t.variantKey.equals(identity.variantKey)))
          .go();
      await (database.delete(database.externalTrackRefs)
            ..where((t) => _matches(t, trackId, identity)))
          .go();
    });
  }

  static Expression<bool> _identityMatches(
          ExternalTrackRefs table, ExternalTrackIdentity identity) =>
      table.provider.equals(identity.provider) &
      table.externalId.equals(identity.externalId) &
      table.variantKey.equals(identity.variantKey);
  static Expression<bool> _matches(ExternalTrackRefs table, int trackId,
          ExternalTrackIdentity identity) =>
      table.trackId.equals(trackId) & _identityMatches(table, identity);
  static ExternalTrackRef _fromRow(ExternalTrackRefRow row) => ExternalTrackRef(
      trackId: row.trackId,
      identity: ExternalTrackIdentity(
          provider: row.provider,
          externalId: row.externalId,
          variantKey: row.variantKey),
      origin: ExternalTrackRefOrigin.fromStorageKey(row.origin),
      linkedAt: row.linkedAt);
  static void _validateTrackId(int trackId) {
    if (trackId <= 0) throw ArgumentError('Требуется сохранённый ID трека.');
  }
}
