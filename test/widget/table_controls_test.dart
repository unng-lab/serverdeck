import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_action_flow.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck/ui/deck_page.dart';

import '../support/design_fonts.dart';
import 'deck_components_test.dart' show pixels;

void main() {
  setUpAll(loadDesignFonts);
  testWidgets('T185 table retains editing and loaded-page callbacks', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var count = 25;
    var dark = false;
    var more = 0;
    final selected = <int>[];
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return MaterialApp(
            theme: dark ? BrandTheme.dark : BrandTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: AutomationLoadedTable(
                  columns: const ['Название', 'Состояние'],
                  rows: List.generate(
                    count,
                    (i) => [
                      Text('record-$i'),
                      Text(i.isEven ? 'Готово' : 'Ошибка'),
                    ],
                  ),
                  onSelect: selected.add,
                  hasMore: true,
                  onMore: () => more++,
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    await tester.enterText(field, 'record-');
    final editor = tester.widget<EditableText>(find.byType(EditableText));
    editor.controller.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 5,
    );
    final controller = editor.controller;
    final focus = editor.focusNode;
    rebuild(() => dark = true);
    tester.view.physicalSize = const Size(390, 1600);
    await tester.pumpAndSettle();
    final resized = tester.widget<EditableText>(find.byType(EditableText));
    expect(resized.controller, same(controller));
    expect(resized.focusNode, same(focus));
    expect(focus.hasFocus, isTrue);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 1, extentOffset: 5),
    );
    expect(controller.text, 'record-');
    final popup = find.byType(PopupMenuButton<String>);
    await tester.tap(popup);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(controller.text, 'record-');
    expect(more, 0);
    expect(selected, isEmpty);
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      Focus.of(
        tester.element(
          find.descendant(of: popup, matching: find.text('Состояние')),
        ),
      ).hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final ready = find.widgetWithText(PopupMenuItem<String>, 'Готово');
    final readyText = find.descendant(of: ready, matching: find.text('Готово'));
    for (var step = 0; step < 3; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      if (Focus.of(tester.element(readyText)).hasFocus) break;
    }
    expect(Focus.of(tester.element(readyText)).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(find.text('record-0'), findsOneWidget);
    expect(find.text('record-1'), findsNothing);
    expect(controller.text, 'record-');
    expect(more, 0);
    expect(selected, isEmpty);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Все 13'));
    await tester.pumpAndSettle();
    // Select a filtered row through its native tap and preserve original index.
    await tester.enterText(field, 'record-24');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate((w) => w is Text && w.data == 'record-24'),
    );
    await tester.pumpAndSettle();
    expect(selected, [24]);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Все 1'));
    await tester.pumpAndSettle();
    final next = find.byTooltip('Следующая страница');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('record-20'), findsOneWidget);
    expect(find.text('record-0'), findsNothing);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(more, 1);
    rebuild(() => count = 45);
    await tester.pumpAndSettle();
    expect(find.text('record-40'), findsOneWidget);
    expect(find.text('record-20'), findsNothing);
    expect(find.widgetWithText(TextButton, '3'), findsOneWidget);
    expect(selected, [24]);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'T185 canonical action layout keeps real44 targets at its fringes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        for (final width in [1100.0, 800.0, 390.0, 360.0]) {
          for (final dark in [false, true]) {
            for (final scale in [1.0, 2.0]) {
              tester.view.physicalSize = Size(width, 800);
              final calls = <String>[];
              await tester.pumpWidget(
                MaterialApp(
                  theme: dark ? BrandTheme.dark : BrandTheme.light,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: DeckPageInsets(
                      padding: const EdgeInsets.all(16),
                      child: DeckPage(
                        title: 'Проверка действий',
                        actions: [
                          OutlinedButton(
                            clipBehavior: Clip.none,
                            onPressed: () => calls.add('first'),
                            child: const Text('Первый'),
                          ),
                          OutlinedButton(
                            clipBehavior: Clip.none,
                            onPressed: () => calls.add('last'),
                            child: const Text('Второй'),
                          ),
                        ],
                        child: DeckActions(
                          phoneBasis: 130,
                          children: [
                            OutlinedButton(
                              clipBehavior: Clip.none,
                              onPressed: () => calls.add('bar'),
                              child: const Text('Действие списка'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final first = find.widgetWithText(OutlinedButton, 'Первый');
              final last = find.widgetWithText(OutlinedButton, 'Второй');
              final flow = find
                  .ancestor(of: first, matching: find.byType(DeckActionFlow))
                  .first;
              final inset = width <= 520 ? 0.0 : 4.0;
              final a = tester.getRect(first),
                  b = tester.getRect(last),
                  group = tester.getRect(flow);
              expect(group.height, closeTo(20 * scale + 24 - inset * 2, .01));
              expect(a.left + inset, closeTo(group.left, .01));
              expect(b.left + inset - (a.right - inset), closeTo(8, .01));
              if (inset != 0) {
                expect(
                  a.width - 8,
                  closeTo(tester.getSize(find.text('Первый')).width + 26, .01),
                );
                for (final point in [
                  Offset(a.left + 1, a.center.dy),
                  Offset(a.center.dx, a.top + 1),
                ]) {
                  await tester.tapAt(point);
                  await tester.pumpAndSettle();
                }
                await tester.tapAt(Offset(b.right - 1, b.center.dy));
                await tester.pumpAndSettle();
                expect(calls, ['first', 'first', 'last']);
              } else {
                expect(calls, isEmpty);
              }
              expect(
                tester.getSemantics(first).getSemanticsData().rect.height,
                greaterThanOrEqualTo(44),
              );
              final bar = find.widgetWithText(
                OutlinedButton,
                'Действие списка',
              );
              final barFlow = find
                  .ancestor(of: bar, matching: find.byType(DeckActionFlow))
                  .first;
              expect(
                tester.getSize(barFlow).height,
                closeTo(20 * scale + 24 - inset * 2, .01),
              );
              expect(tester.takeException(), isNull);
            }
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    },
  );
  for (final width in [1100.0, 800.0, 390.0, 360.0, 520.0, 521.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('T185 table controls $width $dark $scale', (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final theme = dark ? BrandTheme.dark : BrandTheme.light;
            final colors = theme.extension<BrandColors>()!;
            final boundary = GlobalKey();
            final selected = <int>[];
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  backgroundColor: colors['bg'],
                  body: RepaintBoundary(
                    key: boundary,
                    child: ColoredBox(
                      color: colors['bg'],
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: AutomationLoadedTable(
                          columns: const ['Название', 'Состояние'],
                          rows: const [
                            [Text('alpha'), Text('Готово')],
                            [Text('beta'), Text('Ошибка')],
                          ],
                          onSelect: selected.add,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final field = find.byType(TextField);
            final target = tester.getRect(field);
            final phone = width <= 520;
            final visibleHeight = math.max(
              phone ? 44.0 : 40.0,
              20 * scale + 16,
            );
            expect(target.height, closeTo(math.max(44, visibleHeight), .01));
            expect(target.width, closeTo(math.min(360, width - 32), .01));
            final editable = tester.widget<EditableText>(
              find.byType(EditableText),
            );
            expect(editable.style.fontSize, phone ? 14 : 13);
            expect(editable.style.fontWeight, FontWeight.w400);
            expect(
              editable.style.height! * editable.style.fontSize!,
              closeTo(20, .01),
            );
            expect(
              tester.getTopLeft(find.byType(EditableText)).dx - target.left,
              closeTo(34, .01),
            );
            final search = find.byWidgetPredicate(
              (widget) =>
                  widget is SvgPicture &&
                  widget.bytesLoader is SvgAssetLoader &&
                  (widget.bytesLoader as SvgAssetLoader).assetName.endsWith(
                    '/search.svg',
                  ),
            );
            expect(tester.getSize(search), const Size(15, 15));
            expect(
              tester.getTopLeft(search).dx - target.left,
              closeTo(11, .01),
            );
            final tagSemantics = find.ancestor(
              of: find.text('Теги'),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.enabled == false,
              ),
            );
            final chevron = find.descendant(
              of: tagSemantics,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is SvgPicture &&
                    widget.bytesLoader is SvgAssetLoader &&
                    (widget.bytesLoader as SvgAssetLoader).assetName.endsWith(
                      '/chevron.svg',
                    ),
              ),
            );
            expect(tester.getSize(chevron), const Size(12, 12));
            final origin = tester.getTopLeft(find.byKey(boundary));
            final top = target.center.dy - visibleHeight / 2;
            final paint = await pixels(tester, boundary, [
              Offset(target.center.dx - origin.dx, top - origin.dy),
              Offset(target.center.dx - origin.dx, top + 2 - origin.dy),
            ]);
            expect(paint, [colors['control'], colors['surface']]);
            editable.focusNode.requestFocus();
            await tester.pumpAndSettle();
            expect(tester.getRect(field), target);
            expect(
              await pixels(tester, boundary, [
                Offset(target.center.dx - origin.dx, top - 3 - origin.dy),
                Offset(target.center.dx - origin.dx, top - 1 - origin.dy),
              ]),
              [colors['focus'], colors['bg']],
            );
            final sem = tester
                .getSemantics(find.byType(EditableText))
                .getSemanticsData();
            expect(sem.flagsCollection.isTextField, isTrue);
            expect(sem.rect.height, greaterThanOrEqualTo(44));
            if (!phone && scale == 1) {
              // These points are outside the 40px visible field, through all
              // layout ancestors, but inside its real native44px hit target.
              for (final y in [top - 1, top + visibleHeight + 1]) {
                editable.focusNode.unfocus();
                await tester.pumpAndSettle();
                await tester.pump(const Duration(milliseconds: 400));
                await tester.tapAt(Offset(target.center.dx, y));
                await tester.pumpAndSettle();
                expect(
                  editable.focusNode.hasFocus,
                  isTrue,
                  reason: 'single fringe tap at $y',
                );
              }
            }
            await tester.enterText(field, 'alpha');
            await tester.pumpAndSettle();
            final all = find.widgetWithText(OutlinedButton, 'Все 1');
            expect(all, findsOneWidget);
            expect(
              tester
                  .getSemantics(all)
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected,
              ui.Tristate.isTrue,
            );
            final allRect = tester.getRect(all);
            final active = await pixels(tester, boundary, [
              Offset(
                allRect.right - 3 - origin.dx,
                allRect.center.dy - origin.dy,
              ),
            ]);
            expect(active.single, colors['selected']);
            final span =
                tester.renderObject<RenderParagraph>(find.text('Все 1')).text
                    as TextSpan;
            expect(span.style!.fontSize, 12);
            expect(span.style!.fontWeight, FontWeight.w400);
            expect(span.style!.height! * 12, phone ? 20 : 18);
            final popup = find.byType(PopupMenuButton<String>);
            await tester.ensureVisible(popup);
            await tester.tap(popup);
            await tester.pumpAndSettle();
            await tester.tap(
              find.widgetWithText(PopupMenuItem<String>, 'Готово'),
            );
            await tester.pumpAndSettle();
            expect(tester.widget<TextField>(field).controller!.text, 'alpha');
            expect(
              tester
                  .getSemantics(all)
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected,
              ui.Tristate.isFalse,
            );
            expect(
              tester
                  .getSemantics(
                    find.descendant(
                      of: popup,
                      matching: find.byWidgetPredicate(
                        (widget) => widget is ButtonStyleButton,
                      ),
                    ),
                  )
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected,
              ui.Tristate.isTrue,
            );
            expect(selected, isEmpty);
            await tester.ensureVisible(all);
            await tester.tap(all);
            await tester.pumpAndSettle();
            expect(tester.widget<TextField>(field).controller!.text, isEmpty);
            expect(
              find.widgetWithText(OutlinedButton, 'Все 2'),
              findsOneWidget,
            );
            expect(selected, isEmpty);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }
}
