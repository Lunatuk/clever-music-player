import '../domain/models/models.dart';
import '../domain/models/audio_document_identity.dart';
import 'exact_track_copies.dart';
import 'library_track_variants.dart';
import 'metadata_completeness.dart';

enum LibraryTrackSortOption {
  title,
  artist,
  album,
  recentlyAdded,
  recentlyPlayed,
  metadataCompletenessLowFirst,
}

extension LibraryTrackSortOptionLabel on LibraryTrackSortOption {
  String get label {
    return switch (this) {
      LibraryTrackSortOption.title => 'Название',
      LibraryTrackSortOption.artist => 'Исполнитель',
      LibraryTrackSortOption.album => 'Альбом',
      LibraryTrackSortOption.recentlyAdded => 'Недавно добавленные',
      LibraryTrackSortOption.recentlyPlayed => 'Недавно прослушанные',
      LibraryTrackSortOption.metadataCompletenessLowFirst =>
        'Полнота сведений (сначала неполные)',
    };
  }
}

List<Track> buildVisibleLibraryTracks({
  required Iterable<Track> tracks,
  required String searchQuery,
  required bool showMissingTracks,
  required LibraryTrackSortOption sortOption,
  bool showExactCopies = false,
  Map<int, TrackUserState> userStates = const {},
}) {
  return buildLibraryTrackView(
    tracks: tracks,
    searchQuery: searchQuery,
    showMissingTracks: showMissingTracks,
    sortOption: sortOption,
    showExactCopies: showExactCopies,
    userStates: userStates,
  ).tracks;
}

typedef LibraryTrackView = ({
  List<Track> tracks,
  Map<String, LibraryTrackVariants> versions,
});

LibraryTrackView buildLibraryTrackView({
  required Iterable<Track> tracks,
  required String searchQuery,
  required bool showMissingTracks,
  required LibraryTrackSortOption sortOption,
  bool showExactCopies = false,
  Map<int, TrackUserState> userStates = const {},
  LibraryVariantEvidence evidence = const LibraryVariantEvidence(),
}) {
  final groups = groupLibraryTrackVersions(tracks, evidence,
      showExactCopies: showExactCopies, showMissingTracks: showMissingTracks);
  final byMember = {
    for (final group in groups)
      for (final track in group.sourceTracks) track.filePath: group,
  };
  final byDocument = <AudioDocumentIdentity, LibraryTrackVariants?>{};
  for (final entry in byMember.entries) {
    final document = audioDocumentIdentity(entry.key);
    if (document == null) continue;
    if (byDocument.containsKey(document) &&
        byDocument[document] != entry.value) {
      byDocument[document] = null;
    } else {
      byDocument[document] = entry.value;
    }
  }
  final seen = <LibraryTrackVariants>{};
  final visible = <Track>[];
  final normalizedQuery = _normalizeSearchValue(searchQuery);
  for (final track in tracks) {
    if ((!showMissingTracks && track.isMissing) ||
        !_matchesNormalizedSearch(track, normalizedQuery)) {
      continue;
    }
    final group = byMember[track.filePath] ??
        (byDocument.isEmpty
            ? null
            : byDocument[audioDocumentIdentity(track.filePath)]);
    if (group == null) {
      visible.add(track);
    } else if (seen.add(group)) {
      visible.add(group.representative);
    }
  }
  final byRepresentative = {
    for (final group in seen) group.representative.filePath: group,
  };
  final rows = showExactCopies
      ? withoutRepeatedAudioSources(visible)
      : withoutExactTrackCopies(visible,
          preferEquivalent: (track) =>
              byRepresentative.containsKey(track.filePath));
  final sortStates = sortOption == LibraryTrackSortOption.recentlyPlayed &&
          byRepresentative.isNotEmpty
      ? _withVariantPlaybackHistory(userStates, seen)
      : userStates;
  return (
    tracks:
        sortLibraryTracks(rows, sortOption: sortOption, userStates: sortStates),
    versions: byRepresentative,
  );
}

Map<int, TrackUserState> _withVariantPlaybackHistory(
    Map<int, TrackUserState> states, Iterable<LibraryTrackVariants> groups) {
  final result = Map<int, TrackUserState>.of(states);
  for (final group in groups) {
    final id = group.representative.id!;
    for (final track in group.sourceTracks) {
      final state = states[track.id];
      final playedAt = state?.lastPlayedAt;
      final latest = result[id]?.lastPlayedAt;
      if (playedAt != null && (latest == null || playedAt.isAfter(latest))) {
        result[id] = state!;
      }
    }
  }
  return result;
}

bool trackMatchesSearch(Track track, String query) =>
    _matchesNormalizedSearch(track, _normalizeSearchValue(query));

