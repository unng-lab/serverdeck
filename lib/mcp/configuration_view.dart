import 'dart:convert';

import 'package:flutter/material.dart';

import '../ui/deck_components.dart';
import 'grant_owner.dart';

/// C13/C18 composition of public command/args only. No credential input is accepted.
class McpConfigurationView extends StatelessWidget {
  const McpConfigurationView({super.key, required this.configuration});
  final McpConfiguration configuration;
  @override
  Widget build(BuildContext context) {
    final value = const JsonEncoder.withIndent('  ')
        .convert(configuration.toJson());
    return DeckFormSection(
      title: 'Конфигурация клиента',
      children: [
        DeckKeyValue(label: 'JSON MCP', value: value, selectable: true),
        DeckCopyButton(value: value, label: 'Копировать конфигурацию'),
      ],
    );
  }
}
