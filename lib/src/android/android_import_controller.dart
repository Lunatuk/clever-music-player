import 'package:flutter/foundation.dart';

import '../domain/models/metadata_source.dart';
import '../domain/models/track.dart';
import '../domain/repositories/track_repository.dart';
import '../library/artwork_cache_service.dart';
import '../library/metadata_enrichment.dart';
import 'audio_documents.dart';

/// Owns only explicit document imports, never desktop folder scanning.
/// Close invalidates a pending picker and drains any accepted metadata/DB work.
final class AndroidImportController extends ChangeNotifier {
  AndroidImportController(
      {required this.documents,
      required this.imports,
      required this.artworkCache,
      DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final AudioDocuments documents;
  final TrackImportRepository imports;
  final ArtworkCacheService artworkCache;
  final DateTime Function() _clock;
  bool _closed = false;
  bool _busy = false;
  int _processed = 0, _total = 0;
  String? _message;
  Future<void>? _processing;
  Future<void>? _closing;
  bool get busy => _busy;
  int get processed => _processed;
  int get total => _total;
  String? get message => _message;

  Future<void> importSelection() async {
    if (_closed || _busy) return;
    _busy = true;
    _processed = _total = 0;
    _message = null;
    notifyListeners();
    try {
      final selection = await documents.pickAudio();
      if (_closed || selection == null) return;
      final processing = _import(selection);
      _processing = processing;
      await processing;
    } on Object {
      if (!_closed) {
        _message = 'Не удалось добавить музыку. Повторите выбор файлов.';
      }
    } finally {
      _processing = null;
      _busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> _import(AudioDocumentSelection selection) async {
    final sources = selection.sources.toSet().toList(growable: false);
    _total = sources.length;
    var imported = 0;
    var failed = selection.skipped;
    for (final source in sources) {
      if (_closed) return;
      try {
        final metadata = await documents.readAudio(source);
        if (_closed) return;
        // A missing cover/cache error must not prevent importing readable music.
        CachedArtwork? artwork;
        try {
          artwork = await artworkCache.saveEmbeddedArtwork(
              metadata.artwork == null
                  ? null
                  : EmbeddedArtwork(
                      bytes: metadata.artwork!, mimeType: 'image/webp'));
        } on Object {/* Keep the track without a cover. */}
        if (_closed) return;
        final now = _clock();
        final title = metadata.title ?? metadata.name ?? 'Без названия';
        await imports.upsertScannedTracks([
          Track.fromSource(
            source: source,
            title: title,
            artist: metadata.artist,
            album: metadata.album,
            albumArtist: metadata.albumArtist,
            genre: metadata.genre,
            duration: metadata.duration,
            fileSizeBytes: metadata.size,
            artworkPath: artwork?.path,
            artworkHash: artwork?.hash,
            artworkMimeType: artwork?.mimeType,
            metadataSource: metadata.title == null
                ? MetadataSource.filename
                : MetadataSource.embeddedTags,
            addedAt: now,
            updatedAt: now,
            lastSeenAt: now,
          )
        ]);
        imported++;
      } on Object {
        failed++;
      }
      if (_closed) return;
      _processed++;
      notifyListeners();
    }
    _message = 'Добавлено в библиотеку: $imported.'
        '${failed == 0 ? '' : ' Не добавлено: $failed. Выберите эти файлы заново.'}';
  }

  Future<void> close() {
    _closed = true;
    return _closing ??= _drain();
  }

  Future<void> _drain() async {
    await _processing;
  }

  @override
  void dispose() {
    // The app owner awaits close before closing SQLite. Widget unsubscription
    // alone must still stop a delayed picker from writing or notifying.
    _closed = true;
    super.dispose();
  }
}
