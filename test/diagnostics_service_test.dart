import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late LocalDiagnosticsService diagnostics;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cmp-diagnostics-');
    diagnostics =
        LocalDiagnosticsService(directoryProvider: () async => directory);
  });
  tearDown(() async {
    await diagnostics.flush();
    await directory.delete(recursive: true);
  });

  test('persisted events survive a new service and retain chronological order',
      () async {
    diagnostics.record(DiagnosticEvent.appStarted);
    diagnostics.record(DiagnosticEvent.audioLoadCompleted,
        fields: {DiagnosticField.trackId: 5, DiagnosticField.preparing: true});
    await diagnostics.flush();
    final reopened =
        LocalDiagnosticsService(directoryProvider: () async => directory);
    final report =
        jsonDecode(await (await reopened.exportReport()).readAsString()) as Map;
    expect((report['events'] as List).map((e) => e['event']),
        ['appStarted', 'audioLoadCompleted']);
    expect(report['events'][1]['trackId'], 5);
    expect(report['events'][1]['preparing'], true);
    expect(report['lastWriteSucceeded'], true);
  });

  test('sensitive strings and exception details never reach disk or export',
      () async {
    const secret = 'PRIVATE_token_123';
    diagnostics.record(DiagnosticEvent.audioLoadFailed,
        fields: {
          DiagnosticField.trackId: secret,
          DiagnosticField.nativeCode: 17,
          DiagnosticField.cached: _DoNotStringify()
        },
        error: const FileSystemException('https://host/?token=$secret',
            'C:\\Users\\$secret\\private song.mp3', OSError(secret, 5)));
    diagnostics.record(DiagnosticEvent.systemMediaFailed,
        error:
            PlatformException(code: secret, message: secret, details: secret));
    diagnostics.record(DiagnosticEvent.appFailure, error: _DoNotStringify());
    final report = await diagnostics.exportReport();
    final json = jsonDecode(await report.readAsString()) as Map;
    expect(json['events'][0]['osErrorCode'], 5);
    expect(json['events'][0]['errorKind'], 'fileSystem');
    expect(json['events'][0]['nativeCode'], 17);
    expect(json['events'][0].containsKey('trackId'), false);
    await for (final file in directory.list(recursive: true)) {
      if (file is File) {
        expect(await file.readAsString(), isNot(contains(secret)));
      }
    }
  });

  test('unsupported and nonfinite field values are omitted', () async {
    diagnostics.record(DiagnosticEvent.appReady, fields: {
      DiagnosticField.elapsedMs: double.nan,
      DiagnosticField.durationMs: double.infinity,
      DiagnosticField.trackId: {'nested': 'private'},
    });
    final report =
        jsonDecode(await (await diagnostics.exportReport()).readAsString());
    expect(
        report['events'].single.keys.toSet(), {'timeUtc', 'session', 'event'});
  });

  test('rotation bounds journal size and keeps the newest events', () async {
    diagnostics = LocalDiagnosticsService(
        directoryProvider: () async => directory,
        maxFileBytes: 1024,
        maxFiles: 3);
    for (var i = 0; i < 70; i++) {
      diagnostics.record(DiagnosticEvent.audioLoadCompleted,
          fields: {DiagnosticField.trackId: i});
      await diagnostics.flush();
    }
    final files = await directory
        .list()
        .where((e) => e.path.endsWith('.jsonl'))
        .cast<File>()
        .toList();
    expect(files.length, 3);
    for (final file in files) {
      expect(await file.length(), lessThanOrEqualTo(1024));
    }
    final report =
        jsonDecode(await (await diagnostics.exportReport()).readAsString());
    final ids = (report['events'] as List)
        .map((e) => e['trackId'])
        .cast<int>()
        .toList();
    expect(ids.last, 69);
    expect(ids, orderedEquals([...ids]..sort()));
    expect(ids.first, greaterThan(0));
  });

  test(
      'simultaneous exports are consistent and bounded without deleting foreign files',
      () async {
    diagnostics.record(DiagnosticEvent.appStarted);
    final first = await diagnostics.exportReport();
    final foreign = File(p.join(first.parent.path, 'my-notes.json'));
    await foreign.writeAsString('keep');
    final results =
        await Future.wait(List.generate(5, (_) => diagnostics.exportReport()));
    final reports = await first.parent
        .list()
        .where((e) => p.basename(e.path).startsWith('report-'))
        .toList();
    expect(reports.length, 3);
    expect(await foreign.readAsString(), 'keep');
    final report = jsonDecode(await results.last.readAsString());
    expect(report['events'].single['event'], 'appStarted');
  });

  test('burst logging has a bounded queue and reports dropped records',
      () async {
    final gate = Completer<Directory>();
    diagnostics = LocalDiagnosticsService(
        directoryProvider: () => gate.future, maxPendingRecords: 2);
    for (var i = 0; i < 100; i++) {
      diagnostics.record(DiagnosticEvent.appReady);
    }
    gate.complete(directory);
    final report =
        jsonDecode(await (await diagnostics.exportReport()).readAsString());
    expect(report['events'].length, 2);
    expect(report['droppedRecordsThisSession'], 98);
  });

  test('disk failure cannot escape record or poison a later retry', () async {
    var fail = true;
    diagnostics = LocalDiagnosticsService(directoryProvider: () async {
      if (fail) throw const FileSystemException('disk full');
      return directory;
    });
    diagnostics.record(DiagnosticEvent.appStarted);
    await diagnostics.flush();
    await expectLater(
        diagnostics.exportReport(), throwsA(isA<FileSystemException>()));
    fail = false;
    final failedReport =
        jsonDecode(await (await diagnostics.exportReport()).readAsString());
    expect(failedReport['lastWriteSucceeded'], false);
    expect(failedReport['droppedRecordsThisSession'], 1);
    diagnostics.record(DiagnosticEvent.appReady);
    final recovered =
        jsonDecode(await (await diagnostics.exportReport()).readAsString());
    expect(recovered['lastWriteSucceeded'], true);
    expect(recovered['events'].single['event'], 'appReady');
  });

  test('two service instances serialize journal writes and exports', () async {
    final other =
        LocalDiagnosticsService(directoryProvider: () async => directory);
    for (var i = 0; i < 20; i++) {
      diagnostics.record(DiagnosticEvent.audioLoadStarted,
          fields: {DiagnosticField.trackId: i});
      other.record(DiagnosticEvent.audioLoadStarted,
          fields: {DiagnosticField.trackId: i + 20});
    }
    await Future.wait([diagnostics.flush(), other.flush()]);
    final report =
        jsonDecode(await (await other.exportReport()).readAsString());
    expect((report['events'] as List).map((e) => e['trackId']).toSet(),
        {for (var i = 0; i < 40; i++) i});
    expect(report['invalidJournalLines'], 0);
  });

  test('export ignores damaged lines and strips unknown stored fields',
      () async {
    diagnostics.record(DiagnosticEvent.appStarted);
    await diagnostics.flush();
    final journal = File(p.join(directory.path, 'journal-0.jsonl'));
    final entry = jsonDecode((await journal.readAsLines()).single)
        as Map<String, dynamic>;
    entry['token'] = 'PRIVATE';
    entry['errorKind'] = 'PRIVATE';
    entry['trackId'] = 'PRIVATE';
    await journal
        .writeAsString('${jsonEncode(entry)}\n{"broken\n{"event":"PRIVATE"}\n');
    final file = await diagnostics.exportReport();
    final report = jsonDecode(await file.readAsString());
    expect(report['events'].length, 1);
    expect(report['invalidJournalLines'], 2);
    expect(await file.readAsString(), isNot(contains('PRIVATE')));
  });

  test('an oversized previous journal is read within the configured bound',
      () async {
    diagnostics = LocalDiagnosticsService(
        directoryProvider: () async => directory, maxFileBytes: 1024);
    diagnostics.record(DiagnosticEvent.appStarted);
    await diagnostics.flush();
    final journal = File(p.join(directory.path, 'journal-0.jsonl'));
    final valid = await journal.readAsString();
    await journal.writeAsString('${'x' * 5000}\n$valid');
    final report =
        jsonDecode(await (await diagnostics.exportReport()).readAsString());
    expect(report['events'].single['event'], 'appStarted');
  });

  test('a failed export does not block subsequent writes', () async {
    final blocker = File(p.join(directory.path, 'reports'));
    await blocker.writeAsString('not a directory');
    await expectLater(
        diagnostics.exportReport(), throwsA(isA<FileSystemException>()));
    await blocker.delete();
    diagnostics.record(DiagnosticEvent.appStarted);
    final report =
        jsonDecode(await (await diagnostics.exportReport()).readAsString());
    expect(report['events'].single['event'], 'appStarted');
  });

  test('an occupied Windows OS lock drops a record and later recovers',
      () async {
    final lock = await File(p.join(directory.path, 'journal.lock'))
        .open(mode: FileMode.append);
    await lock.lock(FileLock.exclusive);
    try {
      diagnostics.record(DiagnosticEvent.appStarted);
      await diagnostics.flush();
      await expectLater(
          diagnostics.exportReport(), throwsA(isA<FileSystemException>()));
    } finally {
      await lock.unlock();
      await lock.close();
    }
    diagnostics.record(DiagnosticEvent.appReady);
    final report =
        jsonDecode(await (await diagnostics.exportReport()).readAsString());
    expect(report['events'].single['event'], 'appReady');
    expect(report['droppedRecordsThisSession'], 1);
    expect(report['lastWriteSucceeded'], true);
  }, skip: !Platform.isWindows);
}

class _DoNotStringify {
  @override
  String toString() =>
      throw StateError('Sensitive object must not be formatted');
}
