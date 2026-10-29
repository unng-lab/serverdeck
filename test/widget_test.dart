import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/main.dart';

import 'support/dormant_bootstrap.dart';

void main() {
  testWidgets('unfinished scaffold does not claim service readiness', (
    tester,
  ) async {
    await tester.pumpWidget(FoundationApp(bootstrap: dormantBootstrap()));
    expect(find.text('Локальная служба недоступна'), findsWidgets);
  });
}
