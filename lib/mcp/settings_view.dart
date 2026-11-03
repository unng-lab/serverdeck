import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/deck_components.dart';
import '../domain/error_presentation.dart';
import 'settings_controller.dart';
import 'configuration_view.dart';

class McpSettingsView extends StatefulWidget {
  const McpSettingsView({super.key, required this.controller});
  final McpSettingsController controller;
  @override
  State<McpSettingsView> createState() => _McpSettingsViewState();
}

class _McpSettingsViewState extends State<McpSettingsView> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refresh());
  }

  Future<bool> _confirm(
    String title,
    String description,
    String action,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => DeckDialogLayout(
          title: title,
          child: Text(description),
          actions: [
            DeckButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            DeckButton(
              onPressed: () => Navigator.pop(context, true),
              kind: DeckButtonKind.primary,
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _issue() async {
    final name = TextEditingController();
    String? selected;
    try {
      selected = await showDialog<String>(
        context: context,
        builder: (context) => DeckDialogLayout(
          title: 'Разрешить доступ MCP',
          child: DeckFormSection(
            title: 'Новый клиент',
            children: [
              DeckTextField(label: 'Название клиента', controller: name),
              const Text(
                'Клиент сможет читать и создавать SSH-профили, менять учётные данные, подключаться и подтверждать ключи серверов. Разрешение действует 90 дней в текущей учётной записи Windows. Выдавайте его только доверенному клиенту.',
              ),
            ],
          ),
          actions: [
            DeckButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            DeckButton(
              onPressed: () => Navigator.pop(context, name.text),
              kind: DeckButtonKind.primary,
              child: const Text('Разрешить доступ'),
            ),
          ],
        ),
      );
      if (selected != null)
        await widget.controller.issue(selected, confirmed: true);
    } finally {
      name.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return SingleChildScrollView(
        child: DeckFormSection(
          title: 'Доступ MCP',
          children: [
            SwitchListTile(
              title: const Text('Разрешить MCP'),
              subtitle: const Text(
                'ServerDeck должен быть запущен. Клиент не запускает приложение автоматически.',
              ),
              value: c.enabled,
              onChanged: c.pending ? null : c.setEnabled,
            ),
            if (c.transportError() != null)
              DeckNotice(
                title: 'MCP недоступен',
                message: c.transportError()!,
                tone: DeckTone.error,
                actions: [
                  DeckButton(
                    onPressed: c.pending ? null : c.retryMcp,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            if (c.error != null)
              DeckNotice(
                title: 'Операция не выполнена',
                message: OperationPresentation.of(c.error!).message,
                nextStep: OperationPresentation.of(c.error!).nextStep,
                tone: DeckTone.error,
              ),
            DeckButton(
              onPressed: c.pending ? null : _issue,
              kind: DeckButtonKind.primary,
              child: const Text('Добавить клиента'),
            ),
            for (final grant in c.grants)
              DeckSurface(
                child: DeckFormSection(
                  title: grant.name,
                  description: grant.clientId,
                  children: [
                    Text(
                      grant.revoked
                          ? 'Доступ отозван'
                          : 'Действует до ${DateTime.fromMillisecondsSinceEpoch(grant.expiresAt).toLocal()}',
                    ),
                    if (grant.clockRollback)
                      const DeckNotice(
                        message: 'Разрешение отключено после перевода часов. Обновите его.',
                        tone: DeckTone.warning,
                      ),
                    if (grant.exportPending || grant.cleanupRequired)
                      DeckNotice(
                        title: 'Доступ приостановлен',
                        message: 'Нужно завершить закрытие старых каналов и сохранить защищённый файл разрешения.',
                        tone: DeckTone.warning,
                        actions: [
                          DeckButton(
                            onPressed: c.pending
                                ? null
                                : () => c.retry(grant.clientId),
                            child: const Text(
                              'Повторить закрытие и сохранение',
                            ),
                          ),
                        ],
                      ),
                    DeckActions(
                      children: [
                        if (!grant.revoked &&
                            !grant.exportPending &&
                            !grant.cleanupRequired)
                          DeckButton(
                            onPressed: c.pending
                                ? null
                                : () => c.showConfiguration(grant.clientId),
                            child: const Text('Конфигурация'),
                          ),
                        if (!grant.revoked)
                          DeckButton(
                            onPressed: c.pending
                                ? null
                                : () async {
                                    if (await _confirm(
                                      'Обновить разрешение?',
                                      grant.name + '\nСтарые каналы и ожидающие подключения клиента будут закрыты. Новый срок — 90 дней.',
                                      'Обновить',
                                    ))
                                      await c.rotate(
                                        grant.clientId,
                                        confirmed: true,
                                      );
                                  },
                            child: const Text('Обновить разрешение'),
                          ),
                        if (!grant.revoked)
                          DeckButton(
                            onPressed: c.pending
                                ? null
                                : () async {
                                    if (await _confirm(
                                      'Отозвать доступ?',
                                      grant.name + '\nКаналы и ожидающие подключения клиента будут закрыты. Установленные SSH-сеансы приложения сохранятся.',
                                      'Отозвать',
                                    ))
                                      await c.revoke(
                                        grant.clientId,
                                        confirmed: true,
                                      );
                                  },
                            kind: DeckButtonKind.danger,
                            child: const Text('Отозвать'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            if (c.configuration != null)
              McpConfigurationView(configuration: c.configuration!),
          ],
        ),
      );
    },
  );
}
