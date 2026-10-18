import 'dart:async';

import '../domain/models/download_job.dart';
import '../domain/models/remote_library.dart';
import '../domain/repositories/download_job_repository.dart';
import '../domain/repositories/remote_library_repository.dart';
import '../library/library_scan_control.dart';
import 'binary_download.dart';
import 'binary_http_download_transport.dart';
import 'download_lease_owner.dart';
import 'publication_intent.dart';
import 'raw_download_pool.dart';
import 'yandex_audio_selection.dart';
import 'yandex_download_protocol.dart';
import 'yandex_library_protocol.dart';

/// Transfer ownership of the raw file AND latest heartbeat snapshot together.
/// The consumer closes this after all metadata/publishing readers finish.
final class YandexDownloadedTrack {
  const YandexDownloadedTrack._(this.job, this.variant, this.raw);
  final DownloadJob job;
  final YandexDownloadVariant variant;
  final RawDownloadedAudio raw;
  Future<void> close() => raw.close();
}

/// Owns a dedicated credential reader and binary transport. No automatic claim,
/// retry, UI, publication or startup work; accepts one already claimed attempt.
final class YandexTrackDownloader {
  YandexTrackDownloader(
      {required YandexDownloadReader reader,
      required BinaryHttpDownloadTransport transport,
      required DownloadJobRepository jobs,
      required RemoteLibraryRepository accounts,
      DateTime Function()? clock,
      this.leaseFor = const Duration(seconds: 60),
      this.heartbeatEvery = const Duration(seconds: 20)})
      : _reader = reader,
        _transport = transport,
        _jobs = jobs,
        _accounts = accounts,
        _clock = clock ?? DateTime.now {
    if (leaseFor < const Duration(seconds: 1) ||
        leaseFor > const Duration(minutes: 10) ||
        heartbeatEvery <= Duration.zero ||
        heartbeatEvery * 2 > leaseFor) {
      throw ArgumentError('Некорректные границы владения загрузкой.');
    }
  }
  final YandexDownloadReader _reader;
  final BinaryHttpDownloadTransport _transport;
  final DownloadJobRepository _jobs;
  final RemoteLibraryRepository _accounts;
  final DateTime Function() _clock;
  final Duration leaseFor, heartbeatEvery;
  bool _closed = false;
  LibraryScanControl? _control;
  Future<YandexDownloadedTrack>? _active;
  Future<void>? _closing;

  Future<YandexDownloadedTrack> download(DownloadJob job,
      RemoteLibraryAccount account, YandexAudioSelection selection,
      {required int maxBytes,
      LibraryScanControl? control,
      void Function(BinaryDownloadProgress)? onProgress}) {
    if (_closed || _active != null) {
      return Future.error(YandexLibraryException(
          _closed ? YandexLibraryFailure.closed : YandexLibraryFailure.busy));
    }
    final operation = _download(job, account, selection,
            maxBytes: maxBytes, external: control, onProgress: onProgress)
        .whenComplete(() {
      _active = null;
      _control = null;
    });
    operation.ignore();
    return _active = operation;
  }

