# Feature Specification: MCP и делегируемые профили автоматизации

## Поправка 2026-11-01 — прямое SSH-выполнение

Для исполнения действуют [FR-SSH-001–015 и AC-SSH-01–11](../001-service-foundation/spec.md)
и [единый контракт](../001-service-foundation/contracts/direct-ssh.md).
Они заменяют старые executor wire/enrollment/runtime/Ansible решения ниже и в
связанных исторических документах. MCP tools, области прав, immutable revisions,
точные согласия, current-target fences и история сохраняются. ИИ получает только
типизированные операции движка; SSH, commands/scripts/paths и root-доступ наружу
не публикуются. Профиль — декларативный AST существующих supported steps,
не Ansible playbook. Отдельного серверного компонента и его подтверждения нет.

**Последнее указание пользователя — unit only**: все прежние собственные тесты,
fixtures и harness удаляются; пишутся только unit-тесты под эту задачу. Дизайн,
widget/visual/integration/native/реальные SSH/container проверки сейчас не выполняются.
Исторические результаты ниже остаются историей, не текущим gate. Изменение не
разрешает потерять функции, данные, права или проверки целевого поведения в новых units.

**Уточнение2026-10-30, без обратной совместимости**: действующий
[контракт](../001-service-foundation/contracts/embedded-migration.md) исключает legacy runtime/API/bootstrap,
upgrade1/2, rollback к старым сборкам и переходные оболочки. Старый код удаляется
в этой же задаче после переноса используемой логики, а не остаётся «на переход».
Поддерживается только целевой schema3; несовместимые файлы не изменяются.

**Поправка 2026-10-30**: [основа001](../001-service-foundation/spec.md)
заменяет обязательный locald встроенным engine. [Adoption/return](../001-service-foundation/contracts/embedded-migration.md)
сохраняет нынешний ServerDeckNext; hard cutover исключает только сервис до него.
[MCP app host](../021-mcp-control/contracts/embedded-host.md) заменяет autolaunch/identity,
сохраняя tools/grants. Scope проверок — static/unit/widget без native claims.

**Feature**: `021-mcp-control`
**Created**: 2026-10-21
**Status**: Прежний MVP принят пользователем; embedded-поправка001/021 реализуется. Текущая приёмка — новые unit tests этой задачи и обязательные static/review checks. Прежний >80% coverage gate и T213 отменены, не подтверждены выполнением.

## История: отменённый MVP verification update — 2026-10-23

Весь раздел ниже, включая прежний SC-MCP-UNIT-001, superseded последним unit-only reset. Не является текущим gate; coverage-конвейер удалён.

The user accepted the previous task set for the MVP and subsequently changed
its verification requirements: integration/end-to-end/native-process/Docker
acceptance suites are not required for these MVP tasks. Their historical plans
and results below remain evidence, not pending MVP gates. Product behavior,
authorization, secret custody and data preservation requirements are unchanged.

**SC-MCP-UNIT-001**: unit tests must cover strictly more than80% of executable
lines in the first-party MVP runtime: application lib/, the four ServerDeck
packages' lib/ and bin/, and executor/serverdeck_executor/. Count the union of
covered source lines, not the mean of module percentages. Exactly80% fails.
Exclude generated *.g.dart, third-party dependencies, test fixtures and build/
verification tooling; do not exclude an authored runtime file because it was not
loaded by tests. Missing source coverage makes the measurement incomplete and
cannot produce a passing gate. Report each module and the weighted total.

Run isolated tests with in-memory/fake external boundaries. Native process,
real database/network, Docker and installed-server scenarios are not unit tests
and their hits cannot contribute. Isolated widget component tests with mocked services count as component units;
full application journeys and real native/service interactions do not.
Mandatory formatting, analysis, unit checks, specification links and independent
review remain applicable. See the current MVP section in [Plan](plan.md).

**Planning**: [Plan](plan.md), [Tasks](tasks.md), [Contracts](contracts/mcp.md), [Quickstart](quickstart.md).
**Input**: Управление ServerDeck из Codex и других ИИ через MCP: настройки, состояние, журналы, установка приложений и создание/изменение делегируемых профилей автоматизации.

## Clarifications

