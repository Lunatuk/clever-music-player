import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clever_music_player/src/android/android_media_check_controller.dart';
import 'package:clever_music_player/src/android/android_media_check_settings.dart';
import 'package:clever_music_player/src/android/android_media_licenses.dart';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/downloaded_audio_validation.dart';

void main() {
  test('explicit check only, duplicate start is ignored, success follows drain',
      () async {
    final response = Completer<String>();
    var calls = 0;
    final controller = AndroidMediaCheckController(
        diagnostics: const NoopDiagnosticsService(),
        check: (control, onCase) {
          calls++;
          onCase(4);
          return response.future;
        });
    expect(calls, 0);
    final running = controller.check();
    await controller.check();
    expect(calls, 1);
    expect(controller.busy, true);
    response.complete('7.1.5');
    await running;
    expect(controller.message, contains('Тестовые файлы удалены'));
    expect(controller.busy, false);
    await controller.close();
    controller.dispose();
  });
  test('errors stay generic and do not leak provider paths or exception text',
      () async {
    final controller = AndroidMediaCheckController(
        diagnostics: const NoopDiagnosticsService(),
        check: (_, __) async => throw Exception('secret/path/token'));
    await controller.check();
    expect(controller.message, contains('отчёт'));
    expect(controller.message, isNot(contains('secret')));
    await controller.close();
    controller.dispose();
  });
  test('close cancels, drains, and never announces success after cancellation',
      () async {
    final response = Completer<String>();
    late LibraryScanControl accepted;
    final controller = AndroidMediaCheckController(
        diagnostics: const NoopDiagnosticsService(),
        check: (control, onCase) {
          accepted = control;
          return response.future;
        });
    final running = controller.check();
    var closed = false;
    final closing = controller.close().then((_) {
      closed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(accepted.isCancellationRequested, true);
    expect(closed, false);
    response.complete('7.1.5');
    await running;
    await closing;
    expect(controller.message, 'Проверка остановлена.');
    controller.dispose();
  });
  testWidgets('narrow settings render; leaving the page requests cancellation',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final response = Completer<String>();
    late LibraryScanControl accepted;
    final controller = AndroidMediaCheckController(
        diagnostics: const NoopDiagnosticsService(),
        check: (control, onCase) {
          accepted = control;
          return response.future;
        });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AndroidMediaCheckSettings(controller: controller)))));
    await tester.tap(find.text('Проверить теги и обложки'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(accepted.isCancellationRequested, true);
    response.complete('7.1.5');
    await tester.pump();
    await controller.close();
    controller.dispose();
  });
  testWidgets(
      'licenses are local; export uses exact bundled bytes and fixed filename flow',
      (tester) async {
    Uint8List? saved;
    await tester.pumpWidget(MaterialApp(
        home: AndroidMediaLicenses(
            assets: _Assets(),
            save: (bytes) async {
              saved = bytes;
              return 'content://documents/source.zip';
            })));
    await tester.pumpAndSettle();
    expect(find.textContaining('LGPL text'), findsOneWidget);
    await tester.tap(find.text('Сохранить исходники FFmpeg'));
    await tester.pumpAndSettle();
    expect(saved, [80, 75, 3, 4]);
    expect(find.text('Исходники сохранены.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('license export error shows no arbitrary exception text',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: AndroidMediaLicenses(
            assets: _Assets(),
            save: (_) async => throw const AudioValidationException(
                AudioValidationOutcome.unreadable))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить исходники FFmpeg'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось сохранить'), findsOneWidget);
  });
}

class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(
          key.endsWith('.zip') ? [80, 75, 3, 4] : 'LGPL text'.codeUnits));
}
