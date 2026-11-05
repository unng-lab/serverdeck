import 'package:flutter/material.dart';

import '../mcp/settings_controller.dart';
import '../mcp/settings_view.dart';
import '../ui/deck_components.dart';
import '../updates/update_owner.dart';
import '../updates/update_view.dart';

/// Content inside the runtime-owned settings route and its nested Navigator.
class ApplicationSettingsView extends StatefulWidget {
  const ApplicationSettingsView({super.key, required this.updates, this.mcp});
  final UpdateOwner updates;
  final McpSettingsController? mcp;
  @override
  State<ApplicationSettingsView> createState() =>
      _ApplicationSettingsViewState();
}

class _ApplicationSettingsViewState extends State<ApplicationSettingsView> {
  int _selected = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (widget.mcp != null)
        DeckTabs(
          labels: const ['Обновления', 'MCP'],
          icons: const [Icons.system_update_alt, Icons.hub_outlined],
          selected: _selected,
          onSelected: (value) => setState(() => _selected = value),
        ),
      Expanded(
        child: _selected == 0 || widget.mcp == null
            ? UpdateView(owner: widget.updates)
            : McpSettingsView(controller: widget.mcp!),
      ),
    ],
  );
}
