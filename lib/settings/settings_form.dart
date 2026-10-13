import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serverdeck_protocol/models.dart' hide ReadinessView;

import '../profiles/profile_controller.dart';
import '../profiles/mutation_controller.dart';
import '../profiles/mutation_status.dart';
import '../shell/readiness_view.dart';
import '../shell/error_view.dart';
import 'settings_controller.dart';
import '../theme/motion.dart';

class _CloseSettings extends Intent {
  const _CloseSettings();
}

class SettingsForm extends StatefulWidget {
  const SettingsForm({super.key, required this.model});
  final ProfileController model;
  @override
  State<SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<SettingsForm> {
  late final SettingsController draft;
  @override
  void initState() {
    super.initState();
    draft = SettingsController(model: widget.model);
  }

  void _close() => Navigator.of(context).maybePop();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      draft,
      draft.mutation,
      widget.model,
      widget.model.bootstrap,
    ]),
    builder: (context, _) {
      final ready = widget.model.bootstrap.state == ReadinessState.ready;
      final idle = draft.mutation.state == MutationPresentation.idle;
      final enabled = draft.editable;
      return Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): _CloseSettings(),
        },
        child: Actions(
          actions: {
            _CloseSettings: CallbackAction<_CloseSettings>(
              onInvoke: (_) {
                _close();
                return null;
              },
            ),
          },
          child: Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (ready && draft.initialized) ...[
                      Text(
                        'Изменение настроек',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      MotionDropdown<ThemePreference>(
                        key: ValueKey('theme-${draft.revision}'),
                        initialValue: draft.theme,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Тема'),
                        items: const [
                          DropdownMenuItem(
                            value: ThemePreference.system,
                            child: Text('Системная'),
                          ),
                          DropdownMenuItem(
                            value: ThemePreference.light,
                            child: Text('Светлая'),
                          ),
                          DropdownMenuItem(
                            value: ThemePreference.dark,
                            child: Text('Тёмная'),
                          ),
                        ],
                        onChanged: enabled
                            ? (value) => draft.edit(theme: value)
                            : null,
                      ),
                      CheckboxListTile(
                        title: const Text('Уменьшение анимации'),
                        value: draft.reduceMotion,
                        onChanged: enabled
                            ? (value) => draft.edit(reduceMotion: value)
                            : null,
                        contentPadding: EdgeInsets.zero,
                      ),
                      MotionDropdown<String>(
                        changes: widget.model.bootstrap,
                        available: () =>
                            widget.model.bootstrap.state ==
                            ReadinessState.ready,
                        key: ValueKey('selection-${draft.revision}'),
                        initialValue: draft.selectedProfileId ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Активный профиль',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Не выбран'),
                          ),
                          for (final profile in draft.profiles)
                            DropdownMenuItem(
                              value: profile.id,
                              child: Text(
                                profile.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: enabled
                            ? (value) =>
                                  draft.select(value == '' ? null : value)
                            : null,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Выбор профиля не подключает сервер и не подтверждает SSH-доверие',
                      ),
                      if (draft.readError case final error?) Text(error),
                      MutationStatus(
                        controller: draft.mutation,
                        settings: true,
                        onReload: () => draft.reload().ignore(),
                      ),
                      if (!idle)
                        const Text(
                          'Закрытие окна не отменяет уже отправленное сохранение',
                        ),
                    ] else if (ready)
                      if (widget.model.error case final code?)
                        ReadErrorView(
                          code: code,
                          onReadAgain: () => widget.model.refresh().ignore(),
                          onCheckService: () =>
                              widget.model.bootstrap.retry().ignore(),
                        )
                      else
                        const Text('Загрузка настроек')
                    else
                      ReadinessView(
                        state: widget.model.bootstrap.state,
                        reason: widget.model.bootstrap.reason,
                        retryInProgress: widget.model.bootstrap.retryInProgress,
                        onRetry: () => widget.model.bootstrap.retry().ignore(),
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        if (ready && draft.initialized)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(48, 48),
                            ),
                            onPressed: enabled && widget.model.loaded
                                ? () => draft.save().ignore()
                                : null,
                            child: const Text('Сохранить настройки'),
                          ),
                        OutlinedButton(
                          autofocus: true,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: _close,
                          child: Text(idle ? 'Отмена' : 'Закрыть'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }
}
