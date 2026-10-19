import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/models/download_job.dart';
import '../library_sync/yandex_download_runner.dart';
import '../library_sync/yandex_library_update_controller.dart';

class YandexLibraryUpdateSettings extends StatefulWidget {
  const YandexLibraryUpdateSettings({super.key, required this.controller});
  final YandexLibraryUpdateController controller;
  @override
  State<YandexLibraryUpdateSettings> createState() =>
      _YandexLibraryUpdateSettingsState();
}

class _YandexLibraryUpdateSettingsState
    extends State<YandexLibraryUpdateSettings> {
  bool _retryFailed = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable:
          Listenable.merge([widget.controller, widget.controller.connection]),
      builder: (context, _) {
        final c = widget.controller;
        if (!c.supported) {
          return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                  'Загрузка музыки пока доступна на Windows. На этом устройстве можно подключить аккаунт и проверить состав коллекций.'));
        }
        final busy = c.isBusy || c.connection.isBusy;
        final progress = c.progress;
        final bytes = progress?.bytes;
        final total = bytes?.totalBytes;
        final fraction = total != null && total > 0
            ? (bytes!.receivedBytes / total).clamp(0.0, 1.0)
            : null;
        return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Обновление библиотеки',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _Option<int>(
                  key: const ValueKey('yandex-update-folder'),
                  value: c.folderId,
                  label: 'Папка для загрузок',
                  items: c.folders
                      .map((f) => DropdownMenuItem(
                          value: f.id,
                          child: Text(f.displayName ?? f.path,
                              maxLines: 1, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: busy
                      ? null
                      : (id) {
                          if (id != null) unawaited(c.configure(folderId: id));
                        }),
              if (c.folders.isEmpty)
                const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child:
                        Text('Сначала добавь папку в настройках библиотеки.')),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, constraints) {
                final narrow = constraints.maxWidth < 520 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                final quality = _Option<YandexUpdateQuality>(
                    key: const ValueKey('yandex-update-quality'),
                    value: c.quality,
                    label: 'Качество',
                    items: const [
                      DropdownMenuItem(
                          value: YandexUpdateQuality.mp3,
                          child: Text('MP3 · до 320 кбит/с')),
                      DropdownMenuItem(
                          value: YandexUpdateQuality.flac,
                          child: Text('FLAC · без потерь')),
                      DropdownMenuItem(
                          value: YandexUpdateQuality.m4a,
                          child: Text('M4A · AAC до 256 кбит/с'))
                    ],
                    onChanged: busy
                        ? null
                        : (value) {
                            if (value != null) {
                              unawaited(c.configure(quality: value));
                            }
                          });
                final limit = _Option<int>(
                    key: const ValueKey('yandex-update-limit'),
                    value: c.limit,
                    label: 'За один запуск',
                    items: YandexLibraryUpdateController.limits
                        .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(value ==
                                    YandexLibraryUpdateController.limits.last
                                ? 'Все задания'
                                : value == 3
                                    ? '3 трека'
                                    : '$value треков')))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) {
                            if (value != null) {
                              unawaited(c.configure(limit: value));
                            }
                          });
                return narrow
                    ? Column(
                        children: [quality, const SizedBox(height: 12), limit])
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Expanded(child: quality),
                            const SizedBox(width: 12),
                            Expanded(child: limit)
                          ]);
              }),
              const SizedBox(height: 8),
              const Text(
                  'Загрузятся новые треки из «Мне нравится» и выбранных плейлистов. MP3 и M4A — в лучшем доступном качестве; битрейт может быть ниже указанного максимума. FLAC — только без потерь. Доступность зависит от трека и подписки.'),
              CheckboxListTile(
                  key: const ValueKey('yandex-update-retry'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title:
                      const Text('Повторить неудачные и отменённые загрузки'),
                  value: _retryFailed,
                  onChanged: busy
                      ? null
                      : (value) => setState(() => _retryFailed = value!)),
              Wrap(spacing: 12, runSpacing: 8, children: [
                FilledButton.icon(
                    key: const ValueKey('yandex-update-start'),
                    onPressed: busy ||
                            !c.initialized ||
                            c.folderId == null ||
                            c.connection.account == null ||
                            !c.connection.choices
                                .any((choice) => choice.isSelected)
                        ? null
                        : () => c.start(retryFailed: _retryFailed),
                    icon: const Icon(Icons.sync),
                    label: const Text('Обновить библиотеку')),
                if (c.isBusy)
                  OutlinedButton.icon(
                      key: const ValueKey('yandex-update-cancel'),
                      onPressed: c.cancel,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Остановить обновление')),
              ]),
              if (c.isBusy) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                    value:
                        c.stage == YandexUpdateStage.running ? fraction : null),
                const SizedBox(height: 8),
                Text(_stage(c)),
                if (c.stage == YandexUpdateStage.running && progress != null)
                  Text(
                      'Добавлено: ${progress.completed}. Обрабатываю: ${progress.started}. Запланировано треков: ${c.planned}.'),
              ],
              if (c.message != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(c.message!,
                        key: const ValueKey('yandex-update-message'))),
              if (c.failure != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_failure(c),
                        key: const ValueKey('yandex-update-error'))),
              if (c.result != null && c.failure != null)
                Text('Добавлено треков: ${c.result!.completed}.'),
              if (!c.isBusy && c.needsAction > 0)
                Text(
                    'Требуют отдельного повтора: ${c.needsAction}. Для неудачных и отменённых заданий включи повтор выше.'),
            ]));
      });
}

