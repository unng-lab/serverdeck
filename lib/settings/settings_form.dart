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
import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';

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
  bool _readingError = false;
  @override
  void initState() {
    super.initState();
    draft = SettingsController(model: widget.model);
  }

  void _close() => Navigator.of(context).maybePop();

  Future<void> _readAgain() async {
    if (_readingError ||
        draft.reloading ||
        (draft.mutation.busy &&
            draft.mutation.state == MutationPresentation.committed))
      return;
    final model = widget.model;
    setState(() => _readingError = true);
    try {
      await model.refresh();
    } finally {
      if (mounted && identical(widget.model, model)) {
        setState(() => _readingError = false);
      }
    }
  }

  void _reload() {
    if (_readingError) return;
    draft.reload().ignore();
  }

  void _readCommitted() {
    if (_readingError || draft.reloading) return;
    draft.mutation.refreshCommitted().ignore();
  }

  void _save() {
    if (_readingError) return;
    draft.save().ignore();
  }

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
      final enabled = draft.editable && !_readingError;
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
          child: DeckDialogLayout(
            title: ready
                ? 'Изменение настроек'
                : 'Локальное пространство недоступно',
            actions: [
              if (ready && draft.initialized)
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: enabled && widget.model.loaded ? _save : null,
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
            child: !ready
                ? ReadinessView(
                    state: widget.model.bootstrap.state,
                    reason: widget.model.bootstrap.reason,
                    retryInProgress: widget.model.bootstrap.retryInProgress,
                    onRetry: () => widget.model.bootstrap.retry().ignore(),
                  )
                : !draft.initialized
                ? widget.model.error != null
                      ? ReadErrorView(
                          code: widget.model.error!,
                          reading: _readingError,
                          pendingLabel: 'Чтение актуальных настроек',
                          onReadAgain: () => _readAgain().ignore(),
                          onCheckService: () =>
                              widget.model.bootstrap.retry().ignore(),
                        )
                      : const DeckStatus(
                          label: 'Загрузка настроек',
                          pending: true,
                        )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DeckFormSection(
                        title: 'Оформление',
                        description: 'Выбранные значения остаются черновиком до сохранения.',
                        children: [
                          MotionDropdown<ThemePreference>(
                            key: ValueKey('theme-${draft.revision}'),
                            initialValue: draft.theme,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Тема',
                            ),
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
                            title: const DeckFocusLabel(
                              child: Text('Уменьшение анимации'),
                            ),
                            value: draft.reduceMotion,
                            onChanged: enabled
                                ? (value) => draft.edit(reduceMotion: value)
                                : null,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: BrandSpacing.space24),
                      DeckFormSection(
                        title: 'Рабочий контекст',
                        children: [
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
                                  child: Text(profile.name),
                                ),
                            ],
                            onChanged: enabled
                                ? (value) =>
                                      draft.select(value == '' ? null : value)
                                : null,
                          ),
                          const DeckNotice(
                            message: 'Выбор профиля не подключает сервер и не подтверждает SSH-доверие',
                            tone: DeckTone.neutral,
                          ),
                        ],
                      ),
                      if (widget.model.error case final code?) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        ReadErrorView(
                          code: code,
                          reading: _readingError || draft.reloading,
                          pendingLabel: 'Чтение актуальных настроек',
                          onReadAgain: () => _readAgain().ignore(),
                          onCheckService: () =>
                              widget.model.bootstrap.retry().ignore(),
                        ),
                      ],
                      if (_readingError && widget.model.error == null) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        const DeckStatus(
                          label: 'Чтение актуальных настроек',
                          pending: true,
                        ),
                      ],
                      if (draft.readError case final error?) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        DeckNotice(message: error, tone: DeckTone.error),
                      ],
                      if (!idle) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        MutationStatus(
                          controller: draft.mutation,
                          settings: true,
                          reloading: draft.reloading,
                          readPending: _readingError,
                          onReadCommitted: _readCommitted,
                          onReload: _reload,
                        ),
                        const SizedBox(height: BrandSpacing.space12),
                        const Text(
                          'Закрытие окна не отменяет уже отправленное сохранение',
                        ),
                      ],
                    ],
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
