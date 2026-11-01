# ServerDeck

Текущий выпуск: **0.4.0-preview.1** (Flutter version `0.4.0-preview.1+13`).
Это preview исходников; установщики и готовые бинарники не публикуются.
Подробности — в [истории изменений](CHANGELOG.md).

ServerDeck — desktop-приложение со встроенным Dart-движком: профили серверов,
SSH, состояние и журналы, типизированные профили автоматизации, планы, согласия
и задания. Windows-комплект использует один `serverdeck.exe`; отдельная локальная
служба и отдельный MCP executable не требуются.

Закрытие последнего окна оставляет приложение в трее. Меню трея открывает окно,
«Серверы» и «Настройки», показывает состояние и содержит «Выход». «Выход» завершает
приложение и локальный MCP через общий shutdown. При недоступном трее окно остаётся
доступным. Уже принятые удалённые задания живут по правилам executor; закрытие
окна или потеря MCP-соединения не означает их отмену.

MCP-клиент запускает тот же executable с `--mcp-stdio`: это только подключение к
уже работающему приложению. Оно не запускает приложение, движок или хранилище.
Если ServerDeck завершён, ответов MCP нет: соединитель завершается с ненулевым
кодом и безопасной локальной диагностикой в stderr. Права ИИ определяет выданный
доступ, а не путь к executable или аргумент запуска.

## Разработка и проверка

- [Среда, сборка комплекта и текущий запуск](docs/development/foundation.md).
- [Выдача доступа ИИ и настройка MCP](docs/development/mcp.md).
- [Хранилище schema3 и безопасный отказ](docs/development/embedded-engine-storage.md).
- [Платформы, возможности и prerequisites](docs/development/platform-capabilities.md).
- [Журнал component-проверок](docs/development/embedded-engine-verification.md).

Полный разрешённый набор unit/static проверок:

```powershell
$env:SERVERDECK_FLUTTER_ROOT = 'H:/flutter/flutter'
./tools/test-unit.ps1
lychee "specs/**/*.md"
```

SDK должен соответствовать закреплённой identity из инструкции среды. Скрипт
проверяет форматирование, анализ и текущие unit suites. В текущей задаче дизайн,
UI/native/integration, реальные SSH/FS/Isar, сборка, установка и выпуск не
проверяются. Unit/static результаты не доказывают платформенную готовность.
Реализация embedded-поправки принята в разрешённом static/RAM scope; результаты
и история задач указаны в [Tasks001](specs/001-service-foundation/tasks.md).
Нативная поставка и release/runtime qualification этим не подтверждены.

## Данные и совместимость

Принимается только текущий ServerDeckNext schema3/storage format3. Его IDs,
revisions, credentials, trust, grants, enrollment, история, настройки и задания
сохраняются. Несовместимые схемы1/2/unknown и следы старого upgrade отвергаются
без изменения исходных файлов. Повреждённое или закрытое хранилище не заменяется
пустым. Поддержки старого API, автоматической миграции, rollback и переходных
runtime-оболочек нет. Format4 комплекта приложения и format3 данных — разные
контракты. Удаление исходного кода не удаляет данные установленного приложения
или управляемых серверов.

## Спецификации и Spec Kit

Работа ведётся в существующих пакетах; новая feature под embedded-поправку не
создаётся. Её действующие [требования001](specs/001-service-foundation/spec.md),
[план001](specs/001-service-foundation/plan.md) и [контракты](specs/001-service-foundation/contracts/embedded-engine.md)
имеют приоритет над историческим описанием client/locald.

- [Последовательность пакетов](specs/README.md), [бизнес-требования](specs/business-requirements.md), [трассировка](specs/traceability.md).
- [MCP и делегируемая автоматизация021](specs/021-mcp-control/spec.md), [Tasks021](specs/021-mcp-control/tasks.md).
- [Правила работы и независимого review/fix loop](AGENTS.md), [конституция](.specify/memory/constitution.md).
- [Брендбук](docs/brandbook/README.html).

Старые журналы сохраняют историю своих проверок и не закрывают новые gates.