### Session 2026-10-21

- ИИ получает только MCP tools, без выдачи SSH-ключей или произвольного shell. UI использует тот же сервис и правила; перевод самого UI на MCP не требуется.
- ИИ должен уметь создавать и изменять сами профили автоматизации, а не только запускать встроенные.
- Q: Где выполнять изолированную приёмку executor вместо отдельной VM? → A: Использовать Docker и GitHub runners; проект публичный. Реальная systemd Docker fixture допускается для приёмки, mock-only проверки — нет; container init restart учитывается отдельно от host kernel reboot.

## User Scenarios & Testing

### User Story 1 — Подключить ИИ и получить состояние (Priority: P1)

Владелец разрешает MCP-клиенту выбранные серверы и чтения. ИИ находит сервер, получает состояние, настройки, ПО и журналы. UI показывает те же объекты; сохранённые настройки остаются после выхода ИИ.

**Why this priority**: Убирает необходимость выдавать ИИ SSH-доступ и вести отдельную модель инфраструктуры.
**Independent Test**: Один locald, UI, два MCP-клиента, disposable Linux и отказной транспорт; Ansible не требуется.
**Acceptance Scenarios**:

1. **AC-MCP-1A Given** разрешение только на A, **When** ИИ перечисляет серверы и читает состояние/настройки/журнал A, **Then** B и его данные недоступны; наблюдения имеют источник, время, полноту, а UI показывает те же объекты.
2. **AC-MCP-1B Given** отзыв, истечение срока, смена credentials или host key, **When** приходит задержанный ответ чтения, **Then** он не выдаёт прежние данные; изменённый ключ блокирует доступ до решения владельца.
3. **AC-MCP-1C Given** закрытые UI и ИИ, **When** ИИ подключается снова, **Then** сохранены настройки, серверы и история; чтения не выдаются за непрерывный сбор и не восстанавливаются скрыто.

### User Story 2 — Создать и изменить профиль автоматизации (Priority: P1)

ИИ читает каталог, создаёт профиль и новые ревизии шагов/параметров. ServerDeck хранит содержимое, происхождение и изменения. Запуск ссылается на неизменную ревизию; изменение черновика не меняет ранее согласованный код.

**Why this priority**: Автоматизация живёт в ServerDeck и развивается через ИИ.
**Independent Test**: Создание, две конкурентные правки, validation failure, новая ревизия после согласования и рестарт; сервер для авторства не требуется.
**Acceptance Scenarios**:

1. **AC-MCP-2A Given** право author, **When** ИИ создаёт профиль и меняет его, **Then** обе ревизии доступны в UI/MCP с составом, автором и digest; конфликт не теряет первую правку. В пустом пространстве author-only разрешение не требует сервера и позволяет подготовить профили; чтение серверов/запуск при этом запрещены.
2. **AC-MCP-2B Given** разрешённая ревизия, **When** сохранена новая с иными эффектами, **Then** старые задания не меняются, новая не наследует разрешение, validation не меняет сервер. Также одинаковое body у A/r1 и A/r2 либо у A/r1 и B/r1 не даёт права запуска новой ревизии/другого профиля; metadata-only правка не исключение.
3. **AC-MCP-2C Given** недопустимые шаги, источники или секреты, **When** запрошены validation/run, **Then** возвращаются структурированные причины без исполнения, скрытой загрузки или утечки в диагностику.

### User Story 3 — Делегировать настройку и установку (Priority: P1)

Владелец разрешает ИИ определённые ревизии, цели и диапазоны параметров на срок. ИИ строит план и запускает подходящее изменение либо передаёт запрос владельцу. Сервис сохраняет desired state, выполняет поддержанные команды напрямую по SSH и проверяет результат. Установка приложений использует этот же путь с требованиями 006.

**Why this priority**: MCP должен доводить управление до проверенного результата.
**Independent Test**: Disposable Ubuntu24.04 amd64 systemd Docker fixture on GitHub runners (or explicitly owned VM): служба, конфигурационный файл, PostgreSQL и ClickHouse, конфликт, обрыв, отмена и отзыв.
**Acceptance Scenarios**:

