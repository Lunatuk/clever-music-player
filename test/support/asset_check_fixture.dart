import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';

const abcHash =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
final assetCheckedAt = DateTime.utc(2026, 10, 15);

DownloadedAsset testAsset({AudioSourceReference? source}) => DownloadedAsset(
    publication: DownloadedAssetPublication(
        trackId: 1,
        identity:
            ExternalTrackIdentity(provider: 'yandex_music', externalId: '01'),
        source: source ?? FileAudioSource('/test.mp3'),
        publicationId: 'test-publication',
        requestedQuality: 'high'),
    verification: DownloadedAssetVerification(
        actualQuality: 'high',
        container: 'mp3',
        codec: 'mp3',
        fileSizeBytes: 3,
        duration: const Duration(seconds: 10),
        contentHash: abcHash,
        checkedAt: assetCheckedAt),
    state: DownloadedAssetState.verified,
    revision: 1);

Future<DownloadedAsset> registerTestAsset(DriftRepositories repo,
    {AudioSourceReference? source}) async {
  final asset = testAsset(source: source);
  final id = await repo.tracks.upsertTrack(Track.fromSource(
      source: asset.publication.source,
      addedAt: assetCheckedAt,
      updatedAt: assetCheckedAt));
  await repo.externalTracks.linkAll([
    ExternalTrackRef(
        trackId: id,
        identity: asset.publication.identity,
        origin: ExternalTrackRefOrigin.providerResponse,
        linkedAt: assetCheckedAt)
  ]);
  return repo.downloadedAssets.registerVerified(
      DownloadedAssetPublication(
          trackId: id,
          identity: asset.publication.identity,
          source: asset.publication.source,
          publicationId: asset.publication.publicationId,
          requestedQuality: 'high'),
      asset.verification);
}
