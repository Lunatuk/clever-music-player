import '../domain/models/audio_source_reference.dart';
import '../domain/models/audio_document_identity.dart';

final class AudioDocumentRevision {
  const AudioDocumentRevision(
      {required this.authority,
      required this.documentId,
      required this.name,
      required this.size,
      required this.modifiedMs});
  final String authority, documentId, name;
  final int size, modifiedMs;

  static AudioDocumentRevision? parse(Object? value) {
    if (value is! Map || value['version'] != 1) return null;
    final authority = value['authority'], id = value['documentId'];
    final name = value['name'],
        size = value['size'],
        modified = value['modifiedMs'];
    if (authority is! String ||
        authority.isEmpty ||
        authority.length > 512 ||
        id is! String ||
        id.isEmpty ||
        id.length > 4096 ||
        name is! String ||
        name.isEmpty ||
        name.length > 4096 ||
        size is! int ||
        size <= 0 ||
        size > 9007199254740991 ||
        modified is! int ||
        modified <= 0 ||
        modified > 8640000000000000) {
      return null;
    }
    return AudioDocumentRevision(
        authority: authority,
        documentId: id,
        name: name,
        size: size,
        modifiedMs: modified);
  }

  @override
  bool operator ==(Object other) =>
      other is AudioDocumentRevision &&
      authority == other.authority &&
      documentId == other.documentId &&
      name == other.name &&
      size == other.size &&
      modifiedMs == other.modifiedMs;
  @override
  int get hashCode =>
      Object.hash(authority, documentId, name, size, modifiedMs);
}

abstract interface class AudioDocumentInspection {
  /// Checks current permission/readability. Null means ordinary reading is needed.
  Future<AudioDocumentRevision?> inspectAudio(ContentUriAudioSource source);
}

abstract interface class ProfiledAudioDocumentInspection {
  Future<AudioDocumentInspectionResult> inspectProfiledAudio(
      ContentUriAudioSource source);
}

final class AudioDocumentInspectionResult {
  const AudioDocumentInspectionResult(this.revision, {this.timings});
  final AudioDocumentRevision? revision;
  final AudioDocumentInspectionTimings? timings;
}

/// Revision time includes visibility checks. Do not sum those two fields.
final class AudioDocumentInspectionTimings {
  const AudioDocumentInspectionTimings(
      {required this.totalUs,
      required this.permissionUs,
      required this.revisionUs,
      required this.visibilityUs,
      required this.descriptorUs,
      this.artworkUs = 0});
  final int totalUs, permissionUs, revisionUs, visibilityUs, descriptorUs;
  final int artworkUs;

  static AudioDocumentInspectionTimings? parse(Object? value) {
    if (value is! Map || value['version'] != 1) return null;
    const keys = [
      'totalUs',
      'permissionUs',
      'revisionUs',
      'visibilityUs',
      'descriptorUs'
    ];
    for (final key in keys) {
      final v = value[key];
      if (v is! int || v < 0 || v > 3600000000) return null;
    }
    final artworkUs = value['artworkUs'] ?? 0;
    if (artworkUs is! int || artworkUs < 0 || artworkUs > 3600000000) {
      return null;
    }
    if ((value['permissionUs'] as int) +
                (value['revisionUs'] as int) +
                (value['descriptorUs'] as int) +
                artworkUs >
            (value['totalUs'] as int) ||
        (value['visibilityUs'] as int) > (value['revisionUs'] as int)) {
      return null;
    }
    return AudioDocumentInspectionTimings(
        totalUs: value['totalUs'] as int,
        permissionUs: value['permissionUs'] as int,
        revisionUs: value['revisionUs'] as int,
        visibilityUs: value['visibilityUs'] as int,
        descriptorUs: value['descriptorUs'] as int,
        artworkUs: artworkUs);
  }
}

const maxAudioInspectionBatchSize = 8;
const audioInspectionProofLifetimeUs = 500000;

