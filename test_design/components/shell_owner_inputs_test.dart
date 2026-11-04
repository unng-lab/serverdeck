import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/shell/foundation_shell.dart';

import '../support/component_cases.dart';

void main() {
  testWidgets('C17 unavailable suppresses both private content slots', (
    tester,
  ) async {
    await tester.pumpWidget(
      componentHarness(
        const SizedBox(
          height: 500,
          child: FoundationShell(
            state: ReadinessState.unavailable,
            sidebar: Text('Private navigation'),
            child: Text('Private body'),
            status: Text('Unavailable owner'),
          ),
        ),
      ),
    );
    expect(find.text('Private navigation'), findsNothing);
    expect(find.text('Private body'), findsNothing);
    expect(find.text('Unavailable owner'), findsOneWidget);
  });
  testWidgets('C17 renders synthetic owner status and fallback content', (
    tester,
  ) async {
    await tester.pumpWidget(
      componentHarness(
        const SizedBox(
          height: 500,
          child: FoundationShell(
            state: ReadinessState.ready,
            sidebar: Text('Synthetic servers'),
            status: Text('Owner status'),
            child: Text('Owner fallback'),
          ),
        ),
      ),
    );
    expect(find.text('Owner status'), findsOneWidget);
    expect(find.text('Owner fallback'), findsOneWidget);
    expect(find.text('Пример готов'), findsNothing);
  });
}
