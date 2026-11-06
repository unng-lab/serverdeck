import 'dart:convert';
import 'dart:typed_data';

import 'package:xterm/core.dart';

export 'package:xterm/core.dart' show TerminalLimitException;

final class ConsoleTerminalRow {
  const ConsoleTerminalRow(this.text, this.wrapped);
  final String text;
  final bool wrapped;
}

/// One bounded engine for both renderer and MCP, never a second transcript.
final class ConsoleTerminalEngine {
  ConsoleTerminalEngine({
    void Function(String)? onResponse,
    int maxScrollbackLines = 10000,
    int maxScrollbackBytes = 4194304,
  }) : terminal = Terminal(maxLines: 10200, onResponse: onResponse) {
    terminal.mainBuffer
      ..maxScrollbackLines = maxScrollbackLines.clamp(0, 10000)
      ..maxScrollbackBytes = maxScrollbackBytes.clamp(1, 4194304);
    terminal.onResize = (_, __, ___, ____) {
      historyVersion++;
    };
    _decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(StringConversionSink.from(_DecodedText(_write)));
  }
  final Terminal terminal;
  late ByteConversionSink _decoder;
  int historyVersion = 1;
  bool _finished = false;
  bool get truncated => terminal.mainBuffer.truncated;
  bool get isAlt => terminal.isUsingAltBuffer;
  int get cursorX => terminal.buffer.cursorX;
  int get cursorY => terminal.buffer.cursorY;
  List<ConsoleTerminalRow> get scrollback => [
    for (var i = 0; i < terminal.mainBuffer.scrollBack; i++)
      _row(terminal.mainBuffer.lines[i]),
  ];
  List<ConsoleTerminalRow> get screen => [
    for (var i = terminal.buffer.scrollBack; i < terminal.buffer.height; i++)
      _row(terminal.buffer.lines[i]),
  ];
  ConsoleTerminalRow row(bool screen, int index) {
    final buffer = screen ? terminal.buffer : terminal.mainBuffer;
    final offset = screen ? buffer.scrollBack : 0;
    return _row(buffer.lines[index + offset]);
  }

  static ConsoleTerminalRow _row(BufferLine line) =>
      ConsoleTerminalRow(Buffer.plainText(line), line.isWrapped);

  void _write(String text) {
    if (text.isEmpty) return;
    terminal.write(text);
    historyVersion++;
  }

  void feed(Uint8List bytes) {
    if (_finished) return;
    if (bytes.length > 1048576) throw const TerminalLimitException();
    for (var i = 0; i < bytes.length; i += 16384) {
      _decoder.add(
        Uint8List.sublistView(bytes, i, (i + 16384).clamp(0, bytes.length)),
      );
    }
  }

  void finish() {
    if (_finished) return;
    _finished = true;
    _decoder.close();
  }

  void clear() {
    // Discard the in-memory decoder: closing it executes pending remote bytes.
    // A trust reset must never interpret more input or fail before clearing.
    terminal.clearOutput();
    _finished = false;
    _decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(StringConversionSink.from(_DecodedText(_write)));
    historyVersion++;
  }

  void resize(int columns, int rows) {
    terminal.resize(columns.clamp(2, 512), rows.clamp(1, 200));
    historyVersion++;
    terminal.notifyListeners();
  }

  Uint8List _encode(void Function() encode) {
    final output = StringBuffer();
    final previous = terminal.onOutput;
    terminal.onOutput = output.write;
    try {
      encode();
    } finally {
      terminal.onOutput = previous;
    }
    final result = Uint8List.fromList(utf8.encode(output.toString()));
    if (result.isEmpty || result.length > 65536) {
      throw const TerminalLimitException();
    }
    return result;
  }

  Uint8List encodeText(String text, {bool paste = true}) => _encode(() {
    if (paste) {
      terminal.paste(text);
    } else {
      terminal.textInput(text);
    }
  });

  Uint8List encodeKey(String name) => _encode(() {
    if (name.startsWith('Ctrl+') &&
        name.length == 6 &&
        name.codeUnitAt(5) >= 65 &&
        name.codeUnitAt(5) <= 90) {
      terminal.textInput(String.fromCharCode(name.codeUnitAt(5) - 64));
      return;
    }
    final key = switch (name) {
      'Enter' => TerminalKey.enter,
      'Backspace' => TerminalKey.backspace,
      'Tab' => TerminalKey.tab,
      'Escape' => TerminalKey.escape,
      'ArrowUp' => TerminalKey.arrowUp,
      'ArrowDown' => TerminalKey.arrowDown,
      'ArrowLeft' => TerminalKey.arrowLeft,
      'ArrowRight' => TerminalKey.arrowRight,
      'Home' => TerminalKey.home,
      'End' => TerminalKey.end,
      'Delete' => TerminalKey.delete,
      'PageUp' => TerminalKey.pageUp,
      'PageDown' => TerminalKey.pageDown,
      _ => throw ArgumentError('Unsupported terminal key'),
    };
    terminal.keyInput(key);
  });
}

final class _DecodedText implements Sink<String> {
  const _DecodedText(this.write);
  final void Function(String) write;
  @override
  void add(String data) => write(data);
  @override
  void close() {}
}
