import 'dart:async';
import 'dart:io';

import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/bundled_media_helper.dart';
import 'package:clever_music_player/src/ui/media_helper_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(WidgetTester tester, MediaHelperCheck check,
          {Future<void> Function(Directory)? open}) =>
      tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MediaHelperSettings(
                  check: check, openDirectory: open ?? (_) async {}))));

  testWidgets('no startup work; explicit successful check can be repeated',
      (tester) async {
    var calls = 0;
    await show(tester, (_) async {
      calls++;
      return '7.1.5';
    });
    expect(calls, 0);
    await tester.tap(find.text('Проверить медиапомощник'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Медиапомощник готов: FFmpeg 7.1.5'),
        findsOneWidget);
    await tester.tap(find.text('Проверить медиапомощник'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
  testWidgets(
      'pending operation disables repeat, cancel drains then permits retry',
      (tester) async {
    final done = Completer<String>();
    LibraryScanControl? control;
    await show(tester, (value) {
      control = value;
      return done.future;
    });
    await tester.tap(find.text('Проверить медиапомощник'));
    await tester.pump();
    final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Проверить медиапомощник'));
    expect(button.onPressed, isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Отменить проверку'));
    await tester.pump();
    expect(control!.isCancellationRequested, isTrue);
    done.complete('7.1.5');
    await tester.pumpAndSettle();
    expect(find.text('Проверка отменена.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Проверить медиапомощник'))
            .onPressed,
        isNotNull);
  });
  testWidgets(
      'leaving settings cancels pending check and handles its late error',
      (tester) async {
    final done = Completer<String>();
    LibraryScanControl? control;
    await show(tester, (value) {
      control = value;
      return done.future;
    });
    await tester.tap(find.text('Проверить медиапомощник'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(control!.isCancellationRequested, isTrue);
    done.completeError(const LibraryScanCancelled());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  for (final failure in [
    MediaHelperFailure.missing,
    MediaHelperFailure.invalidBundle
  ]) {
    testWidgets('$failure explains reinstalling the complete archive',
        (tester) async {
      await show(tester, (_) async => throw MediaHelperException(failure));
      await tester.tap(find.text('Проверить медиапомощник'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Распакуй полный архив'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  }
  testWidgets('unexpected private exception text is not exposed',
      (tester) async {
    await show(tester, (_) async => throw StateError('private path/token'));
    await tester.tap(find.text('Проверить медиапомощник'));
    await tester.pumpAndSettle();
    expect(find.textContaining('private path/token'), findsNothing);
    expect(find.textContaining('Можно повторить проверку'), findsOneWidget);
  });
  testWidgets('license action opens only the installed helper directory',
      (tester) async {
    Directory? opened;
    await show(tester, (_) async => '7.1.5',
        open: (value) async => opened = value);
    await tester.tap(find.textContaining('лицензия и исходники'));
    await tester.pumpAndSettle();
    expect(
        opened!.path, endsWith('tools${Platform.pathSeparator}media-helper'));
  });
}
