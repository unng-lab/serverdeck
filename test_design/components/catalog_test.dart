import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/component_catalog/examples.dart';
import '../../tool/component_catalog/names.dart';
import '../support/component_cases.dart';

void main() {
  test(
    'registry contains all shared components and catalog metadata agree',
    () {
      final registry = jsonDecode(
        File('docs/design/components/registry.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final components = registry['components'] as List<dynamic>;
      final ids = components.map((c) => c['id']).toSet();
      expect(ids, componentNames.keys.toSet());
      expect(ids.length, 30);
      for (final c in components) {
        expect(componentStates[c['id']], c['applicableStates']);
        final card = componentDocumentation[c['id']]!;
        for (final entry in card.entries) {
          expect(entry.value, c[entry.key], reason: '${c['id']} ${entry.key}');
        }
      }
    },
  );
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
