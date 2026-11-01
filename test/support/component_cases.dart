import 'package:flutter/material.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

const componentFrames = <Size>[
  Size(1100, 760),
  Size(800, 600),
  Size(390, 800),
  Size(360, 800),
];

Widget componentHarness(Widget child, {bool dark = true, double scale = 1}) =>
    MaterialApp(
      theme: dark ? BrandTheme.dark : BrandTheme.light,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );

@immutable
class ComponentRow {
  const ComponentRow(this.id, this.name, this.address);
  final String id, name;
  final String? address;
}

const componentRows = [
  ComponentRow('web', 'atlas-web', '192.0.2.14'),
  ComponentRow('db', 'atlas-db', null),
];

final componentColumns = [
  DeckColumn<ComponentRow>(
    id: 'name',
    label: 'Сервер',
    value: (r) => r.name,
    sortable: true,
  ),
  DeckColumn<ComponentRow>(
    id: 'address',
    label: 'Адрес',
    value: (r) => r.address,
  ),
];
