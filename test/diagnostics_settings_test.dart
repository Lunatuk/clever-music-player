import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/ui/diagnostics_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, _Diagnostics diagnostics,
      {Future<void> Function(Directory)? opener, double width = 800}) async {
    await tester.binding.setSurfaceSize(Size(width, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: DiagnosticsSettings(
          diagnostics: diagnostics, openDirectory: opener ?? (_) async {}),
    ))));
  }

  testWidgets(
      'export disables duplicate requests and exposes the resulting folder',
      (tester) async {
    final diagnostics = _Diagnostics();
    final gate = Completer<File>();
    diagnostics.exporter = () => gate.future;
    final opened = <String>[];
    await pump(tester, diagnostics,
        opener: (directory) async => opened.add(directory.path));
    await tester.tap(find.text('Создать диагностический отчёт'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Создать диагностический отчёт'));
    expect(diagnostics.exports, 1);
    gate.complete(File('${Directory.systemTemp.path}/reports/report.json'));
    await tester.pumpAndSettle();
    expect(find.text('Отчёт сохранён: report.json'), findsOneWidget);
    await tester.tap(find.text('Открыть папку отчёта'));
    await tester.pumpAndSettle();
    expect(opened.single, endsWith('reports'));
  });

  testWidgets(
      'export failure is readable, hides exception details and allows retry',
      (tester) async {
    final diagnostics = _Diagnostics()
      ..exporter = () async => throw const FileSystemException('PRIVATE token');
    await pump(tester, diagnostics);
    await tester.tap(find.text('Создать диагностический отчёт'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Не удалось выполнить действие'), findsOneWidget);
    expect(find.textContaining('PRIVATE'), findsNothing);
    diagnostics.exporter =
        () async => File('${Directory.systemTemp.path}/report.json');
    await tester.tap(find.text('Создать диагностический отчёт'));
    await tester.pumpAndSettle();
    expect(find.text('Отчёт сохранён: report.json'), findsOneWidget);
    expect(find.textContaining('Не удалось выполнить действие'), findsNothing);
  });

  testWidgets('folder opening failure preserves an already created report',
      (tester) async {
    final diagnostics = _Diagnostics();
    await pump(tester, diagnostics,
        opener: (_) async => throw StateError('PRIVATE path'));
    await tester.tap(find.text('Создать диагностический отчёт'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть папку отчёта'));
    await tester.pumpAndSettle();
    expect(find.text('Отчёт сохранён: report.json'), findsOneWidget);
    expect(
        find.textContaining('Не удалось выполнить действие'), findsOneWidget);
  });

  testWidgets('narrow settings do not overflow', (tester) async {
    await pump(tester, _Diagnostics(), width: 320);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing settings during export does not update disposed state',
      (tester) async {
    final gate = Completer<File>();
    final diagnostics = _Diagnostics()..exporter = () => gate.future;
    await pump(tester, diagnostics);
    await tester.tap(find.text('Создать диагностический отчёт'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete(File('${Directory.systemTemp.path}/report.json'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _Diagnostics implements DiagnosticsService {
  int exports = 0;
  Future<File> Function() exporter =
      () async => File('${Directory.systemTemp.path}/report.json');
  @override
  Future<File> exportReport() {
    exports++;
    return exporter();
  }

  @override
  Future<Directory> directory() async => Directory.systemTemp;
  @override
  Future<void> flush() async {}
  @override
  void record(DiagnosticEvent event,
      {Map<DiagnosticField, Object?> fields = const {}, Object? error}) {}
}
