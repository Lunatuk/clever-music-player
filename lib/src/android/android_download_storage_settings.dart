import 'package:flutter/material.dart';

import 'android_download_storage_controller.dart';

final class AndroidDownloadStorageSettings extends StatelessWidget {
  const AndroidDownloadStorageSettings({super.key, required this.controller});
  final AndroidDownloadStorageController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Хранилище загрузок',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text('Подготовка загрузки музыки на Android. '
                        'Сейчас можно проверить временное хранилище, выбрать '
                        'и проверить папку назначения. Скачивание музыки '
                        'на Android ещё готовится.'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                        onPressed:
                            controller.busy ? null : controller.checkWorkspace,
                        icon: const Icon(Icons.storage_outlined),
                        label: const Text('Проверить временное хранилище')),
                    if (controller.checkingWorkspace)
                      TextButton(
                          onPressed: controller.cancelCheck,
                          child: const Text('Остановить проверку')),
                    const SizedBox(height: 12),
                    Text(controller.folder == null
                        ? 'Папка загрузок не выбрана'
                        : 'Папка загрузок: ${controller.folderName}'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                          onPressed:
                              controller.busy ? null : controller.chooseFolder,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text('Выбрать папку загрузок')),
                      if (controller.folder != null) ...[
                        TextButton(
                            onPressed: controller.busy
                                ? null
                                : controller.inspectFolder,
                            child: const Text('Проверить доступ')),
                        TextButton(
                            onPressed: controller.busy
                                ? null
                                : controller.forgetFolder,
                            child: const Text('Сбросить выбор')),
                      ]
                    ]),
                    const SizedBox(height: 8),
                    const Text('Выбор папки не запускает сканирование. '
                        'Проверка записи создаёт небольшой тестовый файл, '
                        'проверяет содержимое и удаляет его.'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                        onPressed:
                            controller.busy || controller.access?.usable != true
                                ? null
                                : controller.checkDestination,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Проверить запись в папку')),
                    if (controller.checkingDestination)
                      TextButton(
                          onPressed: controller.cancelCheck,
                          child: const Text('Остановить проверку')),
                    if (controller.busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (controller.message != null) ...[
                      const SizedBox(height: 12),
                      Text(controller.message!,
                          key: const ValueKey(
                              'android-download-storage-status')),
                    ]
                  ]))));
}