1. **AC-MCP-3A Given** подходящая делегация, **When** ИИ применяет настройку/установку, **Then** один durable job и проверенный результат видны UI/MCP; последующее чтение выявляет drift без автоматической записи.
2. **AC-MCP-3B Given** выход за цели/параметры/срок или новая ревизия, **When** запрошен apply, **Then** нет исполнения; возможен запрос владельцу с точной целью/эффектами, ИИ не подтверждает его сам.
3. **AC-MCP-3C Given** потеря ответа или сбой после эффекта, **When** другой клиент повторяет запрос/recovery, **Then** нет двойного запуска; unknown удерживает physical-host lock, reconciliation не запускает новый playbook.
4. **AC-MCP-3D Given** отзыв во время задания, **When** достигнута безопасная граница, **Then** следующие эффекты запрещены, уже произошедшие сохранены; отзыв не обещает rollback текущей операции.

### Edge Cases

- UI и два ИИ правят одну ревизию или запускают задания через разные профили одного физического хоста.
- Инструкции внутри logs/profile остаются недоверенными данными, не расширяют полномочия.
- Нет прав root/sudo или штатного prerequisite: нет скрытой установки и обхода отказа; обычное доступное SSH-чтение продолжает работать.
- Закрытие MCP-клиента не отменяет durable job, не стирает историю/lock и не разрешает повтор.
- Переполнение журналов, секретные параметры, просроченный план, отозванная ревизия и неизвестный storage format объясняются явно.

## Requirements

### Scope и зависимости

021 владеет MCP, ИИ grants/delegation и авторством профилей автоматизации. [001](../001-service-foundation/spec.md) остаётся владельцем locald, storage, SSH, доверия и jobs; [002](../002-security-storage/spec.md) — защиты секретов; [006](../006-software-installation/spec.md) — критериев установки; [009](../009-observability/spec.md) — расширенных журналов; [010](../010-system-service-management/spec.md)/[013](../013-files-diagnostics/spec.md) — соответствующих системных/конфигурационных действий.

Порядок: 001.1 → 021.1 с необходимыми чтениями 001.2 → 021.2 → jobs 001.3/006 и 021.3. Номер 021 не означает ожидания всех 020 пакетов. Возможности 007–020 автоматически не добавляются в scope; при реализации используют тот же вход. Public network MCP, multi-user SaaS, provisioning и неограниченный shell не входят в первую поставку.

«Только MCP» — граница доступа ИИ в продукте: встроенный engine выполняет SSH внутри приложения. Это не обещает запретить владельцу отдельный SSH-клиент или изолировать процесс с полными правами того же пользователя ОС.

### Functional Requirements

