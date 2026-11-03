import 'package:flutter_test/flutter_test.dart';

import '../tool/component_catalog.dart';

void main() {
  testWidgets('catalog starts with shared component selector', (tester) async {
    await tester.pumpWidget(const ComponentCatalogApp());
    expect(find.text('ServerDeck · Material 3 / Deck'), findsOneWidget);
    expect(find.textContaining('C06'), findsWidgets);
  });
}
