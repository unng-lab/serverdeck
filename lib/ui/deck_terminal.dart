import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';

/// Shared C26 presentation adapter. All execution, consent and ownership is external.
class DeckTerminal extends StatefulWidget {
  const DeckTerminal({
    super.key,
    required this.terminal,
    required this.readOnly,
    required this.onPaste,
    required this.onResize,
    this.keyboardEligible = true,
  });
  final Terminal terminal;
  final bool readOnly, keyboardEligible;
  final Future<void> Function(String text) onPaste;
  final void Function(int columns, int rows) onResize;
  @override
  State<DeckTerminal> createState() => _DeckTerminalState();
}

class _DeckTerminalState extends State<DeckTerminal> {
  final _focus = FocusNode();
  final _controller = TerminalController();
  void Function(int, int, int, int)? _previousResize;
  late void Function(int, int, int, int) _resize;
  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _previousResize = widget.terminal.onResize;
    _resize = (width, height, pixelWidth, pixelHeight) {
      _previousResize?.call(width, height, pixelWidth, pixelHeight);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onResize(width, height);
      });
    };
    widget.terminal.onResize = _resize;
  }

  void _unbind() {
    if (identical(widget.terminal.onResize, _resize))
      widget.terminal.onResize = _previousResize;
  }

  @override
  void didUpdateWidget(DeckTerminal old) {
    super.didUpdateWidget(old);
    if (old.terminal != widget.terminal) {
      if (identical(old.terminal.onResize, _resize))
        old.terminal.onResize = _previousResize;
      _bind();
    }
    if (widget.readOnly || !widget.keyboardEligible) _focus.unfocus();
  }

  Future<void> _paste() async {
    if (widget.readOnly || !widget.keyboardEligible) return;
    final terminal = widget.terminal;
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!mounted ||
        !identical(terminal, widget.terminal) ||
        widget.readOnly ||
        !widget.keyboardEligible ||
        text == null)
      return;
    await _delegatePaste(terminal, text);
  }

  Future<void> _delegatePaste(Terminal terminal, String text) async {
    if (!mounted ||
        !identical(terminal, widget.terminal) ||
        widget.readOnly ||
        !widget.keyboardEligible)
      return;
    await widget.onPaste(text);
  }

  TerminalTheme _theme(BrandColors c) => TerminalTheme(
    cursor: c['focus'],
    selection: c['selected'],
    foreground: c['text'],
    background: c['surface'],
    black: c['bg'],
    white: c['text'],
    red: c['error'],
    green: c['success'],
    yellow: c['warning'],
    blue: c['running'],
    magenta: c['chart2'],
    cyan: c['accent'],
    brightBlack: c['muted'],
    brightRed: c['error'],
    brightGreen: c['success'],
    brightYellow: c['warning'],
    brightBlue: c['running'],
    brightMagenta: c['chart2'],
    brightCyan: c['accent'],
    brightWhite: c['text'],
    searchHitBackground: c['selected'],
    searchHitBackgroundCurrent: c['focus'],
    searchHitForeground: c['text'],
  );
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<BrandColors>()!;
    final terminal = widget.terminal;
    return Actions(
      actions: {
        _DeckPasteIntent: CallbackAction<_DeckPasteIntent>(
          onInvoke: (_) {
            unawaited(_paste());
            return null;
          },
        ),
      },
      child: Semantics(
        label: 'Терминал',
        textField: true,
        readOnly: widget.readOnly,
        child: TerminalView(
          widget.terminal,
          controller: _controller,
          focusNode: _focus,
          readOnly: widget.readOnly || !widget.keyboardEligible,
          onPaste: (text) => _delegatePaste(terminal, text),
          onTextInput: (text) {
            if (widget.readOnly || !widget.keyboardEligible) return true;
            if (text.contains('\n') || text.contains('\r')) {
              unawaited(_delegatePaste(terminal, text));
              return true;
            }
            return false;
          },
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyV, control: true):
                _DeckPasteIntent(),
            SingleActivator(
              LogicalKeyboardKey.keyV,
              control: true,
              shift: true,
            ): _DeckPasteIntent(),
            SingleActivator(LogicalKeyboardKey.insert, shift: true):
                _DeckPasteIntent(),
            SingleActivator(
              LogicalKeyboardKey.keyC,
              control: true,
              shift: true,
            ): CopySelectionTextIntent.copy,
          },
          theme: _theme(colors),
          textStyle: const TerminalStyle(
            fontFamily: BrandAssets.monoFont,
            fontFamilyFallback: BrandAssets.fontFamilyFallback,
            fontSize: 13,
            height: 1.25,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _unbind();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }
}

class _DeckPasteIntent extends Intent {
  const _DeckPasteIntent();
}
