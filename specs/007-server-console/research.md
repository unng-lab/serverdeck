# Research: Консоль сервера

Дата: 2026-11-06. Источники намерений: [spec](spec.md), конституция и текущий код.

## Clarify

Все десять категорий clarify проверены: scope/actors, данные/lifecycle, взаимодействие, нефункциональные требования, зависимости, отказы, ограничения, терминология, acceptance, placeholders — Clear на продуктовом уровне. Вопросов 0: встроенная вкладка, выбор оболочки и общий MCP-доступ уже подтверждены. Оставшиеся вопросы относятся к техническому плану и решены ниже. Extensions hooks отсутствуют.

## Terminal engine

Decision: vendored xterm.dart 4.0.0 (MIT), path dependency third_party/xterm. Точный архив SHA256 168dfedca77cba33fdb6f52e2cd001e9fde216e398e89335c19b524bb22da3a2. Сохраняются LICENSE, origin и локальные patches. Никаких native PTY/process/WebView: удалённый PTY обслуживает существующий SSH.

Rationale: Flutter renderer и готовое VT-состояние; Windows, Dart 3 и Flutter подходят текущему приложению. Непатченный upstream не ограничивает parser state/байты scrollback и смешивает device replies с пользовательским onOutput.

Alternatives: внешний терминал противоречит подтверждённой встроенной вкладке; самостоятельный parser дублирует стандартный движок; непатченный registry dependency не выполняет caps. flutter_pty/ZMODEM не подключаются.

Sources: [registry](https://pub.dev/api/packages/xterm), [4.0.0 archive](https://pub.dev/api/archives/xterm-4.0.0.tar.gz), [upstream](https://github.com/TerminalStudio/xterm.dart), [Terminal API](https://pub.dev/documentation/xterm/latest/xterm/Terminal-class.html). Версия проверена по registry при исследовании, не предполагается из памяти.

Обязательные patches: ограниченный escape parser; clamp spans Buffer к размеру строки; корректный discard scrollback с освобождением ссылок; main/alt caps; CSI8 window resize игнорируется; отдельный onResponse для device/status/cursor/size replies; application cursor keys используют cursorKeysMode, не appKeypadMode; scrollUp/Down не оставляют duplicate ownership строк. [Контракт терминала](contracts/terminal.md) задаёт точные caps и профиль.

## SSH capability и конечная отправка

Decision: расширить существующий vendored dartssh2 bounded cancellable PTY API и типизированной ConsoleConnectionPort; использовать ту же аутентифицированную SSH transport identity. Обычный SSHSession.stdin запрещён для управляемого PTY: он оставляет unsent bytes в async stream/remote-window queue без lease identity.

Rationale: shell().timeout() не отменяет поздний CHANNEL_OPEN/PTY/shell. _AdmittedSocket сейчас принимает уже зашифрованные пакеты и проверяет только connection actor. Выбросить encrypted packet после lease revoke нельзя: SSH sequence/cipher перестанет соответствовать следующему пакету.

Decision: guarded PTY data/setup/window requests проходят новый immediate send boundary. Дождаться socket drain и remote window/rekey вне gate; внутри существующего admission gate проверить socket queue empty, kex idle, actor/session/lease; зарезервировать capacity до encryption и синхронно выполнить trySendPacket + raw.sink.add. Если queue/rekey снова заняты — retry до encryption. После encryption ошибка фатальна для transport, plaintext повторно не отправляется. Flush вне gate удерживает reservation и FIFO tail. Generic packets продолжают штатный путь. [Контракт SSH](contracts/ssh-console.md) фиксирует lifecycle и тестовые seam.

Alternatives: второй SSH-login нарушает общий сеанс; проверка только перед stdin.add не закрывает гонку; фильтрация ciphertext ломает SSH. Полная переделка transport не нужна при атомарном immediate boundary.

## Settings, history и replay

Decision: nullable AppSettings.terminalConfiguration со строгим JSON v1; отсутствующее значение означает built-in default. Это совместимое добавление, format2 сохраняется; generated reader использует readStringOrNull, не initializer как доказательство. Неподдерживаемое/повреждённое значение блокирует терминальные настройки с ошибкой без перезаписи. Остальные функции продолжают работать.

Decision: один engine на сессию; MCP читает plain-text rows того же screen/scrollback. Cursor связывает owner/session generation/historyVersion и row/scalar offset. Version mismatch => historyGap/resetRequired; immutable transcript не создаётся. Внешний клиент может сохранить полученное, приложение этого не отзывает.

Decision: in-memory replay ledger на clientId/grantVersion с монотонным operation sequence и сохранённым high-water; evicted sequences отклоняются, не принимаются как новые. Дисковые mutation receipts003 не содержат terminal payload. Точные параметры — [data model](data-model.md) и [MCP](contracts/mcp-console.md).
