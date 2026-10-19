import 'dart:async';
import 'dart:convert';

import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:clever_music_player/src/library_sync/yandex_download_runner.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_update_controller.dart';
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
