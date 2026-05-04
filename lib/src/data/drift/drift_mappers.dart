import 'package:drift/drift.dart';

import '../../domain/models/models.dart';
import 'app_database.dart';

LibraryFolder libraryFolderFromRow(LibraryFolderRow row) {
  return LibraryFolder(
    id: row.id,
    path: row.path,
    displayName: row.displayName,
    isEnabled: row.isEnabled,
    isRecursive: row.isRecursive,
    lastScannedAt: row.lastScannedAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

LibraryFoldersCompanion libraryFolderToCompanion(LibraryFolder folder) {
  return LibraryFoldersCompanion(
    id: folder.id == null ? const Value.absent() : Value(folder.id!),
    path: Value(folder.path),
    displayName: Value(folder.displayName),
    isEnabled: Value(folder.isEnabled),
    isRecursive: Value(folder.isRecursive),
    lastScannedAt: Value(folder.lastScannedAt),
    createdAt: Value(folder.createdAt),
    updatedAt: Value(folder.updatedAt),
  );
}

Track trackFromRow(TrackRow row) {
  return Track(
    id: row.id,
    libraryFolderId: row.libraryFolderId,
    stableId: row.stableId,
    filePath: row.filePath,
    contentHash: row.contentHash,
    title: row.title,
    artist: row.artist,
    album: row.album,
    albumArtist: row.albumArtist,
    genre: row.genre,
    artworkPath: row.artworkPath,
    artworkHash: row.artworkHash,
    artworkMimeType: row.artworkMimeType,
    codec: row.codec,
    duration: _durationFromMilliseconds(row.durationMs),
    trackNumber: row.trackNumber,
    discNumber: row.discNumber,
    year: row.year,
    metadataSource: MetadataSource.fromStorageKey(row.metadataSource),
    metadataConfidence: row.metadataConfidence,
    fileSizeBytes: row.fileSizeBytes,
    modifiedAt: row.modifiedAt,
    lastSeenAt: row.lastSeenAt,
    isMissing: row.isMissing,
    addedAt: row.addedAt,
    updatedAt: row.updatedAt,
  );
}

Playlist playlistFromRow(PlaylistRow row) {
  return Playlist(
    id: row.id,
    name: row.name,
    description: row.description,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

PlaylistsCompanion playlistToCompanion(Playlist playlist) {
  return PlaylistsCompanion(
    id: playlist.id == null ? const Value.absent() : Value(playlist.id!),
    name: Value(playlist.name),
    description: Value(playlist.description),
    createdAt: Value(playlist.createdAt),
    updatedAt: Value(playlist.updatedAt),
  );
}

TracksCompanion trackToCompanion(Track track) {
  return TracksCompanion(
    id: track.id == null ? const Value.absent() : Value(track.id!),
    libraryFolderId: Value(track.libraryFolderId),
    stableId: Value(track.stableId),
    filePath: Value(track.filePath),
    contentHash: Value(track.contentHash),
    title: Value(track.title),
    artist: Value(track.artist),
    album: Value(track.album),
    albumArtist: Value(track.albumArtist),
    genre: Value(track.genre),
    artworkPath: Value(track.artworkPath),
    artworkHash: Value(track.artworkHash),
    artworkMimeType: Value(track.artworkMimeType),
    codec: Value(track.codec),
    durationMs: Value(track.duration?.inMilliseconds),
    trackNumber: Value(track.trackNumber),
    discNumber: Value(track.discNumber),
    year: Value(track.year),
    metadataSource: Value(track.metadataSource?.storageKey),
    metadataConfidence: Value(track.metadataConfidence),
    fileSizeBytes: Value(track.fileSizeBytes),
    modifiedAt: Value(track.modifiedAt),
    lastSeenAt: Value(track.lastSeenAt),
    isMissing: Value(track.isMissing),
    addedAt: Value(track.addedAt),
    updatedAt: Value(track.updatedAt),
  );
}

PlaybackEvent playbackEventFromRow(PlaybackEventRow row) {
  return PlaybackEvent(
    id: row.id,
    trackId: row.trackId,
    type: PlaybackEventType.fromStorageKey(row.eventType),
    occurredAt: row.occurredAt,
    position: _durationFromMilliseconds(row.positionMs),
    trackDuration: _durationFromMilliseconds(row.durationMs),
    waveMode:
        row.waveMode == null ? null : WaveMode.fromStorageKey(row.waveMode),
    metadataJson: row.metadataJson,
  );
}

PlaybackEventsCompanion playbackEventToCompanion(PlaybackEvent event) {
  return PlaybackEventsCompanion(
    id: event.id == null ? const Value.absent() : Value(event.id!),
    trackId: Value(event.trackId),
    eventType: Value(event.type.storageKey),
    occurredAt: Value(event.occurredAt),
    positionMs: Value(event.position?.inMilliseconds),
    durationMs: Value(event.trackDuration?.inMilliseconds),
    waveMode: Value(event.waveMode?.storageKey),
    metadataJson: Value(event.metadataJson),
  );
}

TrackUserState trackUserStateFromRow(TrackUserStateRow row) {
  return TrackUserState(
    trackId: row.trackId,
    isFavorite: row.isFavorite,
    isHidden: row.isHidden,
    rating: row.rating,
    playCount: row.playCount,
    completeCount: row.completeCount,
    skipCount: row.skipCount,
    lastPlayedAt: row.lastPlayedAt,
    lastSkippedAt: row.lastSkippedAt,
    lastCompletedAt: row.lastCompletedAt,
    userScoreBoost: row.userScoreBoost,
    preferredWaveMode: row.preferredWaveMode == null
        ? null
        : WaveMode.fromStorageKey(row.preferredWaveMode),
    updatedAt: row.updatedAt,
  );
}

TrackUserStatesCompanion trackUserStateToCompanion(TrackUserState state) {
  return TrackUserStatesCompanion(
    trackId: Value(state.trackId),
    isFavorite: Value(state.isFavorite),
    isHidden: Value(state.isHidden),
    rating: Value(state.rating),
    playCount: Value(state.playCount),
    completeCount: Value(state.completeCount),
    skipCount: Value(state.skipCount),
    lastPlayedAt: Value(state.lastPlayedAt),
    lastSkippedAt: Value(state.lastSkippedAt),
    lastCompletedAt: Value(state.lastCompletedAt),
    userScoreBoost: Value(state.userScoreBoost),
    preferredWaveMode: Value(state.preferredWaveMode?.storageKey),
    updatedAt: Value(state.updatedAt),
  );
}

AppSetting appSettingFromRow(AppSettingRow row) {
  return AppSetting(
    key: row.key,
    value: row.value,
    updatedAt: row.updatedAt,
  );
}

AppSettingsCompanion appSettingToCompanion(AppSetting setting) {
  return AppSettingsCompanion(
    key: Value(setting.key),
    value: Value(setting.value),
    updatedAt: Value(setting.updatedAt),
  );
}

Duration? _durationFromMilliseconds(int? milliseconds) {
  return milliseconds == null ? null : Duration(milliseconds: milliseconds);
}
