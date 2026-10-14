import 'dart:async';

import 'package:flutter/material.dart';

import 'android_folder_bookmarks.dart';
import 'android_import_controller.dart';

String _timestamp(DateTime time) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(time.day)}.${two(time.month)}.${time.year} ${two(time.hour)}:${two(time.minute)}';
}

final class AndroidFoldersScreen extends StatefulWidget {
  const AndroidFoldersScreen(
      {super.key, required this.bookmarks, required this.importer});
  final AndroidFolderBookmarks bookmarks;
  final AndroidImportController importer;
  @override
  State<AndroidFoldersScreen> createState() => _AndroidFoldersScreenState();
}

final class _AndroidFoldersScreenState extends State<AndroidFoldersScreen> {
  late final Listenable changes =
      Listenable.merge([widget.bookmarks, widget.importer]);
  @override
  void initState() {
    super.initState();
    unawaited(_command(widget.importer.busy
        ? widget.bookmarks.initialize
        : widget.bookmarks.refreshAccess));
  }

  Future<void> _command(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Не удалось выполнить действие с папкой.')));
      }
    }
  }

  Future<void> _refresh(SavedAudioFolder folder, {bool restore = false}) async {
    if (restore) {
      await widget.importer.restoreFolderAccess(folder);
    } else {
      await widget.importer.refreshFolder(folder);
    }
    await widget.bookmarks.refreshAccess();
  }

  Future<void> _addFolder() async {
    await widget.importer.importFolder();
    await widget.bookmarks.refreshAccess();
  }

  Future<void> _forget(SavedAudioFolder folder) async {
    // A callback can outlive the frame that enabled it.
    if (widget.importer.busy) return;
    await widget.bookmarks.forget(folder.source);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: changes,
      builder: (context, _) {
        final store = widget.bookmarks;
        final importer = widget.importer;
        final blocked = importer.busy || !store.loaded;
        return Scaffold(
          appBar: AppBar(title: const Text('Папки'), actions: [
            IconButton(
                tooltip: 'Проверить доступ',
                onPressed: blocked ? null : () => _command(store.refreshAccess),
                icon: const Icon(Icons.refresh_rounded)),
            IconButton(
                tooltip: 'Добавить папку',
                onPressed: blocked ? null : () => _command(_addFolder),
                icon: const Icon(Icons.create_new_folder_outlined)),
          ]),
          body: SafeArea(
              top: false,
              child: Column(children: [
                if (importer.busy) ...[
                  const LinearProgressIndicator(),
                  if (importer.canCancel)
                    TextButton(
                        onPressed: () => _command(importer.cancel),
                        child: const Text('Остановить импорт')),
                ],
                if (importer.message != null)
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(importer.message!)),
                Expanded(
                    child: store.loadFailed
                        ? const Center(
                            child: Text(
                                'Не удалось открыть список папок. Существующая музыка остаётся доступной.'))
                        : !store.loaded
                            ? const Center(child: CircularProgressIndicator())
                            : store.folders.isEmpty
                                ? const Center(
                                    child: Padding(
                                        padding: EdgeInsets.all(24),
                                        child: Text(
                                            'Сохранённых папок нет. Добавьте папку с музыкой.',
                                            textAlign: TextAlign.center)))
                                : ListView.builder(
                                    itemCount: store.folders.length,
                                    itemBuilder: (context, index) {
                                      final folder = store.folders[index];
                                      final access = store.accessFor(folder);
                                      final time =
                                          folder.lastCompletedAt?.toLocal();
                                      return Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              16, 12, 16, 8),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(children: [
                                                  Expanded(
                                                      child: Text(
                                                          access?.name ??
                                                              folder
                                                                  .displayName,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: Theme.of(
                                                                  context)
                                                              .textTheme
                                                              .titleMedium)),
                                                  IconButton(
                                                      tooltip:
                                                          'Убрать из библиотеки',
                                                      onPressed: blocked
                                                          ? null
                                                          : () => _command(() =>
                                                              _forget(folder)),
                                                      icon: const Icon(Icons
                                                          .folder_off_outlined)),
                                                ]),
                                                Text(access == null
                                                    ? 'Доступ ещё не проверен'
                                                    : access.readable
                                                        ? 'Доступ есть'
                                                        : 'Нет доступа. Выберите эту папку заново.'),
                                                if (time != null)
                                                  Text(
                                                      'Последнее обновление: ${_timestamp(time)}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall),
                                                Wrap(spacing: 8, children: [
                                                  TextButton.icon(
                                                      onPressed: blocked
                                                          ? null
                                                          : () => _command(() =>
                                                              _refresh(folder)),
                                                      icon: const Icon(
                                                          Icons.sync_rounded),
                                                      label: const Text(
                                                          'Обновить')),
                                                  if (access?.readable == false)
                                                    TextButton.icon(
                                                        onPressed: blocked
                                                            ? null
                                                            : () => _command(
                                                                () => _refresh(
                                                                    folder,
                                                                    restore:
                                                                        true)),
                                                        icon: const Icon(Icons
                                                            .folder_open_rounded),
                                                        label: const Text(
                                                            'Разрешить доступ')),
                                                ]),
                                                const Divider(),
                                              ]));
                                    })),
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        '«Убрать из библиотеки» скрывает треки этой папки. Файлы и история сохраняются. Добавьте папку заново, чтобы вернуть её музыку.',
                        textAlign: TextAlign.center)),
              ])),
        );
      });
}
