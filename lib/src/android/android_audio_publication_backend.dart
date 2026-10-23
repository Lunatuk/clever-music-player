import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/models/models.dart';
import '../library/library_scan_control.dart';
import '../library_sync/publication_intent.dart';
import 'android_download_folders.dart';
import 'android_publication_receipt.dart';

enum AudioPublicationStatus {
  prepared,
  published,
  acknowledged,
  pending,
  busy,
  needsReconciliation,
  ownershipLost,
  collision,
  quotaExceeded,
  changed,
  accessDenied,
  noSpace,
  cancelled,
  io,
  released,
}

final class AudioPublicationException implements Exception {
  const AudioPublicationException(this.status);
  final AudioPublicationStatus status;
}

final class AudioPublicationRequest {
  AudioPublicationRequest(
      {required this.intent, required this.tree, required this.owner}) {
    AndroidDownloadFolders.parseTree(tree.storageValue);
    if (!isPublicationId(owner)) throw ArgumentError('Некорректная попытка.');
  }
  final PublicationIntent intent;
  final ContentUriAudioSource tree;
  final String owner;
  Map<String, Object> get arguments => {
        'tree': tree.storageValue,
        'intent': intent.encode(),
        'resource': intent.resourceKey,
        'publicationId': intent.publicationId,
        'sizeBytes': intent.verification.fileSizeBytes,
        'digest': intent.verification.contentHash,
        'container': intent.verification.container,
        'owner': owner,
      };
}

abstract interface class AudioPublicationBackend {
  Future<void> prepare(AudioPublicationRequest request);
  Future<void> releaseUncreated(AudioPublicationRequest request);
  Future<AndroidPublicationReceipt> publish(AudioPublicationRequest request,
      FileAudioSource source, LibraryScanControl control);
  Future<AndroidPublicationReceipt> reconcile(
      AudioPublicationRequest request, LibraryScanControl control);
  Future<List<PublicationIntent>> pending(ContentUriAudioSource tree);
  Future<void> acknowledge(
      AudioPublicationRequest request, ContentUriAudioSource document);
  Future<void> close();
}

/// One accepted RPC at a time. Private admission/ack are drained; cancellation
/// only interrupts provider work, never hides its durably published response.
final class AndroidAudioPublicationBackend implements AudioPublicationBackend {
  AndroidAudioPublicationBackend({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
                'dev.lunatuk.clever_music_player/audio_publication');
  final MethodChannel _channel;
  static int _sequence = 0;
  bool _closed = false;
  Completer<void>? _active;
  LibraryScanControl? _control;
  Future<void>? _closing;

  Future<Map<String, dynamic>> _invoke(String method, Map<String, Object> args,
      {LibraryScanControl? control}) async {
    if (_closed || _active != null) throw StateError('Публикация недоступна.');
    control?.throwIfCancelled();
    final done = _active = Completer<void>();
    _control = control;
    final id = _sequence = _sequence == 0x7fffffff ? 1 : _sequence + 1;
    final call = _channel
        .invokeMapMethod<String, dynamic>(method, {'requestId': id, ...args});
    void cancel() {
      _channel.invokeMethod<void>('cancelAudioPublication',
          {'requestId': id}).catchError((Object _) {});
    }

    control?.addCancellationListener(cancel);
    try {
      final result = await call;
      if (result == null ||
          result['requestId'] is! int ||
          result['requestId'] != id ||
          result['stage'] is! int ||
          result['stage'] < 0 ||
          result['stage'] > 6 ||
          !AudioPublicationStatus.values
              .any((s) => s.name == result['status'])) {
        throw const FormatException('Некорректный ответ публикации.');
      }
      return result;
    } finally {
      control?.removeCancellationListener(cancel);
      _control = null;
      _active = null;
      done.complete();
    }
  }

  void _status(Map<String, dynamic> result, AudioPublicationStatus expected) {
    final actual =
        AudioPublicationStatus.values.byName(result['status'] as String);
    if (actual != expected) throw AudioPublicationException(actual);
  }

  @override
  Future<void> prepare(AudioPublicationRequest request) async => _status(
      await _invoke('prepareAudioPublication', request.arguments),
      AudioPublicationStatus.prepared);

  @override
  Future<void> releaseUncreated(AudioPublicationRequest request) async {
    final result =
        await _invoke('releaseUncreatedAudioPublication', request.arguments);
    _status(result, AudioPublicationStatus.released);
    if (result['stage'] != 2 || result['intent'] != request.intent.encode()) {
      throw const FormatException('Результат не соответствует публикации.');
    }
  }

  Future<AndroidPublicationReceipt> _publish(String method,
      AudioPublicationRequest request, LibraryScanControl control,
      {FileAudioSource? source}) async {
    final result = await _invoke(method,
        {...request.arguments, if (source != null) 'sourcePath': source.path},
        control: control);
    _status(result, AudioPublicationStatus.published);
    final proof = request.intent.verification;
    if (result['stage'] != 6 ||
        result['intent'] != request.intent.encode() ||
        result['sizeBytes'] is! int ||
        result['sizeBytes'] != proof.fileSizeBytes ||
        result['digest'] != proof.contentHash ||
        result['document'] is! String) {
      throw const FormatException('Результат не соответствует публикации.');
    }
    return AndroidPublicationReceipt(
        intent: request.intent,
        location: DocumentPublicationLocation(
            tree: request.tree,
            document: ContentUriAudioSource(result['document'] as String),
            displayName: request.intent.fileName));
  }

  @override
  Future<AndroidPublicationReceipt> publish(AudioPublicationRequest request,
          FileAudioSource source, LibraryScanControl control) =>
      _publish('publishPreparedAudio', request, control, source: source);
  @override
  Future<AndroidPublicationReceipt> reconcile(
          AudioPublicationRequest request, LibraryScanControl control) =>
      _publish('reconcileAudioPublication', request, control);
  @override
  Future<List<PublicationIntent>> pending(ContentUriAudioSource tree) async {
    final result =
        await _invoke('listAudioPublications', {'tree': tree.storageValue});
    _status(result, AudioPublicationStatus.pending);
    final values = result['operations'];
    if (values is! List ||
        values.length > 64 ||
        values.any((v) => v is! String)) {
      throw const FormatException('Некорректный журнал.');
    }
    final intents = values
        .cast<String>()
        .map(PublicationIntent.decode)
        .toList(growable: false);
    if (intents.map((v) => v.operationName).toSet().length != intents.length) {
      throw const FormatException('Повтор записи журнала.');
    }
    return intents;
  }

  @override
  Future<void> acknowledge(AudioPublicationRequest request,
          ContentUriAudioSource document) async =>
      _status(
          await _invoke('acknowledgeAudioPublication',
              {...request.arguments, 'document': document.storageValue}),
          AudioPublicationStatus.acknowledged);
  @override
  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _drain(_active?.future);
  }

  Future<void> _drain(Future<void>? active) async => await active;
}
