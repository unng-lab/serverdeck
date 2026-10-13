import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/shell/error_view.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/models.dart' show ErrorCode;

void main() {
  testWidgets('every safe category is distinct with a permitted next step', (
    tester,
  ) async {
    var reads = 0, checks = 0;
    final categories = <String>{};
    for (final code in ErrorCode.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: Scaffold(
            body: ReadErrorView(
              code: code,
              onReadAgain: () => reads++,
              onCheckService: () => checks++,
            ),
          ),
        ),
      );
      expect(categories.add(ReadErrorView.category(code)), isTrue);
      expect(find.text(ReadErrorView.category(code)), findsOneWidget);
      if (find.text('Повторить чтение').evaluate().isNotEmpty) {
        await tester.tap(find.text('Повторить чтение'));
      } else if (find.text('Повторить проверку службы').evaluate().isNotEmpty) {
        await tester.tap(find.text('Повторить проверку службы'));
      } else {
        expect(find.byType(FilledButton), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
    expect(reads, 5);
    expect(checks, 5);
  });

  for (final dark in [false, true]) {
    testWidgets('safe read retry is reachable with 200% text dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final code in [
        ErrorCode.timeout,
        ErrorCode.resourceLimit,
        ErrorCode.internal,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? BrandTheme.dark : BrandTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: ReadErrorView(
                code: code,
                onReadAgain: () {},
                onCheckService: () {},
              ),
            ),
          ),
        );
        final button = find.byType(FilledButton);
        await tester.ensureVisible(button);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        await tester.tap(button);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
