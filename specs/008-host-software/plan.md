# Implementation Plan: ПО сервера и работа ИИ через shell

**Feature**: `008-host-software` | **Date**: 2026-11-09 | **Spec**: [spec.md](spec.md)

## Summary

ИИ работает через уже реализованную общую SSH-консоль. ServerDeck добавляет
локальные карточки ПО, CRUD через UI/MCP и краткий журнал изменений/сообщений.
Анализ сервера использует тот же shell и сохранение обычных карточек.

## Technical Context

- Language/Version: Dart SDK `>=3.13.5 <4.0.0`, Flutter из проекта.
- Dependencies: существующие dartssh2, xterm, Isar Community3.4.1; новых runtime-зависимостей нет.
- Storage: существующая Isar, две новые коллекции, текущий storage format2.
- Platform: Windows-приложение и тот же EXE в MCP bridge mode; удалённый shell
  существующего SSH-подключения. Примеры для Ubuntu26; установочные команды выбирает ИИ.
- Testing: unit и функциональные widget tests с fake dependencies, без реальных SSH/Isar.
- Bounds: карточка32KiB, событие8KiB, ответ1MiB; до10000 карточек/store,
  до1000/profile, последние10000 событий/store; списки страницами25, максимум100.
- Release: текущий полный офлайн-установщик; отдельный backend, runtime или агент не требуются.
- Concurrency: общий application owner, атомарные локальные транзакции,
  optimistic revision и существующий ReceiptBook. Shell сохраняет правила007.

## Constitution Check

Проверка до исследования и после проектирования: все шесть принципов соблюдены.

| Принцип | Решение |
|---|---|
| I, общие компоненты | C02/C03/C04/C05/C07/C08/C09/C10/C11/C12/C13/C16/C18/C20/C26/C28 из001 |
| II, дизайн | Проверяется поведение функции; новых layout/golden gates нет |
| III, unit | Fake owners/repository/transport; никакого запуска продукта или real integration |
| IV, единый EXE | SSH/MCP/Isar принадлежат существующему экземпляру, один SoftwareOwner |
| V, трей | Скрытие/выход/shutdown остаются у runtime; новых команд завершения нет |
| VI, данные | Добавление пустых коллекций совместимо; schema list расширяется без сброса базы и смены format2 |

## Project Structure

### Documentation

- [Требования](spec.md), [исследование](research.md), [модель](data-model.md).
- [Контракт UI/MCP](contracts/tools.md), [unit-приёмка](quickstart.md).
- [Чеклист требований](checklists/requirements.md).

### Source Code

```text
lib/software/software_models.dart       # Card/Event DTO и validation
lib/software/software_owner.dart        # Общие UI/MCP CRUD и сообщения
lib/software/software_view.dart         # Карточки, форма, журнал, задание анализа
lib/storage/records.dart                # Две коллекции и generated records.g.dart
lib/storage/domain_repository.dart      # Чтение, индексы, транзакции, cascade
lib/domain/receipt_book.dart            # Три новых enum-метода существующих receipts
lib/mcp/router.dart                     # Шесть software.* маршрутов
lib/mcp/tool_schemas.dart               # Проверка новых входов
lib/runtime/feature_runtime.dart        # Composition/lifecycle одного owner
lib/profiles/profile_view.dart         # Вкладка ПО выбранного профиля
assets/mcp/tools.json                   # Registry contractVersion3
specs/003-ssh-mcp/contracts/mcp-tools.json # Точная копия registry
 test/                                 # Unit/functional tests и fake adapters
```

Расположение новых файлов фиксирует границы ответственности. Существующий
DomainRepository расширяется напрямую; отдельного storage/replay framework нет.

## Phase 0 — Research

[Исследование](research.md) установило существующие21 tools, общую консоль,
проверки grant и ReceiptBook. Все необходимые решения приняты в этом пакете.

## Phase 1 — Design

### Владельцы и выполнение

ConsoleOwner, ConnectionOwner и SSH transport сохраняют контракт [007](../007-server-console/contracts/mcp-console.md).
Все команды ИИ видны в обычной консоли. Конфиги читаются и изменяются командами
той же ОС; карточка не исполняет пути и не содержит конфиги. Ответ ввода не означает
завершение команды. При разрыве связи нет автоматического повтора удалённого ввода.

