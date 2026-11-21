import '../domain/models/audio_source_reference.dart';
import '../library/audio_comparison.dart';
import '../library/library_scan_control.dart';
import '../library_sync/downloaded_audio_validation.dart';
import 'android_audio_metadata_backend.dart';

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
