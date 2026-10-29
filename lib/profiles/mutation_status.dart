import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../servers/server_compositions.dart';
import '../shell/error_view.dart';
import '../ui/deck_components.dart';
import '../ui/deck_icon.dart';
import '../ui/deck_page.dart';
import '../theme/brand_theme.dart';
import 'mutation_controller.dart';

class MutationStatus extends StatelessWidget {
  const MutationStatus({
    super.key,
    required this.controller,
    required this.onReload,
    this.deleting = false,
    this.settings = false,
    this.reloading = false,
    this.readPending = false,
    this.onReadCommitted,
    this.asPage = false,
  }) : _reviewBody = false,
       _targetCaption = null;

  const MutationStatus.review({
    super.key,
    required this.controller,
    required this.onReload,
    this.deleting = false,
    this.settings = false,
    this.reloading = false,
    this.readPending = false,
    this.onReadCommitted,
    String? targetCaption,
  }) : _targetCaption = targetCaption,
       asPage = true,
       _reviewBody = true;
  final MutationController controller;
  final VoidCallback onReload;
  final bool deleting;
  final bool asPage;
  final bool settings;
  final bool _reviewBody;
  final String? _targetCaption;
  final bool reloading;
  final bool readPending;
  final VoidCallback? onReadCommitted;
  @override
  Widget build(BuildContext context) {
    if (reloading && !_reviewBody) {
      return DeckStatus(
        label: settings
            ? 'Чтение актуальных настроек'
            : 'Чтение актуального профиля',
        pending: true,
      );
    }
    final state = controller.state;
    if (state == MutationPresentation.idle) return const SizedBox.shrink();
    final label = switch (state) {
      MutationPresentation.submitting => deleting ? 'Удаление' : 'Сохранение',
      MutationPresentation.unknown =>
        deleting ? 'Удаление не подтверждено' : 'Сохранение не подтверждено',
      MutationPresentation.waiting => 'Операция ещё выполняется',
      MutationPresentation.retryAllowed =>
        'Запрос не найден; можно повторить тот же запрос',
      MutationPresentation.committed =>
        deleting
            ? 'Удаление выполнено; ожидается чтение актуального состояния'
            : 'Сохранено; ожидается чтение актуального состояния',
      MutationPresentation.succeeded => deleting ? 'Удалено' : 'Сохранено',
      MutationPresentation.conflict =>
        settings
            ? 'Настройки изменены другим окном. Введённые данные сохранены в форме'
            : deleting
            ? 'Профиль изменён другим окном. Перечитайте его перед удалением'
            : 'Профиль изменён другим окном. Введённые данные сохранены в форме',
      MutationPresentation.failed =>
        deleting ? 'Удаление отклонено' : 'Сохранение отклонено',
      MutationPresentation.idle => '',
    };
    final tone = switch (state) {
      MutationPresentation.submitting ||
      MutationPresentation.waiting => DeckTone.running,
      MutationPresentation.unknown ||
      MutationPresentation.retryAllowed => DeckTone.unknown,
      MutationPresentation.conflict => DeckTone.warning,
      MutationPresentation.failed => DeckTone.error,
      MutationPresentation.committed ||
      MutationPresentation.succeeded => DeckTone.success,
      MutationPresentation.idle => DeckTone.neutral,
    };
    final detail = switch (state) {
      MutationPresentation.submitting => 'Запрос отправлен. Повторная отправка недоступна, пока ожидается результат.',
      MutationPresentation.unknown => 'Потерянный ответ не доказывает, что запись не выполнена. Автоматического повтора нет.',
      MutationPresentation.waiting => 'Окончательный результат ещё не получен. Проверка результата не отправляет запись повторно.',
      MutationPresentation.retryAllowed =>
        'Повтор доступен только для исходного запроса с теми же данными.',
      MutationPresentation.committed => 'Запись подтверждена. Для завершения нужно получить актуальное состояние локального пространства.',
      MutationPresentation.succeeded =>
        'Запись подтверждена, актуальное состояние прочитано.',
      MutationPresentation.conflict =>
        'Перечитайте актуальные данные перед новым подтверждением изменения.',
      MutationPresentation.failed => 'Локальная служба отклонила изменение. Проверьте причину перед новым действием.',
      MutationPresentation.idle => '',
    };
    if (_reviewBody) {
      return Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DeckTabs(
              labels: const [
                'Конфликт',
                'Ожидание',
                'Исход неизвестен',
                'Сохранено',
              ],
              selected: _tab(state),
              onSelected: null,
            ),
            const DeckTabsGap(),
            ServerStatusBody(
              title: _title(state),
              icon: state == MutationPresentation.conflict
                  ? 'warning'
                  : state == MutationPresentation.succeeded ||
                        state == MutationPresentation.committed
                  ? 'check'
                  : 'info',
              tone: tone,
              facts: {
                'Операция': settings
                    ? 'Изменение настроек'
                    : deleting
                    ? 'Удаление профиля'
                    : 'Изменение профиля',
                'Состояние': switch (state) {
                  MutationPresentation.conflict => 'Конфликт ревизии',
                  MutationPresentation.failed =>
                    deleting ? 'Удаление отклонено' : 'Сохранение отклонено',
                  MutationPresentation.submitting =>
                    deleting ? 'Удаление' : 'Сохранение',
                  MutationPresentation.unknown => 'Исход записи неизвестен',
                  MutationPresentation.waiting => 'Операция ещё выполняется',
                  MutationPresentation.retryAllowed => 'Запрос не найден',
                  MutationPresentation.committed => 'Запись подтверждена',
                  MutationPresentation.succeeded =>
                    deleting ? 'Удалено' : 'Сохранено',
                  MutationPresentation.idle => '',
                },
                'Черновик': deleting
                    ? 'Подтверждение удаления сохранено'
                    : 'Черновик сохранён',
                'Следующий шаг': state == MutationPresentation.conflict
                    ? 'Перечитайте данные и проверьте изменения'
                    : detail,
                'Неизвестный исход': switch (state) {
                  MutationPresentation.conflict => 'Подтверждённый конфликт не является неизвестным исходом записи',
                  MutationPresentation.committed ||
                  MutationPresentation.succeeded =>
                    'Запись подтверждена локальной службой',
                  MutationPresentation.failed =>
                    'Изменение отклонено локальной службой',
                  _ => detail,
                },
                if (_targetCaption != null) 'Цель': _targetCaption,
              },
              details: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Text(label, key: const ValueKey('mutation-current-status')),
                  if (controller.requestId != null)
                    DeckKeyValue(
                      label: 'Исходный запрос',
                      value: controller.requestId!,
                      selectable: true,
                    ),
                  if (controller.error != null)
                    Text(ReadErrorView.category(controller.error!)),
                  if (reloading)
                    DeckStatus(
                      label: settings
                          ? 'Чтение актуальных настроек'
                          : 'Чтение актуального профиля',
                      pending: true,
                    ),
                ],
              ),
              actions: _reviewActions(state),
            ),
          ],
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final entry in const [
                'Конфликт',
                'Ожидание',
                'Исход неизвестен',
                'Сохранено',
              ].asMap().entries)
                Semantics(
                  selected: entry.key == _tab(state),
                  child: Tooltip(
                    message:
                        'Состояние определяется результатом текущей операции.',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: entry.key == _tab(state)
                                ? deckColors(context)['accent']
                                : deckColors(context)['border'],
                            width: entry.key == _tab(state) ? 2 : 1,
                          ),
                        ),
                      ),
                      child: Text(
                        entry.value,
                        style: BrandTypography.caption.copyWith(
                          color: deckColors(
                            context,
                          )[entry.key == _tab(state) ? 'accent' : 'muted'],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          DeckPanel(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  DeckIcon(
                    state == MutationPresentation.conflict
                        ? 'warning'
                        : state == MutationPresentation.succeeded ||
                              state == MutationPresentation.committed
                        ? 'check'
                        : 'info',
                    size: 38,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    switch (state) {
                      MutationPresentation.succeeded => 'Изменение завершено',
                      MutationPresentation.committed => 'Запись подтверждена',
                      MutationPresentation.failed => 'Изменение отклонено',
                      MutationPresentation.submitting ||
                      MutationPresentation.waiting => 'Ожидание результата',
                      _ => 'Сохранение требует проверки',
                    },
                    textAlign: TextAlign.center,
                    style: BrandTypography.title.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    key: const ValueKey('mutation-current-status'),
                    textAlign: TextAlign.center,
                    style: BrandTypography.body,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          DeckNotice(
            message: controller.error == null
                ? detail
                : ReadErrorView.category(controller.error!),
            nextStep:
                controller.busy && state != MutationPresentation.submitting
                ? 'Ожидаем ответ текущей проверки; повторные действия недоступны.'
                : controller.error == null
                ? null
                : detail,
            tone: tone,
            actions: [
              if (!controller.busy) ...[
                if ({
                  MutationPresentation.unknown,
                  MutationPresentation.waiting,
                  MutationPresentation.retryAllowed,
                }.contains(state))
                  _action(
                    'Проверить результат',
                    () => controller.checkResult().ignore(),
                  ),
                if (state == MutationPresentation.retryAllowed)
                  _action(
                    'Повторить тот же запрос',
                    () => controller.retry().ignore(),
                  ),
                if (state == MutationPresentation.committed)
                  _action(
                    'Перечитать состояние',
                    readPending
                        ? null
                        : onReadCommitted ??
                              () => controller.refreshCommitted().ignore(),
                  ),
                if (state == MutationPresentation.conflict)
                  _action(
                    settings ? 'Перечитать настройки' : 'Перечитать профиль',
                    readPending ? null : onReload,
                  ),
                if (state == MutationPresentation.failed)
                  _action(
                    deleting ? 'Вернуться к подтверждению' : 'Исправить ввод',
                    controller.reset,
                  ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          DeckPanel(
            title: 'Полные сведения',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DeckKeyValue(label: 'Состояние', value: state.name),
                if (controller.requestId != null)
                  DeckKeyValue(
                    label: 'Исходный запрос',
                    value: controller.requestId!,
                    selectable: true,
                  ),
                DeckKeyValue(label: 'Следующий шаг', value: detail),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _tab(MutationPresentation state) => switch (state) {
    MutationPresentation.conflict => 0,
    MutationPresentation.submitting || MutationPresentation.waiting => 1,
    MutationPresentation.unknown ||
    MutationPresentation.retryAllowed ||
    MutationPresentation.failed => 2,
    _ => 3,
  };

  static String _title(MutationPresentation state) => switch (state) {
    MutationPresentation.succeeded => 'Изменение завершено',
    MutationPresentation.committed => 'Запись подтверждена',
    MutationPresentation.failed => 'Изменение отклонено',
    MutationPresentation.submitting ||
    MutationPresentation.waiting => 'Ожидание результата',
    _ => 'Сохранение требует проверки',
  };

  List<Widget> _reviewActions(MutationPresentation state) => [
    if (!controller.busy && !reloading) ...[
      if ({
        MutationPresentation.unknown,
        MutationPresentation.waiting,
        MutationPresentation.retryAllowed,
      }.contains(state))
        _action('Проверить результат', () => controller.checkResult().ignore()),
      if (state == MutationPresentation.retryAllowed)
        _action('Повторить тот же запрос', () => controller.retry().ignore()),
      if (state == MutationPresentation.committed)
        _action(
          'Перечитать состояние',
          readPending
              ? null
              : onReadCommitted ?? () => controller.refreshCommitted().ignore(),
        ),
      if (state == MutationPresentation.conflict)
        _action(
          settings ? 'Перечитать настройки' : 'Перечитать профиль',
          readPending ? null : onReload,
        ),
      if (state == MutationPresentation.failed)
        _action(
          deleting ? 'Вернуться к подтверждению' : 'Исправить ввод',
          controller.reset,
        ),
    ],
  ];

  Widget _action(String label, VoidCallback? action) => OutlinedButton(
    clipBehavior: Clip.none,
    style: OutlinedButton.styleFrom(
      minimumSize: Size(asPage ? 44 : 48, asPage ? 44 : 48),
    ),
    onPressed: action,
    child: Text(label),
  );
}

class _CloseMutationReview extends Intent {
  const _CloseMutationReview();
}

/// The same operation's page presentation; showing it performs no owner action.
class MutationReviewPage extends StatelessWidget {
  const MutationReviewPage({
    super.key,
    required this.controller,
    required this.onReload,
    this.settings = false,
    this.deleting = false,
    this.reloading = false,
    this.readPending = false,
    this.onReadCommitted,
    this.onClose,
    this.targetCaption,
  });
  final MutationController controller;
  final VoidCallback onReload;
  final VoidCallback? onReadCommitted, onClose;
  final bool settings, deleting, reloading, readPending;
  final String? targetCaption;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): _CloseMutationReview(),
    },
    child: Actions(
      actions: {
        _CloseMutationReview: CallbackAction<_CloseMutationReview>(
          onInvoke: (_) {
            onClose?.call();
            return null;
          },
        ),
      },
      child: DeckPage(
        title: 'Сохранение требует проверки',
        eyebrow: 'Локальное пространство / Рабочее пространство',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MutationStatus.review(
              controller: controller,
              onReload: onReload,
              settings: settings,
              deleting: deleting,
              reloading: reloading,
              readPending: readPending,
              onReadCommitted: onReadCommitted,
              targetCaption: targetCaption,
            ),
            if (onClose != null) ...[
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  clipBehavior: Clip.none,
                  autofocus: true,
                  onPressed: onClose,
                  child: const Text('Закрыть'),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Keeps the ordinary editor alive but outside paint, semantics and shortcuts.
/// Its owner's readiness/enabled rebuilds continue, including private disposal.
class MutationPresentationSwitch extends StatefulWidget {
  const MutationPresentationSwitch({
    super.key,
    required this.showReview,
    required this.form,
    required this.review,
    this.enabled = true,
  });
  final bool enabled;
  final bool showReview;
  final Widget form, review;
  @override
  State<MutationPresentationSwitch> createState() =>
      _MutationPresentationSwitchState();
}

class _MutationPresentationSwitchState
    extends State<MutationPresentationSwitch> {
  final _formFocus = FocusScopeNode(debugLabel: 'Mutation ordinary editor');
  final _reviewFocus = FocusScopeNode(debugLabel: 'Mutation result review');
  FocusNode? _previous;
  int _epoch = 0;
  @override
  void didUpdateWidget(covariant MutationPresentationSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showReview == widget.showReview) return;
    final epoch = ++_epoch;
    if (widget.showReview) {
      final focused = FocusManager.instance.primaryFocus;
      if (_formFocus.descendants.contains(focused)) _previous = focused;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _epoch) return;
      if (widget.showReview) {
        _reviewFocus.requestFocus();
      } else {
        final previous = _previous;
        _previous = null;
        if (previous?.context?.mounted == true && previous!.canRequestFocus)
          previous.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _epoch++;
    _previous = null;
    _formFocus.dispose();
    _reviewFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !widget.enabled
      ? widget.form
      : Stack(
          children: [
            Visibility(
              visible: !widget.showReview,
              maintainState: true,
              child: ExcludeFocus(
                excluding: widget.showReview,
                child: ExcludeSemantics(
                  excluding: widget.showReview,
                  child: FocusScope(node: _formFocus, child: widget.form),
                ),
              ),
            ),
            if (widget.showReview)
              FocusScope(node: _reviewFocus, child: widget.review),
          ],
        );
}
