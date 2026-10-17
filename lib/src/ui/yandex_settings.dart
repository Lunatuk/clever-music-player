import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../library_sync/yandex_connection_controller.dart';
import '../library_sync/yandex_library_protocol.dart';

class YandexSettings extends StatefulWidget {
  const YandexSettings({super.key, required this.controller, this.openHelp});
  final YandexConnectionController controller;
  final Future<void> Function()? openHelp;
  @override
  State<YandexSettings> createState() => _YandexSettingsState();
}

class _YandexSettingsState extends State<YandexSettings> {
  final _token = TextEditingController();
  bool _helpFailed = false;
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.initialize());
  }

  @override
  void didUpdateWidget(covariant YandexSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.cancel();
      _token.clear();
      unawaited(widget.controller.initialize());
    }
  }

  Future<void> _connect() async {
    final input = _token.text;
    _token.clear();
    await widget.controller.connect(input);
  }

  Future<void> _help() async {
    try {
      if (widget.openHelp != null) {
        await widget.openHelp!();
      } else if (!await launchUrl(Uri.parse('https://ym.marshal.dev/token/'),
          mode: LaunchMode.externalApplication)) {
        throw StateError('Browser unavailable');
      }
    } on Object {
      if (mounted) setState(() => _helpFailed = true);
    }
  }

  @override
  void dispose() {
    widget.controller.cancel();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final connection = widget.controller;
        final account = connection.account;
        final busy = connection.isBusy;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Подключи аккаунт, выбери «Мне нравится» и плейлисты. '
              'Сейчас доступна проверка их состава; скачивание появится следующим шагом.'),
          const SizedBox(height: 12),
          if (account == null) ...[
            ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: TextField(
                  key: const ValueKey('yandex-token'),
                  controller: _token,
                  obscureText: true,
                  enabled: !busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: const InputDecoration(
                      labelText: 'OAuth-токен или ссылка с токеном',
                      helperText:
                          'Можно использовать токен из своего загрузчика.',
                      helperMaxLines: 2),
                  onSubmitted: (_) {
                    if (!busy && _token.text.trim().isNotEmpty) {
                      unawaited(_connect());
                    }
                  },
                )),
            const SizedBox(height: 10),
            const Text(
                'Токен хранится в защищённом хранилище этого устройства.'),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, children: [
              ListenableBuilder(
                  listenable: _token,
                  builder: (context, _) => FilledButton.icon(
                      key: const ValueKey('yandex-connect'),
                      onPressed:
                          busy || _token.text.trim().isEmpty ? null : _connect,
                      icon: const Icon(Icons.link),
                      label: const Text('Подключить'))),
              TextButton(
                  onPressed: busy ? null : _help,
                  child: const Text('Как получить токен')),
              if (connection.failure == YandexConnectionFailure.storage ||
                  connection.failure == YandexConnectionFailure.stale)
                OutlinedButton(
                    onPressed: busy ? null : connection.disconnect,
                    child: const Text('Сбросить подключение')),
            ]),
          ] else ...[
            Text('Подключён: ${account.displayName ?? 'Аккаунт Яндекса'}',
                key: const ValueKey('yandex-account'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 8, children: [
              OutlinedButton.icon(
                  key: const ValueKey('yandex-catalogue'),
                  onPressed: busy ? null : connection.loadPlaylists,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Получить список плейлистов')),
              FilledButton.icon(
                  key: const ValueKey('yandex-check'),
                  onPressed: busy ? null : connection.checkCollections,
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('Проверить выбранные коллекции')),
              TextButton(
                  key: const ValueKey('yandex-disconnect'),
                  onPressed: busy ? null : connection.disconnect,
                  child: const Text('Выйти')),
            ]),
            const SizedBox(height: 8),
            const Text(
                'Выбор сохраняется. После перезапуска можно получить актуальный список плейлистов.'),
            const SizedBox(height: 8),
            // Bound widget construction for accounts with many playlists.
            SizedBox(
                height: (connection.choices.length * 76.0).clamp(76.0, 400.0),
                child: ListView.builder(
                  key: const ValueKey('yandex-collections'),
                  itemCount: connection.choices.length,
                  itemBuilder: (context, index) {
                    final choice = connection.choices[index];
                    final subtitle = [
                      if (choice.key.ownerId.isNotEmpty &&
                          choice.key.ownerId != account.identity.accountId)
                        'Сохранённый плейлист',
                      if (choice.itemCount != null)
                        choice.completedAt == null
                            ? 'Позиций в плейлисте: ${choice.itemCount}'
                            : 'Сохранённый состав: ${choice.itemCount} позиций',
                    ].join('\n');
                    return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: choice.isSelected,
                        onChanged: busy
                            ? null
                            : (value) => connection.select(choice.key, value!),
                        title: Text(choice.title,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: subtitle.isEmpty ? null : Text(subtitle),
                        controlAffinity: ListTileControlAffinity.leading);
                  },
                )),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
              key: const ValueKey('yandex-probe'),
              onPressed: busy ? null : connection.probeConnection,
              icon: const Icon(Icons.network_check),
              label: const Text('Проверить соединение')),
          const Text('Проверка доступности API выполняется без токена.'),
          if (busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(switch (connection.activity) {
                    YandexConnectionActivity.restoring =>
                      'Читаю сохранённое подключение…',
                    YandexConnectionActivity.connecting => switch (
                          connection.connectionStep) {
                        YandexConnectionStep.loadingPlaylists =>
                          'Получаю список плейлистов…',
                        YandexConnectionStep.savingCredential =>
                          'Сохраняю подключение…',
                        _ => 'Проверяю аккаунт…',
                      },
                    YandexConnectionActivity.probing =>
                      'Проверяю соединение без токена…',
                    YandexConnectionActivity.catalogue => 'Получаю плейлисты…',
                    YandexConnectionActivity.checking =>
                      'Проверяю состав коллекций…',
                    YandexConnectionActivity.selecting => 'Сохраняю выбор…',
                    YandexConnectionActivity.disconnecting =>
                      'Удаляю подключение…',
                    _ => 'Подожди…',
                  }),
                  if (connection.activity !=
                          YandexConnectionActivity.disconnecting &&
                      connection.activity != YandexConnectionActivity.selecting)
                    TextButton(
                        onPressed: connection.cancel,
                        child: const Text('Отмена')),
                ]),
          ],
          if (connection.failure != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                    _failureMessage(
                        connection.failure!, connection.failureStage),
                    key: const ValueKey('yandex-error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (connection.message != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(connection.message!,
                    key: const ValueKey('yandex-message'))),
          if (_helpFailed)
            const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SelectableText(
                    'Инструкция: https://ym.marshal.dev/token/')),
        ]);
      });
}

