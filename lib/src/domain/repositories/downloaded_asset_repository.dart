import '../models/downloaded_asset.dart';
import '../models/external_track_ref.dart';

abstract interface class DownloadedAssetRepository {
  /// Register a completed, checked publication against an existing exact ref.
  /// A replay preserves state/revision. Replacing bytes/quality requires a new
  /// publication ID and the current snapshot; the musical identity stays fixed.
  Future<DownloadedAsset> registerVerified(
      DownloadedAssetPublication publication,
      DownloadedAssetVerification verification,
      {DownloadedAsset? replaces});

  Future<DownloadedAsset?> findForTrack(int trackId);

  /// Database candidates only. Check current OS access/file state before reuse.
  /// Destination is exact: null means standalone files, not any library folder.
  /// Actual quality is matched, never the requested label or filename extension.
  Future<List<DownloadedAsset>> findCandidates(ExternalTrackIdentity identity,
      {required String quality, required int? libraryFolderId});

  /// Compare-and-set state updates. Stale snapshots return false, without writes.
  Future<bool> invalidate(DownloadedAsset expected, DownloadedAssetState state);
  Future<bool> confirm(
      DownloadedAsset expected, DownloadedAssetVerification verification);
}
