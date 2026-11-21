import '../domain/models/audio_source_reference.dart';
import '../library/audio_comparison.dart';
import '../library/library_scan_control.dart';
import '../library_sync/downloaded_audio_validation.dart';
import 'android_audio_metadata_backend.dart';
import 'audio_documents.dart';

Future<String?> readAndroidAudioRevision(AudioSourceReference source) async {
  if (source is! ContentUriAudioSource) return null;
  final revision = await const AndroidAudioDocuments().inspectAudio(source);
  if (revision == null || revision.size > audioComparisonMaxBytes) return null;
  return audioRevisionKey([
    'android',
    source.storageValue,
    revision.authority,
    revision.documentId,
    revision.name,
    revision.size,
    revision.modifiedMs
  ]);
}

final class AndroidAudioComparisonReader implements AudioComparisonReader {
  AndroidAudioComparisonReader(this._backend);

  static Future<AndroidAudioComparisonReader> open(
      LibraryScanControl control) async {
    final backend = AndroidAudioMetadataBackend();
    try {
      await backend.capabilities(control);
      return AndroidAudioComparisonReader(backend);
    } on Object {
      await backend.close();
      rethrow;
    }
  }

  final AndroidAudioMetadataBackend _backend;

  @override
  Future<AudioPcmSignature> read(
      AudioSourceReference source, LibraryScanControl control) {
    if (source is! ContentUriAudioSource) {
      throw const AudioValidationException(
          AudioValidationOutcome.unsupportedSource);
    }
    return _backend.compareDocumentAudio(source, control);
  }

  @override
  Future<void> close() => _backend.close();
}
