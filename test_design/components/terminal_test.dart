import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/ui/deck_terminal.dart';
import 'package:xterm/core.dart';

import '../support/component_cases.dart';

void main() {
  testWidgets('editable paste is delegated before any terminal input', (
    tester,
  ) async {
    final terminal = Terminal();
    final output = <String>[], pasted = <String>[];
    terminal.onOutput = output.add;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData')
          return {'text': 'first\nsecond'};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      componentHarness(
        SizedBox(
          height: 240,
          child: DeckTerminal(
            terminal: terminal,
            readOnly: false,
            onPaste: (text) async {
              pasted.add(text);
            },
            onResize: (_, __) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DeckTerminal));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(pasted, ['first\nsecond']);
    expect(output, isEmpty);
    Actions.invoke(
      FocusManager.instance.primaryFocus!.context!,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    expect(pasted, ['first\nsecond', 'first\nsecond']);
    expect(output, isEmpty);
  });
  testWidgets(
    'platform multiline edits delegate while ordinary text and Enter remain input',
    (tester) async {
      final terminal = Terminal();
      final output = <String>[], pasted = <String>[];
      terminal.onOutput = output.add;
      await tester.pumpWidget(
        componentHarness(
          SizedBox(
            height: 240,
            child: DeckTerminal(
              terminal: terminal,
              readOnly: false,
              onPaste: (text) async {
                pasted.add(text);
              },
              onResize: (_, __) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DeckTerminal));
      await tester.pump();
      for (final text in ['first\nsecond', '\n', '\r\n']) {
        tester.testTextInput.enterText(text);
        await tester.pump();
      }
      expect(pasted, ['first\nsecond', '\n', '\r\n']);
      expect(output, isEmpty);
      tester.testTextInput.enterText('plain');
      await tester.pump();
      expect(output.join(), 'plain');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(output.join(), 'plain\r');
      expect(pasted.length, 3);
    },
  );
  testWidgets(
    'terminal renders one supplied model and forwards keyboard input',
    (tester) async {
      final terminal = Terminal();
      final output = <String>[];
      terminal.onOutput = output.add;
      terminal.write('synthetic');
      await tester.pumpWidget(
        componentHarness(
          SizedBox(
            height: 240,
            child: DeckTerminal(
              terminal: terminal,
              readOnly: false,
              onPaste: (_) async {},
              onResize: (_, __) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DeckTerminal));
      await tester.pump();
      tester.testTextInput.enterText('a');
      await tester.pump();
      expect(output.join(), contains('a'));
      expect(terminal.buffer.lines[0].getText(), contains('synthetic'));
    },
  );
  testWidgets(
    'read only terminal sends no keys and paste uses explicit callback',
    (tester) async {
      final terminal = Terminal();
      final output = <String>[], pasted = <String>[];
      terminal.onOutput = output.add;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData')
            return {'text': 'first\nsecond'};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        componentHarness(
          SizedBox(
            height: 240,
            child: DeckTerminal(
              terminal: terminal,
              readOnly: true,
              onPaste: (text) async {
                pasted.add(text);
              },
              onResize: (_, __) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DeckTerminal));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      expect(output, isEmpty);
      expect(pasted, isEmpty);
    },
  );
}
