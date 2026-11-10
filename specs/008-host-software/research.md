# Исследование существующих компонентов

## Компактные события — 2026-11-10

Decision: готовая строка C07 compact с C02 действием, C18 для полного сообщения
и метаданных с естественной высотой; состояние по eventId в SoftwareView.
Rationale: по уточнению пользователя коллекция собирается готовым списком,
а не набором отдельных accordion-карточек. Текущий DeckLogMessage в lib/ui/deck_page.dart использует height200,
что оставляет пустую область даже для короткого summary; C18 уже поддерживает
selectable literal value. Все данные загружены действующим history.list.
Alternatives considered: изменение общего C20 затрагивает других пользователей
компонента и не требуется; сокращение summary в storage/MCP теряет исходные данные.
Новых зависимостей/исследовательских неизвестных для редизайна нет.

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

## Таблица ПО — уточнение пользователя 2026-11-10

Decision: C06 DeckCollection с названием/версией/службой/исходным хостом;
подробности одной выбранной записи в общей области C18/C28 с прежними действиями.
Rationale: пользователь явно выбрал таблицу для сравнения однотипных записей.
Alternatives considered: C07 список был предложен пользователю как альтернатива;
отдельные C09/C19 accordion-карточки отклонены по его обратной связи.
