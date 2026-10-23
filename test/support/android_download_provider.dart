import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/android/android_audio_publication_backend.dart';
import 'package:clever_music_player/src/android/android_publication_receipt.dart';
import 'package:clever_music_player/src/android/android_publication_verifier.dart';
import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/publication_intent.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:crypto/crypto.dart';

/// Test-only provider: real byte IO behind deliberately opaque content URIs.
/// No claim that it executes Android ContentResolver/MediaMetadataRetriever.
final class AndroidDownloadProvider {
  AndroidDownloadProvider(this.directory);
  final Directory directory;
  final intents = <String, PublicationIntent>{};
  final receipts = <String, AndroidPublicationReceipt>{};
  final files = <String, File>{};
  int writes = 0, preparations = 0, reconciles = 0, releases = 0;
  int verifies = 0, metadataReads = 0, backendCloses = 0, verifierCloses = 0;
  bool partial = false, failAck = false, failClose = false;
  AudioPublicationStatus? failWrite, failPrepare;
  SourceFingerprintStatus? failVerify;
  Future<void> Function(LibraryScanControl)? onWrite;
  Future<void> Function()? onMetadata, onVerify, onPending;
  Future<AudioDocumentMetadata> Function(File, AndroidPublicationReceipt)?
      metadata;

  AudioPublicationBackend backend() => _Backend(this);
  PublicationDocumentVerifier verifier() => _Verifier(this);

  Future<AudioDocumentMetadata> read(ContentUriAudioSource source) async {
    metadataReads++;
    await onMetadata?.call();
    final receipt =
        receipts.values.singleWhere((r) => r.location.document == source);
    final file = files[source.storageValue]!;
    if (metadata != null) return metadata!(file, receipt);
    return AudioDocumentMetadata(
        name: receipt.intent.fileName,
        title: 'Provider title',
        artist: 'Artist',
        albumArtist: 'Album artist',
        duration: receipt.intent.verification.duration,
        size: await file.length());
  }

  Future<AndroidPublicationReceipt> create(
      AudioPublicationRequest request, File source) async {
    final intent = request.intent;
    await directory.create();
    final target = File(
        '${directory.path}/${intent.publicationId}.${intent.verification.container}');
    final bytes = await source.readAsBytes();
    await target.writeAsBytes(partial ? bytes.sublist(0, 1) : bytes,
        flush: true);
    final receipt = AndroidPublicationReceipt(
        intent: intent,
        location: DocumentPublicationLocation(
            tree: request.tree,
            document: ContentUriAudioSource(Uri(
                scheme: 'content',
                host: request.tree.uri.authority,
                pathSegments: [
                  'tree',
                  request.tree.uri.pathSegments[1],
                  'document',
                  'opaque:${intent.publicationId}'
                ]).toString()),
            displayName: intent.fileName));
    files[receipt.location.document.storageValue] = target;
    receipts[intent.publicationId] = receipt;
    return receipt;
  }

  Future<bool> matches(AndroidPublicationReceipt receipt) async {
    final file = files[receipt.location.document.storageValue];
    if (file == null || !await file.exists()) return false;
    final bytes = await file.readAsBytes();
    return bytes.length == receipt.intent.verification.fileSizeBytes &&
        sha256.convert(bytes).toString() ==
            receipt.intent.verification.contentHash;
  }
}

final class _Backend implements AudioPublicationBackend {
  _Backend(this.p);
  final AndroidDownloadProvider p;
  bool closed = false;
  @override
  Future<void> prepare(AudioPublicationRequest request) async {
    p.preparations++;
    if (p.failPrepare != null) throw AudioPublicationException(p.failPrepare!);
    p.intents[request.intent.publicationId] = request.intent;
  }

  @override
  Future<AndroidPublicationReceipt> publish(AudioPublicationRequest request,
      FileAudioSource source, LibraryScanControl control) async {
    p.writes++;
    final receipt = await p.create(request, File(source.path));
    await p.onWrite?.call(control);
    if (p.failWrite != null) throw AudioPublicationException(p.failWrite!);
    return receipt; // accepted publication wins over late caller cancellation
  }

  @override
  Future<void> releaseUncreated(AudioPublicationRequest request) async {
    p.releases++;
    if (p.receipts.containsKey(request.intent.publicationId)) {
      throw const AudioPublicationException(
          AudioPublicationStatus.needsReconciliation);
    }
    p.intents.remove(request.intent.publicationId);
  }

  @override
  Future<AndroidPublicationReceipt> reconcile(
      AudioPublicationRequest request, LibraryScanControl control) async {
    p.reconciles++;
    control.throwIfCancelled();
    final receipt = p.receipts[request.intent.publicationId];
    if (receipt == null || !await p.matches(receipt)) {
      throw const AudioPublicationException(AudioPublicationStatus.changed);
    }
    return receipt;
  }

  @override
  Future<List<PublicationIntent>> pending(ContentUriAudioSource tree) async {
    await p.onPending?.call();
    return p.intents.values.toList();
  }

  @override
  Future<void> acknowledge(
      AudioPublicationRequest request, ContentUriAudioSource document) async {
    if (p.failAck) {
      throw const AudioPublicationException(AudioPublicationStatus.io);
    }
    p.intents.remove(request.intent.publicationId);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    p.backendCloses++;
    if (p.failClose) throw StateError('synthetic backend close failure');
  }
}

final class _Verifier implements PublicationDocumentVerifier {
  _Verifier(this.p);
  final AndroidDownloadProvider p;
  bool closed = false;
  @override
  Future<SourceFingerprintResult> verify(
      AndroidPublicationReceipt receipt, LibraryScanControl control) async {
    p.verifies++;
    await p.onVerify?.call();
    control.throwIfCancelled();
    if (p.failVerify != null) {
      return SourceFingerprintResult.failure(p.failVerify!);
    }
    return await p.matches(receipt)
        ? SourceFingerprintResult.fingerprinted(
            receipt.intent.verification.fileSizeBytes,
            receipt.intent.verification.contentHash)
        : SourceFingerprintResult.failure(SourceFingerprintStatus.changed);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    p.verifierCloses++;
  }
}
