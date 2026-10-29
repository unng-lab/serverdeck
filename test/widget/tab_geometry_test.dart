import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_page.dart';

import '../support/design_fonts.dart';
import 'deck_components_test.dart' show pixels;

const labels = [
  'Обзор',
  'ПО',
  'Ресурсы',
  'Автоматизация',
  'Offline / сохранённые данные',
];

Widget host({
  GlobalKey? boundary,
  ValueChanged<int>? onSelected,
  bool dark = true,
  double scale = 1,
}) => MaterialApp(
  theme: dark ? BrandTheme.dark : BrandTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: RepaintBoundary(
      key: boundary,
      child: ColoredBox(
        color: (dark ? BrandColors.dark : BrandColors.light)['bg'],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              DeckTabs(labels: labels, selected: 0, onSelected: onSelected),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(loadDesignFonts);
  testWidgets('T189 scrolled hover and underline stay inside the strip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(host(boundary: boundary, onSelected: (_) {}));
    await tester.pumpAndSettle();
    final strip = tester.getRect(find.byType(DeckTabs));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(strip.left + 20, strip.center.dy));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    scroll.position.jumpTo(10);
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(find.byKey(boundary));
    final paint = await pixels(tester, boundary, [
      Offset(strip.left - 2 - origin.dx, strip.center.dy - origin.dy),
      Offset(strip.left - 2 - origin.dx, strip.bottom - 2 - origin.dy),
    ]);
    expect(paint, everyElement(BrandColors.dark['bg']));
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final width in [1100.0, 800.0, 390.0, 360.0, 520.0, 521.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('T189 tab geometry $width dark=$dark scale=$scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          final calls = <int>[];
          try {
            await tester.pumpWidget(
              host(dark: dark, scale: scale, onSelected: calls.add),
            );
            await tester.pumpAndSettle();
            final phone = width <= 520;
            final visibleHeight = scale == 1
                ? (phone ? 44.0 : 42.0)
                : (phone && width <= 390 ? 93.0 : (phone ? 53.0 : 52.0));
            final strip = tester.getRect(find.byType(DeckTabs));
            expect(strip.height, visibleHeight + 1);
            final first = find.text(labels.first);
            final short = find.text('ПО');
            final next = find.text('Ресурсы');
            final firstBox = tester.getRect(first);
            final shortBox = tester.getRect(short);
            final nextBox = tester.getRect(next);
            expect(firstBox.left - strip.left, phone ? 8 : 0);
            if (!phone) {
              expect(shortBox.left - firstBox.right, closeTo(20, .01));
              expect(nextBox.left - shortBox.right, closeTo(20, .01));
            }
            final button = find.widgetWithText(TextButton, 'ПО');
            expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
            expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
            expect(
              tester.getSemantics(button).rect.width,
              greaterThanOrEqualTo(44),
            );
            expect(
              tester.getSemantics(button).rect.height,
              greaterThanOrEqualTo(44),
            );
            if (!phone && scale == 1) {
              // A real pointer in the short tab's native target, outside its
              // source-visible text width, still uses the original handler.
              await tester.tapAt(Offset(shortBox.left - 8, shortBox.center.dy));
              expect(calls, [1]);
              final firstButton = tester.getRect(
                find.widgetWithText(TextButton, labels.first),
              );
              await tester.tapAt(
                Offset(firstButton.center.dx, firstButton.top + .2),
              );
              expect(calls, [1, 0]);
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            semantics.dispose();
          }
        });
      }
    }
  }
  testWidgets('T189 desktop source-visible tab height42 and native target44', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(onSelected: (_) {}));
    await tester.pumpAndSettle();
    // 42px source strip plus its separate 1px decorative bottom border.
    expect(tester.getSize(find.byType(DeckTabs)).height, 43);
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Обзор')).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'T189 keyboard scroll and retained focus dark=$dark scale=$scale',
        (tester) async {
          tester.view.physicalSize = const Size(390, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final boundary = GlobalKey();
          final calls = <int>[];
          await tester.pumpWidget(
            host(
              boundary: boundary,
              dark: dark,
              scale: scale,
              onSelected: calls.add,
            ),
          );
          await tester.pumpAndSettle();
          for (var i = 0; i < labels.length; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
            expect(
              Focus.of(tester.element(find.text(labels[i]))).hasFocus,
              isTrue,
            );
          }
          final lastButton = find.widgetWithText(TextButton, labels.last);
          final state = tester.state(lastButton);
          final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
          expect(scroll.position.pixels, greaterThan(0));
          final strip = tester.getRect(find.byType(DeckTabs));
          final last = tester.getRect(find.text(labels.last));
          final origin = tester.getTopLeft(find.byKey(boundary));
          final paint = await pixels(tester, boundary, [
            Offset(
              last.center.dx.clamp(strip.left + 8, strip.right - 8) - origin.dx,
              strip.top - 3 - origin.dy,
            ),
            Offset(
              tester.getRect(lastButton).right + 3 - origin.dx,
              strip.center.dy - origin.dy,
            ),
          ]);
          expect(
            paint,
            everyElement(
              (dark ? BrandColors.dark : BrandColors.light)['focus'],
            ),
          );
          expect(calls, isEmpty);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(calls, [4]);
          tester.view.physicalSize = const Size(800, 800);
          await tester.pumpWidget(
            host(
              boundary: boundary,
              dark: dark,
              scale: scale,
              onSelected: calls.add,
            ),
          );
          final firstResizeStrip = tester.getRect(find.byType(DeckTabs));
          final firstResizeLast = tester.getRect(lastButton);
          final firstResizeOrigin = tester.getTopLeft(find.byKey(boundary));
          final firstResizePaint = await pixels(tester, boundary, [
            Offset(
              firstResizeLast.right + 3 - firstResizeOrigin.dx,
              firstResizeStrip.center.dy - firstResizeOrigin.dy,
            ),
          ]);
          expect(
            firstResizePaint.single,
            (dark ? BrandColors.dark : BrandColors.light)['focus'],
          );
          tester.view.physicalSize = const Size(1100, 800);
          await tester.pumpWidget(
            host(
              boundary: boundary,
              dark: dark,
              scale: scale,
              onSelected: calls.add,
            ),
          );
          final wideStrip = tester.getRect(find.byType(DeckTabs));
          final wideLast = tester.getRect(lastButton);
          final wideOrigin = tester.getTopLeft(find.byKey(boundary));
          final widePaint = await pixels(tester, boundary, [
            Offset(
              wideLast.right + 3 - wideOrigin.dx,
              wideStrip.center.dy - wideOrigin.dy,
            ),
          ]);
          expect(
            widePaint.single,
            (dark ? BrandColors.dark : BrandColors.light)['focus'],
          );
          await tester.pumpWidget(
            host(
              boundary: boundary,
              dark: !dark,
              scale: scale,
              onSelected: calls.add,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.state(lastButton), same(state));
          expect(
            Focus.of(tester.element(find.text(labels.last))).hasFocus,
            isTrue,
          );
          final resizedStrip = tester.getRect(find.byType(DeckTabs));
          final resizedLast = tester.getRect(lastButton);
          final resizedOrigin = tester.getTopLeft(find.byKey(boundary));
          final resizedPaint = await pixels(tester, boundary, [
            Offset(
              resizedLast.right + 3 - resizedOrigin.dx,
              resizedStrip.center.dy - resizedOrigin.dy,
            ),
          ]);
          expect(
            resizedPaint.single,
            (dark ? BrandColors.light : BrandColors.dark)['focus'],
          );
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          for (var i = labels.length - 2; i >= 0; i--) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
            expect(
              Focus.of(tester.element(find.text(labels[i]))).hasFocus,
              isTrue,
            );
          }
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(calls, [4, 0]);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('T189 overflowing phone tabs keep external focus outline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    final calls = <int>[];
    await tester.pumpWidget(host(boundary: boundary, onSelected: calls.add));
    await tester.pumpAndSettle();
    final strip = tester.getRect(find.byType(DeckTabs));
    final text = find.text('Обзор');
    expect(tester.getTopLeft(text).dx - strip.left, 8);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(text)).hasFocus, isTrue);
    final origin = tester.getTopLeft(find.byKey(boundary));
    final paint = await pixels(tester, boundary, [
      Offset(tester.getCenter(text).dx - origin.dx, strip.top - 3 - origin.dy),
      Offset(strip.left - 3 - origin.dx, strip.center.dy - origin.dy),
    ]);
    expect(paint, everyElement(BrandColors.dark['focus']));
    expect(calls, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, [0]);
    expect(tester.takeException(), isNull);
  });
}
