import '../domain/models/models.dart';
import 'embedded_yandex_identity.dart';
import 'exact_track_copies.dart';
import 'metadata_completeness.dart';

abstract interface class LibraryVariantRepository {
  Stream<LibraryVariantEvidence> watchEvidence();

  Future<void> setPreferred(ExternalTrackIdentity identity, int? trackId);
}

typedef LibraryVariantQuality = ({String codec, String profile});

final class LibraryVariantEvidence {
  const LibraryVariantEvidence({
    this.identities = const {},
    this.preferred = const {},
    this.quality = const {},
  });

  final Map<int, Set<ExternalTrackIdentity>> identities;
  final Map<ExternalTrackIdentity, int> preferred;
  final Map<int, LibraryVariantQuality> quality;
}

final class LibraryTrackVariants {
  const LibraryTrackVariants({
    required this.identity,
    required this.representative,
    required this.tracks,
    required this.sourceTracks,
    required this.preferredId,
  });

  final ExternalTrackIdentity identity;
  final Track representative;
  final List<Track> tracks;
  final List<Track> sourceTracks;
  final int? preferredId;

  List<Track> withPlaybackVersion(Track version, List<Track> visible) => [
        for (final track in visible)
          if (track.filePath == representative.filePath) version else track,
      ];
}

/// Use catalogue evidence only. A bare track link may join a single known
/// album, but it cannot connect two otherwise distinct releases.
List<LibraryTrackVariants> groupLibraryTrackVersions(
  Iterable<Track> tracks,
  LibraryVariantEvidence evidence, {
  required bool showExactCopies,
  required bool showMissingTracks,
}) {
  if (evidence.identities.isEmpty) return const [];
  final linked = <Track, ExternalTrackIdentity>{};
  final albums = <String, Set<String>>{};
  for (final track in tracks) {
    final identities = evidence.identities[track.id];
    if (identities == null) continue;
    final ids = <String>{};
    final trackAlbums = <String>{};
    for (final identity in identities) {
      final id = identity.externalId;
      final album = identity.variantKey;
      if (!isLibraryVariantIdentity(identity)) continue;
      ids.add(id);
      if (album.isNotEmpty) {
        trackAlbums.add(album);
        (albums[id] ??= {}).add(album);
      }
    }
    if ((showMissingTracks || !track.isMissing) &&
        ids.length == 1 &&
        trackAlbums.length <= 1) {
      linked[track] = ExternalTrackIdentity(
          provider: 'yandex_music',
          externalId: ids.single,
          variantKey: trackAlbums.isEmpty ? '' : trackAlbums.single);
    }
  }

  final byIdentity = <ExternalTrackIdentity, List<Track>>{};
  // Resolve Android aliases before examining the bytes of linked versions.
  for (final track in withoutRepeatedAudioSources(linked.keys)) {
    final identity = linked[track]!;
    final knownAlbums = albums[identity.externalId];
    if (identity.variantKey.isEmpty && (knownAlbums?.length ?? 0) > 1) {
      continue;
    }
    final key = identity.variantKey.isEmpty && knownAlbums != null
        ? ExternalTrackIdentity(
            provider: identity.provider,
            externalId: identity.externalId,
            variantKey: knownAlbums.single)
        : identity;
    (byIdentity[key] ??= []).add(track);
  }

  final groups = <LibraryTrackVariants>[];
  for (final entry in byIdentity.entries) {
    final versions = entry.value;
    if (versions.length < 2 || !_durationsAgree(versions)) continue;
    final preferredId = evidence.preferred[entry.key];
    final representative = _representative(versions, preferredId, evidence);
    final distinct = withoutExactTrackCopies(versions,
        preferEquivalent: (candidate) => candidate == representative);
    // The existing exact-copy control already handles byte-identical files.
    if (distinct.length < 2) continue;
    final members = List<Track>.of(showExactCopies ? versions : distinct)
      ..sort((left, right) => left.filePath.compareTo(right.filePath));
    members.remove(representative);
    members.insert(0, representative);
    groups.add(LibraryTrackVariants(
        identity: entry.key,
        representative: representative,
        tracks: List.unmodifiable(members),
        sourceTracks: List.unmodifiable(versions),
        preferredId: preferredId));
  }
  return groups;
}

bool isLibraryVariantIdentity(ExternalTrackIdentity identity) =>
    identity.provider == 'yandex_music' &&
    isYandexCatalogueId(identity.externalId) &&
    (identity.variantKey.isEmpty || isYandexCatalogueId(identity.variantKey));

bool _durationsAgree(List<Track> tracks) {
  final durations = tracks
      .map((track) => track.duration?.inMilliseconds ?? 0)
      .where((duration) => duration > 0)
      .toList();
  if (durations.length < 2) return true;
  durations.sort();
  return durations.last - durations.first <= 2000;
}

Track _representative(
    List<Track> tracks, int? preferredId, LibraryVariantEvidence evidence) {
  final available = tracks.where((track) => !track.isMissing).toList();
  final candidates = available.isEmpty ? tracks : available;
  for (final track in candidates) {
    if (preferredId != null && track.id == preferredId) return track;
  }
  final completeness = {
    for (final track in candidates) track: _tagCompleteness(track),
  };
  final bestCount = completeness.values.reduce((a, b) => a > b ? a : b);
  final complete =
      candidates.where((track) => completeness[track] == bestCount).toList();
  final lossless = complete
      .where((track) => evidence.quality[track.id]?.codec == 'flac')
      .toList();
  if (lossless.isNotEmpty) return lossless.reduce(_earlierTrack);

  // Quality floors are only comparable for validated profiles of one codec.
  final qualities = complete.map((track) => evidence.quality[track.id]);
  final codec = qualities.first?.codec;
  if (codec != null && qualities.every((quality) => quality?.codec == codec)) {
    return complete.reduce((left, right) {
      final comparison = _declaredFloor(evidence.quality[left.id]!.profile)
          .compareTo(_declaredFloor(evidence.quality[right.id]!.profile));
      if (comparison == 0) return _earlierTrack(left, right);
      return comparison > 0 ? left : right;
    });
  }
  return complete.reduce(_earlierTrack);
}

int _tagCompleteness(Track track) => switch (track.metadataSource) {
      MetadataSource.embeddedTags ||
      MetadataSource.manual =>
        MetadataCompleteness.forTrack(track).count,
      _ => 0,
    };

final _lossyProfile =
    RegExp(r'^yandex_(?:mp3|aacMp4)_(?:hq|nq)_([0-9]+)_[0-9]+$');
int _declaredFloor(String profile) =>
    int.tryParse(_lossyProfile.firstMatch(profile)?.group(1) ?? '') ?? 0;

Track _earlierTrack(Track left, Track right) {
  final leftId = left.id;
  final rightId = right.id;
  if (leftId != null && rightId != null && leftId != rightId) {
    return leftId < rightId ? left : right;
  }
  return left.filePath.compareTo(right.filePath) <= 0 ? left : right;
}
