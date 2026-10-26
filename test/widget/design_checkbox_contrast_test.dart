import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/models.dart';

import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_scenario_harness.dart';
import '../support/design_stock_capture.dart';
import '../support/design_stock_paint_support.dart';

Future<void> _choosePrivateKey(WidgetTester tester) async {
  await stockShow(tester, find.text('Без секрета / удалить'));
  await tester.tap(find.text('Без секрета / удалить'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Новый приватный ключ').last);
  await tester.pumpAndSettle();
}

Future<Map<String, Object>> _expectDisabledPaint(
  WidgetTester tester,
  GlobalKey boundary,
  bool checked,
) async {
  final tile = find.byType(CheckboxListTile);
  await stockShow(tester, tile);
  final widget = tester.widget<CheckboxListTile>(tile);
  expect(widget.value, checked);
  expect(widget.onChanged, isNull);
  final semantics = tester
      .getSemantics(tile)
      .getSemanticsData()
      .flagsCollection;
  expect(semantics.isEnabled, ui.Tristate.isFalse);
  expect(
    semantics.isChecked,
    checked ? ui.CheckedState.isTrue : ui.CheckedState.isFalse,
  );
  final checkbox = find.descendant(of: tile, matching: find.byType(Checkbox));
  final rect = tester.getRect(checkbox);
  // CheckboxListTile delegates the complete row hit target to its ListTile.
  expect(tester.getSize(tile).width, greaterThanOrEqualTo(44));
  expect(tester.getSize(tile).height, greaterThanOrEqualTo(44));
  final raster = await StockPaintRaster.capture(tester, boundary);
  final center = rect.center;
  // Sample the real composited Material immediately beside the 18px glyph.
  final background = raster.pixel(center + const Offset(13, 0));
  final glyph = Rect.fromCenter(center: center, width: 18, height: 18);
  final foreground = raster.dominant(glyph, excluding: background);
  final interior = raster.dominant(
    Rect.fromCenter(center: center, width: 10, height: 10),
  );
  expect(
    interior == background,
    !checked,
    reason: 'Checked has a painted fill; unchecked keeps its hollow center',
  );
  final ratio = stockContrast(foreground, background);
  expect(
    ratio,
    greaterThanOrEqualTo(3),
    reason:
        'Disabled checked=$checked glyph actually paints $foreground '
        'against Material $background: $ratio:1',
  );
  Color? tick;
  double? tickContrast;
  if (checked) {
    final interiorRect = Rect.fromCenter(center: center, width: 10, height: 10);
    tick = raster.dominant(interiorRect, excluding: foreground);
    expect(
      raster.histogram(interiorRect)[tick],
      greaterThanOrEqualTo(4),
      reason: 'Checked tick must actually paint solid glyph pixels',
    );
    tickContrast = stockContrast(tick, foreground);
    expect(
      tickContrast,
      greaterThanOrEqualTo(3),
      reason:
          'Actual tick $tick must contrast with actual checked fill $foreground',
    );
  }
  return {
    'foregroundArgb': foreground.toARGB32(),
    'backgroundArgb': background.toARGB32(),
    'glyphContrast': ratio,
    'interiorArgb': interior.toARGB32(),
    'checked': checked,
    'semanticsEnabled': false,
    'semanticsChecked': checked,
    if (tick != null) 'tickArgb': tick.toARGB32(),
    if (tickContrast != null) 'tickContrast': tickContrast,
  };
}

void main() {
  setUpAll(loadDesignFonts);
  for (final width in [360.0, 390.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final checked in [false, true]) {
          final theme = dark ? BrandTheme.dark : BrandTheme.light;
          testWidgets(
            'pending settings checkbox actual contrast width=$width dark=$dark scale=$scale checked=$checked',
            (tester) async {
              stockPaintFrame(tester, width);
              final semantics = tester.ensureSemantics();
              final boundary = GlobalKey();
              final harness = await DesignScenarioHarness.create();
              final pending = Completer<ApiReply>();
              harness.client.mutationGate = pending;
              try {
                await tester.pumpWidget(
                  stockPaintHost(
                    harness.buildOrigin('85-settings-form'),
                    boundaryKey: boundary,
                    theme: theme,
                    scale: scale,
                  ),
                );
                await tester.pumpAndSettle();
                final checkbox = find.byType(CheckboxListTile);
                await stockShow(tester, checkbox);
                if (tester.widget<CheckboxListTile>(checkbox).value !=
                    checked) {
                  await tester.tap(checkbox);
                  await tester.pumpAndSettle();
                }
                final save = find.text('Сохранить настройки');
                await stockShow(tester, save);
                await tester.tap(save);
                await tester.pumpAndSettle();
                expect(harness.client.mutations, hasLength(1));
                final paint = await _expectDisabledPaint(
                  tester,
                  boundary,
                  checked,
                );
                await captureStockPaint(
                  tester,
                  boundary: boundary,
                  family: 'disabled',
                  componentCaseId: 'disabled-settings',
                  caseId:
                      'disabled-settings-${width.toInt()}-${dark ? 'dark' : 'light'}-${(scale * 100).toInt()}-${checked ? 'checked' : 'unchecked'}',
                  originIds: const ['85-settings-form'],
                  productionOwners: const [
                    'lib/settings/settings_form.dart',
                    'lib/settings/settings_controller.dart',
                    'lib/theme/brand_theme.dart',
                  ],
                  components: const ['SettingsForm', 'CheckboxListTile'],
                  width: width,
                  theme: dark ? 'dark' : 'light',
                  scale: scale,
                  reducedMotion: true,
                  state: {
                    ...paint,
                    'pending': 'settings-save',
                    'capturedBeforeDuplicateAttempts': true,
                  },
                  counters: {
                    'mutationRequests': harness.client.mutations.length,
                    'statusRequests': harness.client.statusRequests.length,
                  },
                  limitations: const [
                    'Actual SettingsForm save handler through existing synthetic ModelClient gate; no native/local API effect claimed.',
                  ],
                );
                await tester.tap(checkbox);
                await tester.sendKeyEvent(LogicalKeyboardKey.space);
                await tester.sendKeyEvent(LogicalKeyboardKey.enter);
                await tester.pump();
                expect(
                  tester.widget<CheckboxListTile>(checkbox).value,
                  checked,
                );
                expect(harness.client.mutations, hasLength(1));
                expect(harness.client.statusRequests, isEmpty);
                expect(tester.takeException(), isNull);
              } finally {
                if (!pending.isCompleted) {
                  pending.completeError(
                    const LocalApiException(ErrorCode.timeout),
                  );
                }
                await tester.pumpAndSettle();
                await tester.pumpWidget(const SizedBox.shrink());
                await harness.close();
                semantics.dispose();
              }
            },
          );

          testWidgets(
            'pending picker checkbox actual contrast width=$width dark=$dark scale=$scale checked=$checked',
            (tester) async {
              stockPaintFrame(tester, width);
              final semantics = tester.ensureSemantics();
              final boundary = GlobalKey();
              final picker = Completer<String?>();
              final key = GlobalKey<CredentialInputState>();
              var pickerCalls = 0, submissions = 0;
              try {
                await tester.pumpWidget(
                  stockPaintHost(
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: CredentialInput(
                        key: key,
                        creating: true,
                        enabled: true,
                        pickKey: () {
                          pickerCalls++;
                          return picker.future;
                        },
                        onSubmit: () => submissions++,
                      ),
                    ),
                    boundaryKey: boundary,
                    theme: theme,
                    scale: scale,
                  ),
                );
                await tester.pumpAndSettle();
                await _choosePrivateKey(tester);
                final checkbox = find.byType(CheckboxListTile);
                await stockShow(tester, checkbox);
                if (checked) {
                  await tester.tap(checkbox);
                  await tester.pumpAndSettle();
                }
                final button = find.text('Выбрать файл ключа');
                await stockShow(tester, button);
                await tester.tap(button);
                await tester.pumpAndSettle();
                expect(pickerCalls, 1);
                expect(key.currentState!.picking, isTrue);
                final paint = await _expectDisabledPaint(
                  tester,
                  boundary,
                  checked,
                );
                await captureStockPaint(
                  tester,
                  boundary: boundary,
                  family: 'disabled',
                  componentCaseId: 'disabled-picker',
                  caseId:
                      'disabled-picker-${width.toInt()}-${dark ? 'dark' : 'light'}-${(scale * 100).toInt()}-${checked ? 'checked' : 'unchecked'}',
                  originIds: const ['12-credential-input'],
                  usageOriginIds: const [
                    '07-profile-create',
                    '08-profile-edit',
                  ],
                  productionOwners: const [
                    'lib/profiles/credential_input.dart',
                    'lib/theme/brand_theme.dart',
                  ],
                  components: const ['CredentialInput', 'CheckboxListTile'],
                  width: width,
                  theme: dark ? 'dark' : 'light',
                  scale: scale,
                  reducedMotion: true,
                  state: {
                    ...paint,
                    'pending': 'private-key-picker',
                    'capturedBeforeDuplicateAttempts': true,
                  },
                  counters: {
                    'pickerCallbacks': pickerCalls,
                    'submitCallbacks': submissions,
                  },
                  limitations: const [
                    'Actual CredentialInput picker handler with supplied pending Future; no native file picker or secret data used.',
                  ],
                );
                await tester.tap(checkbox);
                await tester.sendKeyEvent(LogicalKeyboardKey.space);
                await tester.sendKeyEvent(LogicalKeyboardKey.enter);
                await tester.pump();
                expect(key.currentState!.revealed, checked);
                expect(pickerCalls, 1);
                expect(submissions, 0);
                expect(tester.takeException(), isNull);
              } finally {
                if (!picker.isCompleted) picker.complete(null);
                await tester.pumpAndSettle();
                await tester.pumpWidget(const SizedBox.shrink());
                semantics.dispose();
              }
            },
          );
        }
      }
    }
  }
}
