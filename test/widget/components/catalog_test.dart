import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/component_catalog/examples.dart';
import '../../../tool/component_catalog/names.dart';
import '../../support/component_cases.dart';

void main() {
  test('registry joins every reference exactly once and catalog IDs agree', () {
    final registry = jsonDecode(
      File('docs/design/components/registry.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final references = jsonDecode(
      File('docs/design/screens.json').readAsStringSync(),
    ) as List<dynamic>;
    final components = registry['components'] as List<dynamic>;
    final screens = registry['screens'] as List<dynamic>;
    final ids = components.map((c) => c['id']).toSet();
    expect(ids, componentNames.keys.toSet());
    expect(ids.length, 30);
    expect(screens.length, 98);
    expect(
      screens.map((s) => s['screenId']).toSet(),
      references.map((s) => s['id']).toSet(),
    );
    expect(screens.where((s) => s['kind'] == 'existing').length, 35);
    for (final s in screens) {
      expect(s['componentIds'], isNotEmpty);
      expect((s['componentIds'] as List).every(ids.contains), isTrue);
      for (final path in s['productionPaths'] as List) {
        expect(File(path as String).existsSync(), isTrue, reason: path);
      }
    }
    for (final c in components) {
      expect(c['sourceScreenIds'], isNotEmpty, reason: c['id'] as String);
      expect(componentStates[c['id']], c['applicableStates']);
      final card = componentDocumentation[c['id']]!;
      for (final entry in card.entries) {
        expect(entry.value, c[entry.key], reason: '${c['id']} ${entry.key}');
      }
    }
  });
  for (final dark in [true, false]) {
    for (final frame in componentFrames) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'all component examples ${dark ? 'dark' : 'light'} $frame $scale',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = frame;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            for (final id in componentNames.keys) {
              await tester.pumpWidget(
                componentHarness(
                  ComponentExample(key: ValueKey(id), id: id),
                  dark: dark,
                  scale: scale,
                ),
              );
              await tester.pump();
              expect(
                tester.takeException(),
                null,
                reason: '$id $frame scale $scale',
              );
            }
          },
        );
      }
    }
  }
}
