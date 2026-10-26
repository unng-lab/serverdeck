import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

import '../automation/automation_panel.dart';
import '../profiles/profile_controller.dart';
import '../profiles/profile_form.dart';
import '../shell/error_view.dart';
import '../theme/motion.dart';
import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';

/// Server and recipe records remain owned by the same local service.
class SoftwarePanel extends StatefulWidget {
  const SoftwarePanel({
    super.key,
    required this.profiles,
    required this.client,
  });
  final ProfileController profiles;
  final TrustedApiClient? client;

  @override
  State<SoftwarePanel> createState() => _SoftwarePanelState();
}

class _SoftwarePanelState extends State<SoftwarePanel> {
  String? _selected;

  Future<void> _chooseServer() async {
    final owner = widget.profiles;
    final value = await showMotionDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialog) => ListenableBuilder(
        listenable: owner,
        builder: (context, _) => DeckDialogLayout(
          title: 'Сервер для установки',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!owner.loaded && owner.error != null)
                ReadErrorView(
                  code: owner.error!,
                  onReadAgain: () => owner.refresh().ignore(),
                  onCheckService: () => owner.bootstrap.retry().ignore(),
                ),
              if (!owner.loaded && owner.error == null)
                const Text(
                  'Список серверов недоступен: локальная служба не готова',
                ),
              if (owner.loaded)
                for (final row in owner.profiles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: BrandSpacing.space8),
                    child: DeckSurface(
                      selected: row.id == (_selected ?? owner.selected?.id),
                      onTap: () => Navigator.pop(dialog, row.id),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DeckSectionHeader(title: row.name),
                          const SizedBox(height: BrandSpacing.space4),
                          Text(row.address),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
    if (!mounted ||
        !identical(owner, widget.profiles) ||
        !owner.loaded ||
        value == null ||
        !owner.profiles.any((row) => row.id == value))
      return;
    setState(() => _selected = value);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.profiles,
    builder: (context, _) {
      final profiles = widget.profiles.profiles;
      final error = widget.profiles.error;
      if (error != null) {
        return ReadErrorView(
          code: error,
          onReadAgain: () => widget.profiles.refresh().ignore(),
          onCheckService: () => widget.profiles.bootstrap.retry().ignore(),
        );
      }
      if (!widget.profiles.loaded) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: BrandSpacing.space16),
          child: DeckStatus(label: 'Ожидание списка серверов', pending: true),
        );
      }
      final selected = _selected ?? widget.profiles.selected?.id;
      final target = profiles.any((row) => row.id == selected)
          ? selected
          : null;
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: BrandSpacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DeckSectionHeader(
              title: 'Установка ПО',
              description: 'Выберите сервер, откройте доступные точные рецепты и проверьте план перед запуском.',
            ),
            const SizedBox(height: BrandSpacing.space24),
            if (profiles.isEmpty) ...[
              DeckNotice(
                title: 'Серверов пока нет',
                message: 'Добавьте сервер, чтобы открыть каталог установки.',
                tone: DeckTone.neutral,
                actions: [
                  FilledButton(
                    onPressed: () => showMotionDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => ProfileForm(model: widget.profiles),
                    ),
                    child: const Text('Добавить сервер'),
                  ),
                ],
              ),
            ] else ...[
              SoftwareServerSelector(
                profiles: profiles,
                selectedId: target,
                onChoose: () => _chooseServer(),
              ),
              const SizedBox(height: BrandSpacing.space16),
              if (target != null && widget.client != null)
                AutomationPanel(
                  key: ValueKey(target),
                  client: widget.client!,
                  serverId: target,
                  serverProfiles: profiles,
                  installationCatalog: true,
                )
              else
                const DeckNotice(
                  message: 'Выберите сервер. Доступ и доверие подготавливаются в разделе «Серверы».',
                  tone: DeckTone.neutral,
                ),
            ],
          ],
        ),
      );
    },
  );
}

/// Local selection only. Opening recipes and connecting remain separate owner
/// actions, and the complete selected name/address can grow with text scale.
class SoftwareServerSelector extends StatelessWidget {
  const SoftwareServerSelector({
    super.key,
    required this.profiles,
    required this.selectedId,
    required this.onChoose,
  });

  final List<ProfileView> profiles;
  final String? selectedId;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final selected = profiles.where((row) => row.id == selectedId).firstOrNull;
    return DeckSurface(
      child: DeckFormSection(
        title: 'Сервер для установки',
        description: 'Выбор сервера не устанавливает подключение. Открытие рецептов выполняется отдельным действием.',
        children: [
          if (selected != null) ...[
            DeckKeyValue(label: 'Сервер', value: selected.name),
            DeckKeyValue(
              label: 'Адрес',
              value:
                  '${selected.address.contains(':') ? '[${selected.address}]' : selected.address}:${selected.port}',
              selectable: true,
            ),
          ],
          DeckActions(
            children: [
              OutlinedButton(
                onPressed: onChoose,
                child: Text(
                  selected == null ? 'Выбрать сервер' : 'Изменить сервер',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
