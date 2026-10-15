import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/downloaded_asset_repository.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/downloaded_asset_checker.dart';
import 'package:clever_music_player/src/library_sync/source_fingerprint_probe.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/asset_check_fixture.dart';

void main() {
  late _Repository repository;
  late _Probe probe;
  late DownloadedAssetChecker checker;
  setUp(() {
    repository = _Repository();
    probe = _Probe();
    checker = DownloadedAssetChecker(
        repository: repository,
        probe: probe,
        clock: () => assetCheckedAt.add(const Duration(seconds: 1)));
  });
  tearDown(() => checker.close());

  test(
      'matching all bytes retains previous audio properties and advances proof',
      () async {
    expect(await checker.check(testAsset()), AssetCheckOutcome.confirmed);
    final proof = repository.confirmed!;
    expect(proof.describesSameBytes(testAsset().verification), isTrue);
    expect(proof.checkedAt, assetCheckedAt.add(const Duration(seconds: 1)));
    expect(proof.checkedAt.isUtc, isTrue);
    expect(repository.invalidated, isNull);
  });
  for (final result in [
    SourceFingerprintResult.fingerprinted(3, 'a' * 64),
    SourceFingerprintResult.fingerprinted(4, abcHash),
    SourceFingerprintResult.failure(SourceFingerprintStatus.changed)
  ]) {
    test(
        'changed bytes/size/unstable read invalidates: ${result.status}/${result.sizeBytes}/${result.digest}',
        () async {
      probe.result = result;
      expect(await checker.check(testAsset()), AssetCheckOutcome.changed);
      expect(repository.invalidated, DownloadedAssetState.invalid);
      expect(repository.confirmed, isNull);
    });
  }
  for (final status in [
    SourceFingerprintStatus.missing,
    SourceFingerprintStatus.accessDenied
  ]) {
    test('structured $status is saved separately', () async {
      probe.result = SourceFingerprintResult.failure(status);
      final expected = status == SourceFingerprintStatus.missing
          ? AssetCheckOutcome.missing
          : AssetCheckOutcome.accessDenied;
      expect(await checker.check(testAsset()), expected);
      expect(repository.invalidated?.name, status.name);
    });
  }
  for (final status in [
    SourceFingerprintStatus.unreadable,
    SourceFingerprintStatus.cancelled
  ]) {
    test('$status preserves the record', () async {
      probe.result = SourceFingerprintResult.failure(status);
      expect((await checker.check(testAsset())).name, status.name);
      expect(repository.writes, 0);
    });
  }
  test('provider/protocol failure preserves proof and releases admission',
      () async {
    probe.action = (_) => Future.error(const FormatException('bad protocol'));
    expect(await checker.check(testAsset()), AssetCheckOutcome.unreadable);
    expect(repository.writes, 0);
    probe.action = null;
    expect(await checker.check(testAsset()), AssetCheckOutcome.confirmed);
  });
  for (final changed in [false, true]) {
    test(
        'stale ${changed ? 'invalidation' : 'confirmation'} cannot overwrite newer record',
        () async {
      repository.applied = false;
      if (changed) {
        probe.result =
            SourceFingerprintResult.failure(SourceFingerprintStatus.changed);
      }
      expect(await checker.check(testAsset()), AssetCheckOutcome.stale);
    });
  }
  test('pre-cancelled check performs no read or write', () async {
    expect(
        await checker.check(testAsset(),
            control: LibraryScanControl()..cancel()),
        AssetCheckOutcome.cancelled);
    expect(probe.calls, 0);
    expect(repository.writes, 0);
  });
  test('cancelled late successful read cannot confirm', () async {
    final gate = Completer<SourceFingerprintResult>();
    probe.action = (_) => gate.future;
    final control = LibraryScanControl();
    final reading = checker.check(testAsset(), control: control);
    control.cancel();
    gate.complete(probe.result);
    expect(await reading, AssetCheckOutcome.cancelled);
    expect(repository.writes, 0);
  });
  test('timeout cooperatively drains read without invalidating', () async {
    await checker.close();
    probe = _Probe();
    final gate = Completer<SourceFingerprintResult>();
    probe.action = (control) {
      control.addCancellationListener(() => gate.complete(probe.result));
      return gate.future;
    };
    checker = DownloadedAssetChecker(
        repository: repository,
        probe: probe,
        timeout: const Duration(milliseconds: 5));
    expect(await checker.check(testAsset()), AssetCheckOutcome.unreadable);
    expect(repository.writes, 0);
  });
  test('close cancels active read, drains it and closes admission', () async {
    final gate = Completer<SourceFingerprintResult>();
    probe.action = (_) => gate.future;
    final reading = checker.check(testAsset());
    final closing = checker.close();
    expect(identical(checker.close(), closing), isTrue);
    expect(probe.control!.isCancellationRequested, isTrue);
    expect(probe.closed, isFalse);
    await expectLater(checker.check(testAsset()), throwsStateError);
    gate.complete(probe.result);
    expect(await reading, AssetCheckOutcome.cancelled);
    await closing;
    expect(probe.closed, isTrue);
    expect(repository.writes, 0);
  });
  test('close during accepted CAS drains and reports committed result',
      () async {
    final entered = Completer<void>();
    final gate = Completer<bool>();
    repository.action = () {
      entered.complete();
      return gate.future;
    };
    final reading = checker.check(testAsset());
    await entered.future;
    var closed = false;
    final closing = checker.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(probe.closed, isFalse);
    gate.complete(true);
    expect(await reading, AssetCheckOutcome.confirmed);
    await closing;
    expect(probe.closed, isTrue);
  });
  test('concurrent checks rejected instead of growing a queue', () async {
    final gate = Completer<SourceFingerprintResult>();
    probe.action = (_) => gate.future;
    final first = checker.check(testAsset());
    await expectLater(checker.check(testAsset()), throwsStateError);
    expect(probe.calls, 1);
    gate.complete(probe.result);
    await first;
  });
  test('database failures propagate and do not leak admission', () async {
    repository.action = () => Future.error(StateError('database failed'));
    await expectLater(checker.check(testAsset()), throwsStateError);
    repository.action = null;
    expect(await checker.check(testAsset()), AssetCheckOutcome.confirmed);
  });
  test('timeout must be positive and bounded', () {
    for (final timeout in [Duration.zero, const Duration(minutes: 31)]) {
      expect(
          () => DownloadedAssetChecker(
              repository: repository, probe: probe, timeout: timeout),
          throwsArgumentError);
    }
  });

  group('physical file and SQLite', () {
    late Directory temp;
    late File file;
    late AppDatabase database;
    late DriftRepositories repo;
    late DownloadedAsset original;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('cmp_asset_check_');
      file = await File('${temp.path}/track.mp3').writeAsString('abc');
      database = AppDatabase(NativeDatabase.memory());
      repo = DriftRepositories(database);
      original =
          await registerTestAsset(repo, source: FileAudioSource(file.path));
      await checker.close();
      checker = DownloadedAssetChecker(
          repository: repo.downloadedAssets,
          probe: FileSourceFingerprintProbe(),
          clock: () => assetCheckedAt.add(const Duration(seconds: 1)));
    });
    tearDown(() async {
      await checker.close();
      await database.close();
      await temp.delete(recursive: true);
    });
    test('full digest confirmed against actual file and stored in SQLite',
        () async {
      expect(await checker.check(original), AssetCheckOutcome.confirmed);
      final current = (await repo.downloadedAssets
          .findForTrack(original.publication.trackId))!;
      expect(current.revision, 2);
      expect(current.verification.contentHash, abcHash);
      expect(
          current.verification.checkedAt
              .isAfter(original.verification.checkedAt),
          isTrue);
    });
    test('different bytes with identical size invalidated', () async {
      await file.writeAsString('xyz');
      expect(await checker.check(original), AssetCheckOutcome.changed);
      expect(
          (await repo.downloadedAssets
                  .findForTrack(original.publication.trackId))!
              .state,
          DownloadedAssetState.invalid);
    });
    test('removed file marked missing and matching restored file recoverable',
        () async {
      await file.delete();
      expect(await checker.check(original), AssetCheckOutcome.missing);
      final missing = (await repo.downloadedAssets
          .findForTrack(original.publication.trackId))!;
      await file.writeAsString('abc');
      expect(await checker.check(missing), AssetCheckOutcome.confirmed);
    });
    test('late check cannot overwrite a newer SQLite revision', () async {
      await repo.downloadedAssets
          .invalidate(original, DownloadedAssetState.accessDenied);
      expect(await checker.check(original), AssetCheckOutcome.stale);
      expect(
          (await repo.downloadedAssets
                  .findForTrack(original.publication.trackId))!
              .state,
          DownloadedAssetState.accessDenied);
    });
    test('clock regression cannot roll back verified timestamp', () async {
      await checker.close();
      checker = DownloadedAssetChecker(
          repository: repo.downloadedAssets,
          probe: FileSourceFingerprintProbe(),
          clock: () => assetCheckedAt.subtract(const Duration(seconds: 1)));
      expect(await checker.check(original), AssetCheckOutcome.stale);
      expect(
          await repo.downloadedAssets
              .findForTrack(original.publication.trackId),
          original);
    });
  });
}

final class _Probe implements SourceFingerprintProbe {
  SourceFingerprintResult result =
      SourceFingerprintResult.fingerprinted(3, abcHash);
  Future<SourceFingerprintResult> Function(LibraryScanControl)? action;
  LibraryScanControl? control;
  bool closed = false;
  int calls = 0;
  @override
  Future<SourceFingerprintResult> fingerprint(AudioSourceReference source,
      {required int expectedSize, required LibraryScanControl control}) {
    calls++;
    this.control = control;
    return action?.call(control) ?? Future.value(result);
  }

  @override
  Future<void> close() async => closed = true;
}

final class _Repository implements DownloadedAssetRepository {
  DownloadedAssetVerification? confirmed;
  DownloadedAssetState? invalidated;
  int writes = 0;
  bool applied = true;
  Future<bool> Function()? action;
  @override
  Future<bool> confirm(
      DownloadedAsset expected, DownloadedAssetVerification verification) {
    writes++;
    confirmed = verification;
    return action?.call() ?? Future.value(applied);
  }

  @override
  Future<bool> invalidate(
      DownloadedAsset expected, DownloadedAssetState state) {
    writes++;
    invalidated = state;
    return action?.call() ?? Future.value(applied);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repository call');
}
