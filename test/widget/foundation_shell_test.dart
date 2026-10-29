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
Finder nav(FoundationSection section) =>
    find.byKey(ValueKey('foundation-navigation-${section.name}'));
void main() {
  testWidgets('private content removed on every loss of readiness', (
    tester,
  ) async {
    for (final state in ReadinessState.values) {
      await tester.pumpWidget(
        app(
          FoundationShell(
            state: state,
            servers: const Text('private profiles'),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text('private profiles'),
        state == ReadinessState.ready ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });
  for (final dark in [false, true]) {
    for (final size in [
      const Size(1100, 760),
      const Size(800, 600),
      const Size(390, 800),
      const Size(360, 800),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('canonical shell $size scale$scale dark$dark allsections', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            app(
              FoundationShell(
                state: ReadinessState.ready,
                servers: const Text('profiles-pane'),
                software: const Text('software-pane'),
                logs: const Text('logs-pane'),
                jobs: const Text('jobs-pane'),
                settings: const Text('settings-pane'),
              ),
              dark: dark,
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          if (size.width > 520) {
            final badge = find.text('LW');
            final label = tester.widget<Text>(badge);
            final text = TextPainter(
              text: TextSpan(text: label.data, style: label.style),
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.linear(scale),
            )..layout();
            expect(
              tester.getSize(badge).width,
              greaterThanOrEqualTo(text.width - .01),
            );
            expect(
              tester.getSize(badge).height,
              greaterThanOrEqualTo(text.height - .01),
            );
            text.dispose();
          }
          final sidebar = tester.getRect(
            find.byKey(const ValueKey('foundation-sidebar')),
          );
          final topbar = tester.getRect(
            find.byKey(const ValueKey('foundation-topbar')),
          );
          expect(
            sidebar.width,
            size.width <= 520
                ? 0
                : size.width <= 1060
                ? 68
                : 210,
          );
          expect(sidebar.top, 0);
          expect(topbar.left, sidebar.right);
          expect(
            topbar.height,
            scale == 1
                ? (size.width <= 520 ? 62 : 56)
                : greaterThanOrEqualTo(size.width <= 520 ? 62 : 56),
          );
          for (final section in FoundationSection.values) {
            await tester.ensureVisible(nav(section));
            expect(
              tester.getSize(nav(section)).height,
              greaterThanOrEqualTo(44),
            );
            expect(
              tester.getSize(nav(section)).width,
              greaterThanOrEqualTo(44),
            );
            await tester.tap(nav(section));
            await tester.pumpAndSettle();
            final text = switch (section) {
              FoundationSection.servers => 'profiles-pane',
              FoundationSection.software => 'software-pane',
              FoundationSection.logs => 'logs-pane',
              FoundationSection.jobs => 'jobs-pane',
              FoundationSection.settings => 'settings-pane',
            };
            expect(find.text(text), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }
  testWidgets(
    'navigation is keyboard activated and invokes no content command',
    (tester) async {
      var commands = 0;
      await tester.pumpWidget(
        app(
          FoundationShell(
            state: ReadinessState.ready,
            servers: TextButton(
              onPressed: () => commands++,
              child: const Text('command'),
            ),
            software: const Text('software-pane'),
          ),
        ),
      );
      final button = tester.widget<TextButton>(nav(FoundationSection.software));
      button.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('software-pane'), findsOneWidget);
      expect(commands, 0);
    },
  );
  testWidgets('section survives service loss and recovers same section', (
    tester,
  ) async {
    Widget current(ReadinessState state) => app(
      FoundationShell(state: state, software: const Text('software-pane')),
    );
    await tester.pumpWidget(current(ReadinessState.ready));
    await tester.tap(nav(FoundationSection.software));
    await tester.pump();
    await tester.pumpWidget(current(ReadinessState.unavailable));
    expect(find.text('software-pane'), findsNothing);
    await tester.pumpWidget(current(ReadinessState.ready));
    expect(find.text('software-pane'), findsOneWidget);
  });
  testWidgets('resize theme and scale preserve permitted feature draft', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var creations = 0;
    for (final width in [1100.0, 390.0, 800.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 760);
      await tester.pumpWidget(
        app(
          FoundationShell(
            state: ReadinessState.ready,
            servers: _RetainedInput(onCreate: () => creations++),
          ),
          dark: width == 390,
          scale: width == 800 ? 2 : 1,
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('retained-field'));
      if (width == 1100 &&
          tester.widget<TextField>(field).controller!.text.isEmpty)
        await tester.enterText(field, 'RAM draft');
      expect(tester.widget<TextField>(field).controller!.text, 'RAM draft');
      expect(creations, 1);
      expect(tester.takeException(), isNull);
    }
  });
}

class _RetainedInput extends StatefulWidget {
  const _RetainedInput({required this.onCreate});
  final VoidCallback onCreate;
  @override
  State<_RetainedInput> createState() => _RetainedInputState();
}

class _RetainedInputState extends State<_RetainedInput> {
  final controller = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TextField(key: const ValueKey('retained-field'), controller: controller);
}
