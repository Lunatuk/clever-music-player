import 'dart:io';

import 'package:path/path.dart' as p;

import '../android/android_audio_metadata_backend.dart';
import '../domain/models/models.dart';
import '../domain/repositories/library_sync_repository.dart';
import '../library/embedded_yandex_identity.dart';
import '../library/library_scan_control.dart';
import '../library/metadata_completeness.dart';
import '../library/metadata_reader_service.dart';
import 'bundled_media_helper.dart';
import 'downloaded_audio_validation.dart';
import 'ffmpeg_audio_metadata_backend.dart';
import 'yandex_audio_selection.dart';

/// Finds a usable existing copy for this update. No job completion, publication
/// record or audio transfer is created for these files.
final class YandexLocalCopyMatcher {
  YandexLocalCopyMatcher(this.repository, this.inspect, {this.closeProbe});

  factory YandexLocalCopyMatcher.forPlatform(
      LocalDownloadCandidateRepository repository) {
    if (Platform.isAndroid) {
      final backend = AndroidAudioMetadataBackend();
      return YandexLocalCopyMatcher(repository, (source, control) async {
        if (source is! ContentUriAudioSource) return null;
        return backend.inspectDocument(source, control);
      }, closeProbe: backend.close);
    }
    BundledMediaHelper? helper;
    FfmpegAudioMetadataBackend? backend;
    Future<QualifiedMediaHelper>? qualification;
    return YandexLocalCopyMatcher(repository, (source, control) async {
      if (source is! FileAudioSource || !p.isAbsolute(source.path)) return null;
      final file = File(source.path);
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final before = await file.stat();
      if (before.type != FileSystemEntityType.file || before.size <= 0) {
        return null;
      }
      if (backend == null) {
        helper ??= BundledMediaHelper.forCurrentProcess();
        qualification ??= helper!.qualify(control: control);
        backend = (await qualification!).createMetadataBackend();
      }
      final info = await backend!.inspect(file, control);
      final comment = info.tags['comment'];
      if (comment == null) return null;
      final linked =
          await const AudioMetadataReaderService().readYandexIdentity(file);
      if (linked == null || linked != embeddedYandexIdentity([comment])) {
        return null;
      }
      control.throwIfCancelled();
      final after = await file.stat();
      if (after.type != FileSystemEntityType.file ||
          after.size != before.size ||
          info.sizeBytes != after.size ||
          after.modified != before.modified ||
          after.changed != before.changed) {
        return null;
      }
      return info;
    }, closeProbe: () async {
      try {
        await backend?.close();
      } finally {
        await helper?.close();
      }
    });
  }

  final LocalDownloadCandidateRepository repository;
  final Future<DownloadedAudioInspection?> Function(
      AudioSourceReference, LibraryScanControl) inspect;
  final Future<void> Function()? closeProbe;

  Future<Map<DownloadJobKey, LocalDownloadCandidate>> match(
      LibrarySyncPlan plan,
      YandexAudioSelection selection,
      LibraryScanControl control) async {
    final items = plan.items.where(canUseLocalDownload).toList(growable: false);
    final accepted = <DownloadJobKey, LocalDownloadCandidate>{};
    for (var start = 0; start < items.length; start += 64) {
      control.throwIfCancelled();
      final batch = items.skip(start).take(64).toList(growable: false);
      final rows = await repository.findLocalCandidates(
          batch.map((item) => item.key.identity.externalId).toSet());
      final byId = <String, List<LocalDownloadCandidate>>{};
      for (final row in rows) {
        (byId[row.identity.externalId] ??= []).add(row);
      }
      final inspected = <AudioSourceReference, DownloadedAudioInspection?>{};
      for (final item in batch) {
        control.throwIfCancelled();
        LocalDownloadCandidate? best;
        var bestFields = -1, bestBitRate = -1;
        final candidates = matchingLocalCandidates(
            item.key.identity, byId[item.key.identity.externalId] ?? const []);
        for (final candidate in candidates.take(8)) {
          control.throwIfCancelled();
          final info = await _inspect(candidate.track, inspected, control);
          control.throwIfCancelled();
          if (info == null || !_fits(candidate, info, selection)) continue;
          final fields = MetadataCompleteness.forEmbeddedTags(info.tags,
              hasArtwork: info.coverStreamIndex != null);
          final count = fields.count;
          final bitRate = info.bitRate ?? 0;
          if (count > bestFields ||
              count == bestFields && bitRate > bestBitRate) {
            best = candidate;
            bestFields = count;
            bestBitRate = bitRate;
          }
        }
        if (best != null) accepted[item.key] = best;
      }
    }
    return accepted;
  }

  Future<DownloadedAudioInspection?> _inspect(
      Track track,
      Map<AudioSourceReference, DownloadedAudioInspection?> inspected,
      LibraryScanControl control) async {
    try {
      final source = track.source;
      if (!inspected.containsKey(source)) {
        try {
          inspected[source] = await inspect(source, control);
        } on Object {
          control.throwIfCancelled();
          inspected[source] = null;
        }
      }
      return inspected[source];
    } on FormatException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  bool _fits(LocalDownloadCandidate candidate, DownloadedAudioInspection info,
      YandexAudioSelection selection) {
    final minimum = selection.minimumMeasuredBitRate;
    final size = candidate.track.fileSizeBytes;
    final duration = candidate.track.duration;
    final comment = info.tags['comment'];
    return info.container == selection.encoding.container &&
        info.codec == selection.encoding.codec &&
        (minimum == null || (info.bitRate ?? 0) >= minimum) &&
        (size == null || info.sizeBytes == size) &&
        (duration == null ||
            (info.duration - duration).abs() <= const Duration(seconds: 1)) &&
        comment != null &&
        embeddedYandexIdentity([comment]) == candidate.identity;
  }

  Future<void> close() async => await closeProbe?.call();
}
