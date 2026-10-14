import '../models/external_track_ref.dart';

abstract interface class ExternalTrackRepository {
  static const maxBatchSize = 64;

  /// Atomic, bounded association of existing local records. Repeated links are
  /// idempotent, retain the first linkedAt and never downgrade provenance.
  /// No matching by metadata, file IO, downloading or track mutation occurs.
  Future<void> linkAll(List<ExternalTrackRef> refs);

  Future<List<ExternalTrackRef>> listForTrack(int trackId);

  /// All linked copies, including missing/disabled sources. An external ID
  /// alone does not establish a unique usable or verified downloaded asset.
  Future<List<ExternalTrackRef>> findRefs(ExternalTrackIdentity identity);

  /// Remove just this association, preserving tracks/files and user data.
  Future<void> unlink(int trackId, ExternalTrackIdentity identity);
}