class _Option<T> extends StatelessWidget {
  const _Option(
      {super.key,
      required this.value,
      required this.label,
      required this.items,
      required this.onChanged});
  final T? value;
  final String label;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  @override
  Widget build(BuildContext context) => InputDecorator(
      isEmpty: value == null,
      decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: const OutlineInputBorder(),
          enabled: onChanged != null),
      child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              isDense: true,
              hint: const Text('Выбрать'),
              items: items,
              onChanged: onChanged)));
}

String _stage(YandexLibraryUpdateController c) => switch (c.stage) {
      YandexUpdateStage.loading => 'Читаю настройки загрузки…',
      YandexUpdateStage.saving => 'Сохраняю настройки…',
      YandexUpdateStage.refreshing =>
        'Получаю свежий состав выбранных коллекций…',
      YandexUpdateStage.checkingFiles =>
        'Проверяю скачанные файлы: ${c.checked} из ${c.toCheck}…',
      YandexUpdateStage.planning => 'Составляю список новых треков…',
      YandexUpdateStage.running => switch (c.progress?.stage) {
          YandexDownloadRunStage.authenticating => 'Проверяю подключение…',
          YandexDownloadRunStage.preparing => 'Подготавливаю загрузку…',
          YandexDownloadRunStage.recovering =>
            'Восстанавливаю незавершённое задание…',
          YandexDownloadRunStage.processing =>
            'Записываю теги и обложку, проверяю трек…',
          YandexDownloadRunStage.finished => 'Завершаю обновление…',
          _ => 'Скачиваю музыку и обложку…',
        },
      _ => 'Подожди…',
    };
String _failure(YandexLibraryUpdateController c) => switch (c.failure) {
      YandexUpdateFailure.unsupported =>
        'Загрузка на этом устройстве пока недоступна.',
      YandexUpdateFailure.noAccount => 'Сначала подключи аккаунт Яндекса.',
      YandexUpdateFailure.noCollections =>
        'Выбери «Мне нравится» или хотя бы один плейлист.',
      YandexUpdateFailure.destination =>
        'Выбери доступную папку для загрузок. Папка могла быть отключена или удалена из библиотеки.',
      YandexUpdateFailure.stale =>
        'Подключение, выбор коллекций или папка изменились. Повтори обновление.',
      YandexUpdateFailure.fileAccess =>
        'Не удалось прочитать ранее скачанный файл. Проверь доступ к папке и повтори обновление.',
      YandexUpdateFailure.connection =>
        'Не удалось получить свежий состав коллекций. Проверь подключение Яндекса выше и повтори обновление.',
      YandexUpdateFailure.cancelled =>
        'Обновление остановлено. Уже добавленные треки сохранены.',
      YandexUpdateFailure.storage =>
        'Не удалось прочитать или сохранить данные обновления. Повтори действие.',
      YandexUpdateFailure.download => c.result?.cleanupFailed == true
          ? 'Обновление остановлено: не удалось очистить временные файлы. Проверь доступ к диску и повтори действие.'
          : switch (c.result?.jobFailure) {
              DownloadFailure.unavailable =>
                'Яндекс не выдал трек в выбранном формате или качестве. Для FLAC попробуй MP3 или M4A; конвертация в FLAC не улучшит исходное качество.',
              DownloadFailure.noSpace =>
                'Недостаточно места или рабочего резерва для загрузки. Освободи место и повтори действие.',
              DownloadFailure.authorization ||
              DownloadFailure.accountChanged =>
                'Подключение Яндекса изменилось или токен больше не действует. Подключись заново.',
              DownloadFailure.invalidMedia =>
                'Скачанный файл не прошёл проверку. Он не добавлен в библиотеку.',
              _ => switch (c.result?.failure) {
                  YandexDownloadRunFailure.credential ||
                  YandexDownloadRunFailure.authorization =>
                    'Проверь токен и подключи аккаунт заново.',
                  YandexDownloadRunFailure.network =>
                    'Не удалось завершить загрузку из-за сетевой ошибки. Повтори действие позже.',
                  _ =>
                    'Не удалось завершить загрузку. Проверь медиапомощник в диагностике и доступ к папке.',
                },
            },
      _ => 'Не удалось обновить библиотеку.',
    };
