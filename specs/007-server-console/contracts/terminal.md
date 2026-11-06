# Terminal/C26 contract

## Profile and supply

Ограниченный xterm/VT UTF-8 профиль поверх vendored xterm4.0.0 MIT; не полная xterm эмуляция. TERM=xterm-256color. Supports cursor movement/save/restore, CR/LF/tab/backspace, erase/insert/delete within screen, SGR16/256/truecolor, scrolling regions, DEC47/1047/1048/1049 alternate screen, application cursor keys, bracketed paste2004. Keys Enter/Backspace/Tab/Escape/arrows/Home/End/Delete/PageUp/PageDown, Ctrl+A–Z. Unicode width следует таблицам engine (upstream Unicode11); корректность всех grapheme/ZWJ не обещается. Invalid UTF-8 заменяется U+FFFD stateful decoder; partial bytes сохраняются до продолжения, до4bytes decoder carry.

Unsupported OSC52 clipboard, OSC8 links, title/icon/bell внешние эффекты, graphics/Sixel/ZMODEM/file transfer, DCS/APC/PM/SOS payload и remote window manipulation не исполняются. Unsupported control strings bounded consume до ST/BEL где применимо. CSI8 resize игнорируется; size query ответ allowed.

## Bounds

Screen80x24 initially,cols2–512,rows1–200. Resize UI clamp к диапазону перед engine/SSH; remote resize не меняет screen. Main maxLines10200 с дополнительным scrollBack<=10000/4MiB, alt maxLines200 и0scrollback. Old rows discard полностью с detach/dispose и корректными anchors, без dangling references backing storage. UTF-8 budget учитывает LF и пробелы plain-text projection строк. На каждом изменённом row пересчитать cached count и обновить total; выполнять eviction при row mutations/scroll/reflow, не после неограниченного write.

Parser escape token<=16384 UTF-8 bytes,<=32 parameters,<=6digits/parameter,value<=65535. Превышение до allocation/add — TerminalLimitException без payload, owner прекращает канал partial/outputLimit. REP counts ограничены65535; все cell spans clamped к ширине, per-token work bounded count*maxWidth. Незавершённый token сохраняется лишь в cap. raw chunk<=16KiB для processing, queue<=1MiB перед admission; crossed action не принимается частично.

## Engine/owner interface

ConsoleTerminalEngine wraps Terminal, bounded stateful UTF8 decoder, feed(Uint8List), finish(), resize(cols,rows), clear(), rows(section), version/truncated/cursor. UI uses that same Terminal via C26; engine doesn't know actor/SSH. Terminal onOutput идёт только в owner-mediated UI action, не напрямую channel.write. Отдельный onResponse для six device/status/cursor/size replies: owner отправляет как internal response через тот же bounded inputFIFO с active/session/SSH/trust guards, без lease/renewal. Неизвестные/опасные OSC callbacks отсутствуют.

UI input encoded через engine textInput/keyInput/paste, без локального echo. Сбор encoded action в короткоживущий buffer до admission; полный action incl bracketed wrappers<=64KiB или rejectwhole. C26 custom shortcuts отключают built-in PasteTextIntent bypass; clipboard read только по UI intent. Multiline consent делегируется owner/UI C14 и exact bytes/session generation/lease; cancel no effect. ReadOnly — visual/interaction aid, owner fences обязательны.

## Shared C26

lib/ui/deck_terminal.dart: DeckTerminal(Terminal terminal, bool readOnly, onPaste, onResize, onFocus eligibility). BrandTheme/fonts существующие C01, controls C02/C10... у feature. Renderer не создаёт channel, lease, retry, trust или history copy. Документация/registry/catalog/synthetic tests обновляются в scope001. Feature tests проверяют data/actions, не geometry/colors/goldens/overflow.

## Plain-text projection

Physical rows содержат text/wrapped/section. Codepoint0=>space, wide continuation не дублировать; C0/C1/ESC не возвращать. screen — active main/alt, scrollback — main даже при alt. Cursor pagination использует Unicode scalars, не UTF16. Snapshot fields current state/historyVersion позволяют не принимать устаревший экран за актуальный; [MCP](mcp-console.md) задаёт границы выдачи.

Platform/IME text edits containing CR or LF are intercepted before terminal.textInput and delegated to the same onPaste consent callback as shortcut paste. Ordinary text edits pass through; physical Enter remains an ordinary key. Internal PasteTextIntent also delegates through that callback and respects readOnly. C26 checks the captured Terminal identity after clipboard awaits; feature consent rechecks server/session/generation/lease and exact payload before admission. Synthetic units cover platform multiline input, Cancel, context/lease changes, ordinary text/Enter and internal paste intents.
