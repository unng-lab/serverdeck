import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../support/component_cases.dart';

void main() {
  for (final dark in [true, false]) {
    final colors = dark ? BrandColors.dark : BrandColors.light;
    for (final kind in DeckButtonKind.values) {
      for (final state in [
        'default',
        'hover',
        'pressed',
        'focus',
        'disabled',
        'pending',
      ]) {
        testWidgets('C02 $kind $state dark=$dark has one border owner', (
          tester,
        ) async {
          final states = WidgetStatesController();
          addTearDown(states.dispose);
          final disabled = state == 'disabled' || state == 'pending';
          await tester.pumpWidget(
            componentHarness(
              DeckButton(
                kind: kind,
                pending: state == 'pending',
                statesController: states,
                onPressed: state == 'disabled' ? null : () {},
                child: const Text('Action'),
              ),
              dark: dark,
            ),
          );
          final interaction = switch (state) {
            'hover' => WidgetState.hovered,
            'pressed' => WidgetState.pressed,
            'focus' => WidgetState.focused,
            _ => null,
          };
          if (interaction != null) states.update(interaction, true);
          await tester.pumpAndSettle();

          final button = find.byWidgetPredicate((w) => w is ButtonStyleButton);
          final material = tester.widget<Material>(
            find.descendant(of: button, matching: find.byType(Material)).last,
          );
          // The custom painter owns the control border and separate focus ring.
          // A native OutlinedButton side would introduce a second outline.
          expect((material.shape! as OutlinedBorder).side, BorderSide.none);
          final textStyle = DefaultTextStyle.of(
            tester.element(find.text('Action')),
          ).style;
          expect(
            textStyle.color,
            colors[disabled
                ? 'disabled'
                : switch (kind) {
                    DeckButtonKind.primary => 'onAccent',
                    DeckButtonKind.secondary => 'text',
                    DeckButtonKind.text => 'accent',
                    DeckButtonKind.danger => 'error',
                  }],
          );

          final paint = tester.widget<CustomPaint>(
            find
                .descendant(
                  of: button,
                  matching: find.byWidgetPredicate(
                    (w) => w is CustomPaint && w.painter != null,
                  ),
                )
                .last,
          );
          void draw(Canvas canvas) =>
              paint.painter!.paint(canvas, const Size(160, 48));
          // Expected roles come from the C02 HTML variants and :active rule,
          // including its later overrides for danger/text hover and disabled.
          final index = [
            'default',
            'hover',
            'pressed',
            'focus',
            'disabled',
            'pending',
          ].indexOf(state);
          final (fills, borders) = switch (kind) {
            DeckButtonKind.primary => (
              [
                'accent',
                'accentHover',
                'accentHover',
                'accent',
                'raised',
                'raised',
              ],
              [null, null, 'onAccent', null, 'border', 'border'],
            ),
            DeckButtonKind.secondary => (
              ['surface', 'hover', 'selected', 'surface', 'raised', 'raised'],
              ['control', 'control', 'control', 'control', 'border', 'border'],
            ),
            DeckButtonKind.text => (
              [null, null, 'selected', null, 'raised', 'raised'],
              [null, null, 'transparent', null, 'border', 'border'],
            ),
            DeckButtonKind.danger => (
              ['surface', 'surface', 'selected', 'surface', 'raised', 'raised'],
              ['error', 'error', 'error', 'error', 'border', 'border'],
            ),
          };
          expect(
            draw,
            paints..rrect(
              color: fills[index] == null
                  ? Colors.transparent
                  : colors[fills[index]!],
              style: PaintingStyle.fill,
            ),
          );
          final border = borders[index];
          expect(
            draw,
            paintsExactlyCountTimes(
              #drawRRect,
              1 + (border != null ? 1 : 0) + (state == 'focus' ? 1 : 0),
            ),
          );
          // No dashed paths: disabled and pending have one solid border too.
          expect(draw, paintsExactlyCountTimes(#drawPath, 0));
          final pattern = paints..rrect();
          if (border != null) {
            pattern.rrect(
              color: border == 'transparent'
                  ? Colors.transparent
                  : colors[border],
              style: PaintingStyle.stroke,
              strokeWidth: state == 'pressed' ? 2 : 1,
            );
          }
          if (state == 'focus') {
            pattern.rrect(
              color: colors['focus'],
              style: PaintingStyle.stroke,
              strokeWidth: 2,
            );
          }
          expect(draw, pattern);
        });
      }
    }
    testWidgets('C02 icon button retains neutral foreground dark=$dark', (
      tester,
    ) async {
      await tester.pumpWidget(
        componentHarness(
          IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
          dark: dark,
        ),
      );
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.add))).color,
        colors['text'],
      );
    });
  }
}
