import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/console/terminal_engine.dart';

void main() {
  test(
    'trust clear discards incomplete UTF8 and capped OSC without execution',
    () {
      final engine = ConsoleTerminalEngine();
      engine.feed(
        Uint8List.fromList(utf8.encode('secret\r\n\x1b[?1049hsecret-alt')),
      );
      engine.feed(
        Uint8List.fromList([...utf8.encode('\x1b]${'a' * 16382}'), 0xc2]),
      );
      expect(engine.clear, returnsNormally);
      expect(
        engine.screen.map((r) => r.text).join(),
        isNot(contains('secret')),
      );
      engine.feed(Uint8List.fromList(utf8.encode('\x1b[?1049lnew')));
      expect(
        engine.scrollback.map((r) => r.text).join(),
        isNot(contains('secret')),
      );
      expect(
        engine.screen.map((r) => r.text).join(),
        isNot(contains('secret')),
      );
      expect(engine.screen.map((r) => r.text).join(), contains('new'));
    },
  );
  test('saved cursor stays within main and alt screen after shrink', () {
    for (final alt in [false, true]) {
      final engine = ConsoleTerminalEngine();
      if (alt) engine.feed(Uint8List.fromList(utf8.encode('\x1b[?1049h')));
      engine.feed(Uint8List.fromList(utf8.encode('\x1b[24;80H\x1b7')));
      engine.resize(20, 10);
      engine.feed(Uint8List.fromList(utf8.encode('\x1b8X')));
      expect(engine.cursorY, lessThan(10));
      expect(engine.cursorX, lessThanOrEqualTo(20));
      expect(engine.screen.map((r) => r.text).join(), contains('X'));
    }
  });
  test('fragmented UTF8 and VT preserve text and alternate screen', () {
    final engine = ConsoleTerminalEngine();
    for (final byte in utf8.encode('Привет\r\n\x1b[31mred\x1b[0m')) {
      engine.feed(Uint8List.fromList([byte]));
    }
    expect(engine.screen.map((r) => r.text).join('\n'), contains('Привет'));
    expect(engine.screen.map((r) => r.text).join('\n'), contains('red'));
    engine.feed(Uint8List.fromList(utf8.encode('\x1b[?1049hALT')));
    expect(engine.isAlt, isTrue);
    expect(engine.screen.first.text, contains('ALT'));
    engine.feed(Uint8List.fromList(utf8.encode('\x1b[?1049l')));
    expect(engine.screen.map((r) => r.text).join('\n'), contains('Привет'));
  });

  test(
    'device replies use separate owner path and remote resize is ignored',
    () {
      final replies = <String>[];
      final engine = ConsoleTerminalEngine(onResponse: replies.add);
      final user = <String>[];
      engine.terminal.onOutput = user.add;
      engine.feed(Uint8List.fromList(utf8.encode('\x1b[6n\x1b[8;999;999t')));
      expect(replies, isNotEmpty);
      expect(user, isEmpty);
      expect(engine.terminal.viewWidth, 80);
      expect(engine.terminal.viewHeight, 24);
    },
  );

  test('output never manufactures history for unechoed input', () {
    final engine = ConsoleTerminalEngine();
    engine.encodeText('synthetic-password');
    expect(
      engine.screen.map((r) => r.text).join(),
      isNot(contains('password')),
    );
    engine.feed(Uint8List.fromList(utf8.encode('\x1b]52;c;c2VjcmV0\x07safe')));
    expect(engine.screen.first.text, contains('safe'));
    expect(engine.screen.first.text, isNot(contains('c2VjcmV0')));
  });

  test('bounded scrollback evicts oldest text and releases rows', () {
    final engine = ConsoleTerminalEngine(maxScrollbackLines: 3);
    for (var i = 0; i < 32; i++) {
      engine.feed(Uint8List.fromList(utf8.encode('row$i\r\n')));
    }
    expect(engine.scrollback.length, 3);
    expect(engine.truncated, isTrue);
    expect(
      engine.scrollback.map((r) => r.text).join(),
      isNot(contains('row0')),
    );
    engine.clear();
    expect(engine.scrollback, isEmpty);
  });

  test(
    'oversized or unfinished sequences terminate before unbounded state',
    () {
      final engine = ConsoleTerminalEngine();
      engine.feed(Uint8List.fromList(utf8.encode('\x1b]0;')));
      expect(
        () => engine.feed(Uint8List.fromList(utf8.encode('a' * 16384))),
        throwsA(isA<TerminalLimitException>()),
      );
      for (final value in ['\x1b[9999999C', '\x1b[${'1;' * 33}m']) {
        expect(
          () => ConsoleTerminalEngine().feed(
            Uint8List.fromList(utf8.encode(value)),
          ),
          throwsA(isA<TerminalLimitException>()),
        );
      }
    },
  );

  test(
    'scroll region and erase spans stay valid under synthetic large counts',
    () {
      final engine = ConsoleTerminalEngine();
      engine.feed(Uint8List.fromList(utf8.encode('one\r\ntwo\r\nthree')));
      engine.feed(Uint8List.fromList(utf8.encode('\x1b[1;3r\x1b[1S\x1b[1T')));
      expect(engine.screen.length, 24);
      engine.feed(Uint8List.fromList(utf8.encode('\x1b[65535X\x1b[65535@')));
      expect(engine.terminal.buffer.lines[0].length, lessThanOrEqualTo(512));
    },
  );

  test('byte budget and resize reflow retain bounded readable history', () {
    final engine = ConsoleTerminalEngine(maxScrollbackBytes: 162);
    for (var i = 0; i < 40; i++) {
      engine.feed(Uint8List.fromList(utf8.encode('entry$i\r\n')));
    }
    expect(engine.scrollback.length, lessThanOrEqualTo(2));
    expect(engine.truncated, isTrue);
    engine.resize(2, 24);
    expect(engine.terminal.mainBuffer.scrollBack, lessThanOrEqualTo(10000));
    expect(engine.screen.length, 24);
    engine.resize(512, 200);
    expect(engine.screen.length, 200);
  });

  test('application cursor keys and bounded ignored strings preserve data', () {
    final engine = ConsoleTerminalEngine();
    engine.feed(Uint8List.fromList(utf8.encode('\x1b[?1h')));
    expect(utf8.decode(engine.encodeKey('ArrowUp')), '\x1bOA');
    engine.feed(Uint8List.fromList(utf8.encode('\x1bPignored\x1b\\text')));
    expect(engine.screen.first.text, startsWith('text'));
  });
}