SoftwareOwner принимает доверенный UiActor/McpActor, проверяет существующий
DomainCommandGate и вызывает общий repository. Подключение SSH для локального CRUD
не нужно. PublicValue остаётся sealed: typed SoftwareValue wrapper в
lib/domain/models.dart по образцу ConsoleValue оборачивает software DTO, без
возврата raw maps/records через gate. Существующий fake repository находится в
test/fixtures/domain_repository.dart.
Grant проверяется до lookup/replay, перед commit и перед ответом.
Время, автор, UUID и snapshot цели назначаются приложением. Для save/delete/note
после авторизации сначала проверяется committed receipt, затем, только для нового
эффекта, существование профиля/карточки, редакция и цель. Replay после удаления
профиля возвращает прежний MutationValue без восстановления данных.

### Хранение и конкурентность

[Модель](data-model.md) определяет полную замену пяти полей, редакции, пределы,
индексы и события. Save/delete/note, receipt и dataRevision фиксируются одной
транзакцией; ошибки откатывают её целиком. Та же транзакция продвигает existing
profilesListRevision — общий snapshot профилей/ПО для курсоров. Профильные изменения
уже продвигают его; auth-clock/grant bookkeeping меняет global dataRevision,
но не snapshotRevision курсора. Нового поля/миграции для счётчика нет.
Save/update/delete используют существующий
ReceiptBook24h; enum расширяется saveSoftware/deleteSoftware/addSoftwareNote.
После потери ответа нельзя автоматически повторять создание за пределами24h.

В schema list добавляются две коллекции; существующие профили, secrets, settings,
receipts и данные других функций сохраняются. Пустая новая коллекция означает
отсутствие карточек/событий. Обновляются генерация Isar, repository и его fakes.
Удаление профиля каскадно удаляет только его локальные карточки и события.
Смена endpoint оставляет исходную цель видимой; update/note старой карточки
отклоняются, чтение/локальное удаление разрешены.

Журнал хранит metadata и сообщения автора, без terminal transcript.
Последние10000 событий сохраняются между запусками; старые вытесняются при записи.
История удалённой карточки читается в пределах сохранённых событий.

### MCP и UI

[Контракт](contracts/tools.md) фиксирует шесть новых software.* tools, поля,
пагинацию, ошибки и bounds. Registry version3 содержит27 tools; исходные21
и protocol2025-11-25 сохраняются. Две JSON registry и schema validators меняются
вместе с работающими маршрутами. Мост только пересылает запросы существующему owner.

UI использует C16 для вкладки, C07/C09 для записей, C08 для страниц, C05 для
фильтра текущей страницы, C13/C03/C04 для формы, C02 для действий,
C10/C11/C12 для состояний/ошибок, C18/C20/C28 для сведений/журнала/времени,
существующий C26 для консоли. CRUD не вызывает SSH. Конфликт сохраняет введённые
значения и предлагает перечитать карточку; повторное сохранение требует текущей
редакции. Введённое не затирает новую редакцию автоматически.

Анализ: поле желаемого ПО и явная кнопка копирования задания с profileId/целью,
без credentials. UI не запускает внешнего клиента. ИИ обсуждает предложения
с пользователем во внешнем клиенте и сохраняет их через обычный software.save.
Нет отдельной очереди предложений или протокола анализа.

## Implementation Work Packages

Это порядок будущей реализации, а не отчёт о выполненных задачах.

| Пакет | Зависимость и результат | Требования → проверка |
|---|---|---|
| W1 Модель/хранение | DTO, две schema, индексы, queries, quotas, fake transaction; расширить существующий repository | FR-804/806/807/812 → AC-805/808/811, schema audit и synthetic bounds/cascade |
| W2 Общий owner | После W1: CRUD, note, revisions, actor/gate, receipts, atomic events/eviction | FR-805/808/809 → AC-806/807/809/810, stale/replay/revoke/failCommit unit cases |
| W3 MCP | После W2: шесть routes, строгие schemas, registry27, paging/error budgets | FR-801–805/809 → AC-801–807/810, fake route tests, исходные21 tools неизменны |
| W4 UI | После W2: вкладка/форма/история/консоль; подготовка задания анализа | FR-805/806/810/811 → AC-805/808/810–813, functional widgets на fake owners |
| W5 Приёмка | После W3/W4: сценарии quickstart, статические checks, независимое review/fix | FR-801–812 → AC-801–813 и SC-801–805, unit scope без утверждений о real integration |

## Validation

