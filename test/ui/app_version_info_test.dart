import 'dart:async';

import 'package:clever_music_player/src/ui/app_version_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

PackageInfo _package() => PackageInfo(
    appName: 'Clever Music Player',
    packageName: 'dev.lunatuk.clever_music_player.preview',
    version: '1.2.3',
    buildNumber: '2099');

void main() {
  testWidgets(
      'shows the installed version and build after asynchronous loading',
      (tester) async {
    final result = Completer<PackageInfo>();
    var loads = 0;
    final widget = AppVersionInfo(loadInfo: () {
      loads++;
      return result.future;
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
    expect(find.text('Чтение версии…'), findsOneWidget);
    result.complete(_package());
    await tester.pump();
    expect(find.text('Версия 1.2.3 · сборка 2099'), findsOneWidget);
    await tester.pumpWidget(
        MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: widget)));
    expect(loads, 1);
  });

  testWidgets('uses native package metadata by default', (tester) async {
    PackageInfo.setMockInitialValues(
        appName: 'Clever Music Player',
        packageName: 'test',
        version: '2.4.6',
        buildNumber: '2100',
        buildSignature: '');
    await tester.pumpWidget(const MaterialApp(home: AppVersionInfo()));
    await tester.pump();
    expect(find.text('Версия 2.4.6 · сборка 2100'), findsOneWidget);
  });

  testWidgets('a native metadata error does not escape into the app',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: AppVersionInfo(loadInfo: () => throw StateError('unavailable'))));
    await tester.pump();
    expect(
        find.text('Не удалось прочитать версию приложения.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the screen during loading is safe', (tester) async {
    final result = Completer<PackageInfo>();
    await tester.pumpWidget(
        MaterialApp(home: AppVersionInfo(loadInfo: () => result.future)));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    result.complete(_package());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('version wraps in a narrow dialog with large system text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: AlertDialog(
                content: AppVersionInfo(loadInfo: () async => _package())))));
    await tester.pump();
    expect(find.text('Версия 1.2.3 · сборка 2099'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
