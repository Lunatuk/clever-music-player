import 'dart:async';
import 'package:clever_music_player/src/appearance/appearance_controller.dart';
import 'package:clever_music_player/src/appearance/appearance_settings.dart';
import 'package:clever_music_player/src/appearance/appearance_settings_screen.dart';
import 'package:clever_music_player/src/appearance/appearance_theme.dart';
import 'package:clever_music_player/src/data/drift/app_database.dart';
import 'package:clever_music_player/src/data/repositories/drift_repositories.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/test_audio_folders.dart';

void main() {
  for (final raw in [
    null,
    '',
    '[]',
    '{}',
    '{',
    '{"version":2,"mode":"light"}',
    'x' * 5000
  ]) {
    test('missing/malformed/unknown version safely falls back: ${raw?.length}',
        () {
      expect(AppearanceSettings.decode(raw), const AppearanceSettings());
    });
  }
  test(
      'all preference fields round trip and invalid fields recover independently',
      () {
    for (final mode in AppearanceMode.values) {
      for (final motion in AppearanceMotion.values) {
        final value = AppearanceSettings(
            mode: mode,
            motion: motion,
            accentRgb: 0x123abc,
            compact: true,
            coverRadius: 24);
        expect(AppearanceSettings.decode(value.encode()), value);
      }
    }
    expect(
        AppearanceSettings.decode(
            '{"version":1,"mode":"light","motion":"oops","compact":3,"accentRgb":-1,"coverRadius":999}'),
        const AppearanceSettings(mode: AppearanceMode.light, coverRadius: 24));
    expect(
        AppearanceSettings.decode(
            '{"version":1,"accentRgb":1.5,"coverRadius":"x"}'),
        const AppearanceSettings());
  });
  test(
      'SQLite settings survive a new controller without changing unrelated settings',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = DriftRepositories(db).settings;
    await settings.writeString('playback.crossfade', '5');
    final first = AppearanceController(settings: settings);
    await first.initialize();
    final expected = first.value.copyWith(
        mode: AppearanceMode.light,
        accentRgb: 0xabcdef,
        motion: AppearanceMotion.slow,
        compact: true,
        coverRadius: 20);
    await first.update(expected);
    await first.close();
    first.dispose();
    final second = AppearanceController(settings: settings);
    addTearDown(second.dispose);
    await second.initialize();
    expect(second.value, expected);
    expect(await settings.readString('playback.crossfade'), '5');
    await second.reset();
    expect(
        AppearanceSettings.decode(
            await settings.readString(AppearanceSettings.storageKey)),
        const AppearanceSettings());
  });
  test(
      'writes are serialized and a late earlier failure cannot revert the latest choice',
      () async {
    final store = TestFolderSettings();
    final gate = Completer<void>();
    var active = 0, maximum = 0, calls = 0;
    store.writeAction = (key, value) async {
      active++;
      maximum = active > maximum ? active : maximum;
      calls++;
      try {
        if (calls == 1) {
          await gate.future;
          throw StateError('private');
        }
      } finally {
        active--;
      }
    };
    final c = AppearanceController(settings: store);
    addTearDown(c.dispose);
    await c.initialize();
    final a = c.update(c.value.copyWith(accentRgb: 0x123456));
    final b = c.update(c.value.copyWith(accentRgb: 0x654321));
    expect(c.value.accentRgb, 0x654321);
    expect(c.isSaving, isTrue);
    gate.complete();
    await Future.wait([a, b]);
    expect(maximum, 1);
    expect(c.failure, isNull);
    expect(c.isSaving, isFalse);
    expect(
        AppearanceSettings.decode(store.values[AppearanceSettings.storageKey])
            .accentRgb,
        0x654321);
  });
  test('late load cannot overwrite an explicit user change', () async {
    final store = TestFolderSettings();
    final gate = Completer<String?>();
    store.readAction = (_) => gate.future;
    final c = AppearanceController(settings: store);
    addTearDown(c.dispose);
    final loading = c.initialize();
    await c.update(c.value.copyWith(accentRgb: 0x112233));
    gate.complete(const AppearanceSettings(accentRgb: 0xabcdef).encode());
    await loading;
    expect(c.value.accentRgb, 0x112233);
  });
  test('read failure and retry preserve settings, save failure is retryable',
      () async {
    final store = TestFolderSettings();
    store.values[AppearanceSettings.storageKey] =
        const AppearanceSettings(compact: true).encode();
    store.readAction = (_) async => throw StateError('private');
    final c = AppearanceController(settings: store);
    addTearDown(c.dispose);
    await c.initialize();
    expect(c.failure, AppearanceFailure.load);
    expect(store.writes, 0);
    store.readAction = null;
    await c.retry();
    expect(c.value.compact, isTrue);
    store.writeAction = (key, value) async => throw StateError('private');
    await c.update(c.value.copyWith(mode: AppearanceMode.light));
    expect(c.failure, AppearanceFailure.save);
    store.writeAction = null;
    await c.retry();
    expect(c.failure, isNull);
    expect(
        AppearanceSettings.decode(store.values[AppearanceSettings.storageKey])
            .mode,
        AppearanceMode.light);
  });
  test(
      'shutdown drains accepted writes and rejects new edits without notifications',
      () async {
    final store = TestFolderSettings();
    final gate = Completer<void>();
    store.writeAction = (key, value) => gate.future;
    final c = AppearanceController(settings: store);
    await c.initialize();
    var notices = 0;
    c.addListener(() => notices++);
    final writing = c.update(c.value.copyWith(compact: true));
    var closed = false;
    final closing = c.close().then((_) => closed = true);
    await c.update(const AppearanceSettings(mode: AppearanceMode.light));
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    final before = notices;
    c.dispose();
    gate.complete();
    await writing;
    await closing;
    expect(notices, before);
    expect(
        AppearanceSettings.decode(store.values[AppearanceSettings.storageKey])
            .compact,
        isTrue);
  });
  test(
      'custom accent control text chooses readable black or white, themes keep readable labels',
      () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
    }

    for (final rgb in [
      0,
      0xffffff,
      0xffcc33,
      0xff7474,
      0xb4a2ff,
      0x64b5f6,
      0x70d9b4,
      0x0000ff,
      0xff0000
    ]) {
      for (final brightness in Brightness.values) {
        final theme = createAppearanceTheme(
            AppearanceSettings(accentRgb: rgb), brightness);
        final tokens = theme.extension<AppearanceTokens>()!;
        expect(contrast(tokens.accent, tokens.onAccent),
            greaterThanOrEqualTo(4.5));
        expect(contrast(tokens.muted, theme.colorScheme.surface),
            greaterThanOrEqualTo(4.5));
        expect(contrast(tokens.muted, theme.colorScheme.surfaceContainer),
            greaterThanOrEqualTo(4.5));
      }
    }
  });

  Future<void> pump(WidgetTester tester, AppearanceController c,
      {double scale = 1, bool reduced = false}) async {
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: reduced),
            child: child!),
        home: AppearanceSettingsScreen(controller: c)));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(320, 720), const Size(844, 390)]) {
    testWidgets('appearance form remains usable at $size and 200% text',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppearanceController();
      addTearDown(c.dispose);
      await c.initialize();
      await pump(tester, c, scale: 2);
      await tester.scrollUntilVisible(
          find.text('Вернуть исходное оформление'), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('presets, custom hex validation, theme and reset are live',
      (tester) async {
    final c = AppearanceController();
    addTearDown(c.dispose);
    await c.initialize();
    await pump(tester, c);
    await tester.tap(find.text('Мятный'));
    await tester.pumpAndSettle();
    expect(c.value.accentRgb, 0x70d9b4);
    await tester.tap(find.text('Свой цвет'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'oops');
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(find.text('Нужно 6 символов: 0–9, A–F'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '#123456');
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(c.value.accentRgb, 0x123456);
    await tester.tap(find.byType(DropdownButtonFormField<AppearanceMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Светлая').last);
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Акцентный цвет'))).brightness,
        Brightness.light);
    await tester.scrollUntilVisible(
        find.text('Вернуть исходное оформление'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Вернуть исходное оформление'));
    await tester.pumpAndSettle();
    expect(c.value, const AppearanceSettings());
  });
  testWidgets('system theme follows OS changes without replacing preferences',
      (tester) async {
    final c = AppearanceController();
    addTearDown(c.dispose);
    await c.initialize();
    await c.update(c.value.copyWith(mode: AppearanceMode.system));
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    for (final brightness in Brightness.values) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      await pump(tester, c);
      expect(Theme.of(tester.element(find.text('Акцентный цвет'))).brightness,
          brightness);
      expect(c.value.mode, AppearanceMode.system);
    }
  });
  for (final reduced in [false, true]) {
    testWidgets('motion settings respect system reduction=$reduced',
        (tester) async {
      final c = AppearanceController();
      addTearDown(c.dispose);
      await c.initialize();
      for (final motion in AppearanceMotion.values) {
        await c.update(c.value.copyWith(motion: motion));
        await pump(tester, c, reduced: reduced);
        await tester.scrollUntilVisible(
            find.byKey(const ValueKey('appearance-motion-sample')), 200,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        final sample = tester.widget<AnimatedContainer>(
            find.byKey(const ValueKey('appearance-motion-sample')));
        expect(sample.duration,
            reduced ? Duration.zero : appearanceDuration(motion, 320));
      }
    });
  }
}