[Quickstart](quickstart.md) задаёт нормальные, ошибочные и граничные unit-сценарии.
После кода: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`,
`flutter test`, `tools/check-test-boundaries.ps1`; schema/import audits по затронутому
коду. После документов: `lychee "specs/**/*.md"`, затем независимый review/fix loop
по AGENTS.md. Проверки общего дизайна не дублируются в функции.

## Complexity Tracking

Нарушений конституции и исключений нет. План ограничен расширением существующего
приложения; shell и доверие остаются у существующих владельцев.

## Коллекция ПО — уточнение пользователя 2026-11-10

Текущий FR-813/SC-806 заменяет ранее реализованный accordion карточек готовым
C06 `DeckCollection<SoftwareCardView>` с adaptive layout. Порция visible, idOf,
четыре колонки, selectedIds и C02 «Подробности» передаются из SoftwareView.
Сортировка и checkbox selection не добавляются. Только selectedSoftwareId
и общая область C09/C18/C28/DeckActions ниже таблицы; API C06 не меняется.
Lifecycle и ограничения — в [контракте](contracts/tools.md#компактная-карточка-по--2026-11-10).
Реализация и обновление functional tests — новая T038; выполненные T031–T033
сохраняются как история прежней композиции. Тесты проверяют колонки/значения,
single selection, refresh/reset, callbacks/currentTarget/pending и доступность
без layout/golden/overflow/matrix. Shared design gate без изменения001 не нужен.

## Компактные события — 2026-11-10

FR-814/SC-807 расширяют W4 только в SoftwareView: вынести текущую композицию
журнала в `_event(SoftwareEventView)` в `lib/software/software_view.dart`.
Использовать готовую строку C07 compact для списка, C02 для действия подробностей,
C18 для полного selectable текста и метаданных под соответствующей строкой;
сводка C07 title/description/statusLabel из type/name, source/time/outcome и Unicode-safe preview по
[контракту](contracts/tools.md#компактное-событие-истории--2026-11-10).
Превью — чистая presentation-функция, не изменяющая DTO. C20 с фиксированной
высотой текста в этой композиции заменяется C18; общий C20 не меняется.

Отдельный set eventId отвечает за lifecycle по UI-контракту;
не связывать их со сбросом сводок карточек. Очистку исчезнувших id выполнять
при успешной загрузке страницы, не при ошибке. Existing `_historyFor`, `_page`
и `_load` обслуживают прежние запросы; раскрытие вызывает только setState.
Новые события после save/note закрыты, остальные остаются раскрытыми при refresh.

Модель/права/receipts/transactions/storage quotas/версия протокола не меняются.
Пределы summary2048 UTF8 bytes и event8KiB сохраняются; отдельного reader API нет.
Новое локальное состояние описано в data-model.md, обоснование выбора — research.md.
Только fake functional unit/widget tests в test/software/software_view_test.dart;
общие компоненты, темы и каталог не меняются, shared design gate не требуется.
Порядок: T034 (tests RED) → T035 (C07 и GREEN) → T038 (таблица ПО и tests)
→ T036 (обязательные checks и review). T037 — уже выполненное исправление спеки.

## Переход к логам службы — 2026-11-10

Обновить текущие C06 columns до name/version/service, перенести C10 old-target
в name builder, сохранить исходный адрес в C18 details. SoftwareView получает
optional ValueChanged<String> onLogs и проверяет unit через validateJournalTarget
из005, currentTarget, pending и доступность callback. Row C02 «Логи» передаёт
точную строку service, без shell или изменения owner ПО.
ProfileViewPanel связывает callback с section1 и transient initialService,
ограниченным profileId/connectionRevision; ручной выбор вкладки и retire workspace
сбрасывают intent. JournalView принимает optional initialService, ставит local
search и выбирает результат JournalsOwner.ensureService. Init/didUpdate/context
и локальный request epoch защищают async-ответы; manual source/search отменяют
ожидание автоматического выбора. Устаревший ответ не меняет UI.
JournalsOwner.ensureService атомарно проверяет ожидаемую connectionRevision,
переиспользует journal(profileId,exact unit) до quota проверки либо создаёт новый
через общий add path. Enabled/revision/name/payload существующего источника не
меняются. Новые — обычный enabled=true source с текущими caps и read-only collector.
Контракт: [service-logs](contracts/service-logs.md); связанный scope005 обновляется.
Новых storage/MCP schemas, зависимостей, сортировки или общих компонентов нет.
T039–T041: implementation/functional tests/checks+independent review. Только unit
fakes данных/действий, без layout/integration acceptance.
