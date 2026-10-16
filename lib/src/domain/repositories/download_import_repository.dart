import '../models/download_job.dart';
import '../models/download_publication.dart';

abstract interface class DownloadImportRepository {
  /// One short SQLite transaction: Track + provider ref + asset + completion.
  /// null means ownership/session/destination was lost; no partial writes.
  /// Matching completed publication replays preserve IDs/manual data/history.
  Future<DownloadImportResult?> commit(
      DownloadJob expected, DownloadedTrackImport publication,
      {required DateTime Function() clock});
}
