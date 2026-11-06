import 'package:flutter/material.dart';

import '../console/console_settings.dart';
import '../console/console_settings_view.dart';
import '../mcp/settings_controller.dart';
import '../mcp/settings_view.dart';
import '../ui/deck_components.dart';
import '../updates/update_owner.dart';
import '../updates/update_view.dart';

/// Content inside the runtime-owned settings route and its nested Navigator.
class ApplicationSettingsView extends StatefulWidget {
  const ApplicationSettingsView({
    super.key,
    required this.updates,
    this.mcp,
    this.onUpdateRestart,
    this.terminalSettings,
    this.newTerminalProfileId,
  }) : assert((terminalSettings == null) == (newTerminalProfileId == null));
  final UpdateOwner updates;
  final Future<bool> Function(String version)? onUpdateRestart;
  final McpSettingsController? mcp;
  final ConsoleSettingsOwner? terminalSettings;
  final String Function()? newTerminalProfileId;
  @override
  State<ApplicationSettingsView> createState() =>
      _ApplicationSettingsViewState();
}

class _ApplicationSettingsViewState extends State<ApplicationSettingsView> {
  int _selected = 0;
  @override
  Widget build(BuildContext context) {
    final labels = [
      'Обновления',
      if (widget.mcp != null) 'MCP',
      if (widget.terminalSettings != null) 'Терминал',
    ];
    final icons = [
      Icons.system_update_alt,
      if (widget.mcp != null) Icons.hub_outlined,
      if (widget.terminalSettings != null) Icons.terminal,
    ];
    final selected = _selected < labels.length ? _selected : 0;
    final terminalIndex = widget.mcp == null ? 1 : 2;
    final Widget content;
    if (widget.terminalSettings != null && selected == terminalIndex) {
      content = SingleChildScrollView(
        child: ConsoleSettingsView(
          owner: widget.terminalSettings!,
          newId: widget.newTerminalProfileId!,
        ),
      );
    } else if (widget.mcp != null && selected == 1) {
      content = McpSettingsView(controller: widget.mcp!);
    } else {
      content = UpdateView(
        owner: widget.updates,
        onRestart: widget.onUpdateRestart,
      );
    }
    return Column(
      children: [
        if (labels.length > 1)
          DeckTabs(
            labels: labels,
            icons: icons,
            selected: selected,
            onSelected: (value) => setState(() => _selected = value),
          ),
        Expanded(child: content),
      ],
    );
  }
}
