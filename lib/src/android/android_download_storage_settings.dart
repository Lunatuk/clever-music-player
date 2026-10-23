import 'package:flutter/material.dart';

import 'android_download_storage_controller.dart';

final class AndroidDownloadStorageSettings extends StatelessWidget {
  const AndroidDownloadStorageSettings(
      {super.key, required this.controller, this.locked = false});
  final AndroidDownloadStorageController controller;
  final bool locked;

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
                    Text(controller.canUseDestination
                        ? 'Выбери папку для скачивания. Она добавится в библиотеку без полного сканирования; загрузка начнётся по кнопке «Обновить библиотеку».'
                        : 'Подготовка загрузки музыки на Android. '
                            'Сейчас можно проверить временное хранилище, выбрать '
                            'и проверить папку назначения. Скачивание музыки '
                            'на Android ещё готовится.'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                        onPressed: controller.busy || locked
                            ? null
                            : controller.checkWorkspace,
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
                          onPressed: controller.busy || locked
                              ? null
                              : controller.chooseFolder,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text('Выбрать папку загрузок')),
                      if (controller.folder != null) ...[
                        if (controller.canUseDestination)
                          TextButton(
                              onPressed: controller.busy || locked
                                  ? null
                                  : controller.useDestination,
                              child:
                                  const Text('Использовать выбранную папку')),
                        TextButton(
                            onPressed: controller.busy || locked
                                ? null
                                : controller.inspectFolder,
                            child: const Text('Проверить доступ')),
                        TextButton(
                            onPressed: controller.busy || locked
                                ? null
                                : controller.forgetFolder,
                            child: const Text('Сбросить выбор')),
                      ]
                    ]),
                    const SizedBox(height: 8),
                    const Text('Выбор папки не запускает сканирование. '
                        'Проверка создаёт небольшие тестовые файлы, проверяет '
                        'запись и восстановление после прерывания, затем удаляет их.'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                        onPressed: controller.busy ||
                                locked ||
                                controller.access?.usable != true
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
