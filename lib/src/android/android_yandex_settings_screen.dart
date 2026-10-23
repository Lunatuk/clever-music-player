import 'dart:async';

import 'package:flutter/material.dart';

import '../diagnostics/diagnostics_service.dart';
import '../library_sync/yandex_connection_controller.dart';
import '../library_sync/yandex_library_update_controller.dart';
import '../ui/yandex_settings.dart';
import 'android_download_storage_controller.dart';
import 'android_download_storage_settings.dart';
import 'android_diagnostics_settings.dart';
import 'android_media_check_controller.dart';
import 'android_media_check_settings.dart';

/// Starts only local restoration when explicitly opened. Updates outlive this
/// route; folder and diagnostic mutations cannot overlap an accepted update.
final class AndroidYandexSettingsScreen extends StatefulWidget {
  const AndroidYandexSettingsScreen(
      {super.key,
      required this.connection,
      required this.updates,
      required this.storage,
      required this.media,
      this.diagnostics = const NoopDiagnosticsService()});
  final DiagnosticsService diagnostics;
  final YandexConnectionController connection;
  final YandexLibraryUpdateController updates;
  final AndroidDownloadStorageController storage;
  final AndroidMediaCheckController media;
  @override
  State<AndroidYandexSettingsScreen> createState() =>
      _AndroidYandexSettingsScreenState();
}

final class _AndroidYandexSettingsScreenState
    extends State<AndroidYandexSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Restore before descendant listeners are attached: initialize can notify
    // synchronously and must not dirty an already building ancestor.
    unawaited(widget.connection.initialize());
    unawaited(widget.updates.initialize());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Яндекс Музыка')),
      body: SafeArea(
          top: false,
          child: ListenableBuilder(
              listenable: Listenable.merge([
                widget.connection,
                widget.updates,
                widget.storage,
                widget.media
              ]),
              builder: (context, _) {
                final updating =
                    widget.connection.isBusy || widget.updates.isBusy;
                final checking = widget.storage.busy || widget.media.busy;
                final selected = widget.updates.folders.where((f) =>
                    f.id == widget.updates.folderId &&
                    f.path == widget.storage.folder?.storageValue);
                return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          YandexSettings(
                              controller: widget.connection,
                              updates: widget.updates,
                              updateActionsBlocked: checking,
                              updateDestination: Text(selected.isEmpty
                                  ? 'Выбери или подключи папку в разделе «Хранилище загрузок» ниже.'
                                  : 'Папка для загрузок: ${widget.storage.folderName}')),
                          const SizedBox(height: 16),
                          AndroidDownloadStorageSettings(
                              controller: widget.storage,
                              locked: updating || widget.media.busy),
                          const SizedBox(height: 16),
                          AndroidMediaCheckSettings(
                              controller: widget.media,
                              locked: updating || widget.storage.busy),
                          const SizedBox(height: 16),
                          AndroidDiagnosticsSettings(
                              diagnostics: widget.diagnostics),
                        ]));
              })));
}
