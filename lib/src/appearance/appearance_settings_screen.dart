import 'dart:async';
import 'package:flutter/material.dart';
import 'appearance_controller.dart';
import 'appearance_settings.dart';
import 'appearance_theme.dart';

final class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key, required this.controller});
  final AppearanceController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final value = controller.value;
        final brightness = value.mode == AppearanceMode.system
            ? MediaQuery.platformBrightnessOf(context)
            : value.mode == AppearanceMode.light
                ? Brightness.light
                : Brightness.dark;
        return Theme(
            data: createAppearanceTheme(value, brightness),
            child: Builder(
                builder: (context) => Scaffold(
                    appBar: AppBar(title: const Text('Внешний вид')),
                    body: SafeArea(
                        child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 640),
                                child: !controller.initialized
                                    ? const Center(
                                        child: CircularProgressIndicator())
                                    : ListView(
                                        padding: const EdgeInsets.all(20),
                                        children: [
                                            const Text(
                                                'Изменения применяются сразу и сохраняются на этом устройстве.'),
                                            const SizedBox(height: 20),
                                            DropdownButtonFormField<
                                                    AppearanceMode>(
                                                key: ValueKey(
                                                    'appearance-mode-${value.mode.name}'),
                                                initialValue: value.mode,
                                                isExpanded: true,
                                                decoration:
                                                    const InputDecoration(
                                                        labelText: 'Тема',
                                                        floatingLabelBehavior:
                                                            FloatingLabelBehavior
                                                                .always),
                                                items: [
                                                  for (final e in const {
                                                    AppearanceMode.system:
                                                        'Как в системе',
                                                    AppearanceMode.light:
                                                        'Светлая',
                                                    AppearanceMode.dark:
                                                        'Тёмная'
                                                  }.entries)
                                                    DropdownMenuItem(
                                                        value: e.key,
                                                        child: Text(e.value))
                                                ],
                                                onChanged: (v) {
                                                  if (v != null) {
                                                    unawaited(controller.update(
                                                        value.copyWith(
                                                            mode: v)));
                                                  }
                                                }),
                                            const SizedBox(height: 20),
                                            Text('Акцентный цвет',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium),
                                            const SizedBox(height: 8),
                                            Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  for (final e in const {
                                                    0xffcc33: 'Жёлтый',
                                                    0xff7474: 'Коралловый',
                                                    0xb4a2ff: 'Лавандовый',
                                                    0x64b5f6: 'Голубой',
                                                    0x70d9b4: 'Мятный'
                                                  }.entries)
                                                    ChoiceChip(
                                                        key: ValueKey(
                                                            'accent-${e.key}'),
                                                        avatar: CircleAvatar(
                                                            backgroundColor:
                                                                Color(
                                                                    0xff000000 |
                                                                        e.key)),
                                                        label: Text(e.value),
                                                        selected:
                                                            value.accentRgb ==
                                                                e.key,
                                                        onSelected: (_) => unawaited(
                                                            controller.update(
                                                                value.copyWith(
                                                                    accentRgb: e
                                                                        .key)))),
                                                  ActionChip(
                                                      label: const Text(
                                                          'Свой цвет'),
                                                      avatar: const Icon(Icons
                                                          .palette_outlined),
                                                      onPressed: () =>
                                                          _customColor(
                                                              context)),
                                                ]),
                                            const SizedBox(height: 20),
                                            DropdownButtonFormField<
                                                    AppearanceMotion>(
                                                key: ValueKey(
                                                    'appearance-motion-${value.motion.name}'),
                                                initialValue: value.motion,
                                                isExpanded: true,
                                                decoration:
                                                    const InputDecoration(
                                                        labelText: 'Анимации',
                                                        floatingLabelBehavior:
                                                            FloatingLabelBehavior
                                                                .always),
                                                items: [
                                                  for (final e in const {
                                                    AppearanceMotion.off:
                                                        'Выключены',
                                                    AppearanceMotion.slow:
                                                        'Плавные',
                                                    AppearanceMotion.normal:
                                                        'Обычные',
                                                    AppearanceMotion.fast:
                                                        'Быстрые'
                                                  }.entries)
                                                    DropdownMenuItem(
                                                        value: e.key,
                                                        child: Text(e.value))
                                                ],
                                                onChanged: (v) {
                                                  if (v != null) {
                                                    unawaited(controller.update(
                                                        value.copyWith(
                                                            motion: v)));
                                                  }
                                                }),
                                            const SizedBox(height: 8),
                                            const Text(
                                                'Системное отключение анимаций имеет приоритет. Параметр управляет переходами новых экранов и элементов, не плавным переходом звука.'),
                                            SwitchListTile(
                                                contentPadding: EdgeInsets.zero,
                                                title: const Text(
                                                    'Компактные строки'),
                                                value: value.compact,
                                                onChanged: (v) => unawaited(
                                                    controller.update(
                                                        value.copyWith(
                                                            compact: v)))),
                                            const SizedBox(height: 8),
                                            Text(
                                                'Скругление обложек: ${value.coverRadius}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium),
                                            Slider(
                                                key: const ValueKey(
                                                    'appearance-radius'),
                                                min: 0,
                                                max: 24,
                                                divisions: 6,
                                                value: value.coverRadius
                                                    .toDouble(),
                                                label: '${value.coverRadius}',
                                                onChanged: (v) => unawaited(
                                                    controller.update(
                                                        value.copyWith(
                                                            coverRadius:
                                                                v.round())))),
                                            const _MotionSample(),
                                            const SizedBox(height: 12),
                                            if (controller.failure != null) ...[
                                              Text(controller.failure ==
                                                      AppearanceFailure.load
                                                  ? 'Не удалось загрузить оформление.'
                                                  : 'Не удалось сохранить оформление. Оно действует до закрытия приложения.'),
                                              TextButton(
                                                  onPressed: () => unawaited(
                                                      controller.retry()),
                                                  child:
                                                      const Text('Повторить')),
                                            ] else
                                              Text(controller.isSaving
                                                  ? 'Сохраняем…'
                                                  : 'Настройки сохранены.'),
                                            const SizedBox(height: 12),
                                            OutlinedButton(
                                                onPressed: () => unawaited(
                                                    controller.reset()),
                                                child: const Text(
                                                    'Вернуть исходное оформление')),
                                          ])))))));
      });

  Future<void> _customColor(BuildContext context) async {
    final rgb = await showDialog<int>(
        context: context,
        builder: (_) => Theme(
            data: Theme.of(context),
            child: _ColorDialog(initial: controller.value.accentRgb)));
    if (rgb != null) {
      await controller.update(controller.value.copyWith(accentRgb: rgb));
    }
  }
}

