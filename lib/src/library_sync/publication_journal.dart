import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../domain/models/download_job.dart';
import '../domain/models/external_track_ref.dart';
import '../library/library_scan_control.dart';
import 'native_publication_files.dart';
import 'publication_intent.dart';

/// Quotas cover journal operations and reserved staging, not finished music.
final class PublicationRetentionPolicy {
  PublicationRetentionPolicy({
    this.maxOperations = 512,
    this.maxStagingBytes = 16 * 1024 * 1024 * 1024,
    this.importedAge = Duration.zero,
    this.abandonedAge = const Duration(days: 1),
  }) {
    if (maxOperations <= 0 ||
        maxOperations > 10000 ||
        maxStagingBytes <= 0 ||
        maxStagingBytes > 1024 * 1024 * 1024 * 1024 ||
        importedAge.isNegative ||
        abandonedAge.isNegative) {
      throw ArgumentError('Некорректные лимиты журнала.');
    }
  }
  final int maxOperations, maxStagingBytes;
  final Duration importedAge, abandonedAge;
}

/// Written before creating audio.part. Old journals without this remain valid.
final class PublicationReservation {
  PublicationReservation(
      {required this.jobId,
      required this.key,
      required this.publicationId,
      required this.sizeBytes,
      required DateTime createdAt})
      : createdAt = createdAt.toUtc() {
    if (jobId <= 0 ||
        !isPublicationId(publicationId) ||
        sizeBytes <= 0 ||
        sizeBytes > 8 * 1024 * 1024 * 1024 ||
        this.createdAt.microsecondsSinceEpoch <= 0) {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
  }
  final int jobId, sizeBytes;
  final DownloadJobKey key;
  final String publicationId;
  final DateTime createdAt;
  String get operationName => '${publicationResourceKey(key)}-$publicationId';
  String encode() => jsonEncode({
        'version': 1,
        'jobId': jobId,
        'folderId': key.libraryFolderId,
        'provider': key.identity.provider,
        'externalId': key.identity.externalId,
        'variantKey': key.identity.variantKey,
        'quality': key.quality,
        'publicationId': publicationId,
        'sizeBytes': sizeBytes,
        'createdAtUs': createdAt.microsecondsSinceEpoch,
      });
  static PublicationReservation decode(String value) {
    try {
      final map = jsonDecode(value) as Map<String, dynamic>;
      final result = PublicationReservation(
          jobId: map['jobId'] as int,
          key: DownloadJobKey(
              libraryFolderId: map['folderId'] as int,
              identity: ExternalTrackIdentity(
                  provider: map['provider'] as String,
                  externalId: map['externalId'] as String,
                  variantKey: map['variantKey'] as String),
              quality: map['quality'] as String),
          publicationId: map['publicationId'] as String,
          sizeBytes: map['sizeBytes'] as int,
          createdAt: DateTime.fromMicrosecondsSinceEpoch(
              map['createdAtUs'] as int,
              isUtc: true));
      if (result.encode() != value) throw const FormatException();
      return result;
    } on Object {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
  }
}

final class PublicationJournalEntry {
  PublicationJournalEntry(
      this.directory, this.files, this.reservation, this.intent, this.retiring);
  final Directory directory;
  final Map<String, File> files;
  final PublicationReservation? reservation;
  final PublicationIntent? intent;
  final bool retiring;
  String get resourceKey => p.basename(directory.path).substring(0, 64);
  String get publicationId => p.basename(directory.path).substring(65);
  DateTime? get createdAt =>
      reservation?.createdAt ?? intent?.verification.checkedAt;
  String get retirementRecord => jsonEncode({
        'version': 1,
        'reservation': reservation?.encode(),
        'intent': intent?.encode(),
      });

  static Future<PublicationJournalEntry> read(Directory directory) async {
    try {
      return await _read(directory);
    } on FormatException {
      throw const PublicationException(PublicationFailure.invalidJournal);
    } on TypeError {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
  }

  static Future<PublicationJournalEntry> _read(Directory directory) async {
    await publicationDirectory(directory.path);
    final name = p.basename(directory.path);
    if (RegExp(r'^[0-9a-f]{64}-[0-9a-f]{64}$').stringMatch(name) != name) {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
    final files = <String, File>{};
    await for (final child in directory.list(followLinks: false)) {
      final name = p.basename(child.path);
      if (files.length >= 16 ||
          child is! File ||
          !({
                'audio.part',
                'reservation.json',
                'intent.json',
                'published.json',
                'retention.json'
              }.contains(name) ||
              RegExp(r'^journal-[0-9a-f]{64}\.part$').stringMatch(name) ==
                  name)) {
        throw const PublicationException(PublicationFailure.invalidJournal);
      }
      await publicationFile(child.path);
      if (name != 'audio.part' &&
          await child.length() > (name == 'retention.json' ? 65536 : 16384)) {
        throw const PublicationException(PublicationFailure.invalidJournal);
      }
      files[name] = child;
    }
    String? reservation, intent;
    final retiring = files.containsKey('retention.json');
    if (retiring) {
      final text =
          await readPublicationRecord(files['retention.json']!, limit: 65536);
      final map = jsonDecode(text) as Map<String, dynamic>;
      reservation = map['reservation'] as String?;
      intent = map['intent'] as String?;
      if ((reservation == null && intent == null) ||
          jsonEncode({
                'version': 1,
                'reservation': reservation,
                'intent': intent
              }) !=
              text) {
        throw const PublicationException(PublicationFailure.invalidJournal);
      }
    }
    for (final key in ['reservation.json', 'intent.json']) {
      final file = files[key];
      if (file == null) continue;
      final value = await readPublicationRecord(file);
      final old = key == 'reservation.json' ? reservation : intent;
      if (retiring && old != value) {
        throw const PublicationException(PublicationFailure.invalidJournal);
      }
      if (key == 'reservation.json') {
        reservation = value;
      } else {
        intent = value;
      }
    }
    final reserved =
        reservation == null ? null : PublicationReservation.decode(reservation);
    final planned = intent == null ? null : PublicationIntent.decode(intent);
    if ((reserved != null && reserved.operationName != name) ||
        (planned != null && planned.operationName != name) ||
        (reserved != null &&
            planned != null &&
            (reserved.jobId != planned.jobId ||
                reserved.key != planned.key ||
                reserved.sizeBytes != planned.verification.fileSizeBytes)) ||
        (files.containsKey('published.json') &&
            (planned == null ||
                await readPublicationRecord(files['published.json']!) !=
                    planned.encode()))) {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
    final audio = files['audio.part'];
    if (audio != null &&
        await audio.length() >
            (reserved?.sizeBytes ??
                planned?.verification.fileSizeBytes ??
                8 * 1024 * 1024 * 1024)) {
      throw const PublicationException(PublicationFailure.invalidStaging);
    }
    return PublicationJournalEntry(
        directory, files, reserved, planned, retiring);
  }

  Future<int> reservedBytes() async {
    final audio = files['audio.part'];
    final actual = audio == null ? 0 : await audio.length();
    // A published receipt releases the reservation only when staging is absent.
    if (files.containsKey('published.json') && audio == null) return 0;
    return max(actual, reservation?.sizeBytes ?? 0);
  }
}

Future<List<Directory>> publicationOperations(
    String root, LibraryScanControl control) async {
  final result = <Directory>[];
  await for (final child
      in Directory(p.join(root, '.cmp-publications-v1', 'operations'))
          .list(followLinks: false)) {
    control.throwIfCancelled();
    if (result.length >= 10000 || child is! Directory) {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
    result.add(child);
  }
  result.sort((a, b) => a.path.compareTo(b.path));
  return result;
}

Future<void> reservePublication(
    String root,
    PublicationReservation reservation,
    PublicationRetentionPolicy policy,
    PublicationFiles files,
    LibraryScanControl control) async {
  final path = p.join(root, '.cmp-publications-v1', 'locks', 'quota.lock');
  try {
    await File(path).create(exclusive: true);
  } on FileSystemException {
    await publicationFile(path);
  }
  await publicationFile(path);
  final lock = await files.lock(path);
  try {
    final entries = await publicationOperations(root, control);
    if (entries.length >= policy.maxOperations) {
      throw const PublicationException(PublicationFailure.quotaExceeded);
    }
    var total = 0;
    for (final directory in entries) {
      control.throwIfCancelled();
      total +=
          await (await PublicationJournalEntry.read(directory)).reservedBytes();
      if (total > policy.maxStagingBytes - reservation.sizeBytes) {
        throw const PublicationException(PublicationFailure.quotaExceeded);
      }
    }
    if (reservation.sizeBytes > policy.maxStagingBytes - total) {
      throw const PublicationException(PublicationFailure.quotaExceeded);
    }
    control.throwIfCancelled();
    final directory = p.join(
        root, '.cmp-publications-v1', 'operations', reservation.operationName);
    if (!await files.createDirectory(directory)) {
      throw const PublicationException(PublicationFailure.collision);
    }
    await atomicPublicationRecord(File(p.join(directory, 'reservation.json')),
        reservation.encode(), files);
  } finally {
    await lock.close();
  }
}

Future<void> publicationDirectory(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const PublicationException(PublicationFailure.unsafePath);
  }
}

Future<void> publicationFile(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const PublicationException(PublicationFailure.unsafePath);
  }
}

Future<String> readPublicationRecord(File file, {int limit = 16384}) async {
  await publicationFile(file.path);
  final input = await file.open();
  try {
    if (await input.length() > limit) {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
    final bytes = await input.read(limit + 1);
    if (bytes.length > limit || (await input.read(1)).isNotEmpty) {
      throw const PublicationException(PublicationFailure.invalidJournal);
    }
    return utf8.decode(bytes);
  } finally {
    await input.close();
  }
}

Future<void> atomicPublicationRecord(
    File target, String value, PublicationFiles files) async {
  if (utf8.encode(value).length > 65536) {
    throw const PublicationException(PublicationFailure.invalidJournal);
  }
  final random = Random.secure();
  final id = List.generate(
      32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  final temporary = File(p.join(target.parent.path, 'journal-$id.part'));
  await temporary.create(exclusive: true);
  await temporary.writeAsString(value, flush: true);
  await files.moveNoReplace(temporary.path, target.path);
}
