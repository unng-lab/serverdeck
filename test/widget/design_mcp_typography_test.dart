import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/theme/brand_assets.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../support/design_automation_fixtures.dart';
import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_server_fixtures.dart';

const _monoReference = 'MCP bundled mono reference';
const _available = AutomationActionAvailability(
  read: true,
  mutate: true,
  select: true,
);

Finder _value(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is DeckKeyValue && widget.label == label,
  ),
  matching: find.byType(EditableText),
);

Future<void> _show(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .4);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadDesignFonts();
    await (FontLoader(
      _monoReference,
    )..addFont(rootBundle.load(BrandAssets.monoRegularFont))).load();
  });

  for (final width in [360.0, 390.0, 1100.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final label in ['Команда', 'Аргументы']) {
          testWidgets(
            'MCP $label actual mono glyphs width=$width dark=$dark scale=$scale',
            (tester) async {
              final frame = Size(width, width == 1100 ? 760 : 800);
              tester.view.physicalSize = frame;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final configuration =
                  DesignAutomationFixtures.launchConfiguration();
              final command = configuration['command'] as String;
              final args = configuration['args'] as List;
              final originalArgs = List<Object?>.of(args);
              final expected = label == 'Команда' ? command : args.join(', ');
              var copies = 0, otherActions = 0;
              void unexpected() => otherActions++;
              final theme = dark ? BrandTheme.dark : BrandTheme.light;
              await tester.pumpWidget(
                MaterialApp(
                  theme: Motion.theme(theme, true),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      disableAnimations: true,
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: AutomationGrantsSection(
                        grants: [
                          AutomationGrantPresentation(
                            value: DesignAutomationFixtures.grant(),
                            current: true,
                          ),
                        ],
                        serverProfiles: [DesignServerFixtures.profile()],
                        loaded: true,
                        actions: _available,
                        launchConfiguration: configuration,
                        onRefresh: unexpected,
                        onCreate: unexpected,
                        onConfigure: (_) => unexpected(),
                        onEdit: (_) => unexpected(),
                        onRevoke: (_) => unexpected(),
                        onCopyConfiguration: () => copies++,
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.text('Доступ ИИ рабочего пространства'));
              await tester.pumpAndSettle();
              final value = _value(label);
              await _show(tester, value);
              final editor = tester.widget<EditableText>(value);
              final render = tester
                  .state<EditableTextState>(value)
                  .renderEditable;
              expect(editor.controller.text, expected);
              expect(render.text!.toPlainText(), expected);
              expect(editor.readOnly, isTrue);
              expect(editor.selectionEnabled, isTrue);
              expect(editor.maxLines, isNull);

              // The alias loads the actual bundled TTF independently of the
              // production role. Compare real glyph advances before checking
              // metadata so a proportional body face produces a causal red.
              final reference = TextPainter(
                text: TextSpan(
                  text: expected,
                  style: TextStyle(
                    fontFamily: _monoReference,
                    fontSize: 13,
                    height: 20 / 13,
                    fontWeight: FontWeight.w400,
                    letterSpacing: editor.style.letterSpacing,
                    wordSpacing: editor.style.wordSpacing,
                    fontFeatures: editor.style.fontFeatures,
                    fontVariations: editor.style.fontVariations,
                  ),
                ),
                textDirection: TextDirection.ltr,
                textScaler: render.textScaler,
              )..layout();
              // Sample the prefix before a soft-wrap boundary. Full final
              // glyph bounds below independently verify wrapped content.
              for (var index = 0; index < 8; index++) {
                final selection = TextSelection(
                  baseOffset: index,
                  extentOffset: index + 1,
                );
                final actual = render.getBoxesForSelection(selection);
                final bundled = reference.getBoxesForSelection(selection);
                expect(actual, hasLength(1), reason: '$label glyph $index');
                expect(bundled, hasLength(1));
                expect(
                  actual.single.right - actual.single.left,
                  closeTo(bundled.single.right - bundled.single.left, .015),
                  reason:
                      '$label glyph ${expected[index]} at $index must use '
                      'the bundled Mono 13px advance at scale=$scale',
                );
              }
              reference.dispose();
              final style = (render.text! as TextSpan).style!;
              expect(style.fontFamily, BrandAssets.monoFont);
              expect(style.fontFamilyFallback, BrandAssets.fontFamilyFallback);
              expect(style.fontSize, 13);
              expect(style.fontWeight, FontWeight.w400);
              expect(style.height! * style.fontSize!, closeTo(20, .001));
              expect(render.preferredLineHeight, closeTo(20 * scale, .01));

              final last = render
                  .getBoxesForSelection(
                    TextSelection(
                      baseOffset: expected.length - 1,
                      extentOffset: expected.length,
                    ),
                  )
                  .single;
              expect(last.left, greaterThanOrEqualTo(0));
              expect(last.right, lessThanOrEqualTo(render.size.width + .01));
              expect(last.top, greaterThanOrEqualTo(0));
              expect(last.bottom, lessThanOrEqualTo(render.size.height + .01));
              final lastGlobal = render.localToGlobal(
                Offset(last.right, last.bottom),
              );
              expect(lastGlobal.dx, lessThanOrEqualTo(frame.width));
              expect(lastGlobal.dy, lessThanOrEqualTo(frame.height));
              expect(lastGlobal.dy, greaterThan(0));
              if (width < 500 && (label == 'Аргументы' || scale == 2)) {
                expect(render.size.height, greaterThan(20 * scale));
              }

              final caption = tester.renderObject<RenderParagraph>(
                find.text(label),
              );
              final captionStyle = (caption.text as TextSpan).style!;
              expect(captionStyle.fontFamily, BrandAssets.uiFont);
              expect(captionStyle.fontSize, 12);
              expect(captionStyle.height! * captionStyle.fontSize!, 16);
              final human = tester.renderObject<RenderParagraph>(
                find.text('Синтетический сервер'),
              );
              final humanStyle = (human.text as TextSpan).style!;
              expect(humanStyle.fontFamily, BrandAssets.uiFont);
              expect(humanStyle.fontSize, 14);
              expect(humanStyle.height! * humanStyle.fontSize!, 20);
              final address = tester.widget<EditableText>(_value('Адрес'));
              expect(address.style.fontFamily, BrandAssets.uiFont);
              expect(address.style.fontSize, 14);
              expect(address.style.height! * address.style.fontSize!, 20);

              final first = render
                  .getBoxesForSelection(
                    const TextSelection(baseOffset: 0, extentOffset: 1),
                  )
                  .single;
              await tester.longPressAt(
                render.localToGlobal(
                  Offset(
                    (first.left + first.right) / 2,
                    (first.top + first.bottom) / 2,
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(editor.controller.selection.isValid, isTrue);
              expect(editor.controller.selection.isCollapsed, isFalse);
              tester.state<EditableTextState>(value).hideToolbar();
              editor.focusNode.unfocus();
              await tester.pumpAndSettle();
              final copy = find.widgetWithText(
                OutlinedButton,
                'Скопировать конфигурацию',
              );
              await _show(tester, copy);
              await tester.tap(copy);
              await tester.pumpAndSettle();
              expect(copies, 1);
              expect(otherActions, 0);
              expect(configuration['command'], command);
              expect(configuration['args'], originalArgs);
              expect(editor.controller.text, expected);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            },
          );
        }
      }
    }
  }
}
