import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serverdeck_protocol/models.dart' hide ReadinessView;

import '../shell/readiness_view.dart';
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
  String? _readError;
  @override
  void initState() {
    super.initState();
    target = widget.initial;
    mutation = MutationController(model: widget.model);
  }

  Future<void> _delete() async {
    if (_reloading ||
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
    if (_reloading || mutation.busy) return;
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
          child: Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (ready) ...[
                      Text(
                        'Удаление профиля',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      Text(target.name),
                      Text(
                        target.address.contains(':')
                            ? '[${target.address}]:${target.port}'
                            : '${target.address}:${target.port}',
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Удаляется локальный профиль; сервер не меняется',
                      ),
                      if (_readError != null) Text(_readError!),
                      MutationStatus(
                        controller: mutation,
                        deleting: true,
                        onReload: () => _reload().ignore(),
                      ),
                      if (!idle)
                        const Text(
                          'Закрытие окна не отменяет уже отправленное удаление',
                        ),
                    ] else
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
                        if (ready)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(48, 48),
                            ),
                            onPressed:
                                idle &&
                                    !_reloading &&
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
    mutation.dispose();
    super.dispose();
  }
}
