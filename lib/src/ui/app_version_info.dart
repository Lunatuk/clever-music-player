import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Reads the installed package, including versions overridden at build time.
/// Opening this widget never delays application startup or playback.
final class AppVersionInfo extends StatefulWidget {
  const AppVersionInfo({super.key, this.loadInfo});

  final Future<PackageInfo> Function()? loadInfo;

  @override
  State<AppVersionInfo> createState() => _AppVersionInfoState();
}

final class _AppVersionInfoState extends State<AppVersionInfo> {
  late final Future<PackageInfo> _info =
      Future.sync(widget.loadInfo ?? PackageInfo.fromPlatform);

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
        future: _info,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Не удалось прочитать версию приложения.');
          }
          final info = snapshot.data;
          if (info == null) {
            return const Text('Чтение версии…');
          }
          return SelectableText(
              'Версия ${info.version} · сборка ${info.buildNumber}');
        },
      );
}
