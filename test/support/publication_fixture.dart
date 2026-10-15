import 'package:clever_music_player/src/domain/models/download_job.dart';
import 'package:clever_music_player/src/domain/models/downloaded_asset.dart';
import 'package:clever_music_player/src/domain/models/external_track_ref.dart';
import 'package:clever_music_player/src/domain/repositories/download_job_repository.dart';

final publicationNow = DateTime.utc(2030);
const publicationAbcHash =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
DownloadJob publicationJob(
        {String quality = 'high',
        String id = '001',
        String variant = '',
        int folder = 1,
        String token = '',
        DownloadJobState state = DownloadJobState.running,
        DownloadJobStage stage = DownloadJobStage.publication}) =>
    DownloadJob(
        id: 1,
        key: DownloadJobKey(
            libraryFolderId: folder,
            identity: ExternalTrackIdentity(
                provider: 'yandex_music', externalId: id, variantKey: variant),
            quality: quality),
        accountId: 1,
        accountRevision: 1,
        state: state,
        stage: stage,
        revision: 1,
        attemptCount: 1,
        maxAttempts: 3,
        remainingAttempts: 2,
        createdAt: publicationNow,
        updatedAt: publicationNow,
        attemptToken: token.isEmpty ? 'a' * 64 : token,
        leaseUntil: publicationNow.add(const Duration(minutes: 10)),
        retryAt: null,
        failure: null,
        completedTrackId: null);
DownloadedAssetVerification publicationProof(
        {String quality = 'high',
        String hash = publicationAbcHash,
        int size = 3}) =>
    DownloadedAssetVerification(
        actualQuality: quality,
        container: 'mp3',
        codec: 'mp3',
        fileSizeBytes: size,
        duration: const Duration(seconds: 3),
        contentHash: hash,
        checkedAt: publicationNow);

final class PublicationTestJobs implements DownloadJobRepository {
  PublicationTestJobs(this.path);
  final String path;
  bool owned = true;
  int fences = 0;
  Future<void> Function(int)? beforeFence;
  Future<void> Function(int)? afterFence;
  @override
  Future<T?> withOwnedDestination<T extends Object>(DownloadJob expected,
      {required DateTime Function() clock,
      required Future<T> Function(String destinationPath) action}) async {
    final number = ++fences;
    await beforeFence?.call(number);
    if (!owned) return null;
    final value = await action(path);
    await afterFence?.call(number);
    return value;
  }

  @override
  Future<List<DownloadAttempt>> listAttempts(int jobId,
          {int limit = 50}) async =>
      [
        DownloadAttempt(
            jobId: jobId,
            number: 1,
            token: 'a' * 64,
            accountId: 1,
            accountRevision: 1,
            stage: DownloadJobStage.publication,
            outcome: DownloadAttemptOutcome.running,
            startedAt: publicationNow,
            finishedAt: null,
            failure: null)
      ];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected job call');
}
