import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/shell/foundation_shell.dart';

import '../support/component_cases.dart';

void main() {
  testWidgets('C17 renders synthetic owner status and fallback content', (
    tester,
  ) async {
    await tester.pumpWidget(
      componentHarness(
        const SizedBox(
          height: 500,
          child: FoundationShell(
            state: ReadinessState.ready,
            requestedSection: FoundationSection.logs,
            status: Text('Owner status'),
            fallbackContent: Text('Owner fallback'),
          ),
        ),
      ),
    );
    expect(find.text('Owner status'), findsOneWidget);
    expect(find.text('Owner fallback'), findsOneWidget);
    expect(find.text('Пример готов'), findsNothing);
  });
}
