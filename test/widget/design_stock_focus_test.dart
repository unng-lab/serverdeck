import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';

import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_scenario_harness.dart';
import '../support/design_stock_capture.dart';
import '../support/design_stock_paint_support.dart';

Finder _tile(Finder label) =>
    find.ancestor(of: label, matching: find.byType(ListTile)).first;

Future<Map<String, Object>> _expectFocusOutline(
  WidgetTester tester,
  GlobalKey boundary,
  Finder text,
  ThemeData theme,
) async {
  final raster = await StockPaintRaster.capture(tester, boundary);
  final rect = tester.getRect(text);
  final y = rect.center.dy;
  final row = [
    for (final delta in [-4.0, -3.0, -2.0, -1.0])
      raster.pixel(Offset(rect.left + delta, y)),
  ];
  final focus = theme.extension<BrandColors>()!['focus'];
  final background = raster.dominant(rect);
  expect(row, [
    focus,
    focus,
    background,
    background,
  ], reason: 'Keyboard focus must paint its 2px outline and 2px gap');
  expect(stockContrast(focus, background), greaterThanOrEqualTo(3));
  return {
    'focusArgb': focus.toARGB32(),
    'backgroundArgb': background.toARGB32(),
    'leftSampleArgb': [for (final color in row) color.toARGB32()],
    'outlineWidth': 2,
    'gap': 2,
    'indicatorContrast': stockContrast(focus, background),
  };
}

Future<void> _expectNoClosedLabelOutline(
  WidgetTester tester,
  GlobalKey boundary,
  Finder text,
  ThemeData theme,
) async {
  final raster = await StockPaintRaster.capture(tester, boundary);
  final rect = tester.getRect(text);
  final focus = theme.extension<BrandColors>()!['focus'];
  for (final delta in [-4.0, -3.0, -2.0, -1.0]) {
    expect(
      raster.pixel(Offset(rect.left + delta, rect.center.dy)),
      isNot(focus),
      reason: 'Closed form retains its InputDecorator outline; no second label ring',
    );
  }
}

