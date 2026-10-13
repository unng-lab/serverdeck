import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/models.dart';

Widget app(FoundationShell shell, {bool dark = false, double scale = 1}) =>
    MaterialApp(
      theme: dark ? BrandTheme.dark : BrandTheme.light,
      home: shell,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    );

void main() {
  testWidgets('private content and target are removed on loss of readiness', (
    tester,
  ) async {
    FoundationShell shell(ReadinessState state) => FoundationShell(
      state: state,
      servers: const Text('private profile list'),
      settings: const Text('private settings'),
      targetName: 'private target',
      targetAddress: '192.0.2.1',
    );
    await tester.pumpWidget(app(shell(ReadinessState.ready)));
    expect(find.text('private profile list'), findsOneWidget);
    expect(find.textContaining('private target'), findsOneWidget);
    for (final state in ReadinessState.values.where(
      (state) => state != ReadinessState.ready,
    )) {
      await tester.pumpWidget(app(shell(state)));
      expect(find.text('private profile list'), findsNothing);
      expect(find.text('private settings'), findsNothing);
      expect(find.textContaining('private target'), findsNothing);
      expect(find.textContaining('192.0.2.1'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'wide navigation preserves local section across service failure',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(const FoundationShell(state: ReadinessState.ready)),
      );
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('Серверы'), findsNWidgets(2));
      await tester.tap(find.widgetWithText(OutlinedButton, 'ПО'));
      await tester.pump();
      expect(
        find.text('Управление ПО будет доступно после подключения к серверу'),
        findsOneWidget,
      );
      await tester.pumpWidget(
        app(const FoundationShell(state: ReadinessState.unavailable)),
      );
      expect(find.text('Локальная служба недоступна'), findsOneWidget);
      expect(find.text('ПО'), findsNWidgets(2));
      await tester.pumpWidget(
        app(const FoundationShell(state: ReadinessState.ready)),
      );
      expect(
        find.text('Управление ПО будет доступно после подключения к серверу'),
        findsOneWidget,
      );
    },
  );

  for (final dark in [false, true]) {
    for (final size in const [
      Size(1100, 760),
      Size(800, 600),
      Size(360, 800),
      Size(390, 800),
    ]) {
      testWidgets('all sections reachable at $size scale200 dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(
            const FoundationShell(state: ReadinessState.ready),
            dark: dark,
            scale: 2,
          ),
        );
        for (final section in FoundationSection.values) {
          if (size.width <= 800) {
            await tester.tap(find.byIcon(Icons.menu));
            await tester.pumpAndSettle();
          }
          final button = find.widgetWithText(OutlinedButton, section.label);
          await tester.ensureVisible(button);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(find.widgetWithText(AppBar, section.label), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('navigation supports keyboard activation', (tester) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(const FoundationShell(state: ReadinessState.ready)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.text('Управление ПО будет доступно после подключения к серверу'),
      findsOneWidget,
    );
  });
}