final class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.initial});
  final int initial;
  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

final class _ColorDialogState extends State<_ColorDialog> {
  late final input = TextEditingController(
      text: widget.initial.toRadixString(16).padLeft(6, '0').toUpperCase());
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          scrollable: true,
          title: const Text('Свой акцентный цвет'),
          content: Form(
              key: form,
              child: TextFormField(
                  controller: input,
                  autofocus: true,
                  maxLength: 7,
                  decoration: const InputDecoration(
                      labelText: 'HEX', hintText: '#FFCC33'),
                  validator: (v) =>
                      RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(v?.trim() ?? '')
                          ? null
                          : 'Нужно 6 символов: 0–9, A–F')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () {
                  if (form.currentState!.validate()) {
                    Navigator.pop(
                        context,
                        int.parse(input.text.trim().replaceFirst('#', ''),
                            radix: 16));
                  }
                },
                child: const Text('Применить'))
          ]);
}

final class _MotionSample extends StatefulWidget {
  const _MotionSample();
  @override
  State<_MotionSample> createState() => _MotionSampleState();
}

final class _MotionSampleState extends State<_MotionSample> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final tokens = AppearanceTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextButton(
          onPressed: () => setState(() => expanded = !expanded),
          child: const Text('Проверить анимацию')),
      AnimatedContainer(
          key: const ValueKey('appearance-motion-sample'),
          duration: tokens.duration(context, 320),
          curve: Curves.easeInOutCubic,
          width: expanded ? 240 : 90,
          height: 32,
          decoration: BoxDecoration(
              color: tokens.accent,
              borderRadius: BorderRadius.circular(tokens.coverRadius))),
    ]);
  }
}
