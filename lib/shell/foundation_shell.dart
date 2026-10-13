import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState, ErrorCode;

import '../theme/brand_assets.dart';
import '../theme/motion.dart';
import 'readiness_view.dart';

enum FoundationSection {
  servers('Серверы', Icons.dns_outlined),
  software('ПО', Icons.apps_outlined),
  logs('Журналы', Icons.article_outlined),
  jobs('Задания', Icons.task_alt_outlined),
  settings('Настройки', Icons.settings_outlined);

  const FoundationSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Navigation is local UI state; service readiness gates every private child.
class FoundationShell extends StatefulWidget {
  const FoundationShell({
    super.key,
    required this.state,
    this.reason,
    this.onRetry,
    this.retryInProgress = false,
    this.servers,
    this.settings,
    this.targetName,
    this.targetAddress,
    this.recoveryAction,
  });

  final ReadinessState state;
  final ErrorCode? reason;
  final VoidCallback? onRetry;
  final bool retryInProgress;
  final Widget? servers, settings;
  final String? targetName, targetAddress;
  final Widget? recoveryAction;

  @override
  State<FoundationShell> createState() => _FoundationShellState();
}

class _FoundationShellState extends State<FoundationShell> {
  FoundationSection _section = FoundationSection.servers;

  void _select(FoundationSection section, {required bool drawer}) {
    setState(() => _section = section);
    if (drawer) Navigator.of(context).pop();
  }

  Widget _navigation({required bool drawer}) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Image.asset(
            BrandAssets.logo(Theme.of(context).brightness),
            height: 48,
            semanticLabel: 'ServerDeck',
          ),
        ),
        for (final section in FoundationSection.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: OutlinedButton(
              onPressed: () => _select(section, drawer: drawer),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 56),
                backgroundColor: section == _section
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(12),
              ),
              child: Semantics(
                selected: section == _section,
                child: Row(
                  children: [
                    Icon(section.icon),
                    const SizedBox(width: 12),
                    Expanded(child: Text(section.label)),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _content() {
    if (widget.state != ReadinessState.ready) {
      return ReadinessView(
        state: widget.state,
        reason: widget.reason,
        onRetry: widget.onRetry,
        retryInProgress: widget.retryInProgress,
      );
    }
    return switch (_section) {
      FoundationSection.servers =>
        widget.servers ??
            const _Unavailable('Управление профилями пока недоступно'),
      FoundationSection.settings =>
        widget.settings ?? const _Unavailable('Настройки пока недоступны'),
      FoundationSection.software => const _Unavailable(
        'Управление ПО будет доступно после подключения к серверу',
      ),
      FoundationSection.logs => const _Unavailable(
        'Журналы сервера будут доступны после подключения',
      ),
      FoundationSection.jobs => const _Unavailable(
        'Выполнение заданий пока недоступно',
      ),
    };
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth <= 800;
      final reduced = Motion.reduced(context);
      final ready = widget.state == ReadinessState.ready;
      final name = ready ? widget.targetName : null;
      final address = ready ? widget.targetAddress : null;
      return Scaffold(
        appBar: AppBar(
          actions: ready && widget.recoveryAction != null
              ? [widget.recoveryAction!]
              : null,
          leading: compact && reduced
              ? IconButton(
                  tooltip: 'Открыть меню навигации',
                  onPressed: () => showMotionDialog<void>(
                    context: context,
                    barrierDismissible: true,
                    builder: (_) => Align(
                      alignment: Alignment.centerLeft,
                      child: Drawer(
                        child: SafeArea(child: _navigation(drawer: true)),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.menu),
                )
              : null,
          toolbarHeight: 72,
          title: Text(
            _section.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        drawer: compact && !reduced
            ? Drawer(child: SafeArea(child: _navigation(drawer: true)))
            : null,
        body: Row(
          children: [
            if (!compact) ...[
              SizedBox(width: 256, child: _navigation(drawer: false)),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ready)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * .25,
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            name != null && address != null
                                ? '$name · $address\nНе подключён'
                                : 'Локальная служба готова',
                          ),
                        ),
                      ),
                    ),
                  Expanded(child: _content()),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
