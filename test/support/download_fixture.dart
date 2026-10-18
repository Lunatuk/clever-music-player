import 'dart:io';

import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library/metadata_reader_service.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_metadata.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

final class DownloadFixture {
  DownloadFixture._(this.root, this.database)
      : repositories = DriftRepositories(database);
  final Directory root;
  final AppDatabase database;
  final DriftRepositories repositories;
  DateTime now = DateTime.utc(2030);
  DateTime clock() => now;
  late RemoteLibraryAccount account;
  late int folderId;
  Directory get destination => Directory(p.join(root.path, 'music'));
  File get raw => File(p.join(root.path, 'raw.part'));
  static Future<DownloadFixture> open({bool persistent = false}) async {
    final root = await Directory.systemTemp.createTemp('cmp_download_');
    final database = AppDatabase(persistent
        ? NativeDatabase.createInBackground(
            File(p.join(root.path, 'state.sqlite')))
        : NativeDatabase.memory());
    final fixture = DownloadFixture._(root, database);
    await fixture.destination.create();
    await fixture.raw.writeAsString('abc');
    fixture.account = await fixture.repositories.remoteLibrary.activateAccount(
        RemoteAccountIdentity(provider: 'yandex_music', accountId: 'test'));
    fixture.folderId = await fixture.repositories.libraryFolders.upsertFolder(
        LibraryFolder(
            path: fixture.destination.path,
            createdAt: fixture.now,
            updatedAt: fixture.now));
    await database.customStatement('PRAGMA busy_timeout = 5000');
    return fixture;
  }

  Future<DownloadJob> claim(
      {String externalId = '001',
      String variant = '',
      DownloadJobStage stage = DownloadJobStage.download}) async {
    final key = DownloadJobKey(
        libraryFolderId: folderId,
        identity: ExternalTrackIdentity(
            provider: 'yandex_music',
            externalId: externalId,
            variantKey: variant),
        quality: 'high');
    await repositories.downloadJobs.enqueue(account, [key], now: now);
    var job = (await repositories.downloadJobs.claimNext(account, now: now))!;
    while (job.stage.index < stage.index) {
      job = (await repositories.downloadJobs.advance(
          job, DownloadJobStage.values[job.stage.index + 1],
          now: now))!;
    }
    return job;
  }

  DownloadedAssetVerification proof({DateTime? checkedAt}) =>
      DownloadedAssetVerification(
          actualQuality: 'high',
          container: 'mp3',
          codec: 'mp3',
          fileSizeBytes: 3,
          duration: const Duration(seconds: 3),
          contentHash: sha256.convert('abc'.codeUnits).toString(),
          checkedAt: checkedAt ?? now);

  DownloadedTrackImport publication(DownloadJob job,
      {String? id,
      String? path,
      Track? track,
      DownloadedAssetVerification? verification}) {
    final token = id ?? 'a' * 64;
    final proof = verification ?? this.proof();
    return DownloadedTrackImport(
        jobId: job.id,
        key: job.key,
        publicationId: token,
        verification: proof,
        track: track ??
            Track(
                filePath: path ??
                    p.join(destination.path,
                        'cmp-${downloadPublicationResourceKey(job.key)}-$token.mp3'),
                libraryFolderId: job.key.libraryFolderId,
                title: 'Provider title',
                artist: 'Artist',
                albumArtist: 'Album artist',
                stableId: 'same-metadata',
                contentHash: proof.contentHash,
                codec: proof.container,
                duration: proof.duration,
                fileSizeBytes: proof.fileSizeBytes,
                metadataSource: MetadataSource.embeddedTags,
                addedAt: now,
                updatedAt: now));
  }

  Future<int> count(String table) async => (await database
          .customSelect('SELECT COUNT(*) AS n FROM $table')
          .getSingle())
      .read<int>('n');

  Future<void> close() async {
    await database.close();
    await root.delete(recursive: true); // Exclusively our fixture directory.
  }

  Future<DownloadFixture> reopen() async {
    final file = File(p.join(root.path, 'state.sqlite'));
    if (!await file.exists()) {
      throw StateError('Fixture must use a persistent database.');
    }
    await database.close();
    final result = DownloadFixture._(
        root, AppDatabase(NativeDatabase.createInBackground(file)))
      ..now = now
      ..folderId = folderId;
    result.account = (await result.repositories.remoteLibrary
        .findAccount(account.identity))!;
    await result.database.customStatement('PRAGMA busy_timeout = 5000');
    return result;
  }
}

DownloadedAudioExpectation downloadExpectation() => DownloadedAudioExpectation(
        quality: 'high',
        container: DownloadedAudioContainer.mp3,
        codec: DownloadedAudioCodec.mp3,
        fileSizeBytes: 3,
        duration: const Duration(seconds: 3),
        minimumBitRate: 96000,
        tags: const {
          'title': 'Provider title',
          'artist': 'Artist',
          'album_artist': 'Album artist'
        });

/// Deterministic unit-test backend, deliberately not a decoder. Real codecs
/// and the complete coordinator are also exercised with the bundled helper.
base class DownloadTestBackend implements AudioMetadataBackend {
  Future<void> Function(LibraryScanControl)? onWrite;
  bool reject = false, closed = false;
  int writes = 0;
  @override
  Future<DownloadedAudioInspection> inspect(
          File file, LibraryScanControl control) async =>
      DownloadedAudioInspection(
          container: DownloadedAudioContainer.mp3,
          codec: DownloadedAudioCodec.mp3,
          duration: const Duration(seconds: 3),
          sizeBytes: await file.length(),
          audioStreamIndex: 0,
          sampleRate: 48000,
          channels: 2,
          bitRate: 128000,
          tags: downloadExpectation().tags);
  @override
  Future<String> digest(File file, DownloadedAudioInspection info,
          AudioCopyDigest mode, LibraryScanControl control) async =>
      sha256.convert(await file.readAsBytes()).toString();
  @override
  Future<void> writeMetadata(
      File source,
      File output,
      DownloadedAudioInspection info,
      DownloadedAudioExpectation expected,
      LibraryScanControl control,
      {File? cover,
      EmbeddedCoverFormat? coverFormat,
      int? maxOutputBytes}) async {
    writes++;
    await onWrite?.call(control);
    control.throwIfCancelled();
    if (reject) {
      throw const AudioValidationException(AudioValidationOutcome.invalidAudio);
    }
    await output.writeAsBytes(await source.readAsBytes());
  }

  @override
  Future<Duration> decodeAudio(File file, DownloadedAudioInspection inspection,
          LibraryScanControl control) async =>
      const Duration(seconds: 3);
  @override
  Future<void> decodeCover(File file, DownloadedAudioInspection inspection,
      LibraryScanControl control) async {}
  @override
  Future<void> close() async => closed = true;
}

final class DownloadTestMetadataReader implements MetadataReaderService {
  Future<void> Function(File)? onRead;
  bool fail = false;
  @override
  Future<AudioMetadata> read(File file) async {
    await onRead?.call(file);
    if (fail) throw const FormatException('synthetic reader failure');
    final stat = await file.stat();
    return AudioMetadata(
        filePath: p.normalize(file.absolute.path),
        fileSizeBytes: stat.size,
        modifiedAt: stat.modified,
        title: 'Provider title',
        artist: 'Artist',
        albumArtist: 'Album artist',
        codec: 'mp3',
        duration: const Duration(seconds: 3),
        metadataSource: MetadataSource.embeddedTags,
        metadataConfidence: 1);
  }
}