String _failureMessage(
        YandexConnectionFailure value, YandexRequestStage? stage) =>
    switch (value) {
      YandexConnectionFailure.invalidToken =>
        'Не удалось распознать токен. Вставь сам токен или ссылку с access_token.',
      YandexConnectionFailure.storage =>
        'Не удалось прочитать или сохранить подключение. Повтори действие; при необходимости сбрось подключение и войди заново.',
      YandexConnectionFailure.stale =>
        'Подключение изменилось. Открой настройки заново или подключи аккаунт повторно.',
      YandexConnectionFailure.unauthorized =>
        'Токен недействителен или доступ отозван. Подключи аккаунт заново.',
      YandexConnectionFailure.accessDenied =>
        'Яндекс не разрешил доступ к коллекции. Сохранённый состав остаётся доступен.',
      YandexConnectionFailure.network =>
        'Не удалось связаться с Яндексом. Проверь сеть и повтори действие.',
      YandexConnectionFailure.timeout => switch (stage) {
          YandexRequestStage.connecting =>
            'Не удалось установить соединение с API Яндекс Музыки вовремя. Проверь сеть и маршрут VPN, затем повтори действие.',
          YandexRequestStage.waitingForResponse =>
            'Соединение с Яндексом установлено, но ответ не получен вовремя. Повтори действие.',
          YandexRequestStage.receivingBody =>
            'Яндекс начал отвечать, но ответ не удалось получить полностью вовремя. Повтори действие.',
          YandexRequestStage.decoding =>
            'Превышено время обработки ответа Яндекса. Повтори действие.',
          _ =>
            'Превышено время обращения к Яндексу. Проверь соединение и повтори действие.',
        },
      YandexConnectionFailure.rateLimited =>
        'Яндекс временно ограничил запросы. Повтори проверку позже.',
      YandexConnectionFailure.incomplete =>
        'Получена не вся коллекция. Сохранённый состав оставлен прежним.',
      YandexConnectionFailure.changed =>
        'Коллекция изменилась во время чтения. Повтори проверку.',
      YandexConnectionFailure.cancelled => 'Операция отменена.',
      _ =>
        'Не удалось проверить ответ Яндекса. Сохранённые коллекции остаются доступны.',
    };
