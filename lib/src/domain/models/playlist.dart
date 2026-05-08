import 'track.dart';

final class Playlist {
  const Playlist({
    this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  Playlist copyWith({
    int? id,
    String? name,
    Object? description = _unsetPlaylistDescription,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: identical(description, _unsetPlaylistDescription)
          ? this.description
          : description as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Playlist &&
            other.id == id &&
            other.name == name &&
            other.description == description &&
            other.createdAt == createdAt &&
            other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(id, name, description, createdAt, updatedAt);
  }
}

final class PlaylistWithCount {
  const PlaylistWithCount({
    required this.playlist,
    required this.trackCount,
  });

  final Playlist playlist;
  final int trackCount;

  int? get id => playlist.id;
  String get name => playlist.name;
  String? get description => playlist.description;
  DateTime get createdAt => playlist.createdAt;
  DateTime get updatedAt => playlist.updatedAt;
}

final class PlaylistEntry {
  const PlaylistEntry({
    required this.playlistId,
    required this.trackId,
    required this.position,
    required this.addedAt,
    required this.track,
    this.unavailableReason,
  });

  final int playlistId;
  final int trackId;
  final int position;
  final DateTime addedAt;
  final Track track;
  final String? unavailableReason;

  bool get isPlayable => unavailableReason == null && !track.isMissing;
}

const Object _unsetPlaylistDescription = Object();
