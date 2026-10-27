import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;
import 'package:serverdeck_protocol/profile_validation.dart';

import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_server_fixtures.dart';
import '../support/design_stock_capture.dart';
import '../support/design_stock_paint_support.dart';

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

bool _focused(WidgetTester tester, Finder editor) =>
    tester.widget<EditableText>(editor).focusNode.hasPrimaryFocus;

Finder _button(String label) => find
    .ancestor(of: find.text(label), matching: find.byType(TextButton))
    .first;

Future<void> _tabToEditor(WidgetTester tester, Finder editor) async {
  for (var i = 0; i < 35; i++) {
    if (_focused(tester, editor)) return;
    await _key(tester, LogicalKeyboardKey.tab);
  }
  expect(
    _focused(tester, editor),
    isTrue,
    reason: 'Real Tab journey must reach the bounded selectable text',
  );
}

Rect _glyph(WidgetTester tester, Finder editor, int offset) {
  final render = tester.state<EditableTextState>(editor).renderEditable;
  final box = render
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
      )
      .single;
  return Rect.fromLTRB(
    box.left,
    box.top,
    box.right,
    box.bottom,
  ).shift(render.localToGlobal(Offset.zero));
}

bool _inside(Rect viewport, Rect glyph) =>
    glyph.left >= viewport.left - .5 &&
    glyph.right <= viewport.right + .5 &&
    glyph.top >= viewport.top - .5 &&
    glyph.bottom <= viewport.bottom + .5;