  Future<YandexDownloadedTrack> _download(DownloadJob job,
      RemoteLibraryAccount account, YandexAudioSelection selection,
      {required int maxBytes,
      LibraryScanControl? external,
      void Function(BinaryDownloadProgress)? onProgress}) async {
    if (maxBytes <= 0 || maxBytes > maximumRawDownloadBytes) {
      throw ArgumentError('Некорректный предел загрузки.');
    }
    if (!account.isActive ||
        job.accountId != account.id ||
        job.accountRevision != account.revision ||
        account.identity.provider != 'yandex_music' ||
        job.key.identity.provider != 'yandex_music' ||
        job.state != DownloadJobState.running ||
        job.stage != DownloadJobStage.download ||
        job.key.quality != selection.resourceQuality) {
      throw const PublicationException(PublicationFailure.ownershipLost);
    }
    final control = LibraryScanControl();
    _control = control;
    final owner = DownloadLeaseOwner(
        job: job,
        jobs: _jobs,
        clock: _clock,
        leaseFor: leaseFor,
        heartbeatEvery: heartbeatEvery);
    external?.addCancellationListener(control.cancel);
    owner.lossControl.addCancellationListener(control.cancel);
    RawDownloadedAudio? raw;
    var delivered = false;
    var ownerStopped = false;
    try {
      control.throwIfCancelled();
      await owner.start();
      control.throwIfCancelled();
      final currentAccount = await _accounts.findAccount(account.identity);
      if (currentAccount == null ||
          !currentAccount.isActive ||
          currentAccount.id != account.id ||
          currentAccount.revision != account.revision) {
        throw const PublicationException(PublicationFailure.ownershipLost);
      }
      final variant = await _reader.resolveDownload(
          account.identity, job.key.identity, selection,
          control: control);
      control.throwIfCancelled();
      if (variant.account != account.identity ||
          variant.metadata.identity != job.key.identity ||
          variant.selection != selection) {
        throw const YandexDownloadException(
            YandexDownloadFailure.identityMismatch);
      }
      raw = await _transport.download(variant.address,
          maxBytes: maxBytes,
          expectedBytes: variant.expectedBytes,
          control: control,
          onProgress: onProgress);
      control.throwIfCancelled();
      // A final writer fence catches session/folder revocation even if no
      // heartbeat tick occurred during this short transfer. No file IO in SQL.
      await owner.withOwnedDestination(owner.current,
          clock: _clock, action: (_) async => true);
      await owner.close();
      ownerStopped = true;
      control.throwIfCancelled();
      delivered = true;
      return YandexDownloadedTrack._(owner.current, variant, raw);
    } on Object catch (error) {
      final lost = owner.lost ||
          (error is PublicationException &&
              error.reason == PublicationFailure.ownershipLost);
      if (!lost) {
        try {
          if (ownerStopped) {
            // Cancellation may arrive while the final heartbeat is draining.
            // No heartbeat can now race this CAS on the final current snapshot.
            if (control.isCancellationRequested) {
              await _jobs.cancel(owner.current, now: _clock());
            } else {
              await _jobs.fail(owner.current, _jobFailure(error),
                  now: _clock());
            }
          } else {
            await owner.fail(_jobFailure(error),
                cancelled: control.isCancellationRequested);
          }
        } on Object {
          // A competing revocation/CAS wins. Never adopt a new attempt.
        }
      }
      if (lost) {
        throw const PublicationException(PublicationFailure.ownershipLost);
      }
      if (control.isCancellationRequested || error is LibraryScanCancelled) {
        throw const YandexLibraryException(YandexLibraryFailure.cancelled);
      }
      if (error is YandexDownloadException ||
          error is YandexLibraryException ||
          error is BinaryDownloadException ||
          error is PublicationException) {
        rethrow;
      }
      throw const YandexDownloadException(YandexDownloadFailure.internal);
    } finally {
      await owner.close();
      owner.lossControl.removeCancellationListener(control.cancel);
      external?.removeCancellationListener(control.cancel);
      if (!delivered) await raw?.close();
    }
  }

  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _close(_active);
  }

  Future<void> _close(Future<YandexDownloadedTrack>? active) async {
    try {
      await active;
    } on Object {/* Accepted work is fully drained. */}
    await Future.wait([_reader.close(), _transport.close()]);
  }
}

DownloadFailure _jobFailure(Object error) => switch (error) {
      YandexLibraryException(:final failure) => switch (failure) {
          YandexLibraryFailure.unauthorized => DownloadFailure.authorization,
          YandexLibraryFailure.accessDenied => DownloadFailure.accessDenied,
          YandexLibraryFailure.notFound => DownloadFailure.unavailable,
          YandexLibraryFailure.rateLimited => DownloadFailure.rateLimited,
          YandexLibraryFailure.accountMismatch =>
            DownloadFailure.accountChanged,
          YandexLibraryFailure.cancelled => DownloadFailure.cancelled,
          _ => DownloadFailure.network,
        },
      YandexDownloadException(:final failure) => switch (failure) {
          YandexDownloadFailure.unavailable ||
          YandexDownloadFailure.qualityMismatch ||
          YandexDownloadFailure.unsupportedTransport =>
            DownloadFailure.unavailable,
          _ => DownloadFailure.invalidMedia,
        },
      BinaryDownloadException(:final failure) => switch (failure) {
          BinaryDownloadFailure.unauthorized => DownloadFailure.authorization,
          BinaryDownloadFailure.accessDenied => DownloadFailure.accessDenied,
          BinaryDownloadFailure.notFound => DownloadFailure.unavailable,
          BinaryDownloadFailure.rateLimited => DownloadFailure.rateLimited,
          BinaryDownloadFailure.quotaExceeded => DownloadFailure.noSpace,
          BinaryDownloadFailure.storage ||
          BinaryDownloadFailure.unsafePath =>
            DownloadFailure.internalError,
          BinaryDownloadFailure.cancelled => DownloadFailure.cancelled,
          _ => DownloadFailure.network,
        },
      _ => DownloadFailure.internalError,
    };
