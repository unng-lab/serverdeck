import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serverdeck_protocol/models.dart' hide ReadinessView;

import '../shell/readiness_view.dart';
import '../shell/error_view.dart';
import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';
import 'mutation_controller.dart';
import 'mutation_status.dart';
import 'profile_controller.dart';

class _CloseDelete extends Intent {
  const _CloseDelete();
}

class ProfileDelete extends StatefulWidget {
  const ProfileDelete({super.key, required this.model, required this.initial});
  final ProfileController model;
  final ProfileView initial;
  @override
  State<ProfileDelete> createState() => _ProfileDeleteState();
}

class _ProfileDeleteState extends State<ProfileDelete> {
  late ProfileView target;
  late final MutationController mutation;
  bool _reloading = false, _missing = false;
  bool _readingError = false;
  String? _readError;
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

  void _close() => Navigator.of(context).maybePop();
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
      return Shortcuts(
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
          child: DeckDialogLayout(
            title: ready
                ? 'Удаление профиля'
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
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed:
                      idle &&
                          !_reloading &&
                          !_readingError &&
                          !_missing &&
                          widget.model.loaded
                      ? () => _delete().ignore()
                      : null,
                  child: const Text('Подтвердить удаление'),
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
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const DeckNotice(
                        title: 'Подтверждение удаления',
                        message:
                            'Удаляется локальный профиль; сервер не меняется',
                        nextStep: 'Для удаления этого профиля нажмите «Подтвердить удаление». Отмена сохраняет профиль.',
                      ),
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
                      if (!idle) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        MutationStatus(
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
    },
  );

  @override
  void dispose() {
    mutation.dispose();
    super.dispose();
  }
}