bool _matchesNormalizedSearch(Track track, String normalizedQuery) {
  if (normalizedQuery.isEmpty) {
    return true;
  }

  return _searchableTrackValues(track).any((value) {
    return _normalizeSearchValue(value).contains(normalizedQuery);
  });
}

List<Track> sortLibraryTracks(
  Iterable<Track> tracks, {
  required LibraryTrackSortOption sortOption,
  Map<int, TrackUserState> userStates = const {},
}) {
  final sorted = tracks.toList(growable: false);
  // Compute once per row, not repeatedly inside the O(n log n) comparator.
  final completeness =
      sortOption == LibraryTrackSortOption.metadataCompletenessLowFirst
          ? {
              for (final track in sorted)
                track: MetadataCompleteness.forTrack(track).count
            }
          : const <Track, int>{};
  sorted.sort((left, right) {
    final comparison = switch (sortOption) {
      LibraryTrackSortOption.title => _compareDisplayTitle(left, right),
      LibraryTrackSortOption.artist => _compareArtist(left, right),
      LibraryTrackSortOption.album => _compareAlbum(left, right),
      LibraryTrackSortOption.recentlyAdded => _compareRecentlyAdded(
          left,
          right,
        ),
      LibraryTrackSortOption.recentlyPlayed => _compareRecentlyPlayed(
          left,
          right,
          userStates,
        ),
      LibraryTrackSortOption.metadataCompletenessLowFirst =>
        _compareMetadataCompleteness(left, right, completeness),
    };

    if (comparison != 0) {
      return comparison;
    }
    return left.filePath.compareTo(right.filePath);
  });
  return sorted;
}

Iterable<String?> _searchableTrackValues(Track track) {
  return [
    track.title,
    track.artist,
    track.album,
    track.albumArtist,
    _fileName(track.filePath),
    track.filePath,
  ];
}

String _normalizeSearchValue(String? value) {
  return value?.trim().toLowerCase() ?? '';
}

String _fileName(String filePath) {
  return filePath.split(RegExp(r'[/\\]')).last;
}

int _compareDisplayTitle(Track left, Track right) {
  return _compareNonEmptyStrings(left.displayTitle, right.displayTitle);
}

int _compareArtist(Track left, Track right) {
  final artistComparison = _compareNullableStrings(left.artist, right.artist);
  if (artistComparison != 0) {
    return artistComparison;
  }
  return _compareDisplayTitle(left, right);
}

int _compareAlbum(Track left, Track right) {
  final albumComparison = _compareNullableStrings(left.album, right.album);
  if (albumComparison != 0) {
    return albumComparison;
  }

  final trackNumberComparison = _compareNullableInts(
    left.trackNumber,
    right.trackNumber,
  );
  if (trackNumberComparison != 0) {
    return trackNumberComparison;
  }

  return _compareDisplayTitle(left, right);
}

int _compareRecentlyAdded(Track left, Track right) {
  final dateComparison = right.addedAt.compareTo(left.addedAt);
  if (dateComparison != 0) {
    return dateComparison;
  }
  return _compareDisplayTitle(left, right);
}

int _compareRecentlyPlayed(
  Track left,
  Track right,
  Map<int, TrackUserState> userStates,
) {
  final leftPlayedAt =
      left.id == null ? null : userStates[left.id]?.lastPlayedAt;
  final rightPlayedAt =
      right.id == null ? null : userStates[right.id]?.lastPlayedAt;
  final dateComparison = _compareNullableDatesDesc(leftPlayedAt, rightPlayedAt);
  if (dateComparison != 0) {
    return dateComparison;
  }
  return _compareDisplayTitle(left, right);
}

int _compareMetadataCompleteness(
    Track left, Track right, Map<Track, int> counts) {
  final comparison = counts[left]!.compareTo(counts[right]!);
  if (comparison != 0) {
    return comparison;
  }
  return _compareDisplayTitle(left, right);
}

int _compareNullableStrings(String? left, String? right) {
  final normalizedLeft = _normalizeSortValue(left);
  final normalizedRight = _normalizeSortValue(right);
  if (normalizedLeft.isEmpty && normalizedRight.isEmpty) {
    return 0;
  }
  if (normalizedLeft.isEmpty) {
    return 1;
  }
  if (normalizedRight.isEmpty) {
    return -1;
  }
  return normalizedLeft.compareTo(normalizedRight);
}

int _compareNonEmptyStrings(String left, String right) {
  return _normalizeSortValue(left).compareTo(_normalizeSortValue(right));
}

String _normalizeSortValue(String? value) {
  return value?.trim().toLowerCase() ?? '';
}

int _compareNullableInts(int? left, int? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return left.compareTo(right);
}

int _compareNullableDatesDesc(DateTime? left, DateTime? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return right.compareTo(left);
}