- **FR-MCP-001**: Стандартные MCP-клиенты MUST обнаруживать и вызывать tools без SDK конкретной ИИ-компании. Stdout содержит только протокол; несовместимость версии/lifecycle явная.
- **FR-MCP-002**: Единственный встроенный engine MUST владеть серверами, настройками, наблюдениями, автоматизацией, permissions и jobs. UI/MCP используют одни ID/ревизии/правила; ИИ не получает credentials/raw SSH/shell. Bridge соединяется с работающим app, включая tray.
- **FR-MCP-003**: Владелец MUST выдавать/видеть/отзывать отдельные grants: цели, read/logs/author/plan/apply, точные ревизии профилей, параметры и срок. Default deny; чтение/авторство не дают apply, grant management или подтверждение доверия.
- **FR-MCP-004**: Locald MUST проверять полномочия каждого вызова, перед новым эффектом и выдачей результата. Отзыв/срок/ревизии цели, доступа и доверия инвалидируют прежние планы и задержанные чтения; рестарт не восстанавливает отозванные права.
- **FR-MCP-005**: Tools MUST предоставлять inventory/state/configuration и bounded logs с фильтрами/курсорoм, источником/временем и stale/denied/unsupported/incomplete/dropped. Бюджеты 001 общие с UI; raw logs не сохраняются в основной БД.
- **FR-MCP-006**: Author MUST создавать, перечислять, читать, сравнивать, проверять, изменять и архивировать профили. Ревизия содержит назначение, среду, шаги, параметры, права, эффекты, post-checks, версию/digest/автора. История неизменна; validation не исполняет профиль.
- **FR-MCP-007**: Новая ревизия MUST NOT наследовать право исполнения или менять старую. Контракт задаёт поддержанные шаги и проверяемую область эффектов; произвольные plugins/loaders/shell и обход типизированного SSH-адаптера запрещены, ограничения видны до запуска.
- **FR-MCP-008**: План MUST сохранять exact inputs, desired state, ревизии профиля/рецепта, эффекты, host identity, credentials/trust revision, предусловия и post-checks. Drift — отличие desired/observed со временем; reconcile не исправляет сервер автоматически.
- **FR-MCP-009**: Apply MUST требовать согласия на неизменный план либо действующей делегации на тройку (profileId, revision, bodyDigest), цели и параметры. Иначе approval-required; только владелец через доверенный UI расширяет права/подтверждает запрос. Подходящая делегация не требует повторного UI-подтверждения каждого запуска.
- **FR-MCP-010**: Установка MUST использовать тот же plan/job/direct-SSH путь и все требования 006: package pins, fresh preflight, соседние данные, защита NetBird, SQL post-check. Exit SSH-команды не заменяет проверку результата.
- **FR-MCP-011**: Изменения MUST использовать expected revision и durable request identity; duplicate возвращает прежний job, другой input с тем же id отклонён. Один physical-host writer для UI/ИИ/контроллеров; unknown сохраняет lock до установления исхода.
- **FR-MCP-012**: Jobs MUST иметь status, упорядоченные bounded events/progress, отмену и reconciliation. Отмена до старта не пишет; после старта останавливает будущие шаги на безопасной границе без обещания rollback. MCP disconnect не отменяет durable job и не провоцирует повтор.
- **FR-MCP-013**: Engine MUST объявлять compatibility/prerequisites прямого SSH до apply: права root/noninteractive sudo и штатные средства ОС. Отдельные executor/control node/Ansible не требуются. Чтение не устанавливает зависимости; секреты не попадают в argv, scripts, обычные файлы или events.
- **FR-MCP-014**: UI MUST показывать grants/scope/срок/отзыв, профили/изменения, запросы согласия, desired/observed и jobs с теми же результатами, что MCP. История содержит origin client и основание полномочий без секретов.
- **FR-MCP-015**: Обновление MUST сохранять данные новой реализации 001, добавлять структуры атомарно с явной версией и отказом несовместимости без reset. Hard cutover старого сервиса не повторяется для нового пространства.
- **FR-MCP-016**: Поставка MUST включать MCP entry point, совместимые UI/locald, tool schemas, примеры независимых клиентов, prerequisites check и изолированную воспроизводимую приёмку; реальные сохранённые серверы не подключаются автоматически.

### Key Entities

- **Client grant**: отдельная идентичность ИИ, права/цели/срок/ревизия/отзыв.
- **Automation revision**: неизменное содержимое, типизированные параметры, digest, автор, родитель, совместимость/post-checks.
- **Delegation**: разрешённые ревизии, границы параметров/целей, срок, владелец/отзыв.
- **Plan / desired state / observation / job**: общие сущности locald с origin/grant/profile revision, намерение отдельно от результата.
- **Approval request**: ожидающий решения владельца неизменный план, не самостоятельное право ИИ.

## Success Criteria

### Measurable Outcomes

- **SC-MCP-001**: Два независимых стандартных клиента проходят discovery → state/logs → profile create/update → plan → apply/status на одном пространстве; UI показывает те же ревизии/job ID.
- **SC-MCP-002**: Все AC-MCP-1A–3D проходят, включая отказы/границы; запрещённые действия не меняют сервер, seeded credentials отсутствуют в ответах/диагностике.
- **SC-MCP-003**: Повтор до/после потери ответа и рестарта создаёт ровно один job/эффект; unknown/конкуренция не допускают второго writer.
- **SC-MCP-004**: Реальная изолированная приёмка подтверждает службу/файл, PostgreSQL/ClickHouse, drift и post-checks; mock-only результат gate не закрывает.
- **SC-MCP-005**: Авторство/сохранённое состояние работают без подключения к серверу; исполнение объясняет недоступность. Все лимиты 001 соблюдаются суммарно для UI/ИИ.
- **SC-MCP-006**: Миграция сохраняет профили/секреты/настройки/историю новой реализации; mandatory checks и completed independent review не имеют незакрытых подтверждённых замечаний.