abstract interface class BatchedAudioDocumentInspection {
  Future<AudioInspectionBatchResult> inspectAudioBatch(
      int batch, List<AudioInspectionBatchRequest> items);
  Future<void> cancelAudioInspectionBatch(int batch);
}

final class AudioInspectionBatchRequest {
  const AudioInspectionBatchRequest(this.source,
      {this.artworkPath, this.artworkHash});
  final ContentUriAudioSource source;
  final String? artworkPath, artworkHash;
  bool get hasArtwork => artworkPath != null;
  Map<String, Object?> message() => {
        'source': source.storageValue,
        'hasArtwork': hasArtwork,
        'artworkPath': artworkPath,
        'artworkHash': artworkHash
      };

  static void validate(int batch, List<AudioInspectionBatchRequest> items) {
    if (batch <= 0 ||
        items.isEmpty ||
        items.length > maxAudioInspectionBatchSize ||
        items.map((i) => i.source).toSet().length != items.length ||
        items.any((i) =>
            i.source.storageValue.length > 16384 ||
            (i.artworkPath == null) != (i.artworkHash == null))) {
      throw ArgumentError('Invalid inspection batch');
    }
  }
}

enum AudioArtworkCheck { unchecked, available, missing, absent }

final class AudioInspectionBatchEntry {
  const AudioInspectionBatchEntry(
      {required this.source,
      required this.inspection,
      required this.artwork,
      required this.failed,
      required this.ageUs});
  final ContentUriAudioSource source;
  final AudioDocumentInspectionResult inspection;
  final AudioArtworkCheck artwork;
  final bool failed;
  final int ageUs;
}

final class AudioInspectionBatchResult {
  AudioInspectionBatchResult(List<AudioInspectionBatchEntry> entries,
      {required this.cancelled})
      : entries = List.unmodifiable(entries);
  final List<AudioInspectionBatchEntry> entries;
  final bool cancelled;

  static AudioInspectionBatchResult parse(
      Object? value, List<AudioInspectionBatchRequest> requests) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['results'] is! List ||
        value['cancelled'] is! bool) {
      throw const FormatException('Invalid inspection batch response');
    }
    final frames = value['results'] as List;
    if (frames.length > requests.length ||
        value['consumed'] != frames.length ||
        (frames.isEmpty && value['cancelled'] == false)) {
      throw const FormatException('Invalid inspection batch prefix');
    }
    final result = <AudioInspectionBatchEntry>[];
    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i], request = requests[i];
      if (frame is! Map ||
          frame['source'] != request.source.storageValue ||
          frame['failed'] is! bool ||
          frame['ageUs'] is! int ||
          (frame['ageUs'] as int) < 0 ||
          (frame['ageUs'] as int) > 3600000000 ||
          frame['artwork'] is! int ||
          (frame['artwork'] as int) < 0 ||
          (frame['artwork'] as int) > 3) {
        throw const FormatException('Invalid inspection batch item');
      }
      final failed = frame['failed'] as bool;
      final artwork = AudioArtworkCheck.values[frame['artwork'] as int];
      if (!failed &&
          ((request.hasArtwork && artwork == AudioArtworkCheck.absent) ||
              (!request.hasArtwork && artwork != AudioArtworkCheck.absent))) {
        throw const FormatException('Artwork proof does not match request');
      }
      final revision = failed ? null : AudioDocumentRevision.parse(frame);
      final identity = audioDocumentIdentity(request.source.storageValue);
      if (revision != null &&
          (identity == null ||
              identity.authority != revision.authority ||
              identity.documentId != revision.documentId)) {
        throw const FormatException(
            'Revision does not match requested document');
      }
      result.add(AudioInspectionBatchEntry(
          source: request.source,
          failed: failed,
          ageUs: frame['ageUs'] as int,
          artwork: artwork,
          inspection: AudioDocumentInspectionResult(revision,
              timings: AudioDocumentInspectionTimings.parse(
                  frame['inspectionTimings']))));
    }
    return AudioInspectionBatchResult(result,
        cancelled: value['cancelled'] as bool);
  }
}
