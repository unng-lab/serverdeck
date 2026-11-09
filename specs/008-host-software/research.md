# Исследование существующих компонентов

## SSH/shell

Decision: переиспользовать ConsoleOwner007 и восемь console.* tools.
Rationale: [ConnectionOwner.bindConsole](../../lib/connections/connection_owner.dart)
проверяет уже подключённую сессию, [transport.openConsole](../../lib/connections/ssh_transport.dart)
использует startOwnedPty существующего клиента; [router](../../lib/mcp/router.dart)
уже маршрутизирует console.*. Нет необходимости в новом transport или runtime.
Alternatives considered: отдельный non-PTY exec не нужен для заданного shell-сценария.

## Конфиги

Decision: чтение/редактирование через команды той же консоли.
Rationale: SSH-пользователь и удалённая ОС определяют права; ИИ выбирает quoting,
редактор, резервную копию и проверку. Пути карточки — только сведения.
Alternatives considered: отдельный file API добавил бы файловый протокол и обработку форматов.

## История

Decision: сохранить существующий volatile console history; добавить краткий metadata-журнал ПО.
Rationale: [007 FR-714/720](../007-server-console/spec.md) запрещает disk transcript;
[console_history](../../lib/console/console_history.dart) уже выдаёт экран/scrollback.
У каждой команды нет надёжного собственного exit code; это интерпретирует ИИ.
Alternatives considered: запись всего терминала не требуется для карточек/журнала.

## CRUD и MCP

Decision: один SoftwareOwner, две Isar-коллекции, существующие DomainCommandGate,
ReceiptBook и MCP grant. [ReceiptBook](../../lib/domain/receipt_book.dart) уже
обеспечивает24h metadata replay и общую квоту100000; не нужен отдельный replay engine.
Alternatives considered: отдельные серверы, модели состояния и permissions не нужны.

## Среда и проверка

Decision: текущий Flutter/Dart/Isar Windows-клиент; нет новых зависимостей выпуска.
Для примеров подходит Ubuntu26, а shell работает в рамках существующей007.
Source facts inspected read-only; исследование не запускало приложение или тесты.
Все проверки реализации — unit/fake/synthetic и разрешённые static checks по AGENTS.md.