## Assumptions

- Windows первая, Ubuntu 24.04 amd64/systemd первая target; обязательное облако/смена Flutter/Dart/Isar не требуются.
- Локальный stdio MCP достаточен для первой поставки; remote MCP требует отдельного auth/network design.
- Авторство означает поддержанное декларативное содержимое, компилируемое движком в ограниченные SSH-операции. Неограниченное выполнение скачанного playbook не подразумевается; выразительность определяется Plan/контрактом до реализации.
- ИИ не подтверждает host key и не выдаёт себе права. Владелец подготавливает credentials/trust; дальнейшие разрешённые действия не требуют лишнего повторного согласия.
- Completed tasks 001 сохраняются; интеграция добавляется новыми задачами с отдельной приёмкой.

## UI-компоненты и приёмка (003.4)

Обязательны [библиотека C01–C30](../003-design-system/component-library.md) и [общий контракт применения](../003-design-system/contracts/feature-adoption.md). C ID задаёт семейство готовых элементов, а не новый backend scope. C01 (токены), C02 (действия), C10–C12 (статусы/сообщения/состояния) и C17 (каркас страницы) применяются там, где соответствующая UI-композиция уже требуется этим пакетом.

| Композиция этого пакета | Готовые элементы | Данные, состояния и ограничения |
| --- | --- | --- |
| Grants, делегации и запросы согласия | C03, C04, C05, C06, C13, C14, C18, C24, C28 | Scope/цели/ревизии/параметры/срок/отзыв и отдельный UI-owner; кнопка не выдаёт права, stdout MCP не получает UI/demo вывод. |
| Профили автоматизации и drift | C05, C06, C13, C18, C19, C25, C26 | Exact revision/bodyDigest/author, validation и desired/observed; редактор не выполняет профиль, сравнение не запускает reconcile. |
| План, задания и журнал | C10, C11, C18, C20, C23, C24 | Тот же plan/job ID и authority, что у MCP; unknown/cancel-requested/terminal различимы, disconnect не создаёт новый job, origin не раскрывает секреты. |

- **FR-UI-021-01**: Объявленные композиции MUST использовать перечисленные семейства и их применимые варианты; поля/действия сохраняют предметный смысл таблицы. Общая разметка, токены и поведение не копируются в отдельную реализацию экрана. Отсутствующий вариант сначала расширяется в 003 по общему контракту.
- **FR-UI-021-02**: Данные, callbacks, validation, поддерживаемая порция/сортировка и разрешённые эффекты MUST принадлежать owner этого пакета через действующий контракт 001; компонент не выполняет собственные запросы, retries или выдачу полномочий. Loading/empty/no-results/error/unavailable/stale/partial/unknown применяются по смыслу полученного результата.
- **FR-UI-021-03**: План и задачи MUST содержать mapping «композиция → C ID/вариант → данные/событие owner → критерий проверки». UI-работы ограничены объявленными здесь сценариями; существующая история задач сохраняется, реализация будущих backend возможностей приёмкой 003 не подтверждается.

**Проверяемая приёмка UI:**

- **AC-UI-021-01**: Для каждой строки таблицы сопоставлены её данные/действия и C IDs в плане/задачах; новый экран собирается из готовых элементов. Предметные последствия и ограничения строки видны пользователю, без копирования palette/spacing правил из 003.
- **AC-UI-021-02**: В утверждённом gate данного этапа проверены применимые normal/failure/boundary состояния, точная цель/ревизия и отсутствие запрещённого callback. Утрата readiness/authority не оставляет приватный draft или применимые поздние результаты; неизвестный исход записи не запускает повтор. N/A с причиной фиксируется в mapping.
- **AC-UI-021-03**: При UI-приёмке применяются матрица размеров/тем/масштабов, keyboard/focus/semantics и сохранение всех полей из 003. Существующий unit-only или иной ограниченный gate пакета не расширяется этой поправкой: непроведённые UI/native проверки записываются pending с их будущим gate, без заявления UI-готовности.
