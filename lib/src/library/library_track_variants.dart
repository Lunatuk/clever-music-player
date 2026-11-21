import '../domain/models/models.dart';
import '../domain/models/audio_document_identity.dart';
import 'audio_comparison.dart';
import 'embedded_yandex_identity.dart';
import 'exact_track_copies.dart';
import 'metadata_completeness.dart';

abstract interface class LibraryVariantRepository {
  Stream<LibraryVariantEvidence> watchEvidence();

  Future<void> setPreferred(ExternalTrackIdentity identity, int? trackId);
}

typedef LibraryVariantQuality = ({String codec, String profile});

const audioMatchSettingPrefix = 'library.audio-match.v1.';
String audioMatchSettingKey(int trackId) => '$audioMatchSettingPrefix$trackId';

enum AudioMatchSaveResult { saved, changed, releaseConflict }

abstract interface class AudioMatchRepository {
  Future<AudioMatchSaveResult> rememberAudioMatch(AudioMatchProof proof);

  Future<void> forgetAudioMatches(Map<int, String> matches);
}

final class LibraryVariantEvidence {
  const LibraryVariantEvidence({
    this.identities = const {},
    this.preferred = const {},
    this.quality = const {},
    this.audioMatches = const {},
  });

  final Map<int, Set<ExternalTrackIdentity>> identities;
  final Map<ExternalTrackIdentity, int> preferred;
  final Map<int, LibraryVariantQuality> quality;
  final Map<int, String> audioMatches;
}

final class LibraryTrackVariants {
  const LibraryTrackVariants({
    required this.identity,
    required this.representative,
    required this.tracks,
    required this.sourceTracks,
    required this.preferredId,
    this.audioMatches = const {},
  });

  final ExternalTrackIdentity identity;
  final Track representative;
  final List<Track> tracks;
  final List<Track> sourceTracks;
  final int? preferredId;
  final Map<int, String> audioMatches;

  List<Track> withPlaybackVersion(Track version, List<Track> visible) => [
        for (final track in visible)
          if (track.filePath == representative.filePath) version else track,
      ];
}

List<LibraryTrackVariants> groupLibraryTrackVersions(
  Iterable<Track> tracks,
  LibraryVariantEvidence evidence, {
  required bool showExactCopies,
  required bool showMissingTracks,
}) {
  final byIdentity = _versionAssignments(tracks, evidence, showMissingTracks);
  final groups = <LibraryTrackVariants>[];
  for (final entry in byIdentity.entries) {
    final versions = withoutRepeatedAudioSources(entry.value);
    if (versions.length < 2 ||
        (entry.key.provider == 'yandex_music' && !_durationsAgree(versions))) {
      continue;
    }
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
        sourceTracks: List.unmodifiable(entry.value),
        preferredId: preferredId,
        audioMatches: {
          for (final track in entry.value)
            if (evidence.audioMatches[track.id] case final String key)
              track.id!: key,
        }));
  }
  return groups;
}

bool libraryAudioMatchFitsCatalogue(Iterable<Track> tracks,
    LibraryVariantEvidence evidence, int firstId, int secondId) {
  final groups = _versionAssignments(tracks, evidence, false);
  return groups.entries.any((entry) =>
      entry.value.any((track) => track.id == firstId) &&
      entry.value.any((track) => track.id == secondId) &&
      (entry.key.provider == 'local_pcm' || _durationsAgree(entry.value)));
}

/// A bare catalogue link may join one known album. PCM proofs can attach
/// unlinked versions but never connect distinct or ambiguous catalogue groups.
Map<ExternalTrackIdentity, List<Track>> _versionAssignments(
    Iterable<Track> tracks,
    LibraryVariantEvidence evidence,
    bool showMissingTracks) {
  if (evidence.identities.isEmpty && evidence.audioMatches.isEmpty) return {};
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
  final keysById = <int?, ExternalTrackIdentity>{};
  final keysByDocument = <AudioDocumentIdentity, ExternalTrackIdentity>{};
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
    keysById[track.id] = key;
    final document = audioDocumentIdentity(track.filePath);
    if (document != null) keysByDocument[document] = key;
  }

  if (evidence.audioMatches.isEmpty) return byIdentity;
  final byAudio = <String, List<Track>>{};
  for (final track in tracks) {
    if ((!showMissingTracks && track.isMissing) ||
        evidence.audioMatches[track.id] == null) {
      continue;
    }
    final key = evidence.audioMatches[track.id]!;
    if (isAudioMatchKey(key)) (byAudio[key] ??= []).add(track);
  }
  for (final entry in byAudio.entries) {
    if (withoutRepeatedAudioSources(entry.value).length < 2) continue;
    final catalogueKeys = <ExternalTrackIdentity>{};
    final extras = <Track>[];
    var ambiguous = false;
    for (final track in entry.value) {
      final key = keysById[track.id] ??
          keysByDocument[audioDocumentIdentity(track.filePath)];
      if (key != null) {
        catalogueKeys.add(key);
        if (!byIdentity[key]!.contains(track)) extras.add(track);
      } else {
        ambiguous |= (evidence.identities[track.id]?.isNotEmpty ?? false);
        extras.add(track);
      }
    }
    if (ambiguous || catalogueKeys.length > 1 || extras.isEmpty) continue;
    if (catalogueKeys.isEmpty) {
      byIdentity[audioVariantIdentity(entry.key)] = extras;
    } else {
      final group = byIdentity[catalogueKeys.single]!;
      if (_durationsAgree([...group, ...extras])) group.addAll(extras);
    }
  }
  return byIdentity;
}

ExternalTrackIdentity audioVariantIdentity(String key) =>
    ExternalTrackIdentity(provider: 'local_pcm', externalId: key);

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
