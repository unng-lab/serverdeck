import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' show ThemePreference;

import '../profiles/profile_controller.dart';
import '../shell/error_view.dart';
import 'settings_form.dart';
import '../theme/motion.dart';

/// Current service-owned values; edits live in a separate RAM draft.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.controller});
  final ProfileController controller;
  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final error = controller.error;
    if (error != null) {
      return ReadErrorView(
        code: error,
        onReadAgain: () => controller.refresh().ignore(),
        onCheckService: () => controller.bootstrap.retry().ignore(),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!controller.loaded || settings == null)
            const Text('Загрузка настроек')
          else ...[
            Text(
              'Тема: ${switch (settings.theme) {
                ThemePreference.system => 'системная',
                ThemePreference.light => 'светлая',
                ThemePreference.dark => 'тёмная',
              }}',
            ),
            const SizedBox(height: 16),
            Text(
              'Уменьшение анимации: ${settings.reduceMotion ? 'включено' : 'выключено'}',
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => showMotionDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => SettingsForm(model: controller),
              ),
              child: const Text('Изменить настройки'),
            ),
          ],
          const SizedBox(height: 24),
          const Text('Экспорт приватных данных недоступен'),
        ],
      ),
    );
  }
}
