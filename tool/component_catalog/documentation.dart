import 'package:flutter/material.dart';
import 'package:serverdeck/ui/deck_components.dart';

import 'names.dart';

class ComponentDocumentation extends StatelessWidget {
  const ComponentDocumentation({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final card = componentDocumentation[id]!;
    String lines(String key) => (card[key]! as List).join('\n');
    final reasons = (card['notApplicableReasons']! as Map).entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
    return DeckFormSection(
      title: 'Контракт $id',
      children: [
        DeckKeyValue(label: 'Анатомия', value: lines('anatomy')),
        DeckKeyValue(label: 'Варианты', value: lines('variants')),
        DeckKeyValue(
          label: 'Параметры',
          value: lines('parameters'),
          selectable: true,
        ),
        DeckKeyValue(
          label: 'События',
          value: lines('events'),
          selectable: true,
        ),
        DeckKeyValue(label: 'Ограничения', value: lines('limitations')),
        DeckKeyValue(
          label: 'Критерии приёмки',
          value: lines('acceptanceCriteria'),
        ),
        DeckKeyValue(
          label: 'Применимые состояния',
          value: componentStates[id]!.join(', '),
        ),
        DeckCode(
          label: 'Пример подключения',
          text: card['usageExample']! as String,
        ),
        DeckKeyValue(
          label: 'Работающий пример',
          value: card['runnableExamplePath']! as String,
          selectable: true,
        ),
        DeckExpander(
          title: const Text('Неприменимые состояния и причины'),
          children: [Text(reasons)],
        ),
      ],
    );
  }
}
