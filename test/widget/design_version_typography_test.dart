import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/theme/brand_assets.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';

import '../support/design_automation_fixtures.dart';
import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_server_fixtures.dart';
import '../support/design_stock_capture.dart';
import '../support/design_stock_paint_support.dart' show StockPaintRaster;

const _monoReference = 'Version bundled mono reference';
const _available = AutomationActionAvailability(
  read: true,
  mutate: true,
  select: true,
);

Future<void> _show(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .4);
  await tester.pumpAndSettle();
}

String _plain(Text widget) => widget.data ?? widget.textSpan!.toPlainText();

TextStyle _styleAt(InlineSpan root, int target) {
  var cursor = 0;
  TextStyle? result;
  void visit(TextSpan span, TextStyle inherited) {
    final effective = inherited.merge(span.style);
    final text = span.text ?? '';
    if (target >= cursor && target < cursor + text.length) result = effective;
    cursor += text.length;
    for (final child in span.children ?? <InlineSpan>[]) {
      visit(child as TextSpan, effective);
    }
  }

  visit(root as TextSpan, const TextStyle());
  return result!;
}

void main() {
  setUpAll(() async {
    await loadDesignFonts();
    await (FontLoader(
      _monoReference,
    )..addFont(rootBundle.load(BrandAssets.monoRegularFont))).load();
  });

  for (final frame in const [
    Size(1100, 760),
    Size(800, 600),
    Size(390, 800),
    Size(360, 800),
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final site in [
          'recipe-header',
          'plan-effect',
          'configuration-recipe',
          'executor-runtime',
        ]) {
          testWidgets(
            'version $site actual mono glyphs frame=${frame.width.toInt()}x${frame.height.toInt()} dark=$dark scale=$scale',
            (tester) async {
              tester.view.physicalSize = frame;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final boundary = GlobalKey();
              final changes = ChangeNotifier();
              final recipe = DesignAutomationFixtures.recipe();
              final catalog = DesignAutomationFixtures.catalog();
              final plan = DesignAutomationFixtures.plan();
              final version = site == 'executor-runtime'
                  ? DesignServerFixtures.executor().runtimeVersion
                  : recipe['version'] as String;
              final inspection = DesignServerFixtures.executorInspection();
              final executorProfile = DesignServerFixtures.profile();
              final beforeRecipe = jsonEncode(recipe);
              final beforeInspection = jsonEncode(inspection);
              final calls = <String, int>{};
              final digests = <String>[];
              void call(String action) =>
                  calls.update(action, (value) => value + 1, ifAbsent: () => 1);
              // Synthetic display projection through the actual production
              // plan widget. It grants no authority and invokes no client.
              plan['effects'] = [
                {
                  'id': 'install',
                  'sourceStepId': 'install',
                  'kind': 'install_recipe',
                  'recipeDigest': recipe['digest'],
                  'version': recipe['version'],
                },
              ];
              (plan['preflight'] as Map<String, Object?>)['recipes'] = [recipe];
              final comparison = <String, Object?>{
                'observation': {
                  'resourceId': 'postgresql.service',
                  'status': 'known',
                  'value': {'exists': true},
                },
                'comparison': {
                  'differences': <Map<String, Object?>>[],
                  'observedAt': DesignServerFixtures.observedAt,
                  'confirmedAt': DesignServerFixtures.observedAt,
                  'basis': 'recipe',
                },
                'desired': {'desiredRevision': '7'},
                'expected': {
                  'kind': 'recipe',
                  'id': 'postgresql16',
                  'version': recipe['version'],
                },
              };
              final content = switch (site) {
                'recipe-header' => AutomationRecipesSection(
                  catalog: catalog,
                  canMutate: true,
                  onCreatePlan: (digest) {
                    digests.add(digest);
                    call('createPlan');
                  },
                ),
                'plan-effect' => AutomationPlanSection(
                  plan: plan,
                  serverProfiles: [
                    DesignServerFixtures.profile(connectionRevision: '2'),
                  ],
                  automationProfile: DesignAutomationFixtures.profile(),
                  runnable: true,
                  expired: false,
                  actions: _available,
                  onApprove: () => call('approve'),
                  onDeny: () => call('deny'),
                  onApply: () => call('apply'),
                  onRefresh: () => call('refresh'),
                ),
                'configuration-recipe' => ServerConfigurationResult(
                  value: comparison,
                  comparisonStatus: 'matched',
                ),
                _ => ServerExecutorConfirmation(
                  inspection: inspection,
                  profile: executorProfile,
                  changes: changes,
                  currentProfile: () => executorProfile,
                  currentInspection: () => inspection,
                  onCancel: () => call('cancel'),
                  onConfirm: () => call('confirm'),
                ),
              };
              try {
                await tester.pumpWidget(
                  RepaintBoundary(
                    key: boundary,
                    child: MaterialApp(
                      theme: Motion.theme(
                        dark ? BrandTheme.dark : BrandTheme.light,
                        true,
                      ),
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          disableAnimations: true,
                          textScaler: TextScaler.linear(scale),
                        ),
                        child: child!,
                      ),
                      home: Scaffold(
                        body: site == 'executor-runtime'
                            ? content
                            : SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: content,
                              ),
                      ),
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                if (site == 'executor-runtime') {
                  await _show(tester, find.text('Технические сведения'));
                  await tester.tap(find.text('Технические сведения'));
                  await tester.pumpAndSettle();
                }
                final selectable = site == 'executor-runtime';
                final value = selectable
                    ? find.byWidgetPredicate(
                        (widget) =>
                            widget is EditableText &&
                            widget.controller.text == version,
                      )
                    : find.byWidgetPredicate(
                        (widget) =>
                            widget is Text && _plain(widget).contains(version),
                      );
                expect(value, findsOneWidget);
                await _show(tester, value);
                final RenderBox render;
                final InlineSpan text;
                final TextScaler scaler;
                final List<TextBox> Function(TextSelection) boxes;
                var didExceedMaxLines = false;
                if (selectable) {
                  final editable = tester
                      .state<EditableTextState>(value)
                      .renderEditable;
                  render = editable;
                  text = editable.text!;
                  scaler = editable.textScaler;
                  boxes = editable.getBoxesForSelection;
                  final editor = tester.widget<EditableText>(value);
                  expect(editor.readOnly, isTrue);
                  expect(editor.selectionEnabled, isTrue);
                  expect(editor.maxLines, isNull);
                } else {
                  final paragraph = tester.renderObject<RenderParagraph>(value);
                  render = paragraph;
                  text = paragraph.text;
                  scaler = paragraph.textScaler;
                  boxes = paragraph.getBoxesForSelection;
                  didExceedMaxLines = paragraph.didExceedMaxLines;
                  expect(didExceedMaxLines, isFalse);
                }
                final plain = text.toPlainText();
                final start = plain.indexOf(version);
                expect(start, greaterThanOrEqualTo(0));
                if (site == 'plan-effect') {
                  expect(
                    plain,
                    'Установить ПО по точному рецепту · версия $version',
                  );
                } else if (site == 'configuration-recipe') {
                  expect(plain, 'Рецепт: postgresql16 $version');
                  expect(find.text('Желаемая версия: 7'), findsOneWidget);
                }
                final style = _styleAt(text, start);
                final reference = TextPainter(
                  text: TextSpan(
                    text: version,
                    style: TextStyle(
                      fontFamily: _monoReference,
                      fontSize: 13,
                      height: 20 / 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: style.letterSpacing,
                      wordSpacing: style.wordSpacing,
                      fontFeatures: style.fontFeatures,
                      fontVariations: style.fontVariations,
                    ),
                  ),
                  textDirection: TextDirection.ltr,
                  textScaler: scaler,
                )..layout();
                try {
                  for (
                    var index = 0;
                    index < math.min(8, version.length);
                    index++
                  ) {
                    final actual = boxes(
                      TextSelection(
                        baseOffset: start + index,
                        extentOffset: start + index + 1,
                      ),
                    );
                    final expected = reference.getBoxesForSelection(
                      TextSelection(baseOffset: index, extentOffset: index + 1),
                    );
                    expect(actual, hasLength(1));
                    expect(expected, hasLength(1));
                    expect(
                      actual.single.right - actual.single.left,
                      closeTo(
                        expected.single.right - expected.single.left,
                        .015,
                      ),
                      reason:
                          '$site version glyph ${version[index]} must have '
                          'the bundled Mono13/400 advance at scale=$scale',
                    );
                  }
                } finally {
                  reference.dispose();
                }
                expect(style.fontFamily, BrandAssets.monoFont);
                expect(
                  style.fontFamilyFallback,
                  BrandAssets.fontFamilyFallback,
                );
                expect(style.fontSize, 13);
                expect(style.fontWeight, FontWeight.w400);
                expect(style.height! * style.fontSize!, closeTo(20, .001));
                if (start > 0) {
                  final human = _styleAt(text, 0);
                  expect(
                    human.fontFamily,
                    site == 'recipe-header'
                        ? BrandAssets.semiboldFamily
                        : BrandAssets.uiFont,
                  );
                  if (site == 'recipe-header')
                    expect(human.fontWeight, BrandTypography.semiboldWeight);
                  expect(human.fontSize, 14);
                }

                final last = boxes(
                  TextSelection(
                    baseOffset: start + version.length - 1,
                    extentOffset: start + version.length,
                  ),
                ).single;
                expect(last.left, greaterThanOrEqualTo(0));
                // SkParagraph's trailing selection box can exceed fractional
                // intrinsic width by 1/8px; allow half a physical pixel at DPR1.
                expect(last.right, lessThanOrEqualTo(render.size.width + .5));
                expect(last.top, greaterThanOrEqualTo(0));
                expect(
                  last.bottom,
                  lessThanOrEqualTo(render.size.height + .01),
                );
                final lastGlobal = render.localToGlobal(
                  Offset(last.right, last.bottom),
                );
                expect(lastGlobal.dx, lessThanOrEqualTo(frame.width));
                expect(lastGlobal.dy, lessThanOrEqualTo(frame.height));
                expect(lastGlobal.dy, greaterThan(0));
                if (site == 'recipe-header') {
                  expect(find.text('PostgreSQL 16'), findsOneWidget);
                  final package = tester.renderObject<RenderParagraph>(
                    find.text('PostgreSQL 16'),
                  );
                  expect(
                    _styleAt(package.text, 0).fontFamily,
                    BrandAssets.semiboldFamily,
                  );
                }
                if (site == 'configuration-recipe') {
                  final revision = tester.renderObject<RenderParagraph>(
                    find.text('Желаемая версия: 7'),
                  );
                  expect(
                    _styleAt(revision.text, 0).fontFamily,
                    BrandAssets.uiFont,
                  );
                }
                final first = boxes(
                  TextSelection(baseOffset: start, extentOffset: start + 1),
                ).single;
                if (frame.width <= 390 &&
                    scale == 2 &&
                    site != 'recipe-header') {
                  expect(render.size.height, greaterThan(20 * scale));
                }
                if (frame.width <= 390 && scale == 2 && selectable) {
                  expect(last.top, greaterThan(first.top));
                }
                final raster = await StockPaintRaster.capture(tester, boundary);
                final foreground = style.color!;
                // A single thin13px glyph can contain only antialiased pixels
                // at a fractional x offset. Sample the same real leading run
                // whose individual advances were checked against the bundled
                // Mono font above, without including a label or another row.
                final paintedRun = boxes(
                  TextSelection(
                    baseOffset: start,
                    extentOffset: start + math.min(8, version.length),
                  ),
                ).first;
                final glyphRect = Rect.fromLTRB(
                  paintedRun.left,
                  paintedRun.top,
                  paintedRun.right,
                  paintedRun.bottom,
                ).shift(render.localToGlobal(Offset.zero));
                expect(glyphRect.left, greaterThanOrEqualTo(0));
                expect(glyphRect.right, lessThanOrEqualTo(frame.width));
                expect(glyphRect.top, greaterThanOrEqualTo(0));
                expect(glyphRect.bottom, lessThanOrEqualTo(frame.height));
                final glyphPixels =
                    raster.histogram(glyphRect)[foreground] ?? 0;
                expect(glyphPixels, greaterThan(0));
                expect(calls, isEmpty);
                await captureStockPaint(
                  tester,
                  boundary: boundary,
                  family: 'versions',
                  componentCaseId: 'version-$site',
                  caseId:
                      'version-$site-${frame.width.toInt()}-${dark ? 'dark' : 'light'}-${(scale * 100).toInt()}',
                  originIds: const [],
                  usageOriginIds: switch (site) {
                    'recipe-header' => const [
                      '16-install-catalog',
                      '17-recipe-detail',
                    ],
                    'plan-effect' => const [
                      '18-install-preflight',
                      '19-plan-approval',
                      '34-profile-revisions',
                      '94-plan-invalidated',
                    ],
                    'configuration-recipe' => const ['06-server-overview'],
                    _ => const ['40-executor-binding'],
                  },
                  productionOwners: [
                    site == 'recipe-header' || site == 'plan-effect'
                        ? 'lib/automation/automation_sections.dart'
                        : 'lib/servers/server_sections.dart',
                    'lib/ui/deck_components.dart',
                  ],
                  components: [
                    switch (site) {
                      'recipe-header' => 'AutomationRecipesSection',
                      'plan-effect' => 'AutomationPlanSection',
                      'configuration-recipe' => 'ServerConfigurationResult',
                      _ => 'ServerExecutorConfirmation',
                    },
                  ],
                  width: frame.width,
                  height: frame.height,
                  theme: dark ? 'dark' : 'light',
                  scale: scale,
                  reducedMotion: true,
                  state: {
                    'preciseValue': version,
                    'fontFamily': style.fontFamily,
                    'fontSize': style.fontSize,
                    'lineHeight': style.height! * style.fontSize!,
                    'fontWeight': style.fontWeight!.value,
                    'foregroundArgb': foreground.toARGB32(),
                    'actualGlyphPixelCount': glyphPixels,
                    'didExceedMaxLines': didExceedMaxLines,
                    'selectable': selectable,
                    'wrapping': last.top > first.top,
                  },
                  counters: {'callbacks': calls.length},
                  limitations: const [
                    'Production component typography with synthetic display metadata; usageOrigins are references, not full-origin acceptance.',
                    'No client, executor, recipe execution, installation, trust or permission proof. Capture precedes callbacks and selection interaction.',
                  ],
                );
                if (selectable) {
                  await tester.longPressAt(
                    render.localToGlobal(
                      Offset(
                        (first.left + first.right) / 2,
                        (first.top + first.bottom) / 2,
                      ),
                    ),
                  );
                  await tester.pumpAndSettle();
                  final editor = tester.widget<EditableText>(value);
                  expect(editor.controller.selection.isValid, isTrue);
                  expect(editor.controller.selection.isCollapsed, isFalse);
                  tester.state<EditableTextState>(value).hideToolbar();
                  editor.focusNode.unfocus();
                }
                if (site == 'recipe-header') {
                  final select = find.text('PostgreSQL 16');
                  await _show(tester, select);
                  await tester.tap(select);
                  await tester.pumpAndSettle();
                  expect(calls, isEmpty);
                }
                final action = switch (site) {
                  'recipe-header' => 'Создать план',
                  'plan-effect' => 'Подтвердить план',
                  'executor-runtime' => 'Привязать исполнитель',
                  _ => null,
                };
                if (action != null) {
                  await _show(tester, find.text(action));
                  await tester.tap(find.text(action));
                  await tester.pumpAndSettle();
                  expect(calls, {
                    switch (site) {
                      'recipe-header' => 'createPlan',
                      'plan-effect' => 'approve',
                      _ => 'confirm',
                    }: 1,
                  });
                } else {
                  expect(calls, isEmpty);
                }
                if (site == 'recipe-header') {
                  expect(digests, [recipe['digest']]);
                }
                expect(jsonEncode(recipe), beforeRecipe);
                expect(jsonEncode(inspection), beforeInspection);
                expect(
                  (recipe['packagePins'] as List).single['version'],
                  '16.10-1',
                );
                expect(
                  (plan['effects'] as List).single['version'],
                  recipe['version'],
                );
                expect(
                  (comparison['expected'] as Map)['version'],
                  recipe['version'],
                );
                expect(tester.takeException(), isNull);
              } finally {
                await tester.pumpWidget(const SizedBox.shrink());
                changes.dispose();
              }
            },
          );
        }
      }
    }
  }
}
