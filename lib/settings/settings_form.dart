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
import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';
import '../ui/deck_icon.dart';
import '../ui/deck_components.dart';
import '../ui/deck_page.dart';
import '../ui/deck_control_target.dart';
import '../ui/deck_input_border.dart';

class _CloseSettings extends Intent {
  const _CloseSettings();
}

class SettingsForm extends StatefulWidget {
  const SettingsForm({
    super.key,
    required this.model,
    this.asPage = false,
    this.onClose,
  });
  final ProfileController model;
  final bool asPage;
  final VoidCallback? onClose;
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

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

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

  Widget _labelField(String label, Widget child, {bool required = false}) =>
      DeckHitOverflow(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Text.rich(
                TextSpan(
                  text: label,
                  children: [
                    if (required)
                      TextSpan(
                        text: ' *',
                        style: TextStyle(color: deckColors(context)['accent']),
                      ),
                  ],
                ),
                style: BrandTypography.caption.copyWith(
                  height: 20 / 12,
                  fontFamily: BrandAssets.semiboldFamily,
                  fontWeight: BrandTypography.semiboldWeight,
                  fontVariations: BrandTypography.semiboldVariations,
                ),
              ),
            ),
            const SizedBox(height: 7),
            DeckControlTarget(
              visibleHeight: MediaQuery.sizeOf(context).width <= 520 ? 44 : 42,
              child: Semantics(
                label: label,
                isRequired: required,
                child: child,
              ),
            ),
          ],
        ),
      );

  Widget _pageFields(bool enabled) {
    final decoration = deckFormDecoration(context);
    final fields = [
      _labelField(
        'Тема',
        MotionDropdown<ThemePreference>(
          key: ValueKey('page-theme-${draft.revision}'),
          initialValue: draft.theme,
          changes: widget.model.bootstrap,
          available: () => widget.model.bootstrap.state == ReadinessState.ready,
          isExpanded: true,
          decoration: decoration,
          items: [
            DropdownMenuItem(
              value: ThemePreference.system,
              child: Text('Системная', style: deckFormTextStyle(context)),
            ),
            DropdownMenuItem(
              value: ThemePreference.light,
              child: Text('Светлая', style: deckFormTextStyle(context)),
            ),
            DropdownMenuItem(
              value: ThemePreference.dark,
              child: Text('Тёмная', style: deckFormTextStyle(context)),
            ),
          ],
          onChanged: enabled ? (value) => draft.edit(theme: value) : null,
        ),
        required: true,
      ),
      _labelField(
        'Уменьшение анимации',
        MotionDropdown<bool>(
          key: ValueKey('page-motion-${draft.revision}'),
          initialValue: draft.reduceMotion,
          changes: widget.model.bootstrap,
          available: () => widget.model.bootstrap.state == ReadinessState.ready,
          isExpanded: true,
          decoration: decoration,
          items: [
            DropdownMenuItem(
              value: false,
              child: Text('Выключено', style: deckFormTextStyle(context)),
            ),
            DropdownMenuItem(
              value: true,
              child: Text('Включено', style: deckFormTextStyle(context)),
            ),
          ],
          onChanged: enabled
              ? (value) => draft.edit(reduceMotion: value)
              : null,
        ),
        required: true,
      ),
      _labelField(
        'Активный профиль',
        MotionDropdown<String>(
          key: ValueKey('page-selection-${draft.revision}'),
          initialValue: draft.selectedProfileId ?? '',
          changes: widget.model.bootstrap,
          available: () => widget.model.bootstrap.state == ReadinessState.ready,
          isExpanded: true,
          decoration: decoration,
          items: [
            DropdownMenuItem(
              value: '',
              child: Text('Не выбран', style: deckFormTextStyle(context)),
            ),
            for (final profile in draft.profiles)
              DropdownMenuItem(
                value: profile.id,
                child: Text(profile.name, style: deckFormTextStyle(context)),
              ),
          ],
          onChanged: enabled
              ? (value) => draft.select(value == '' ? null : value)
              : null,
        ),
      ),
      _labelField(
        'Выбор профиля',
        Semantics(
          readOnly: true,
          child: TextFormField(
            key: const ValueKey('settings-profile-selection-note'),
            initialValue: 'Без подключения и подтверждения SSH-доверия',
            readOnly: true,
            maxLines: MediaQuery.textScalerOf(context).scale(14) > 14
                ? null
                : 1,
            decoration: decoration,
            style: deckFormTextStyle(context),
          ),
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Параметры',
          style: BrandTypography.body.copyWith(
            height: 22 / 14,
            fontFamily: BrandAssets.semiboldFamily,
            fontWeight: BrandTypography.semiboldWeight,
            fontVariations: BrandTypography.semiboldVariations,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Проверьте выбранную цель и значения полей.',
          style: BrandTypography.caption.copyWith(
            height: 20 / 12,
            color: deckColors(context)['muted'],
          ),
        ),
        SizedBox(height: MediaQuery.sizeOf(context).width <= 520 ? 20 : 18),
        DeckHitOverflow(
          child: LayoutBuilder(
            builder: (context, bounds) {
              final phone = MediaQuery.sizeOf(context).width <= 520;
              final columns =
                  !phone && MediaQuery.textScalerOf(context).scale(14) < 22;
              final width = columns
                  ? (bounds.maxWidth - 14) / 2
                  : bounds.maxWidth;
              return Wrap(
                spacing: 14,
                runSpacing: phone ? 20 : 18,
                children: [
                  for (final field in fields)
                    DeckHitOverflow(
                      child: SizedBox(width: width, child: field),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _layout({
    required String title,
    required Widget child,
    List<Widget> actions = const [],
  }) {
    if (!widget.asPage)
      return DeckDialogLayout(title: title, child: child, actions: actions);
    final colors = deckColors(context);
    final form = Container(
      decoration: BoxDecoration(
        color: colors['surface'],
        border: Border.all(color: colors['border']),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors['border'])),
              ),
              padding: MediaQuery.sizeOf(context).width <= 520
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 18)
                  : const EdgeInsets.all(20),
              child: child,
            ),
            Container(
              padding: MediaQuery.sizeOf(context).width <= 520
                  ? const EdgeInsets.all(14)
                  : const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: colors['raised'],
                border: Border(top: BorderSide(color: colors['border'])),
              ),
              child: DeckFormActions(children: actions),
            ),
          ],
        ),
      ),
    );
    final help = DeckPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors['selected'],
              borderRadius: BorderRadius.circular(9),
            ),
            child: DeckIcon('info', size: 20, color: colors['accent']),
          ),
          const SizedBox(height: 14),
          Text(
            'Перед продолжением',
            style: BrandTypography.body.copyWith(
              height: 22 / 14,
              fontFamily: BrandAssets.semiboldFamily,
              fontWeight: BrandTypography.semiboldWeight,
              fontVariations: BrandTypography.semiboldVariations,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Проверьте значения и выбранный объект. Выбор профиля не подключает сервер и не подтверждает доверие к SSH-ключу.',
            style: BrandTypography.caption.copyWith(
              height: 20 / 12,
              color: colors['muted'],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Изменения относятся к локальному пространству этого устройства и применяются после сохранения.',
            style: BrandTypography.caption.copyWith(
              height: 20 / 12,
              color: colors['muted'],
            ),
          ),
        ],
      ),
    );
    return DeckPage(
      title: title,
      eyebrow: 'Настройки / Рабочее пространство',
      description: 'Укажите параметры и проверьте их перед продолжением',
      child: Flex(
        direction: MediaQuery.sizeOf(context).width > 960
            ? Axis.horizontal
            : Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(flex: 165, fit: FlexFit.loose, child: form),
          if (MediaQuery.sizeOf(context).width > 960) ...[
            const SizedBox(width: 20),
            Flexible(flex: 100, fit: FlexFit.loose, child: help),
          ],
        ],
      ),
    );
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
      final form = Shortcuts(
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
          child: _layout(
            title: ready
                ? 'Изменение настроек'
                : 'Локальное пространство недоступно',
            actions: [
              if (ready && draft.initialized)
                FilledButton(
                  clipBehavior: Clip.none,
                  style: FilledButton.styleFrom(
                    minimumSize: Size(
                      widget.asPage ? 44 : 48,
                      widget.asPage ? 44 : 48,
                    ),
                  ),
                  onPressed: enabled && widget.model.loaded ? _save : null,
                  child: const Text('Сохранить настройки'),
                ),
              OutlinedButton(
                clipBehavior: Clip.none,
                autofocus: true,
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(
                    widget.asPage ? 44 : 48,
                    widget.asPage ? 44 : 48,
                  ),
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
                      if (widget.asPage)
                        _pageFields(enabled)
                      else ...[
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
                      ],
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
                      if (!widget.asPage && !idle) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        MutationStatus(
                          controller: draft.mutation,
                          asPage: widget.asPage,
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
      return MutationPresentationSwitch(
        enabled: widget.asPage,
        showReview: widget.asPage && ready && !idle,
        form: form,
        review: MutationReviewPage(
          controller: draft.mutation,
          settings: true,
          reloading: draft.reloading,
          readPending: _readingError,
          onReadCommitted: _readCommitted,
          onReload: _reload,
          onClose: _close,
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
