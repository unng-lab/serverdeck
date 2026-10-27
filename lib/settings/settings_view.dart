import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' show ThemePreference;

import '../profiles/profile_controller.dart';
import '../shell/error_view.dart';
import 'settings_form.dart';
import '../theme/motion.dart';
import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';

/// Current service-owned values; edits live in a separate RAM draft.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.controller});
  final ProfileController controller;
  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final selected = controller.selected;
    final error = controller.error;
    if (error != null) {
      return ReadErrorView(
        code: error,
        onReadAgain: () => controller.refresh().ignore(),
        onCheckService: () => controller.bootstrap.retry().ignore(),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: BrandSpacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!controller.loaded || settings == null)
            const DeckStatus(label: 'Загрузка настроек', pending: true)
          else ...[
            DeckSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DeckSectionHeader(
                    title: 'Оформление и рабочий контекст',
                    description: 'Текущие настройки локального пространства. Изменения сначала открываются в отдельной форме.',
                  ),
                  const SizedBox(height: BrandSpacing.space16),
                  Text(
                    'Тема: ${switch (settings.theme) {
                      ThemePreference.system => 'системная',
                      ThemePreference.light => 'светлая',
                      ThemePreference.dark => 'тёмная',
                    }}',
                  ),
                  const SizedBox(height: BrandSpacing.space12),
                  Text(
                    'Уменьшение анимации: ${settings.reduceMotion ? 'включено' : 'выключено'}',
                  ),
                  const SizedBox(height: BrandSpacing.space12),
                  DeckKeyValue(
                    label: 'Активный профиль',
                    value: selected != null
                        ? '${selected.name} · ${selected.address.contains(':') ? '[${selected.address}]' : selected.address}:${selected.port}'
                        : 'Не выбран',
                  ),
                  const SizedBox(height: BrandSpacing.space16),
                  DeckActions(
                    children: [
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () => showMotionDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => SettingsForm(model: controller),
                        ),
                        child: const Text('Изменить настройки'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: BrandSpacing.space24),
          const DeckNotice(
            message: 'Экспорт приватных данных недоступен',
            nextStep: 'В этой версии доступно изменение оформления и активного профиля через форму настроек.',
            tone: DeckTone.neutral,
          ),
        ],
      ),
    );
  }
}
