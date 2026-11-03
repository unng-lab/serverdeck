import 'package:flutter/material.dart';

import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

import 'component_catalog/examples.dart';
import 'component_catalog/names.dart';
import 'component_catalog/documentation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ComponentCatalogApp());
}

/// An isolated entrypoint: no bootstrap, engine, controllers, credentials, or I/O.
class ComponentCatalogApp extends StatefulWidget {
  const ComponentCatalogApp({super.key});
  @override
  State<ComponentCatalogApp> createState() => _ComponentCatalogAppState();
}

class _ComponentCatalogAppState extends State<ComponentCatalogApp> {
  bool dark = true;
  String id = 'C06';
  String state = 'default';
  double width = 1100, scale = 1;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? BrandTheme.dark : BrandTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('ServerDeck · Material 3 / Deck')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: DeckActions(
                children: [
                  SizedBox(
                    width: 280,
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: id,
                      items: componentNames.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text('${entry.key} · ${entry.value}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null)
                          setState(() {
                            id = value;
                            state = 'default';
                          });
                      },
                    ),
                  ),
                  DeckButton(
                    onPressed: () => setState(() => dark = !dark),
                    child: Text(dark ? 'Светлая тема' : 'Тёмная тема'),
                  ),
                  DropdownButton<double>(
                    value: width,
                    items: [1100.0, 800.0, 390.0, 360.0]
                        .map(
                          (n) => DropdownMenuItem(
                            value: n,
                            child: Text('${n.round()} px'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => width = value);
                    },
                  ),
                  DeckButton(
                    onPressed: () => setState(() => scale = scale == 1 ? 2 : 1),
                    child: Text('Текст ${(scale * 100).round()}%'),
                  ),
                  DropdownButton<String>(
                    value: state,
                    items: componentStates[id]!
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => state = value);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey('catalog-$id'),
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        size: Size(
                          width,
                          width == 800
                              ? 600
                              : width == 1100
                              ? 760
                              : 800,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DeckSectionHeader(
                            title: '$id · ${componentNames[id]}',
                            description: 'Готовый production-компонент на синтетических данных. Все действия в этом каталоге локальные.',
                          ),
                          const SizedBox(height: 24),
                          ComponentExample(
                            key: ValueKey('$id-$state'),
                            id: id,
                            state: state,
                          ),
                          const SizedBox(height: 24),
                          ComponentDocumentation(id: id),
                          const SizedBox(height: 24),
                          const DeckNotice(
                            message: 'Подключение',
                            nextStep: 'Импортируйте lib/ui/deck_components.dart. Передайте данные, контроллеры и callbacks владельца экрана. Каталог не выдаёт права и не выполняет серверные операции.',
                            tone: DeckTone.neutral,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
