import 'downloaded_asset.dart';
import 'external_track_ref.dart';

enum DownloadJobState {
  queued,
  running,
  needsReconciliation,
  reconciling,
  completed,
  failed,
  cancelled
}

enum DownloadJobStage {
  download,
  metadata,
  verification,
  publication,
  importing
}

enum DownloadFailure {
  network,
  rateLimited,
  authorization,
  subscription,
  unavailable,
  invalidMedia,
  noSpace,
  accessDenied,
  internalError,
  interrupted,
  accountChanged,
  destinationDisabled,
  cancelled
}

enum DownloadAttemptOutcome {
  running,
  completed,
  failed,
  interrupted,
  cancelled
}

/// A managed destination, exact musical identity and requested resource quality.
/// Account/session and display names deliberately do not form the dedup key.
final class DownloadJobKey {
  factory DownloadJobKey(
      {required int libraryFolderId,
      required ExternalTrackIdentity identity,
      required String quality}) {
    if (libraryFolderId <= 0) {
      throw ArgumentError('Требуется папка назначения.');
    }
    validateAssetQuality(quality);
    return DownloadJobKey._(libraryFolderId, identity, quality);
  }
  const DownloadJobKey._(this.libraryFolderId, this.identity, this.quality);
  final int libraryFolderId;
  final ExternalTrackIdentity identity;
  final String quality;
  @override
  bool operator ==(Object other) =>
      other is DownloadJobKey &&
      libraryFolderId == other.libraryFolderId &&
      identity == other.identity &&
      quality == other.quality;
  @override
  int get hashCode => Object.hash(libraryFolderId, identity, quality);
}

/// A complete immutable CAS snapshot. Stages are intent/checkpoints, not proof
/// that a physical write has finished; interrupted work must be reconciled.
final class DownloadJob {
  const DownloadJob(
      {required this.id,
      required this.key,
      required this.accountId,
      required this.accountRevision,
      required this.state,
      required this.stage,
      required this.revision,
      required this.attemptCount,
      required this.maxAttempts,
      required this.remainingAttempts,
      required this.createdAt,
      required this.updatedAt,
      required this.attemptToken,
      required this.leaseUntil,
      required this.retryAt,
      required this.failure,
      required this.completedTrackId});
  final int id,
      accountId,
      accountRevision,
      revision,
      attemptCount,
      maxAttempts,
      remainingAttempts;
  final DownloadJobKey key;
  final DownloadJobState state;
  final DownloadJobStage stage;
  final DateTime createdAt, updatedAt;
  final String? attemptToken;
  final DateTime? leaseUntil, retryAt;
  final DownloadFailure? failure;

  /// Historical result ID; availability must still be verified before reuse.
  final int? completedTrackId;
  bool get isExecuting =>
      state == DownloadJobState.running ||
      state == DownloadJobState.reconciling;
  bool get isTerminal =>
      state == DownloadJobState.completed ||
      state == DownloadJobState.failed ||
      state == DownloadJobState.cancelled;
  @override
  bool operator ==(Object other) =>
      other is DownloadJob &&
      id == other.id &&
      key == other.key &&
      accountId == other.accountId &&
      accountRevision == other.accountRevision &&
      state == other.state &&
      stage == other.stage &&
      revision == other.revision &&
      attemptCount == other.attemptCount &&
      maxAttempts == other.maxAttempts &&
      remainingAttempts == other.remainingAttempts &&
      createdAt == other.createdAt &&
      updatedAt == other.updatedAt &&
      attemptToken == other.attemptToken &&
      leaseUntil == other.leaseUntil &&
      retryAt == other.retryAt &&
      failure == other.failure &&
      completedTrackId == other.completedTrackId;
  @override
  int get hashCode => Object.hashAll([
        id,
        key,
        accountId,
        accountRevision,
        state,
        stage,
        revision,
        attemptCount,
        maxAttempts,
        remainingAttempts,
        createdAt,
        updatedAt,
        attemptToken,
        leaseUntil,
        retryAt,
        failure,
        completedTrackId
      ]);
}

final class DownloadAttempt {
  const DownloadAttempt(
      {required this.jobId,
      required this.number,
      required this.token,
      required this.accountId,
      required this.accountRevision,
      required this.stage,
      required this.outcome,
      required this.startedAt,
      required this.finishedAt,
      required this.failure});
  final int jobId, number, accountId, accountRevision;
  final String token;
  final DownloadJobStage stage;
  final DownloadAttemptOutcome outcome;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final DownloadFailure? failure;
}
