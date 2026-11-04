import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide ConnectionState;

import '../domain/models.dart';
import '../domain/error_presentation.dart';
import '../ui/deck_components.dart';
import '../monitoring/monitoring_owner.dart';
import '../monitoring/monitoring_view.dart';
import 'profile_controller.dart';
import 'profile_form.dart';

class ProfileViewPanel extends StatefulWidget {
  const ProfileViewPanel({
    super.key,
    required this.controller,
    required this.pickKey,
    this.monitoring,
  });
  final ProfileController controller;
  final MonitoringOwner? monitoring;
  final Future<Uint8List?> Function() pickKey;
  @override
  State<ProfileViewPanel> createState() => _ProfileViewPanelState();
}

class _ProfileViewPanelState extends State<ProfileViewPanel> {
  final _search = TextEditingController();
  String _query = '';
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refresh());
  }

  Future<void> _edit([ProfileView? profile]) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProfileForm(
        controller: widget.controller,
        pickKey: widget.pickKey,
        profile: profile,
      ),
    );
    if (mounted) await widget.controller.refresh();
  }

  Future<bool> _confirm(String title, Widget child, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => DeckDialogLayout(
          title: title,
          child: child,
          actions: [
            DeckButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            DeckButton(
              kind: DeckButtonKind.danger,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _delete(ProfileView p) async {
    if (await _confirm(
      'Удалить сервер?',
      Text(
        '${p.displayName}\n${p.username}@${p.host}:${p.port}\nПодключение будет закрыто. Профиль и его учётные данные будут удалены.',
      ),
      'Удалить',
    ))
      await widget.controller.delete(p, confirmed: true);
  }

  Future<void> _trust(ProfileView p, TrustChallenge c) async {
    final verb = switch (c.kind) {
      TrustKind.first => 'Принять ключ',
      TrustKind.replace => 'Заменить ключ',
      TrustKind.retain => 'Сохранить прежний ключ',
    };
    final confirmed = await _confirm(
      verb,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${c.host}:${c.port} · ${c.keyType}'),
          if (c.oldFingerprint != null)
            DeckKeyValue(
              label: 'Прежний отпечаток',
              value: c.oldFingerprint!,
              selectable: true,
            ),
          DeckKeyValue(
            label: 'Подтверждаемый отпечаток',
            value: c.fingerprint,
            selectable: true,
          ),
          const Text(
            'Сверьте отпечаток с доверенным источником. Решение действует для всех профилей этого адреса.',
          ),
        ],
      ),
      verb,
    );
    if (confirmed)
      await widget.controller.decide(
        p.profileId,
        c,
        confirmed: true,
        mutationId: widget.controller.newId(),
      );
    else if (c.kind == TrustKind.first)
      await widget.controller.cancel(p.profileId, c.attemptId);
  }

  Future<void> _phrase(String id, PendingInput pending) async {
    final value = TextEditingController();
    String? phrase;
    try {
      phrase = await showDialog<String>(
        context: context,
        builder: (context) => DeckDialogLayout(
          title: 'Passphrase приватного ключа',
          child: DeckTextField(
            label: 'Passphrase',
            controller: value,
            secret: true,
          ),
          actions: [
            DeckButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            DeckButton(
              onPressed: () => Navigator.pop(context, value.text),
              child: const Text('Продолжить'),
            ),
          ],
        ),
      );
      value.clear();
      if (phrase != null)
        await widget.controller.providePassphrase(id, pending, phrase);
      else
        await widget.controller.cancel(id, pending.attemptId);
    } finally {
      phrase = null;
      value.clear();
      value.dispose();
    }
  }

  String _state(ConnectionState state) => switch (state) {
    ConnectionState.disconnected => 'Не подключён',
    ConnectionState.connecting => 'Подключаемся',
    ConnectionState.needTrust => 'Ожидает подтверждения ключа',
    ConnectionState.needPassphrase => 'Ожидает passphrase',
    ConnectionState.authenticating => 'Проверяем учётные данные',
    ConnectionState.cancelled => 'Подключение отменено',
    ConnectionState.connected => 'Подключён',
    ConnectionState.failed => 'Ошибка подключения',
  };
  Widget _details(ProfileDetails d) {
    final p = d.profile,
        c = d.connection,
        t = d.trust,
        challenge = t.challenge ?? c.challenge;
    return DeckFormSection(
      title: p.displayName,
      description: '${p.username}@${p.host}:${p.port}',
      children: [
        DeckStatus(
          label: _state(c.state),
          tone: c.state == ConnectionState.connected
              ? DeckTone.available
              : DeckTone.neutral,
        ),
        if (c.failureCode != null)
          DeckNotice(
            title: 'Состояние подключения',
            message: OperationPresentation.of(OperationFailure(c.failureCode!))
                .message,
            nextStep: OperationPresentation.of(OperationFailure(c.failureCode!))
                .nextStep,
            tone: DeckTone.error,
          ),
        DeckKeyValue(
          label: 'Способ входа',
          value: p.authKind == AuthKind.password
              ? 'Пароль'
              : 'Приватный ключ OpenSSH',
        ),
        if (t.acceptedFingerprint != null)
          DeckKeyValue(label: 'Доверенный ключ', value: t.acceptedFingerprint!),
        if (t.changed)
          DeckNotice(
            title: 'Ключ сервера изменился',
            message:
                'Доверенный: ${t.acceptedFingerprint ?? "—"}\nНаблюдаемый: ${t.observedFingerprint ?? "—"}\nПеред решением проверьте ключ через доверенный источник.',
            tone: DeckTone.warning,
          ),
        if (challenge != null)
          DeckButton(
            onPressed: widget.controller.pending
                ? null
                : () => _trust(p, challenge),
            child: Text(switch (challenge.kind) {
              TrustKind.first => 'Проверить и принять ключ',
              TrustKind.replace => 'Проверить замену ключа',
              TrustKind.retain => 'Подтвердить прежний ключ',
            }),
          ),
        if (t.changed && challenge == null)
          const Text(
            'Для нового подтверждения повторите подключение. После решения о замене подключитесь снова.',
          ),
        DeckActions(
          children: [
            if (c.state == ConnectionState.disconnected ||
                c.state == ConnectionState.failed ||
                c.state == ConnectionState.cancelled)
              DeckButton(
                onPressed: widget.controller.pending
                    ? null
                    : () => widget.controller.connect(p),
                kind: DeckButtonKind.primary,
                child: const Text('Подключиться'),
              ),
            if (c.attemptId != null && c.state != ConnectionState.connected)
              DeckButton(
                onPressed: widget.controller.pending
                    ? null
                    : () => widget.controller.cancel(p.profileId, c.attemptId!),
                child: const Text('Отменить подключение'),
              ),
            if (c.sessionId != null)
              DeckButton(
                onPressed: widget.controller.pending
                    ? null
                    : () => widget.controller.disconnect(
                        p.profileId,
                        c.sessionId!,
                      ),
                child: const Text('Отключиться'),
              ),
            if (c.pendingInput != null)
              DeckButton(
                onPressed: widget.controller.pending
                    ? null
                    : () => _phrase(p.profileId, c.pendingInput!),
                child: const Text('Ввести passphrase'),
              ),
            DeckButton(
              onPressed: widget.controller.pending ? null : () => _edit(p),
              child: const Text('Изменить'),
            ),
            DeckButton(
              onPressed: widget.controller.pending ? null : () => _delete(p),
              kind: DeckButtonKind.danger,
              child: const Text('Удалить'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _server(ProfileView p, ProfileController c) {
    final header = DeckListItem(
      title: p.displayName,
      description: '${p.username}@${p.host}:${p.port}',
      selected: c.selected == p.profileId,
      onTap: () => unawaited(c.select(p.profileId)),
      trailing: c.trusts[p.profileId]?.changed == true
          ? const DeckStatus(
              label: 'Ключ сервера изменился',
              tone: DeckTone.warning,
            )
          : null,
    );
    final monitoring = widget.monitoring;
    return monitoring == null
        ? header
        : MonitoringServerPanel(
            owner: monitoring,
            profileId: p.profileId,
            header: header,
          );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller,
          visible = c.items.where(
            (p) => '${p.displayName} ${p.host} ${p.username}'
                .toLowerCase()
                .contains(_query.toLowerCase()),
          );
      return SingleChildScrollView(
        child: DeckFormSection(
          title: 'Серверы',
          trailing: DeckButton(
            onPressed: c.pending ? null : () => _edit(),
            kind: DeckButtonKind.primary,
            child: const Text('Добавить сервер'),
          ),
          children: [
            if (widget.monitoring != null)
              MonitoringControls(owner: widget.monitoring!),
            DeckSearch(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
            ),
            if (c.error != null)
              DeckNotice(
                title: 'Операция не выполнена',
                message: OperationPresentation.of(c.error!).message,
                nextStep: OperationPresentation.of(c.error!).nextStep,
                tone: DeckTone.error,
                actions: [
                  DeckButton(
                    onPressed: c.refresh,
                    child: const Text('Обновить'),
                  ),
                ],
              ),
            if (c.loading)
              const DeckNotice(
                title: 'Загружаем серверы',
                message: 'Подождите',
                tone: DeckTone.running,
              ),
            if (!c.loading && c.items.isEmpty)
              const DeckNotice(
                title: 'Серверов пока нет',
                message: 'Добавьте SSH-профиль для подключения.',
              ),
            for (final p in visible) _server(p, c),
            if (c.details != null) _details(c.details!),
          ],
        ),
      );
    },
  );
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}
