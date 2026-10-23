import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clever_music_player/src/android/android_diagnostics_settings.dart';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late LocalDiagnosticsService diagnostics;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cmp_android_report_');
    diagnostics =
        LocalDiagnosticsService(directoryProvider: () async => directory);
    diagnostics.record(DiagnosticEvent.androidDownloadCoordinated,
        fields: {
          DiagnosticField.needsReconciliation: true,
          DiagnosticField.coordinationStage: 3
        },
        error: StateError('PRIVATE_MUSIC_TITLE_AND_TOKEN'));
  });
  tearDown(() async {
    await diagnostics.flush();
    await directory.delete(recursive: true);
  });
  Future<void> pump(
      WidgetTester tester, Future<String?> Function(String, Uint8List) save,
      {DiagnosticsService? service}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AndroidDiagnosticsSettings(
                    diagnostics: service ?? diagnostics, save: save)))));
    await tester.runAsync(
        () => tester.tap(find.text('Сохранить диагностический отчёт')));
  }

  Future<void> until(WidgetTester tester, String text) async {
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.textContaining(text).evaluate().isNotEmpty) return;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    fail('Expected export result');
  }

  testWidgets(
      'explicit export passes basename and actual sanitized JSON bytes to system save seam',
      (tester) async {
    String? name;
    Uint8List? bytes;
    await pump(tester, (n, b) async {
      name = n;
      bytes = b;
      return '/PRIVATE_DESTINATION/report.json';
    });
    await until(tester, 'Отчёт сохранён.');
    expect(name, startsWith('report-'));
    expect(name, endsWith('.json'));
    expect(name, isNot(contains(directory.path)));
    final text = utf8.decode(bytes!);
    expect(jsonDecode(text), isA<Map>());
    expect(text, contains('androidDownloadCoordinated'));
    expect(text, contains('needsReconciliation'));
    expect(text, isNot(contains('PRIVATE_MUSIC_TITLE_AND_TOKEN')));
    expect(find.textContaining('PRIVATE_DESTINATION'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'picker cancellation is clear and permits another explicit export',
      (tester) async {
    var calls = 0;
    await pump(tester, (n, b) async {
      calls++;
      return null;
    });
    await until(tester, 'Сохранение отменено.');
    await tester.runAsync(
        () => tester.tap(find.text('Сохранить диагностический отчёт')));
    await until(tester, 'Сохранение отменено.');
    expect(calls, 2);
  });
  testWidgets(
      'export failure cannot expose private exception text or open picker',
      (tester) async {
    var saves = 0;
    await pump(tester, (n, b) async {
      saves++;
      return 'unused';
    }, service: _FailedDiagnostics());
    await until(tester, 'Не удалось сохранить отчёт.');
    expect(saves, 0);
    expect(find.textContaining('PRIVATE_FAILURE'), findsNothing);
  });
  testWidgets(
      'accepted export blocks duplicate action and late picker reply after route close is drained',
      (tester) async {
    final entered = Completer<void>(), release = Completer<String?>();
    var calls = 0;
    await pump(tester, (n, b) {
      calls++;
      entered.complete();
      return release.future;
    });
    for (var i = 0; i < 100 && !entered.isCompleted; i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(entered.isCompleted, isTrue);
    final button = find.byType(OutlinedButton);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    release.complete('saved');
    await tester.pump();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}

final class _FailedDiagnostics implements DiagnosticsService {
  @override
  Future<File> exportReport() async => throw StateError('PRIVATE_FAILURE');
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('unused');
}
