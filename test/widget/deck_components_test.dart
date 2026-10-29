import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck/ui/deck_icon.dart';

Widget host(
  Widget child, {
  ThemeData? theme,
  bool reduced = true,
  double scale = 1,
}) => MaterialApp(
  theme: theme ?? BrandTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: reduced,
      textScaler: TextScaler.linear(scale),
    ),
    child: child!,
  ),
  home: Scaffold(body: child),
);

Future<List<Color>> pixels(
  WidgetTester tester,
  GlobalKey boundaryKey,
  List<Offset> points,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final values = points.map((p) {
    final offset = (p.dy.floor() * image.width + p.dx.floor()) * 4;
    return Color.fromARGB(
      data.getUint8(offset + 3),
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
  }).toList();
  image.dispose();
  return values;
}

void main() {
  for (final width in [1100.0, 800.0, 390.0, 360.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('T219 source notice layout $width $dark $scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var calls = 0;
          final boundary = GlobalKey();
          const message = 'Полная причина с идентичностью операции и цели.';
          const next = 'Проверьте исходное состояние перед продолжением.';
          await tester.pumpWidget(
            host(
              RepaintBoundary(
                key: boundary,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DeckNotice(
                    title: 'Причина',
                    message: message,
                    nextStep: next,
                    tone: DeckTone.error,
                    actions: [
                      OutlinedButton(
                        onPressed: () => calls++,
                        child: const Text('Подробнее'),
                      ),
                    ],
                  ),
                ),
              ),
              theme: dark ? BrandTheme.dark : BrandTheme.light,
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          final notice = find.byType(DeckNotice);
          final container = find
              .descendant(of: notice, matching: find.byType(Container))
              .first;
          final decoration =
              tester.widget<Container>(container).decoration! as BoxDecoration;
          final border = decoration.border! as Border;
          final colors = dark ? BrandColors.dark : BrandColors.light;
          for (final side in [
            border.left,
            border.top,
            border.right,
            border.bottom,
          ]) {
            expect(side.width, 1);
            expect(side.color, colors['border']);
          }
          expect(decoration.borderRadius, BorderRadius.circular(8));
          final box = tester.getRect(container);
          final origin = tester.getTopLeft(find.byKey(boundary));
          final actualPaint = await pixels(tester, boundary, [
            Offset(box.left + 1.5, box.center.dy) - origin,
            Offset(box.left + 3.5, box.center.dy) - origin,
            Offset(box.center.dx, box.top + .2) - origin,
            Offset(box.right - .2, box.center.dy) - origin,
            Offset(box.center.dx, box.bottom - .2) - origin,
          ]);
          expect(actualPaint, [
            colors['error'],
            colors['surface'],
            colors['border'],
            colors['border'],
            colors['border'],
          ]);
          final icon = find.descendant(
            of: notice,
            matching: find.byType(DeckIcon),
          );
          expect(tester.widget<DeckIcon>(icon).name, 'close');
          final iconBox = tester.getRect(icon);
          final heading = tester.getRect(find.text('Причина'));
          final phone = width <= 520;
          expect(iconBox.size, Size.square(phone ? 18 : 17));
          expect(iconBox.left - box.left, phone ? 15 : 18);
          expect(iconBox.top - box.top, phone ? 16 : 15);
          expect(heading.left - iconBox.right, 10);
          expect(
            tester.getRect(find.text(message)).top - heading.bottom,
            closeTo(3, .01),
          );
          expect(tester.widget<Text>(find.text(message)).style!.fontSize, 12);
          expect(
            tester.widget<Text>(find.text(message)).style!.color,
            colors['muted'],
          );
          expect(tester.widget<Text>(find.text(next)).style!.fontSize, 12);
          expect(find.text(message), findsOneWidget);
          expect(find.text(next), findsOneWidget);
          expect(calls, 0);
          final action = find.widgetWithText(OutlinedButton, 'Подробнее');
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(calls, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('surface keeps expansion ink above its painted background', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const DeckSurface(
          child: ExpansionTile(
            title: Text('Selectable details'),
            children: [ListTile(title: Text('Actual detail'))],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Selectable details'));
    await tester.pumpAndSettle();
    expect(find.text('Actual detail').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final theme in [BrandTheme.light, BrandTheme.dark]) {
    testWidgets(
      'filled button paints focus2 gap2 on the actual card ${theme.brightness}',
      (tester) async {
        final key = GlobalKey();
        final node = FocusNode();
        final c = theme.extension<BrandColors>()!;
        await tester.pumpWidget(
          host(
            Center(
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: c['raised'],
                  child: SizedBox(
                    width: 160,
                    child: FilledButton(
                      focusNode: node,
                      onPressed: () {},
                      child: const Text('Action'),
                    ),
                  ),
                ),
              ),
            ),
            theme: theme,
          ),
        );
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        node.requestFocus();
        await tester.pumpAndSettle();
        expect(node.hasFocus, true);
        final height = tester.getSize(find.byKey(key)).height;
        final row = await pixels(tester, key, [
          for (double x = 0; x < 6; x++) Offset(x, height / 2),
        ]);
        expect(row, [
          c['focus'],
          c['focus'],
          c['raised'],
          c['raised'],
          c['accent'],
          c['accent'],
        ]);
        expect(
          tester.getSize(find.byType(FilledButton)).height,
          greaterThanOrEqualTo(44),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        node.dispose();
      },
    );

    testWidgets(
      'surface keeps selection error and keyboard focus ${theme.brightness}',
      (tester) async {
        final key = GlobalKey();
        final node = FocusNode();
        final c = theme.extension<BrandColors>()!;
        var calls = 0;
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            Center(
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: c['bg'],
                  child: SizedBox(
                    width: 220,
                    child: DeckSurface(
                      selected: true,
                      error: true,
                      focusNode: node,
                      semanticLabel: 'Selected action',
                      onTap: () => calls++,
                      child: const Text('Selected'),
                    ),
                  ),
                ),
              ),
            ),
            theme: theme,
          ),
        );
        node.requestFocus();
        await tester.pumpAndSettle();
        final size = tester.getSize(find.byKey(key));
        final row = await pixels(tester, key, [
          for (final x in [0.0, 1.0, 2.0, 3.0, 4.0, 6.0])
            Offset(x, size.height / 2),
        ]);
        expect(row.take(4).toList(), [
          c['focus'],
          c['focus'],
          c['bg'],
          c['bg'],
        ]);
        expect(row[4], c['error']);
        expect(row[5], c['selected']);
        final nodeData = tester.getSemantics(find.byType(DeckSurface));
        expect(nodeData.flagsCollection.isSelected, ui.Tristate.isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(calls, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        node.dispose();
        semantics.dispose();
      },
    );

    testWidgets(
      'disabled surface uses opaque text and no callback ${theme.brightness}',
      (tester) async {
        var calls = 0;
        final focus = FocusNode();
        await tester.pumpWidget(
          host(
            DeckSurface(
              enabled: false,
              onTap: () => calls++,
              focusNode: focus,
              child: const Text('Unavailable'),
            ),
            theme: theme,
          ),
        );
        await tester.tap(find.text('Unavailable'));
        focus.requestFocus();
        await tester.pump();
        expect(calls, 0);
        expect(focus.hasFocus, false);
        expect(find.byType(Opacity), findsNothing);
        expect(
          DefaultTextStyle.of(tester.element(find.text('Unavailable')))
              .style
              .color,
          theme.extension<BrandColors>()!['disabled'],
        );
        await tester.pumpWidget(const SizedBox.shrink());
        focus.dispose();
      },
    );

    testWidgets(
      'field error stays visible with separate focused outline ${theme.brightness}',
      (tester) async {
        final key = GlobalKey();
        final focus = FocusNode();
        final c = theme.extension<BrandColors>()!;
        await tester.pumpWidget(
          host(
            Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 260,
                  child: TextField(
                    focusNode: focus,
                    decoration: const InputDecoration(
                      labelText: 'Field',
                      errorText: 'Validation error',
                    ),
                  ),
                ),
              ),
            ),
            theme: theme,
          ),
        );
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(find.text('Validation error'), findsOneWidget);
        expect(
          tester
              .widget<InputDecorator>(find.byType(InputDecorator))
              .decoration
              .fillColor,
          c['bg'],
        );
        final row = await pixels(tester, key, [
          for (double x = 0; x < 9; x++) Offset(x, 24),
        ]);
        expect(row.take(5).toList(), [
          c['error'],
          c['bg'],
          c['bg'],
          c['focus'],
          c['focus'],
        ]);
        for (final role in ['focus', 'error']) {
          final foreground = c[role].computeLuminance();
          final background = c['bg'].computeLuminance();
          final contrast = foreground > background
              ? (foreground + .05) / (background + .05)
              : (background + .05) / (foreground + .05);
          expect(contrast, greaterThanOrEqualTo(3), reason: '$role on bg');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        focus.dispose();
      },
    );

    testWidgets('surface hover changes the actual fill ${theme.brightness}', (
      tester,
    ) async {
      final key = GlobalKey();
      final c = theme.extension<BrandColors>()!;
      await tester.pumpWidget(
        host(
          Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 180,
                child: DeckSurface(onTap: () {}, child: const Text('Hover')),
              ),
            ),
          ),
          theme: theme,
        ),
      );
      final point = Offset(8, tester.getSize(find.byKey(key)).height / 2);
      expect((await pixels(tester, key, [point])).single, c['surface']);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(DeckSurface)));
      await tester.pumpAndSettle();
      expect((await pixels(tester, key, [point])).single, c['hover']);
      await mouse.removePointer();
    });
  }

  testWidgets('pending retains text and a static symbol with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const DeckStatus(label: 'Ожидание результата', pending: true)),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is DeckIcon && widget.name == 'clock',
      ),
      findsOneWidget,
    );
    expect(find.text('Ожидание результата'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(
      host(
        const DeckStatus(label: 'Ожидание результата', pending: true),
        reduced: false,
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Ожидание результата'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('each status has its canonical symbol and supplied text', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Column(
          children: [
            for (final tone in DeckTone.values)
              DeckStatus(label: tone.name, tone: tone),
          ],
        ),
      ),
    );
    for (final tone in DeckTone.values)
      expect(find.text(tone.name), findsOneWidget);
    final icons = tester
        .widgetList<DeckIcon>(find.byType(DeckIcon))
        .map((widget) => widget.name)
        .toList();
    expect(icons, [
      'info',
      'check',
      'close',
      'info',
      'warning',
      'warning',
      'clock',
      'check',
    ]);
  });

  testWidgets('content surfaces do not insert extra keyboard stops', (
    tester,
  ) async {
    final before = FocusNode(), after = FocusNode();
    await tester.pumpWidget(
      host(
        Column(
          children: [
            TextButton(
              focusNode: before,
              onPressed: () {},
              child: const Text('Before'),
            ),
            const DeckSurface(child: Text('Information')),
            TextButton(
              focusNode: after,
              onPressed: () {},
              child: const Text('After'),
            ),
          ],
        ),
      ),
    );
    before.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(after.hasFocus, true);
    await tester.pumpWidget(const SizedBox.shrink());
    before.dispose();
    after.dispose();
  });

  testWidgets(
    'form dialog scrolls wrapped content and actions above keyboard at200',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      var accepted = 0;
      final launcher = FocusNode();
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              focusNode: launcher,
              onPressed: () => showMotionDialog<void>(
                context: context,
                barrierDismissible: true,
                builder: (context) => DeckDialogLayout(
                  title: 'Длинное подтверждение изменения профиля',
                  target: const DeckKeyValue(
                    label: 'Цель',
                    value: 'Целевой Unicode сервер с очень длинным именем',
                  ),
                  child: const DeckFormSection(
                    title: 'Параметры изменения',
                    description: 'Описанные последствия остаются доступны.',
                    children: [
                      DeckSectionHeader(
                        title: 'Длинная секция',
                        trailing: Text('Дополнительное описание'),
                      ),
                      TextField(
                        decoration: InputDecoration(
                          labelText: 'Название',
                          errorText: 'Ошибка сохраняется в поле',
                        ),
                      ),
                      DeckNotice(
                        message: 'Длинное объяснение причины, которое переносится на узком экране',
                        nextStep: 'Исправить введённые значения',
                        tone: DeckTone.error,
                      ),
                    ],
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => accepted++,
                      child: const Text('Подтвердить изменение'),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена'),
                    ),
                  ],
                ),
              ),
              child: const Text('Открыть'),
            ),
          ),
          scale: 2,
        ),
      );
      launcher.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Ошибка сохраняется в поле'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final cancel = find.widgetWithText(OutlinedButton, 'Отмена');
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      expect(cancel.hitTestable(), findsOneWidget);
      expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(500));
      expect(tester.getSize(cancel).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(cancel).height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(accepted, 0);
      expect(launcher.hasFocus, true);
      await tester.pumpWidget(const SizedBox.shrink());
      launcher.dispose();
    },
  );
}