void main() {
  setUpAll(loadDesignFonts);
  for (final frame in const [
    Size(1100, 760),
    Size(800, 600),
    Size(390, 800),
    Size(360, 800),
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final site in [
          'shell-context',
          'log-record',
          't102-log-record-unresolved',
        ]) {
          testWidgets(
            'bounded $site keyboard frame=${frame.width.toInt()} dark=$dark scale=$scale',
            (tester) async {
              tester.view.physicalSize = frame;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final previous = FocusManager.instance.highlightStrategy;
              FocusManager.instance.highlightStrategy =
                  FocusHighlightStrategy.alwaysTraditional;
              addTearDown(
                () => FocusManager.instance.highlightStrategy = previous,
              );
              final boundary = GlobalKey();
              final clipboardWrites = <String>[];
              tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                SystemChannels.platform,
                (call) async {
                  if (call.method == 'Clipboard.setData') {
                    clipboardWrites.add(
                      (call.arguments as Map)['text'] as String,
                    );
                    return null;
                  }
                  if (call.method == 'Clipboard.getData') {
                    return {
                      'text': clipboardWrites.isEmpty
                          ? ''
                          : clipboardWrites.last,
                    };
                  }
                  if (call.method == 'Clipboard.hasStrings') {
                    return {'value': clipboardWrites.isNotEmpty};
                  }
                  return null;
                },
              );
              addTearDown(
                () => tester.binding.defaultBinaryMessenger
                    .setMockMethodCallHandler(SystemChannels.platform, null),
              );
              final shell = site == 'shell-context';
              final unresolved = site == 't102-log-record-unresolved';
              // Actual maximum valid Unicode name and DNS address, validated
              // by the production protocol validator (not an impossible UI fixture).
              final name = List.filled(127, '例').join() + 'Я';
              final address = [
                for (var i = 0; i < 3; i++) List.filled(63, 'a').join(),
                List.filled(61, 'z').join(),
              ].join('.');
              final normalized = normalizeProfileFields({
                'name': name,
                'address': address,
                'sshUser': 'operator',
              });
              expect(normalized['name'], name);
              expect(name.runes.length, 128);
              expect(address.runes.length, 253);
              final message = shell
                  ? '$name · $address'
                  : [
                      for (var i = 0; i < 48; i++)
                        'Запись ${i.toString().padLeft(2, '0')} 例 /usr/bin/serverdeck --exact-value=abcdef',
                      'LAST-GLYPH-Я',
                    ].join('\n');
              final profile = DesignServerFixtures.profile(
                address: '2001:db8::44',
                connectionRevision: unresolved ? '2' : '1',
              );
              const timestamp = 'Время записи: 2026-10-25T18:24:00.000Z UTC';
              const observedAt = '2026-10-26T09:15:00.000Z';
              final contextText = [
                if (unresolved) ...[
                  'Цель записи: ${DesignServerFixtures.serverId}',
                  'Параметры цели записи не подтверждены текущими сведениями',
                  'Закройте окно и получите журнал для текущих параметров.',
                ] else ...[
                  profile.name,
                  '[2001:db8::44]:2222',
                ],
                'Источник: journald',
                timestamp,
                'Наблюдение: $observedAt UTC',
              ];
              final record = DesignServerFixtures.record(
                timestamp: '2026-10-25T18:24:00.000Z',
                message: message,
              );
              final logs = {
                ...DesignServerFixtures.logs(records: [record]),
                'observedAt': observedAt,
              };
              final recordContext = ServerLogRecordContext.capture(
                profile,
                logs,
              );
              var opened = 0, closed = 0, other = 0;
              Widget launcher(BuildContext context) => Column(
                children: [
                  TextButton(
                    onPressed: () async {
                      opened++;
                      await showMotionDialog<void>(
                        context: context,
                        builder: (context) => ServerLogRecordDialog(
                          recordContext: recordContext,
                          record:
                              (logs['records'] as List).single
                                  as Map<String, Object?>,
                          onClose: () {
                            closed++;
                            Navigator.of(context).pop();
                          },
                        ),
                      );
                    },
                    child: const Text('Открыть запись'),
                  ),
                  TextButton(
                    onPressed: () => other++,
                    child: const Text('Следующее действие'),
                  ),
                ],
              );
              await tester.pumpWidget(
                RepaintBoundary(
                  key: boundary,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
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
                    home: shell
                        ? FoundationShell(
                            state: ReadinessState.ready,
                            targetName: name,
                            targetAddress: address,
                            servers: Builder(builder: launcher),
                          )
                        : Scaffold(body: Builder(builder: launcher)),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              if (!shell) {
                for (var i = 0; i < 20; i++) {
                  if (stockContainsFocus(tester, _button('Открыть запись')))
                    break;
                  await _key(tester, LogicalKeyboardKey.tab);
                }
                expect(
                  stockContainsFocus(tester, _button('Открыть запись')),
                  isTrue,
                );
                await _key(tester, LogicalKeyboardKey.enter);
                expect(opened, 1);
              }
              final editor = find.byWidgetPredicate(
                (widget) =>
                    widget is EditableText && widget.controller.text == message,
              );
              expect(editor, findsOneWidget);
              await _tabToEditor(tester, editor);
              final scroll = find
                  .ancestor(
                    of: editor,
                    matching: find.byType(SingleChildScrollView),
                  )
                  .first;
              final position = tester
                  .state<ScrollableState>(
                    find
                        .descendant(
                          of: scroll,
                          matching: find.byType(Scrollable),
                        )
                        .first,
                  )
                  .position;
              var viewport = tester.getRect(scroll);
              expect(
                viewport.height,
                lessThanOrEqualTo(shell ? frame.height * .35 : 240),
              );
              final contextRects = <String, Rect>{};
              if (!shell) {
                final semantics = tester.ensureSemantics();
                for (final text in contextText) {
                  final label = find.descendant(
                    of: find.byType(ServerLogRecordDialog),
                    matching: find.text(text),
                  );
                  expect(label, findsOneWidget);
                  await tester.ensureVisible(label);
                  await tester.pumpAndSettle();
                  expect(
                    find.bySemanticsLabel(RegExp(RegExp.escape(text))),
                    findsWidgets,
                  );
                }
                semantics.dispose();
                // Outer scrolling may reveal long context at 200%. Return to
                // the bounded region before testing its independent keyboard scroll.
                await tester.ensureVisible(scroll);
                await tester.pumpAndSettle();
                viewport = tester.getRect(scroll);
                for (final text in contextText) {
                  contextRects[text] = tester.getRect(find.text(text));
                  expect(
                    contextRects[text]!.bottom,
                    lessThanOrEqualTo(tester.getRect(scroll).top),
                  );
                }
              }
              if (!shell || (frame.width <= 390 && scale == 2)) {
                expect(position.maxScrollExtent, greaterThan(0));
              }
              await _key(tester, LogicalKeyboardKey.home);
              expect(position.pixels, closeTo(position.minScrollExtent, .01));
              expect(_inside(viewport, _glyph(tester, editor, 0)), isTrue);

              Future<void> capture(String view) async {
                final railLabels = FoundationSection.values
                    .expand(
                      (section) => find
                          .byWidgetPredicate(
                            (widget) =>
                                widget is Text &&
                                widget.textSpan?.toPlainText() == section.label,
                          )
                          .evaluate(),
                    )
                    .length;
                if (shell && frame.width == 800) {
                  expect(
                    railLabels,
                    0,
                    reason: 'Leaving rail focus must retire every navigation tooltip before capturing bounded text',
                  );
                }
                final raster = await StockPaintRaster.capture(tester, boundary);
                final colors = (dark ? BrandTheme.dark : BrandTheme.light)
                    .extension<BrandColors>()!;
                final region = find
                    .ancestor(of: scroll, matching: find.byType(CustomPaint))
                    .first;
                final bounds = tester.getRect(region);
                final focusPixels =
                    raster.histogram(bounds)[colors['focus']] ?? 0;
                expect(
                  focusPixels,
                  greaterThan(0),
                  reason: 'Actual visible focus outline pixels',
                );
                // The flat adjacent surface is sampled just inside the reserved
                // outline gap, rather than assuming a theme pair is composited.
                final background = raster.pixel(
                  Offset(bounds.center.dx, bounds.top + 3),
                );
                expect(
                  raster.pixel(Offset(bounds.center.dx, bounds.top + .5)),
                  colors['focus'],
                );
                expect(
                  raster.pixel(Offset(bounds.center.dx, bounds.top + 1.5)),
                  colors['focus'],
                );
                expect(
                  raster.pixel(Offset(bounds.center.dx, bounds.top + 2.5)),
                  background,
                );
                expect(
                  raster.pixel(Offset(bounds.center.dx, bounds.top + 3.5)),
                  background,
                );
                final ratio = stockContrast(colors['focus'], background);
                expect(ratio, greaterThanOrEqualTo(3));
                final visibleGlyph = _glyph(
                  tester,
                  editor,
                  view == 'start' ? 0 : message.length - 1,
                );
                final glyphForeground = tester
                    .widget<EditableText>(editor)
                    .style
                    .color!;
                final glyphPixels =
                    raster.histogram(visibleGlyph)[glyphForeground] ?? 0;
                expect(
                  glyphPixels,
                  greaterThan(0),
                  reason: 'The reached first/last glyph must actually paint inside its visible bounds',
                );
                expect(_focused(tester, editor), isTrue);
                expect(closed, 0);
                expect(other, 0);
                // The T087 writer retains its two-component/64-frame schema.
                // The unresolved branch still ran every actual paint check;
                // its opt-in images belong to the T102 server state journey.
                if (unresolved) return;
                await captureStockPaint(
                  tester,
                  boundary: boundary,
                  family: 'scroll',
                  componentCaseId: 'scroll-$site',
                  caseId:
                      'scroll-$site-${frame.width.toInt()}-${dark ? 'dark' : 'light'}-${(scale * 100).toInt()}-$view',
                  originIds: const [],
                  usageOriginIds: shell
                      ? const ['05-server-list']
                      : const ['23-log-record'],
                  productionOwners: [
                    'lib/ui/deck_components.dart',
                    shell
                        ? 'lib/shell/foundation_shell.dart'
                        : 'lib/servers/server_sections.dart',
                  ],
                  components: [
                    shell ? 'FoundationShell' : 'ServerLogRecordDialog',
                  ],
                  width: frame.width,
                  height: frame.height,
                  theme: dark ? 'dark' : 'light',
                  scale: scale,
                  reducedMotion: true,
                  state: {
                    'view': view,
                    'focused': _focused(tester, editor),
                    'scrollPixels': position.pixels,
                    'minScrollExtent': position.minScrollExtent,
                    'maxScrollExtent': position.maxScrollExtent,
                    'atStart':
                        (position.pixels - position.minScrollExtent).abs() <
                        .01,
                    'atEnd':
                        (position.pixels - position.maxScrollExtent).abs() <
                        .01,
                    'viewport': {
                      'left': viewport.left,
                      'top': viewport.top,
                      'right': viewport.right,
                      'bottom': viewport.bottom,
                    },
                    'firstGlyphVisible': _inside(
                      viewport,
                      _glyph(tester, editor, 0),
                    ),
                    'lastGlyphVisible': _inside(
                      viewport,
                      _glyph(tester, editor, message.length - 1),
                    ),
                    'focusIndicatorContrast': ratio,
                    'focusWidth': 2,
                    'focusGap': 2,
                    'focusPixelCount': focusPixels,
                    'visibleGlyphPaintedPixels': glyphPixels,
                    'visibleGlyphForegroundArgb': glyphForeground.toARGB32(),
                    'selectable': tester
                        .widget<EditableText>(editor)
                        .selectionEnabled,
                    'selectionCollapsed': tester
                        .widget<EditableText>(editor)
                        .controller
                        .selection
                        .isCollapsed,
                    if (shell && frame.width == 800)
                      'railTooltipOverlayCount': railLabels
                    else
                      'railTooltipOverlayNotApplicableReason': shell
                          ? 'This frame uses phone/sidebar navigation, not the icon-only rail.'
                          : 'The log record scenario has no shell navigation.',
                  },
                  counters: {'open': opened, 'close': closed, 'other': other},
                  limitations: const [
                    'Actual production bounded region and real keyboard journey with validated synthetic profile metadata or synthetic log data; usage origins are references, not full-origin acceptance.',
                    'Capture precedes selection/copy and close. No client, service request, SSH, authority, retention or privacy lifecycle proof.',
                  ],
                );
              }

              await capture('start');
              if (position.maxScrollExtent > 0) {
                await _key(tester, LogicalKeyboardKey.arrowDown);
                expect(position.pixels, greaterThan(0));
                await _key(tester, LogicalKeyboardKey.arrowUp);
                expect(position.pixels, closeTo(0, .01));
                await _key(tester, LogicalKeyboardKey.pageDown);
                expect(position.pixels, greaterThan(0));
                await _key(tester, LogicalKeyboardKey.pageUp);
                expect(position.pixels, closeTo(0, .01));
              }
              await _key(tester, LogicalKeyboardKey.end);
              expect(position.pixels, closeTo(position.maxScrollExtent, .01));
              expect(
                _inside(viewport, _glyph(tester, editor, message.length - 1)),
                isTrue,
                reason: 'End must reveal the actual final glyph in the bounded viewport',
              );
              await capture('end');
              if (!shell) {
                for (final text in contextText) {
                  expect(tester.getRect(find.text(text)), contextRects[text]);
                }
              }
              final selection = tester.widget<EditableText>(editor).controller;
              await _chord(
                tester,
                LogicalKeyboardKey.controlLeft,
                LogicalKeyboardKey.keyA,
              );
              expect(selection.selection.textInside(message), message);
              await _chord(
                tester,
                LogicalKeyboardKey.controlLeft,
                LogicalKeyboardKey.keyC,
              );
              expect(clipboardWrites, [message]);
              expect(selection.text, message);
              await _key(tester, LogicalKeyboardKey.tab);
              expect(_focused(tester, editor), isFalse);
              await _chord(
                tester,
                LogicalKeyboardKey.shiftLeft,
                LogicalKeyboardKey.tab,
              );
              expect(_focused(tester, editor), isTrue);
              await _chord(
                tester,
                LogicalKeyboardKey.shiftLeft,
                LogicalKeyboardKey.tab,
              );
              expect(_focused(tester, editor), isFalse);
              await _key(tester, LogicalKeyboardKey.tab);
              expect(_focused(tester, editor), isTrue);
              await _key(tester, LogicalKeyboardKey.tab);
              if (!shell) {
                expect(stockContainsFocus(tester, _button('Закрыть')), isTrue);
                await _key(tester, LogicalKeyboardKey.enter);
                expect(closed, 1);
                expect(find.text('Запись журнала'), findsNothing);
                expect(
                  stockContainsFocus(tester, _button('Открыть запись')),
                  isTrue,
                );
              }
              expect(other, 0);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            },
          );
        }
      }
    }
  }
}
