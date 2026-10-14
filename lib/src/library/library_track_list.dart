import '../domain/models/models.dart';
import 'exact_track_copies.dart';

enum LibraryTrackSortOption {
  title,
  artist,
  album,
  recentlyAdded,
  recentlyPlayed,
  metadataConfidenceLowFirst,
}

extension LibraryTrackSortOptionLabel on LibraryTrackSortOption {
  String get label {
    return switch (this) {
      LibraryTrackSortOption.title => 'Название',
      LibraryTrackSortOption.artist => 'Исполнитель',
      LibraryTrackSortOption.album => 'Альбом',
      LibraryTrackSortOption.recentlyAdded => 'Недавно добавленные',
      LibraryTrackSortOption.recentlyPlayed => 'Недавно прослушанные',
      LibraryTrackSortOption.metadataConfidenceLowFirst =>
        'Уверенность метаданных (сначала низкая)',
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
  final visible = tracks.where((track) {
    if (!showMissingTracks && track.isMissing) {
      return false;
    }
    return trackMatchesSearch(track, searchQuery);
  }).toList(growable: false);

  return sortLibraryTracks(
    showExactCopies ? visible : withoutExactTrackCopies(visible),
    sortOption: sortOption,
    userStates: userStates,
  );
}

bool trackMatchesSearch(Track track, String query) {
  final normalizedQuery = _normalizeSearchValue(query);
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
      LibraryTrackSortOption.metadataConfidenceLowFirst =>
        _compareMetadataConfidence(left, right),
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

int _compareMetadataConfidence(Track left, Track right) {
  final leftConfidence = left.metadataConfidence ?? -1;
  final rightConfidence = right.metadataConfidence ?? -1;
  final confidenceComparison = leftConfidence.compareTo(rightConfidence);
  if (confidenceComparison != 0) {
    return confidenceComparison;
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
