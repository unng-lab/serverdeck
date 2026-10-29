import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' show ThemePreference;

import '../profiles/profile_controller.dart';
import '../shell/error_view.dart';
import '../theme/brand_theme.dart';
import '../ui/deck_components.dart';
import '../ui/deck_page.dart';
import 'settings_form.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.controller, this.onAiAccess});
  final ProfileController controller;
  final VoidCallback? onAiAccess;
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _editFocus = FocusNode(debugLabel: 'Изменить настройки');
  int _tab = 0;
  bool _editing = false;
  @override
  void dispose() {
    _editFocus.dispose();
    super.dispose();
  }

  void _closeEditor() {
    setState(() => _editing = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_editing) _editFocus.requestFocus();
    });
  }

  Widget _row(
    String title,
    String value, {
    bool first = false,
    bool last = false,
  }) {
    final phone = MediaQuery.sizeOf(context).width <= 520;
    return Container(
      constraints: BoxConstraints(minHeight: phone ? 56 : 0),
      padding: EdgeInsets.only(
        top: first
            ? 0
            : phone
            ? 18
            : 16,
        bottom: last
            ? 0
            : phone
            ? 18
            : 16,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: deckColors(context)['border'])),
      ),
      child: LayoutBuilder(
        builder: (context, bounds) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: phone
                    ? BrandTypography.body.copyWith(height: 22 / 14)
                    : BrandTypography.table,
              ),
            ),
            SizedBox(width: phone ? 12 : 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: bounds.maxWidth * .58),
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: BrandTypography.body.copyWith(height: 20 / 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final model = widget.controller, settings = model.settings;
      if (_editing)
        return SettingsForm(model: model, asPage: true, onClose: _closeEditor);
      if (model.error case final code?)
        return ReadErrorView(
          code: code,
          onReadAgain: () => model.refresh().ignore(),
          onCheckService: () => model.bootstrap.retry().ignore(),
        );
      final actions = <Widget>[
        FilledButton(
          clipBehavior: Clip.none,
          focusNode: _editFocus,
          onPressed: settings == null
              ? null
              : () => setState(() => _editing = true),
          child: const Text('Изменить настройки'),
        ),
        OutlinedButton(
          clipBehavior: Clip.none,
          onPressed: widget.onAiAccess,
          child: const Text('ИИ-доступ'),
        ),
      ];
      return DeckPage(
        title: 'Настройки приложения',
        description: 'Параметры и доступные возможности',
        eyebrow: 'Настройки / Рабочее пространство',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DeckTabs(
              labels: const ['Внешний вид', 'Доступность', 'Приложение'],
              selected: _tab,
              onSelected: (value) => setState(() => _tab = value),
            ),
            const DeckTabsGap(),
            if (!model.loaded || settings == null)
              const DeckPanel(
                child: DeckStatus(label: 'Загрузка настроек', pending: true),
              )
            else
              DeckPanel(
                title: _tab == 0
                    ? 'Настройки и ограничения'
                    : _tab == 1
                    ? 'Доступность'
                    : 'Приложение',
                padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width <= 520 ? 16 : 18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_tab == 0)
                      _row('Тема', switch (settings.theme) {
                        ThemePreference.system => 'Системная',
                        ThemePreference.light => 'Светлая',
                        ThemePreference.dark => 'Тёмная',
                      }, first: true),
                    if (_tab != 2)
                      _row(
                        'Уменьшение анимации',
                        settings.reduceMotion ? 'Включено' : 'Выключено',
                        first: _tab == 1,
                        last: _tab == 1,
                      ),
                    if (_tab != 1) ...[
                      _row(
                        'Активный профиль',
                        model.selected == null
                            ? 'Не выбран'
                            : '${model.selected!.name} · ${model.selected!.address}:${model.selected!.port}',
                        first: _tab == 2,
                      ),
                      _row('Приватный экспорт', 'Недоступен'),
                      _row('Язык', 'Русский', last: true),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 20),
            DeckActions(children: actions),
          ],
        ),
      );
    },
  );
}
