import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serverdeck_protocol/models.dart' hide ReadinessView;

import '../shell/readiness_view.dart';
import '../shell/error_view.dart';
import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';
import '../ui/deck_page.dart';
import 'profile_presentation.dart';
import 'mutation_controller.dart';
import 'mutation_status.dart';
import 'profile_controller.dart';

class _CloseDelete extends Intent {
  const _CloseDelete();
}

class ProfileDelete extends StatefulWidget {
  const ProfileDelete({
    super.key,
    required this.model,
    required this.initial,
    this.asPage = false,
    this.onClose,
  });
  final ProfileController model;
  final ProfileView initial;
  final bool asPage;
  final VoidCallback? onClose;
  @override
  State<ProfileDelete> createState() => _ProfileDeleteState();
}

class _ProfileDeleteState extends State<ProfileDelete> {
  late ProfileView target;
  late final MutationController mutation;
  bool _reloading = false, _missing = false;
  bool _readingError = false, _confirmed = false;
  String? _readError;
  int _consentEpoch = -1;
  @override
  void initState() {
    super.initState();
    target = widget.initial;
    mutation = MutationController(model: widget.model);
  }

  Future<void> _delete() async {
    if (_reloading ||
        _readingError ||
        _missing ||
        !_confirmed ||
        _consentEpoch != widget.model.bootstrap.readinessEpoch ||
        !widget.model.loaded ||
        mutation.state != MutationPresentation.idle)
      return;
    await mutation.submit(ApiMethod.profilesDelete, {
      'profileId': target.id,
      'expectedRevision': target.revision,
    });
  }

  Future<void> _reload() async {
    if (_reloading || _readingError || mutation.busy) return;
    setState(() => _reloading = true);
    await widget.model.refresh();
    if (!mounted) return;
    ProfileView? current;
    for (final profile in widget.model.profiles) {
      if (profile.id == target.id) current = profile;
    }
    setState(() {
      _reloading = false;
      if (!widget.model.loaded) {
        _readError = 'Не удалось перечитать профиль; удаление не повторено';
      } else if (current == null) {
        _missing = true;
        _readError =
            'Профиль уже удалён другим окном; ваше удаление не выполнено';
      } else {
        target = current;
        _confirmed = false;
        _readError = null;
        mutation.reset();
      }
    });
  }

  Future<void> _readAgain() async {
    if (_readingError ||
        _reloading ||
        (mutation.busy && mutation.state == MutationPresentation.committed))
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

  void _readCommitted() {
    if (_readingError || _reloading) return;
    mutation.refreshCommitted().ignore();
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.model,
      widget.model.bootstrap,
      mutation,
    ]),
    builder: (context, _) {
      final ready = widget.model.bootstrap.state == ReadinessState.ready;
      final idle = mutation.state == MutationPresentation.idle;
      if (_consentEpoch != widget.model.bootstrap.readinessEpoch)
        _confirmed = false;
      final form = Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): _CloseDelete(),
        },
        child: Actions(
          actions: {
            _CloseDelete: CallbackAction<_CloseDelete>(
              onInvoke: (_) {
                _close();
                return null;
              },
            ),
          },
          child: ProfileEditorFrame(
            asPage: widget.asPage,
            showHelper: false,
            plan: ready,
            planNotice: const DeckNotice(
              title: 'Удаление локальных данных',
              message: 'Удаляется локальный профиль; сервер не меняется',
              nextStep:
                  'Проверьте цель и последствия. Назад сохраняет профиль.',
              tone: DeckTone.warning,
            ),
            actionReview: ready
                ? CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Цель и последствия проверены'),
                    value: _confirmed,
                    onChanged:
                        idle && !_reloading && !_readingError && !_missing
                        ? (value) => setState(() {
                            _confirmed = value ?? false;
                            _consentEpoch =
                                widget.model.bootstrap.readinessEpoch;
                          })
                        : null,
                  )
                : null,
            description: 'Проверьте цель и последствия перед удалением локальных данных.',
            title: ready
                ? 'Удаление локального профиля'
                : 'Локальное пространство недоступно',
            target: ready
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DeckKeyValue(label: 'Профиль', value: target.name),
                      DeckKeyValue(
                        label: 'Адрес SSH',
                        value: target.address.contains(':')
                            ? '[${target.address}]:${target.port}'
                            : '${target.address}:${target.port}',
                      ),
                    ],
                  )
                : null,
            actions: [
              if (ready)
                FilledButton(
                  clipBehavior: Clip.none,
                  style: FilledButton.styleFrom(
                    minimumSize: Size(
                      widget.asPage ? 44 : 48,
                      widget.asPage ? 44 : 48,
                    ),
                  ),
                  onPressed:
                      idle &&
                          !_reloading &&
                          !_readingError &&
                          !_missing &&
                          _confirmed &&
                          widget.model.loaded
                      ? () => _delete().ignore()
                      : null,
                  child: const Text('Удалить профиль'),
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
                child: Text(idle ? 'Назад' : 'Закрыть'),
              ),
            ],
            child: !ready
                ? ReadinessView(
                    state: widget.model.bootstrap.state,
                    reason: widget.model.bootstrap.reason,
                    retryInProgress: widget.model.bootstrap.retryInProgress,
                    onRetry: () => widget.model.bootstrap.retry().ignore(),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const DeckPanel(
                        title: 'Цель и последствия',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DeckKeyValue(
                              label: '01 · Будет удалено',
                              value: 'Локальный профиль, ссылки и сохранённые наблюдения',
                            ),
                            SizedBox(height: 16),
                            DeckKeyValue(
                              label: '02 · На сервере',
                              value: 'Изменений нет',
                            ),
                            SizedBox(height: 16),
                            DeckKeyValue(
                              label: '03 · Проверка',
                              value: 'Локальная служба проверит активные и неподтверждённые операции перед удалением',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (widget.model.error case final code?) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        ReadErrorView(
                          code: code,
                          reading: _readingError || _reloading,
                          pendingLabel: 'Чтение актуального профиля',
                          onReadAgain: () => _readAgain().ignore(),
                          onCheckService: () =>
                              widget.model.bootstrap.retry().ignore(),
                        ),
                      ],
                      if (_readingError && widget.model.error == null) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        const DeckStatus(
                          label: 'Чтение актуального профиля',
                          pending: true,
                        ),
                      ],
                      if (_readError != null) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        DeckNotice(message: _readError!, tone: DeckTone.error),
                      ],
                      if (!widget.asPage && !idle) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        MutationStatus(
                          asPage: widget.asPage,
                          controller: mutation,
                          deleting: true,
                          reloading: _reloading,
                          readPending: _readingError,
                          onReadCommitted: _readCommitted,
                          onReload: () => _reload().ignore(),
                        ),
                        const SizedBox(height: BrandSpacing.space12),
                        const Text(
                          'Закрытие окна не отменяет уже отправленное удаление',
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
          controller: mutation,
          targetCaption:
              '${target.name} · ${target.address.contains(':') ? '[${target.address}]' : target.address}:${target.port}',
          deleting: true,
          reloading: _reloading,
          readPending: _readingError,
          onReadCommitted: _readCommitted,
          onReload: () => _reload().ignore(),
          onClose: _close,
        ),
      );
    },
  );

  @override
  void dispose() {
    mutation.dispose();
    super.dispose();
  }
}
