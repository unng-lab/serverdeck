import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

import '../automation/automation_panel.dart';
import '../automation/automation_sections.dart';
import '../profiles/profile_controller.dart';
import '../profiles/profile_form.dart';
import '../shell/error_view.dart';
import '../theme/motion.dart';
import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';
import '../ui/deck_page.dart';

/// Server and recipe records remain owned by the same local service.
class SoftwarePanel extends StatefulWidget {
  const SoftwarePanel({
    super.key,
    required this.profiles,
    required this.client,
    this.serverId,
    this.onServerSelected,
  }) : assert(serverId == null || onServerSelected != null);
  final ProfileController profiles;
  final TrustedApiClient? client;

  /// A non-null navigation target stays explicit even if its profile disappears.
  /// A null target may use the saved initial default. Selection stays in RAM.
  final String? serverId;
  final ValueChanged<String>? onServerSelected;

  @override
  State<SoftwarePanel> createState() => _SoftwarePanelState();
}

class _SoftwarePanelState extends State<SoftwarePanel> {
  String? _selected;
  int _selectionEpoch = 0;
  String? get _selectedId =>
      widget.serverId ??
      (widget.onServerSelected == null ? _selected : null) ??
      widget.profiles.selected?.id;

  @override
  void didUpdateWidget(covariant SoftwarePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.profiles, widget.profiles) ||
        !identical(oldWidget.client, widget.client) ||
        oldWidget.serverId != widget.serverId ||
        (oldWidget.onServerSelected == null) !=
            (widget.onServerSelected == null)) {
      _selectionEpoch++;
      _selected = null;
    }
  }

  Future<void> _chooseServer() async {
    final owner = widget.profiles;
    final client = widget.client;
    final epoch = ++_selectionEpoch;
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
                      selected: row.id == _selectedId,
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
              clipBehavior: Clip.none,
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
    if (!mounted ||
        epoch != _selectionEpoch ||
        !identical(owner, widget.profiles) ||
        !identical(client, widget.client) ||
        !owner.loaded ||
        value == null ||
        !owner.profiles.any((row) => row.id == value))
      return;
    final select = widget.onServerSelected;
    if (select != null) {
      select(value);
    } else {
      setState(() => _selected = value);
    }
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
      final selected = _selectedId;
      final target = profiles.any((row) => row.id == selected)
          ? selected
          : null;
      final selector = SoftwareServerSelector(
        profiles: profiles,
        selectedId: target,
        onChoose: () => _chooseServer(),
      );
      if (target != null && widget.client != null)
        return AutomationPanel(
          key: ValueKey(target),
          client: widget.client!,
          serverId: target,
          serverProfiles: profiles,
          installationCatalog: true,
          contextBar: selector,
          contextBarBuilder: (environment) => SoftwareServerSelector(
            profiles: profiles,
            selectedId: target,
            onChoose: () => _chooseServer(),
            environment: environment,
          ),
        );
      return DeckPage(
        title: 'Каталог установки',
        description: 'Выберите сервер, откройте доступные точные рецепты и проверьте план перед запуском.',
        eyebrow: 'ПО / Рабочее пространство',
        contextBar: profiles.isEmpty ? null : selector,
        child: profiles.isEmpty
            ? DeckEmptyState(
                title: 'Серверов пока нет',
                description:
                    'Добавьте сервер, чтобы открыть каталог установки.',
                icon: 'software',
                actions: [
                  FilledButton(
                    clipBehavior: Clip.none,
                    onPressed: () => showMotionDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => ProfileForm(model: widget.profiles),
                    ),
                    child: const Text('Добавить сервер'),
                  ),
                ],
              )
            : const DeckNotice(
                message: 'Выберите сервер. Доступ и доверие подготавливаются в разделе «Серверы».',
                tone: DeckTone.neutral,
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
    this.environment,
  });

  final List<ProfileView> profiles;
  final String? selectedId;
  final VoidCallback onChoose;
  final String? environment;

  @override
  Widget build(BuildContext context) {
    final selected = profiles.where((row) => row.id == selectedId).firstOrNull;
    return DeckPanel(
      title: 'Область просмотра',
      trailing: TextButton(
        clipBehavior: Clip.none,
        onPressed: onChoose,
        child: Text(selected == null ? 'Выбрать сервер' : 'Изменить сервер'),
      ),
      child: AutomationFacts(
        tableContext: true,
        values: {
          'Сервер для установки': selected == null
              ? 'Сервер не выбран'
              : '${selected.name} · ${AutomationServerTargets.address(selected)}',
          'Среда': environment == 'ubuntu24.04-amd64-systemd'
              ? 'Ubuntu 24.04 · amd64 · systemd'
              : environment ?? 'Не предоставлено',
        },
      ),
    );
  }
}
