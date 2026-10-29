import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/automation/automation_panel.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../support/design_fonts.dart';
import 'deck_components_test.dart' show pixels;

void main() {
  setUpAll(loadDesignFonts);
  testWidgets(
    'Jobs header keeps data actions and both workspace entries reachable',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      for (final dark in [false, true]) {
        for (final width in [1100.0, 800.0, 390.0, 360.0]) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = Size(width, 800);
            final calls = <String>[];
            final actions = [
              ...automationPageActions(
                section: 'jobs',
                availability: const AutomationActionAvailability(
                  read: true,
                  mutate: true,
                  select: true,
                ),
                onRefresh: () => calls.add('refresh'),
                onOpenJob: () => calls.add('job'),
                onCreate: () => calls.add('unexpected create'),
                onLoadRecipes: () => calls.add('unexpected recipes'),
              ),
              OutlinedButton(
                clipBehavior: Clip.none,
                onPressed: () => calls.add('grants'),
                child: const Text('ИИ-доступ'),
              ),
              OutlinedButton(
                clipBehavior: Clip.none,
                onPressed: () => calls.add('profiles'),
                child: const Text('Ansible-профили'),
              ),
            ];
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? BrandTheme.dark : BrandTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DeckPage(
                      title: 'Задания',
                      actions: actions,
                      child: const SizedBox(height: 20),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(calls, isEmpty);
            for (final action in actions) {
              final finder = find.byWidget(action);
              await tester.ensureVisible(finder);
              final rect = tester.getRect(finder);
              final reserve = width <= 520 ? 0.0 : 4.0;
              expect(rect.left + reserve, greaterThanOrEqualTo(16 - .01));
              expect(rect.right - reserve, lessThanOrEqualTo(width - 16 + .01));
              expect(rect.height, greaterThanOrEqualTo(44));
              await tester.tap(finder);
              await tester.pumpAndSettle();
            }
            expect(calls, ['refresh', 'job', 'grants', 'profiles']);
            expect(tester.takeException(), isNull);
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final frame in const [
    Size(1100, 760),
    Size(800, 600),
    Size(390, 800),
    Size(360, 800),
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('T184 visible controls and focus $frame $dark $scale', (
          tester,
        ) async {
          tester.view.physicalSize = frame;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final theme = dark ? BrandTheme.dark : BrandTheme.light;
          final colors = theme.extension<BrandColors>()!;
          final phone = frame.width <= 520;
          for (final kind in ['filled', 'outlined', 'text']) {
            final node = FocusNode(), boundary = GlobalKey();
            var effects = 0;
            Widget button(bool enabled) {
              final VoidCallback? action = enabled ? () => effects++ : null;
              return switch (kind) {
                'filled' => FilledButton(
                  clipBehavior: Clip.none,
                  focusNode: node,
                  onPressed: action,
                  child: const Text('Действие'),
                ),
                'outlined' => OutlinedButton(
                  clipBehavior: Clip.none,
                  focusNode: node,
                  onPressed: action,
                  child: const Text('Действие'),
                ),
                _ => TextButton(
                  clipBehavior: Clip.none,
                  focusNode: node,
                  onPressed: action,
                  child: const Text('Действие'),
                ),
              };
            }

            Future<void> pump(bool enabled) async {
              await tester.pumpWidget(
                MaterialApp(
                  theme: theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: RepaintBoundary(
                        key: boundary,
                        child: ColoredBox(
                          color: colors['raised'],
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: SizedBox(width: 200, child: button(enabled)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
            }

            try {
              await pump(true);
              final actual = find.byWidgetPredicate(
                (widget) =>
                    widget is ButtonStyleButton && widget.focusNode == node,
              );
              expect(actual, findsOneWidget);
              // Use the actual control bounds, not the requested minimumSize.
              final rect = tester.getRect(actual);
              expect(rect.height, closeTo(20 * scale + 24, .01));
              expect(rect.width, greaterThanOrEqualTo(44));
              final origin = tester.getTopLeft(find.byKey(boundary));
              final controlLeft = rect.left - origin.dx + (phone ? 0 : 4);
              final centerY = rect.center.dy - origin.dy;
              final normal = await pixels(tester, boundary, [
                Offset(controlLeft + 3, centerY),
              ]);
              expect(
                normal.single,
                colors[kind == 'filled'
                    ? 'accent'
                    : kind == 'outlined'
                    ? 'surface'
                    : 'raised'],
              );
              node.requestFocus();
              await tester.pumpAndSettle();
              final focusX = rect.left - origin.dx + (phone ? -3 : 1);
              final gapX = rect.left - origin.dx + (phone ? -1 : 3);
              final focus = await pixels(tester, boundary, [
                Offset(focusX, centerY),
                Offset(gapX, centerY),
              ]);
              expect(focus.first, colors['focus']);
              expect(focus.last, colors['raised']);
              await pump(false);
              await tester.tap(actual);
              await tester.pumpAndSettle();
              expect(effects, 0);
              expect(tester.takeException(), isNull);
              // The label remains complete in every state.
              expect(find.text('Действие'), findsOneWidget);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              node.dispose();
            }
          }
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton(
                        clipBehavior: Clip.none,
                        style: const ButtonStyle(
                          padding: WidgetStatePropertyAll(EdgeInsets.all(4)),
                        ),
                        onPressed: () {},
                        child: const Text('Собственное поле'),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.add, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final custom = find.widgetWithText(TextButton, 'Собственное поле');
          expect(
            tester.getSize(custom).width,
            closeTo(
              tester.getSize(find.text('Собственное поле')).width + 8,
              .01,
            ),
          );
          expect(tester.getSize(find.byType(IconButton)), const Size(44, 44));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
        testWidgets('T184 header and grant bar grow $frame $dark $scale', (
          tester,
        ) async {
          tester.view.physicalSize = frame;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var effects = 0;
          void action() => effects++;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? BrandTheme.dark : BrandTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DeckPage(
                    title: 'Доступ ИИ',
                    actions: [
                      OutlinedButton(
                        clipBehavior: Clip.none,
                        onPressed: action,
                        child: const Text('Коротко'),
                      ),
                      OutlinedButton(
                        clipBehavior: Clip.none,
                        onPressed: action,
                        child: const Text('Длинное действие'),
                      ),
                    ],
                    child: AutomationGrantsSection(
                      grants: const [],
                      loaded: true,
                      showHeaderActions: false,
                      actions: const AutomationActionAvailability(
                        read: true,
                        mutate: true,
                        select: true,
                      ),
                      onRefresh: action,
                      onCreate: action,
                      onCopyConfiguration: action,
                      onConfigure: (_) => action(),
                      onEdit: (_) => action(),
                      onRevoke: (_) => action(),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final first = find.widgetWithText(OutlinedButton, 'Коротко');
          final second = find.widgetWithText(
            OutlinedButton,
            'Длинное действие',
          );
          final width = frame.width - 32;
          if (frame.width <= 520) {
            final a = tester.getRect(first), b = tester.getRect(second);
            if ((a.top - b.top).abs() < .01) {
              expect(a.width + 8 + b.width, closeTo(width, .01));
              expect(b.left - a.right, closeTo(8, .01));
              expect(b.width, greaterThan(a.width));
            } else {
              expect(a.width, closeTo(width, .01));
              expect(b.width, closeTo(width, .01));
              expect(b.top - a.bottom, closeTo(8, .01));
            }
            final revoke = find.widgetWithText(OutlinedButton, 'Отозвать');
            final configure = find.widgetWithText(
              OutlinedButton,
              'Конфигурация MCP',
            );
            await tester.ensureVisible(configure);
            await tester.pumpAndSettle();
            final r = tester.getRect(revoke), c = tester.getRect(configure);
            final panel = find.byWidgetPredicate(
              (widget) =>
                  widget is DeckPanel && widget.title == 'Область просмотра',
            );
            expect(r.top - tester.getRect(panel).bottom, 16);
            if ((r.top - c.top).abs() < .01) {
              expect(r.width + 8 + c.width, closeTo(width, .01));
              if (scale == 1) expect(r.width, closeTo(c.width, .01));
            } else {
              expect(r.width, closeTo(width, .01));
              expect(c.width, closeTo(width, .01));
            }
          }
          expect(effects, 0);
          await tester.ensureVisible(first);
          await tester.tap(first);
          await tester.pumpAndSettle();
          expect(effects, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
  testWidgets('T184 action focus survives theme, scale and phone breakpoints', (
    tester,
  ) async {
    final header = FocusNode(), bar = FocusNode();
    var headerCalls = 0, barCalls = 0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    Future<void> pump(double width, bool dark, double scale) async {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? BrandTheme.dark : BrandTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: DeckPage(
                title: 'Проверка фокуса',
                actions: [
                  OutlinedButton(
                    clipBehavior: Clip.none,
                    focusNode: header,
                    onPressed: () => headerCalls++,
                    child: const Text('Основное действие'),
                  ),
                  OutlinedButton(
                    clipBehavior: Clip.none,
                    onPressed: () {},
                    child: const Text('Другое действие'),
                  ),
                ],
                child: DeckActions(
                  phoneBasis: 130,
                  children: [
                    OutlinedButton(
                      clipBehavior: Clip.none,
                      focusNode: bar,
                      onPressed: () => barCalls++,
                      child: const Text('Действие списка'),
                    ),
                    OutlinedButton(
                      clipBehavior: Clip.none,
                      onPressed: () {},
                      child: const Text('Другой выбор'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    try {
      await pump(1100, false, 1);
      header.requestFocus();
      await tester.pumpAndSettle();
      for (final node in [header, bar]) {
        node.requestFocus();
        await tester.pumpAndSettle();
        for (final dark in [false, true]) {
          for (final width in [1100.0, 390.0, 800.0, 360.0]) {
            for (final scale in [1.0, 2.0]) {
              await pump(width, dark, scale);
              expect(
                node.hasPrimaryFocus,
                isTrue,
                reason: '$width $dark $scale',
              );
              expect(tester.takeException(), isNull);
            }
          }
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      }
      expect(headerCalls, 1);
      expect(barCalls, 1);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      header.dispose();
      bar.dispose();
    }
  });
}
