# Vendored xterm.dart 4.0.0

Origin: https://pub.dev/api/archives/xterm-4.0.0.tar.gz
Archive SHA256: 168dfedca77cba33fdb6f52e2cd001e9fde216e398e89335c19b524bb22da3a2
License: MIT, preserved in LICENSE. Only library sources are included.

ServerDeck patches: bounds/parser/control strings; main/alt scrollback cleanup and row ownership; split device replies; reject remote resize; application cursor mode; UI paste routing. ZMODEM optional export/source removed: file transfer is outside the supported profile. SDK formatting and Flutter API compatibility are maintained locally. Behavioral contract: specs/007-server-console/contracts/terminal.md in the application repository.

Saved cursors clamp to resized main/alt screens. Trust clear resets both buffers and parser; the application discards unfinished UTF8 without executing it. Circular row ownership and bounded reflow are maintained locally.

TerminalView exposes onTextInput interception and onPaste delegation. ServerDeck routes platform/IME multiline edits and internal PasteTextIntent to the owner-mediated consent path; ordinary text/Enter retain their normal semantics. TerminalActions respects readOnly and mounted context before paste.
