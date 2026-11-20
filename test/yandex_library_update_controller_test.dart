import 'dart:async';
import 'dart:convert';

import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/library_sync_repository.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_runner.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_update_controller.dart';
import 'package:clever_music_player/src/library_sync/yandex_local_copy_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/library_update_fixture.dart';
import 'support/yandex_fixture.dart';

void main() {
  late LibraryUpdateFixture x;
  setUp(() async {
    x = await LibraryUpdateFixture.open();
  });
  tearDown(() async {
    await x.close();
  });
  Future<void> until(bool Function() test) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!test()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Expected asynchronous update progress');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<List<DownloadJob>> jobs() => x.f.repositories.downloadJobs.listJobs();

  Future<Track> linkedCopy(String name,
      {String variant = '009', String id = '001'}) async {
    final saved = await x.f.repositories.tracks.upsertTrack(Track(
        filePath: '${x.f.root.path}/$name',
        title: 'Local title',
        fileSizeBytes: 100,
        addedAt: x.f.now,
        updatedAt: x.f.now));
    await x.f.repositories.externalTracks.linkAll([
      ExternalTrackRef(
          trackId: saved,
          linkedAt: x.f.now,
          origin: ExternalTrackRefOrigin.embeddedTag,
          identity: ExternalTrackIdentity(
              provider: 'yandex_music', externalId: id, variantKey: variant))
    ]);
    return (await x.f.repositories.tracks.findById(saved))!;
  }

  DownloadedAudioInspection mp3(
          {int bitrate = 192000,
          bool rich = false,
          String comment = 'https://music.yandex.ru/album/009/track/001'}) =>
      DownloadedAudioInspection(
          container: DownloadedAudioContainer.mp3,
          codec: DownloadedAudioCodec.mp3,
          duration: const Duration(seconds: 3),
          sizeBytes: 100,
          audioStreamIndex: 0,
          sampleRate: 48000,
          channels: 2,
          bitRate: bitrate,
          tags: {
            'title': 'Provider title',
            'artist': 'Artist',
            'comment': comment,
            if (rich) ...{'album': 'Album', 'date': '2026'}
          });

  Future<void> useLocalProbe(
      Future<DownloadedAudioInspection?> Function(AudioSourceReference)
          probe) async {
    await x.updates.close();
    x.localMatcherFactory = () => YandexLocalCopyMatcher(
        x.f.repositories.librarySync as LocalDownloadCandidateRepository,
        (source, _) => probe(source));
    x.updates = x.newController();
    await x.ready();
  }

  test(
      'same quality skips a local copy and prioritizes fuller file tags over bitrate',
      () async {
    final poor = await linkedCopy('poor.mp3');
    final rich = await linkedCopy('rich.mp3');
    final checked = <AudioSourceReference>[];
    await useLocalProbe((source) async {
      checked.add(source);
      return source == rich.source ? mp3(rich: true) : mp3(bitrate: 320000);
    });
    await x.updates.start();
    expect(x.updates.failure, isNull);
    expect(x.updates.localCopies, 1);
    expect(x.updates.message, contains('Уже есть в библиотеке: 1'));
    expect(checked, [poor.source, rich.source]);
    expect(x.plans.lastLocalCopies.values.single.track, rich);
    expect((await jobs()).single.key.identity.externalId, '2');
    expect(await x.f.count('downloaded_assets'), 0);
  });

  test(
      'wrong format, changed embedded link and low bit rate leave jobs eligible',
      () async {
    final a = await linkedCopy('low.mp3');
    final b = await linkedCopy('changed.mp3');
    await useLocalProbe((source) async => source == a.source
        ? mp3(bitrate: 64000)
        : mp3(comment: 'https://music.yandex.ru/album/009/track/999'));
    await x.updates.start();
    expect(x.updates.localCopies, 0);
    expect(await jobs(), hasLength(2));
    await x.updates.configure(quality: YandexUpdateQuality.flac);
    final attempts = <AudioSourceReference>[];
    await useLocalProbe((source) async {
      attempts.add(source);
      return mp3();
    });
    expect(x.updates.quality, YandexUpdateQuality.flac);
    await x.updates.start();
    expect(x.updates.localCopies, 0);
    expect(attempts, [a.source, b.source]);
    expect((await jobs()).where((j) => j.key.quality == 'yandex_flac_lossless'),
        hasLength(2));
  });

  test('a previously queued local match is excluded only for this run',
      () async {
    await x.ready();
    await x.updates.start();
    final queued =
        (await jobs()).firstWhere((j) => j.key.identity.externalId == '001');
    final copy = await linkedCopy('copy.mp3');
    await useLocalProbe((_) async => mp3());
    await x.updates.start();
    expect(x.fakeRunner.excluded, {queued.id});
    final claim = await x.f.repositories.downloadJobs.claimNext(x.f.account,
        now: x.f.now, excludedJobIds: x.fakeRunner.excluded);
    expect(claim?.key.identity.externalId, '2');
    expect(await x.f.repositories.downloadJobs.findByKey(queued.key), queued);
    await x.f.repositories.tracks.deleteTrack(copy.id!);
    final next = await x.f.repositories.downloadJobs
        .claimNext(x.f.account, now: x.f.now);
    expect(next?.id, queued.id);
  });

  test(
      'an indexed link removed after inspection invalidates the apply transaction',
      () async {
    final copy = await linkedCopy('copy.mp3');
    await useLocalProbe((_) async => mp3());
    x.plans.onApply = () => x.f.repositories.tracks.deleteTrack(copy.id!);
    await x.updates.start();
    expect(x.updates.failure, YandexUpdateFailure.stale);
    expect(await jobs(), isEmpty);
    expect(x.fakeRunner.calls, 0);
  });

  test('an ambiguous track-only request ignores conflicting local releases',
      () async {
    x.tracks = [yandexTrack('001', album: '')];
    await linkedCopy('first.mp3');
    await linkedCopy('second.mp3', variant: '010');
    var calls = 0;
    await useLocalProbe((_) async {
      calls++;
      return mp3();
    });
    await x.updates.start();
    expect(x.updates.failure, isNull);
    expect(calls, 0);
    expect((await jobs()).single.key.identity.variantKey, isEmpty);
  });
  test(
      'initialization is local, restores no automatic destination and starts no runner',
      () async {
    expect(x.updates.initialized, isFalse);
    await x.updates.initialize();
    expect(x.updates.folderId, isNull);
    expect(x.updates.quality, YandexUpdateQuality.mp3);
    expect(x.updates.limit, 3);
    expect(x.transport.requests, isEmpty);
    expect(x.fakeRunner.calls, 0);
    expect(await jobs(), isEmpty);
  });
  test('folder,quality and limit persist without a path or credential',
      () async {
    await x.ready();
    await x.updates.configure(quality: YandexUpdateQuality.flac, limit: 100000);
    final saved = (await x.f.repositories.settings
        .readString(YandexLibraryUpdateController.optionsKey))!;
    expect(jsonDecode(saved), {
      'version': 1,
      'folder': x.f.folderId,
      'quality': 'flac',
      'limit': 100000
    });
    expect(saved, isNot(contains(x.f.root.path)));
    expect(saved, isNot(contains('SECRET')));
    await x.updates.close();
    x.updates = x.newController();
    await x.updates.initialize();
    expect(x.updates.folderId, x.f.folderId);
    expect(x.updates.quality, YandexUpdateQuality.flac);
    expect(x.updates.limit, 100000);
    expect(x.fakeRunner.calls, 0);
  });
  for (final saved in [
    'bad json',
    '{"version":9,"folder":1,"quality":"flac","limit":3}',
    '{"version":1,"folder":-1,"quality":"flac","limit":3}',
    '{"version":1,"folder":1,"quality":"unsupported","limit":3}'
  ]) {
    test('malformed options keep safe defaults: $saved', () async {
      await x.f.repositories.settings
          .writeString(YandexLibraryUpdateController.optionsKey, saved);
      await x.updates.initialize();
      expect(x.updates.folderId, isNull);
      expect(x.updates.quality, YandexUpdateQuality.mp3);
      expect(x.updates.limit, 3);
      expect(x.fakeRunner.calls, 0);
    });
  }
  test('a missing saved folder never silently selects another folder',
      () async {
    await x.f.repositories.settings.writeString(
        YandexLibraryUpdateController.optionsKey,
        '{"version":1,"folder":999,"quality":"mp3","limit":3}');
    await x.updates.initialize();
    await x.updates.start();
    expect(x.updates.folderId, isNull);
    expect(x.updates.failure, YandexUpdateFailure.destination);
    expect(x.transport.requests, isEmpty);
    expect(await jobs(), isEmpty);
  });
  test('no selected collections prevents network/queue changes', () async {
    await x.ready();
    await x.connection.select(yandexLiked, false);
    await x.updates.start();
    expect(x.updates.failure, YandexUpdateFailure.noCollections);
    expect(x.transport.requests, isEmpty);
    expect(x.fakeRunner.calls, 0);
  });
  test('no account prevents network and job creation', () async {
    await x.ready();
    await x.connection.disconnect();
    await x.updates.start();
    expect(x.updates.failure, YandexUpdateFailure.noAccount);
    expect(x.fakeRunner.calls, 0);
    expect(await jobs(), isEmpty);
  });
  test('fresh collection composition deduplicates identities before scheduling',
      () async {
    await x.ready();
    await x.updates.start();
    expect(x.updates.failure, isNull);
    expect(x.updates.planned, 2);
    final queued = await jobs();
    expect(queued, hasLength(2));
    expect(queued.every((j) => j.state == DownloadJobState.queued), isTrue);
    expect(queued.map((j) => j.key.identity.externalId).toSet(), {'001', '2'});
    expect(
        x.transport.requests
            .where((r) => r.endpoint == YandexReadEndpoint.likedTracks)
            .length,
        greaterThanOrEqualTo(2));
    expect(x.fakeRunner.calls, 1);
    expect(x.fakeRunner.folder, x.f.folderId);
    expect(x.fakeRunner.limit, 3);
    expect(x.fakeRunner.selection, x.updates.quality.selection);
  });
  test('cached collection contents are replaced before the plan is applied',
      () async {
    await x.ready();
    x.tracks = [yandexTrack('9')];
    await x.connection.checkCollections();
    x.tracks = [yandexTrack('001')];
    await x.updates.start();
    expect((await jobs()).single.key.identity.externalId, '001');
  });
  test('provider snapshot older than this update is rejected before enqueue',
      () async {
    await x.ready();
    x.apiClock = x.f.now.subtract(const Duration(days: 1));
    await x.updates.start();
    expect(x.updates.failure, YandexUpdateFailure.stale);
    expect(await jobs(), isEmpty);
    expect(x.fakeRunner.calls, 0);
  });
  test('network failure preserves previous collection and creates no jobs',
      () async {
    await x.ready();
    await x.connection.checkCollections();
    final before = await x.f.repositories.remoteLibrary
        .readContent(x.f.account.identity, yandexLiked);
    x.transport.onGet = (_, __) async =>
        throw const YandexLibraryException(YandexLibraryFailure.network);
    await x.updates.start();
    expect(x.updates.failure, YandexUpdateFailure.connection);
    expect(await jobs(), isEmpty);
    expect(
        (await x.f.repositories.remoteLibrary
                .readContent(x.f.account.identity, yandexLiked))!
            .items,
        before!.items);
  });
  test(
      'partial success across collections does not partially schedule downloads',
      () async {
    await x.ready();
    await x.connection.loadPlaylists();
    await x.connection.select(yandexPlaylist, true);
    x.transport.onGet = (request, _) async {
      if (request.endpoint == YandexReadEndpoint.playlist) {
        throw const YandexLibraryException(YandexLibraryFailure.network);
      }
      return x.reply(request);
    };
    await x.updates.start();
    expect(x.updates.failure, YandexUpdateFailure.connection);
    expect(await jobs(), isEmpty);
    expect(x.fakeRunner.calls, 0);
  });
  test('canonical apply rejects a changed plan without starting runner',
      () async {
    await x.ready();
    x.plans.stale = true;
    await x.updates.start();
    expect(x.updates.failure, YandexUpdateFailure.stale);
    expect(await jobs(), isEmpty);
    expect(x.fakeRunner.calls, 0);
  });
  test('confirmed existing bytes are re-captured and not scheduled again',
      () async {
    await x.ready();
    await x.asset();
    await x.updates.start();
    expect(x.updates.failure, isNull);
    expect(x.updates.checked, 1);
    expect(x.probe.calls, 1);
    expect(x.probe.closes, 1);
    expect(x.plans.captures, 2);
    expect((await jobs()).single.key.identity.externalId, '2');
  });
  for (final status in [
    SourceFingerprintStatus.missing,
    SourceFingerprintStatus.changed
  ]) {
    test('$status file is invalidated and included in a new plan', () async {
      await x.ready();
      final asset = await x.asset();
      x.probe.result = SourceFingerprintResult.failure(status);
      await x.updates.start();
      expect(x.updates.failure, isNull);
      expect(await jobs(), hasLength(2));
      expect(
          (await x.f.repositories.downloadedAssets
                  .findForTrack(asset.publication.trackId))!
              .state,
          status == SourceFingerprintStatus.missing
              ? DownloadedAssetState.missing
              : DownloadedAssetState.invalid);
    });
  }
  for (final status in [
    SourceFingerprintStatus.accessDenied,
    SourceFingerprintStatus.unreadable
  ]) {
    test('$status existing file stops update before queue mutations', () async {
      await x.ready();
      await x.asset();
      x.probe.result = SourceFingerprintResult.failure(status);
      await x.updates.start();
      expect(x.updates.failure, YandexUpdateFailure.fileAccess);
      expect(x.probe.closes, 1);
      expect(await jobs(), isEmpty);
      expect(x.fakeRunner.calls, 0);
    });
  }
  test('selection changes during file check cancel before enqueue', () async {
    await x.ready();
    await x.asset();
    x.probe.onProbe = (_) => x.connection.select(yandexLiked, false);
    await x.updates.start();
    expect(x.updates.failure, YandexUpdateFailure.stale);
    expect(await jobs(), isEmpty);
    expect(x.fakeRunner.calls, 0);
  });
  test('cancellation during fresh API read drains before returning idle',
      () async {
    await x.ready();
    final entered = Completer<void>(), release = Completer<void>();
    x.transport.onGet = (request, control) async {
      if (request.endpoint == YandexReadEndpoint.likedTracks) {
        entered.complete();
        control.addCancellationListener(release.complete);
        await release.future;
        control.throwIfCancelled();
      }
      return x.reply(request);
    };
    final operation = x.updates.start();
    await entered.future;
    x.updates.cancel();
    await operation;
    expect(x.updates.failure, YandexUpdateFailure.cancelled);
    expect(x.updates.isBusy, isFalse);
    expect(await jobs(), isEmpty);
  });
  test('folder revocation during download cancels the accepted run', () async {
    await x.ready();
    final entered = Completer<void>(), release = Completer<void>();
    x.fakeRunner.onRun = (control, _) async {
      entered.complete();
      control.addCancellationListener(release.complete);
      await release.future;
      return const YandexDownloadRunResult(
          YandexDownloadRunOutcome.cancelled, 1, 0);
    };
    final operation = x.updates.start();
    await entered.future;
    await x.f.repositories.libraryFolders
        .setFolderEnabled(x.f.folderId, isEnabled: false, updatedAt: x.f.now);
    await operation.timeout(const Duration(seconds: 3));
    expect(x.updates.failure, YandexUpdateFailure.destination);
    expect(x.updates.folderId, isNull);
    expect(x.updates.result!.completed, 0);
  });
  test('disabling an idle destination clears the choice without a fallback',
      () async {
    await x.ready();
    await x.f.repositories.libraryFolders
        .setFolderEnabled(x.f.folderId, isEnabled: false, updatedAt: x.f.now);
    await until(() => x.updates.folderId == null);
    await x.updates.start();
    expect(x.updates.failure, YandexUpdateFailure.destination);
    expect(x.fakeRunner.calls, 0);
    expect(x.transport.requests, isEmpty);
  });
  test('close drains a running batch and closes runner once', () async {
    await x.ready();
    final entered = Completer<void>(), release = Completer<void>();
    x.fakeRunner.onRun = (control, _) async {
      entered.complete();
      control.addCancellationListener(release.complete);
      await release.future;
      return const YandexDownloadRunResult(
          YandexDownloadRunOutcome.cancelled, 1, 0);
    };
    final operation = x.updates.start();
    await entered.future;
    await x.updates.close();
    await operation;
    expect(x.fakeRunner.closes, 1);
    expect(x.updates.isBusy, isFalse);
    await x.updates.start();
    expect(x.fakeRunner.calls, 1);
  });
  test('busy UI cannot change options or start a concurrent update', () async {
    await x.ready();
    final entered = Completer<void>(), release = Completer<void>();
    x.fakeRunner.onRun = (_, __) async {
      entered.complete();
      await release.future;
      return const YandexDownloadRunResult(
          YandexDownloadRunOutcome.completed, 0, 0);
    };
    final operation = x.updates.start();
    await entered.future;
    await x.updates.configure(quality: YandexUpdateQuality.flac);
    await x.updates.start();
    expect(x.fakeRunner.calls, 1);
    expect(x.updates.quality, YandexUpdateQuality.mp3);
    release.complete();
    await operation;
  });
  test(
      'typed download failure retains completed count and writes numeric diagnostics',
      () async {
    await x.ready();
    x.fakeRunner.onRun = (_, __) async => const YandexDownloadRunResult(
        YandexDownloadRunOutcome.failed, 2, 1,
        failure: YandexDownloadRunFailure.pipeline,
        jobFailure: DownloadFailure.unavailable);
    await x.updates.start();
    expect(x.updates.failure, YandexUpdateFailure.download);
    expect(x.updates.result!.completed, 1);
    final entry = x.diagnostics.entries.last;
    expect(entry.event, DiagnosticEvent.yandexUpdateFailed);
    expect(entry.fields[DiagnosticField.syncJobFailure],
        DownloadFailure.unavailable.index);
    expect(entry.fields.values.every((v) => v is num || v is bool), isTrue);
    expect(entry.fields[DiagnosticField.addedTracks], 1);
  });
  test(
      'partial completion reports failed track count without a stopped-run error',
      () async {
    await x.ready();
    x.fakeRunner.onRun = (_, __) async => const YandexDownloadRunResult(
        YandexDownloadRunOutcome.completedWithFailures, 2, 1,
        failed: 1);
    await x.updates.start();
    expect(x.updates.failure, isNull);
    expect(x.updates.message, contains('Добавлено треков: 1.'));
    expect(x.updates.message, contains('после повторов: 1.'));
    expect(x.updates.result!.failed, 1);
  });
  test('unsupported platform performs no folder, settings or update network IO',
      () async {
    await x.close();
    x = await LibraryUpdateFixture.open(supported: false);
    await x.updates.initialize();
    await x.updates.start();
    expect(x.updates.failure, YandexUpdateFailure.unsupported);
    expect(x.updates.folders, isEmpty);
    expect(x.transport.requests, isEmpty);
    expect(x.fakeRunner.calls, 0);
    expect(await jobs(), isEmpty);
  });
}
