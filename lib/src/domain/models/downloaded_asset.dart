import 'audio_source_reference.dart';
import 'external_track_ref.dart';

enum DownloadedAssetState {
  verified,
  missing,
  accessDenied,
  invalid;

  static DownloadedAssetState fromStorageKey(String key) =>
      values.firstWhere((value) => value.name == key,
          orElse: () =>
              throw const FormatException('Неизвестное состояние файла.'));
}

/// One completed publication, not a temporary file or a download job.
final class DownloadedAssetPublication {
  factory DownloadedAssetPublication({
    required int trackId,
    required ExternalTrackIdentity identity,
    required AudioSourceReference source,
    required String publicationId,
    required String requestedQuality,
  }) {
    if (trackId <= 0) throw ArgumentError('Требуется сохранённый ID трека.');
    if (_publicationPattern.stringMatch(publicationId) != publicationId) {
      throw const FormatException('Некорректный ID публикации файла.');
    }
    validateAssetQuality(requestedQuality);
    return DownloadedAssetPublication._(
        trackId, identity, source, publicationId, requestedQuality);
  }
  const DownloadedAssetPublication._(this.trackId, this.identity, this.source,
      this.publicationId, this.requestedQuality);
  final int trackId;
  final ExternalTrackIdentity identity;
  final AudioSourceReference source;
  final String publicationId, requestedQuality;

  @override
  bool operator ==(Object other) =>
      other is DownloadedAssetPublication &&
      trackId == other.trackId &&
      identity == other.identity &&
      source == other.source &&
      publicationId == other.publicationId &&
      requestedQuality == other.requestedQuality;
  @override
  int get hashCode =>
      Object.hash(trackId, identity, source, publicationId, requestedQuality);
}

/// Produced by a future physical file verifier, after tags/cover are written.
/// The registry records this evidence; it does not inspect audio itself.
final class DownloadedAssetVerification {
  factory DownloadedAssetVerification({
    required String actualQuality,
    required String container,
    required String codec,
    required int fileSizeBytes,
    required Duration duration,
    required String contentHash,
    required DateTime checkedAt,
  }) {
    validateAssetQuality(actualQuality);
    if (_formatPattern.stringMatch(container) != container ||
        _formatPattern.stringMatch(codec) != codec) {
      throw const FormatException('Некорректный формат аудиофайла.');
    }
    if (fileSizeBytes <= 0 || duration.inMilliseconds <= 0) {
      throw ArgumentError('Проверенный файл должен содержать аудио.');
    }
    final hash = contentHash.toLowerCase();
    if (_hashPattern.stringMatch(hash) != hash) {
      throw const FormatException('Требуется SHA-256 готового файла.');
    }
    return DownloadedAssetVerification._(
        actualQuality,
        container,
        codec,
        fileSizeBytes,
        Duration(milliseconds: duration.inMilliseconds),
        hash,
        checkedAt.toUtc());
  }
  const DownloadedAssetVerification._(
      this.actualQuality,
      this.container,
      this.codec,
      this.fileSizeBytes,
      this.duration,
      this.contentHash,
      this.checkedAt);
  final String actualQuality, container, codec, contentHash;
  final int fileSizeBytes;
  final Duration duration;
  final DateTime checkedAt;

  bool describesSameBytes(DownloadedAssetVerification other) =>
      actualQuality == other.actualQuality &&
      container == other.container &&
      codec == other.codec &&
      fileSizeBytes == other.fileSizeBytes &&
      duration == other.duration &&
      contentHash == other.contentHash;
  @override
  bool operator ==(Object other) =>
      other is DownloadedAssetVerification &&
      describesSameBytes(other) &&
      checkedAt == other.checkedAt;
  @override
  int get hashCode => Object.hash(actualQuality, container, codec,
      fileSizeBytes, duration, contentHash, checkedAt);
}

/// A revisioned snapshot. Keep it when starting a check and pass it back so
/// a late result cannot overwrite a newer publication or state change.
final class DownloadedAsset {
  factory DownloadedAsset({
    required DownloadedAssetPublication publication,
    required DownloadedAssetVerification verification,
    required DownloadedAssetState state,
    required int revision,
  }) {
    if (revision <= 0) throw ArgumentError('Некорректная ревизия файла.');
    return DownloadedAsset._(publication, verification, state, revision);
  }
  const DownloadedAsset._(
      this.publication, this.verification, this.state, this.revision);
  final DownloadedAssetPublication publication;
  final DownloadedAssetVerification verification;
  final DownloadedAssetState state;
  final int revision;
  bool get fulfillsRequestedQuality =>
      publication.requestedQuality == verification.actualQuality;

  @override
  bool operator ==(Object other) =>
      other is DownloadedAsset &&
      publication == other.publication &&
      verification == other.verification &&
      state == other.state &&
      revision == other.revision;
  @override
  int get hashCode => Object.hash(publication, verification, state, revision);
}

void validateAssetQuality(String value) {
  if (value.trim().isEmpty ||
      value.length > 128 ||
      value.runes.any((rune) => rune < 32 || rune == 127)) {
    throw const FormatException('Некорректное обозначение качества.');
  }
}

final _publicationPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
final _formatPattern = RegExp(r'^[a-z][a-z0-9._+-]{0,31}$');
final _hashPattern = RegExp(r'^[0-9a-f]{64}$');