void main() {
  setUpAll(loadDesignFonts);
  for (final width in [360.0, 390.0]) {
    for (final dark in [false, true]) {
      final theme = dark ? BrandTheme.dark : BrandTheme.light;
      for (final scenario in ['credential', 'settings', 'profile', 'log']) {
        testWidgets(
          'stock focus $scenario actual paint width=$width dark=$dark scale=2',
          (tester) async {
            stockPaintFrame(tester, width);
            final semantics = tester.ensureSemantics();
            final boundary = GlobalKey();
            final harness = await DesignScenarioHarness.create();
            try {
              final child = switch (scenario) {
                'credential' => const SingleChildScrollView(
                  padding: EdgeInsets.all(24),
                  child: CredentialInput(creating: true, enabled: true),
                ),
                'settings' => harness.buildOrigin('85-settings-form'),
                'profile' => harness.buildOrigin('05-server-list'),
                _ => SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: harness.buildOrigin('22-server-logs'),
                ),
              };
              await tester.pumpWidget(
                stockPaintHost(child, boundaryKey: boundary, theme: theme),
              );
              await tester.pumpAndSettle();
              if (scenario == 'credential') {
                await stockShow(tester, find.text('Без секрета / удалить'));
                await tester.tap(find.text('Без секрета / удалить'));
                await tester.pumpAndSettle();
                await tester.tap(find.text('Новый пароль').last);
                await tester.pumpAndSettle();
              }
              final label = switch (scenario) {
                'credential' => find.text('Показать введённый секрет'),
                'settings' => find.text('Уменьшение анимации'),
                'profile' => find.text(harness.initialProfile.name),
                _ => find.textContaining(' UTC').last,
              };
              final tile = _tile(label);
              await stockTabTo(tester, tile);
              expect(stockContainsFocus(tester, tile), isTrue);
              expect(tester.getSize(tile).height, greaterThanOrEqualTo(44));
              final paint = await stockExpectReadable(tester, boundary, label);
              Map<String, Object>? subtitlePaint;
              if (scenario == 'log') {
                final subtitle = find.descendant(
                  of: tile,
                  matching: find.byWidgetPredicate(
                    (widget) => widget is Text && widget.maxLines == 4,
                  ),
                );
                subtitlePaint = await stockExpectReadable(
                  tester,
                  boundary,
                  subtitle,
                );
              }
              final outline = await _expectFocusOutline(
                tester,
                boundary,
                label,
                theme,
              );
              expect(harness.client.mutations, isEmpty);
              await captureStockPaint(
                tester,
                boundary: boundary,
                family: 'focus',
                componentCaseId: 'focus-$scenario',
                caseId:
                    'focus-$scenario-${width.toInt()}-${dark ? 'dark' : 'light'}-200',
                originIds: [
                  switch (scenario) {
                    'credential' => '12-credential-input',
                    'settings' => '85-settings-form',
                    'profile' => '05-server-list',
                    _ => '22-server-logs',
                  },
                ],
                productionOwners: [
                  switch (scenario) {
                    'credential' => 'lib/profiles/credential_input.dart',
                    'settings' => 'lib/settings/settings_form.dart',
                    'profile' => 'lib/profiles/profile_list.dart',
                    _ => 'lib/servers/server_sections.dart',
                  },
                  'lib/ui/deck_components.dart',
                  'lib/theme/brand_theme.dart',
                ],
                components: [
                  switch (scenario) {
                    'credential' => 'CredentialInput',
                    'settings' => 'SettingsForm',
                    'profile' => 'ProfileList',
                    _ => 'ServerLogsSection',
                  },
                  scenario == 'credential' || scenario == 'settings'
                      ? 'CheckboxListTile'
                      : scenario == 'profile'
                      ? 'ExpansionTile'
                      : 'ListTile',
                ],
                width: width,
                theme: dark ? 'dark' : 'light',
                scale: 2,
                reducedMotion: true,
                state: {
                  'focused': true,
                  'keyboardTraversal': 'Tab',
                  'textPaint': paint,
                  if (subtitlePaint != null) 'subtitlePaint': subtitlePaint,
                  'focusOutline': outline,
                  if (scenario == 'credential' || scenario == 'settings')
                    'checked': tester
                        .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                        .value,
                  'capturedBeforeActivation': true,
                },
                counters: {
                  ...harness.counters.values,
                  'mutationRequests': harness.client.mutations.length,
                  'statusRequests': harness.client.statusRequests.length,
                },
                limitations: const [
                  'Production widget with existing synthetic ModelClient/display seam; no native, SSH or API lifecycle acceptance.',
                ],
              );
              if (scenario == 'credential' || scenario == 'settings') {
                final checkbox = find.byType(CheckboxListTile);
                final before = tester.widget<CheckboxListTile>(checkbox).value!;
                final beforeSemantics = tester
                    .getSemantics(checkbox)
                    .getSemanticsData();
                expect(
                  beforeSemantics.flagsCollection.isEnabled,
                  ui.Tristate.isTrue,
                );
                await tester.sendKeyEvent(LogicalKeyboardKey.space);
                await tester.pumpAndSettle();
                expect(
                  tester.widget<CheckboxListTile>(checkbox).value,
                  !before,
                );
                expect(
                  tester
                      .getSemantics(checkbox)
                      .getSemanticsData()
                      .flagsCollection
                      .isChecked,
                  before ? ui.CheckedState.isFalse : ui.CheckedState.isTrue,
                );
              } else if (scenario == 'profile') {
                await tester.sendKeyEvent(LogicalKeyboardKey.enter);
                await tester.pumpAndSettle();
                expect(
                  find.text('Пользователь SSH: admin').hitTestable(),
                  findsOneWidget,
                );
              } else {
                await tester.sendKeyEvent(LogicalKeyboardKey.enter);
                await tester.pumpAndSettle();
                expect(harness.counters['openRecord'], 1);
                expect(harness.counters['readLogs'], 0);
              }
              expect(harness.client.mutations, isEmpty);
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await harness.close();
              semantics.dispose();
            }
          },
        );
      }

      testWidgets(
        'normal dropdown real keyboard popup paint width=$width dark=$dark scale=2',
        (tester) async {
          stockPaintFrame(tester, width);
          final boundary = GlobalKey();
          var calls = 0;
          String? selected;
          await tester.pumpWidget(
            stockPaintHost(
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: MotionDropdown<String>(
                  initialValue: 'one',
                  decoration: const InputDecoration(labelText: 'Режим'),
                  items: const [
                    DropdownMenuItem(value: 'one', child: Text('Первый режим')),
                    DropdownMenuItem(value: 'two', child: Text('Второй режим')),
                  ],
                  onChanged: (value) {
                    calls++;
                    selected = value;
                  },
                ),
              ),
              boundaryKey: boundary,
              theme: theme,
              reduced: false,
            ),
          );
          await tester.pumpAndSettle();
          final dropdown = find.byType(DropdownButtonFormField<String>);
          expect(dropdown, findsOneWidget);
          final closedText = find.text('Первый режим').first;
          final closedRect = tester.getRect(closedText);
          await stockTabTo(tester, dropdown);
          expect(tester.getRect(closedText), closedRect);
          await _expectNoClosedLabelOutline(
            tester,
            boundary,
            closedText,
            theme,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          final label = find.text('Второй режим').last;
          final item = find
              .ancestor(of: label, matching: find.byType(InkWell))
              .first;
          expect(stockContainsFocus(tester, item), isTrue);
          expect(tester.getSize(item).height, greaterThanOrEqualTo(44));
          final paint = await stockExpectReadable(tester, boundary, label);
          final outline = await _expectFocusOutline(
            tester,
            boundary,
            label,
            theme,
          );
          expect(calls, 0);
          await captureStockPaint(
            tester,
            boundary: boundary,
            family: 'focus',
            componentCaseId: 'focus-motion-dropdown',
            caseId:
                'focus-motion-dropdown-${width.toInt()}-${dark ? 'dark' : 'light'}-200',
            originIds: const [],
            usageOriginIds: const [
              '07-profile-create',
              '08-profile-edit',
              '12-credential-input',
              '85-settings-form',
            ],
            productionOwners: const [
              'lib/theme/motion.dart',
              'lib/ui/deck_components.dart',
              'lib/theme/brand_theme.dart',
            ],
            components: const ['MotionDropdown', 'DropdownButtonFormField'],
            width: width,
            theme: dark ? 'dark' : 'light',
            scale: 2,
            reducedMotion: false,
            state: {
              'focused': true,
              'keyboardTraversal': 'Tab, Enter, ArrowDown',
              'textPaint': paint,
              'focusOutline': outline,
              'selectedBeforeActivation': 'one',
              'focusedValue': 'two',
              'capturedBeforeActivation': true,
            },
            counters: {'selectionCallbacks': calls},
            limitations: const [
              'Isolated production component case with supplied display values; usage origins are references, not runtime origin acceptance.',
            ],
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(calls, 1);
          expect(selected, 'two');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );

      testWidgets(
        'resource dropdown real keyboard popup paint width=$width dark=$dark scale=2',
        (tester) async {
          stockPaintFrame(tester, width);
          final boundary = GlobalKey();
          var changes = 0, reads = 0;
          String? selected;
          await tester.pumpWidget(
            stockPaintHost(
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ServerConfigurationSection(
                  resource: 'system.motd',
                  busy: false,
                  onResourceChanged: (value) {
                    changes++;
                    selected = value;
                  },
                  onRead: () => reads++,
                ),
              ),
              boundaryKey: boundary,
              theme: theme,
              reduced: false,
            ),
          );
          await tester.pumpAndSettle();
          final dropdown = find.byType(DropdownButtonFormField<String>);
          final closedText = find.text('Приветствие сервера').first;
          final closedRect = tester.getRect(closedText);
          await stockTabTo(tester, dropdown);
          expect(tester.getRect(closedText), closedRect);
          await _expectNoClosedLabelOutline(
            tester,
            boundary,
            closedText,
            theme,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          final label = find.text('Служба PostgreSQL').last;
          final item = find
              .ancestor(of: label, matching: find.byType(InkWell))
              .first;
          expect(stockContainsFocus(tester, item), isTrue);
          expect(tester.getSize(item).height, greaterThanOrEqualTo(44));
          final paint = await stockExpectReadable(tester, boundary, label);
          final outline = await _expectFocusOutline(
            tester,
            boundary,
            label,
            theme,
          );
          expect(changes, 0);
          expect(reads, 0);
          await captureStockPaint(
            tester,
            boundary: boundary,
            family: 'focus',
            componentCaseId: 'focus-resource-dropdown',
            caseId:
                'focus-resource-dropdown-${width.toInt()}-${dark ? 'dark' : 'light'}-200',
            originIds: const [],
            productionOwners: const [
              'lib/servers/server_sections.dart',
              'lib/servers/server_panel.dart',
              'lib/ui/deck_components.dart',
              'lib/theme/brand_theme.dart',
            ],
            components: const [
              'ServerConfigurationSection',
              'DropdownButtonFormField',
            ],
            width: width,
            theme: dark ? 'dark' : 'light',
            scale: 2,
            reducedMotion: false,
            state: {
              'focused': true,
              'keyboardTraversal': 'Tab, Enter, ArrowDown',
              'textPaint': paint,
              'focusOutline': outline,
              'selectedBeforeActivation': 'system.motd',
              'focusedValue': 'postgresql.service',
              'capturedBeforeActivation': true,
            },
            counters: {'selectionCallbacks': changes, 'readCallbacks': reads},
            limitations: const [
              'Extracted production ServerConfigurationSection without owning ServerPanel lifecycle; component case only.',
            ],
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(changes, 1);
          expect(selected, 'postgresql.service');
          expect(reads, 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
