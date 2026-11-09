# Tasks: ПО сервера и работа ИИ через shell

**Input**: [spec.md](spec.md), [plan.md](plan.md), [data-model.md](data-model.md),
[контракт](contracts/tools.md), [unit-приёмка](quickstart.md).

Тесты ограничены unit/fake/synthetic и функциональными widget tests по AGENTS.md.
US1=US-801, US2=US-802, US3=US-803, US4=US-804. [P] означает независимые файлы,
не разрешение менять один owner параллельно. Отметка означает выполненный результат,
а не намерение. Внешние GitHub issues и выпуск не входят в scope.

## Phase 1 — Setup

- [X] T001 Зафиксировать Clarify/Checklist/Analyze и карту FR→задачи в specs/008-host-software/stages.md; проверить актуальные console/repository/gate seams до кода (FR-801–812).
- [X] T002 Проверить доступные fake adapters и структуру unit suite в test/fixtures/ и lib/storage/domain_repository.dart; использовать существующие зависимости, без новых runtime и без запуска продукта (FR-807/812).

## Phase 2 — Foundation

- [X] T003 Реализовать DTO/validation в lib/software/software_models.dart: «IDs UUIDv4 lowercase; revision и UTC timestamps — safe JSON integer; revision≥1», «Все строки — корректный Unicode без NUL», name «Trim,1..100 символов», version/service «null или trim-строка≤256 символов», dataPaths/configPaths «Каждый список≤16 уникальных абсолютных POSIX-путей,≤1024 UTF8 bytes на путь, без CR/LF/NUL; literal, без чтения/нормализации файлов», полный CardView≤32KiB; полная замена пяти полей (FR-804/806).
- [X] T004 Добавить SoftwareCardRecord/SoftwareEventRecord в lib/storage/records.dart и workspaceSchemas, сгенерировать lib/storage/records.g.dart: auto id, unique business UUID, индекс profileId/softwareId/createdAt, цель endpointId/host/port/username, revision/времена от owner. Для event: kind «created / updated / deleted / note», action «install / update / remove / configure / analyze / status / other» только note; outcome «success / failed / unknown» только note, summary «Для note1..2048 UTF8 bytes; для CRUD фиксированный текст по kind», changedFields из пяти полей только updated; actorKind ui/mcp, clientId только MCP; EventView≤8KiB. Сохранить format2 и существующие schema/данные (FR-807/808/809/812).
- [X] T005 Расширить DomainRead/DomainTransaction/Isar adapter в lib/storage/domain_repository.dart и fake repository в test/fixtures/: indexed reads/counts/ordered pages, атомарные card/event/receipt/dataRevision, cascade профиля; последние10000 events/store с eviction oldest(createdAt,eventId), максимум10000 cards/store и1000/profile без eviction карточек (FR-807/808/812).
- [X] T006 Добавить typed SoftwareValue wrapper по образцу ConsoleValue и расширить существующие failure/field enums в lib/domain/models.dart и ReceiptMethod в lib/domain/receipt_book.dart: SOFTWARE_NOT_FOUND и saveSoftware/deleteSoftware/addSoftwareNote; общий metadata replay24h/квота100000, без второго replay engine (FR-805/808/809).
- [X] T007 Создать unit tests validation/transaction rollback/schema list в test/software/: границы Unicode/пути/nullable/бюджеты, failAfterWrite/failCommit и отсутствие частичных card/event/receipt/dataRevision, сохранение format2 и чужих данных на fake repository (FR-804/807/808/812; AC-805/808/809).

## Phase 3 — US1: ИИ работает с сервером (P1)

**Goal**: общий существующий shell для команд и конфигов.
**Independent Test**: fake transport, действующие console.* routes, общий UI/MCP вывод.

- [X] T008 [US1] Добавить/переиспользовать проверяемые unit cases в test/console/ для console open/acquire/write/read, команд чтения/изменения конфига как обычного ввода, busy/disconnect/revoke; ack ввода не является command completion, retry не отправляет удалённую команду повторно (FR-801/802/803; AC-801–804; SC-802). При доказанном покрытии сослаться на конкретные существующие тесты в stages.md, без бессмысленных дублей.
- [X] T009 [US1] Проверить привязку lib/connections/connection_owner.dart, lib/console/console_owner.dart и lib/mcp/router.dart к существующему transport и gate; исправлять только подтверждённые отклонения контракта007, никаких новых exec/file/agent API (FR-801/802/803; AC-801–804).

## Phase 4 — US2: Карточки ПО (P1)

**Goal**: одинаковый локальный CRUD для UI/MCP, сохранение данных и редакций.
**Independent Test**: fake repository + owner/routes, полный roundtrip пяти полей.

- [X] T010 [US2] Написать owner unit cases в test/software/software_owner_test.dart: CRUD, duplicate name, stale update/delete, profile cascade, endpoint change, потерянный ответ/replay после удаления профиля, отзыв до replay/commit/response, quotas и rollback (FR-804–808/812; AC-805–809; SC-801/803/804).
- [X] T011 [US2] Реализовать lib/software/software_owner.dart: общий DomainCommandGate/UiActor/McpActor; auth→receipt→profile/entity/revision/target для нового эффекта, повтор lookup в фактической транзакции; save/delete + event/receipt/dataRevision атомарны. Delete физический локальный, история остаётся; noop save повышает revision; изменённая цель блокирует update, но не read/delete; target/actor/time назначает root (FR-805–808/812; AC-805–809).
- [X] T012 [US2] Реализовать paging в lib/software/software_owner.dart: limit default25,max100; cards ascending(createdAt,softwareId), cursor≤512 canonical base64url JSON с v/kind/profileId/softwareId/snapshotRevision/offset, scope/формат→INVALID_ARGUMENT, изменённая snapshotRevision→CONFLICT; snapshot и полный MCP ответ≤1MiB без усечения полей (FR-805; AC-805/806).
- [X] T013 [US2] Добавить четыре CRUD routes software.list/get/save/delete в lib/mcp/router.dart и validation в lib/mcp/tool_schemas.dart, strict unknown/duplicate/type checks, взаимное наличие softwareId/expectedRevision на update, MutationValue только metadata; unit cases в test/software/software_mcp_test.dart (FR-805; AC-805–807).
- [X] T014 [US2] Подключить единственный SoftwareOwner к lib/runtime/feature_runtime.dart и существующему profile deletion path; UI/MCP делят owner/repository/gate. Не менять tray/bridge/shutdown/credential lifecycle (FR-805/807/812; AC-807/808).
- [X] T015 [US2] Реализовать карточки и форму в lib/software/software_view.dart и вкладку lib/profiles/profile_view.dart: C16/C07/C09/C08/C05/C13/C03/C04/C02/C10/C11/C12/C18. CRUD offline; фильтр только текущей страницы явно обозначен, исходная цель видна, shortcut консоли старой цели disabled; конфликт сохраняет ввод и требует перечитать revision (FR-805/806/810; AC-805–808).
- [X] T016 [US2] Написать functional widget tests в test/software/software_view_test.dart на fake owner: поля/actions, validation/empty/loading/error/conflict, пагинация/фильтр, local delete, endpoint marker/disabled shortcut; без design/layout assertions (FR-805/806; AC-805–808; SC-801).

## Phase 5 — US3: История (P1)

**Goal**: metadata-журнал с автором, временем и сообщённым исходом.
**Independent Test**: fake note/CRUD/delete/eviction и исторический softwareId.

- [X] T017 [US3] Дополнить test/software/software_owner_test.dart cases для note actor/time, action/outcome, размера, replay/revoke/rollback, фильтра удалённой карточки, eviction10000, отсутствие terminal payload (FR-808/809/810; AC-809–811; SC-804).
- [X] T018 [US3] Добавить addNote/history в lib/software/software_owner.dart: nullable softwareId, current target проверяется только для нового эффекта с карточкой, profile-level note использует текущую цель; indexed history descending(createdAt,eventId), filter/cursor/budget как в контракте; история удалённой карточки не требует её существования (FR-809/810; AC-810/811).
- [X] T019 [US3] Добавить software.history.list/add в lib/mcp/router.dart и lib/mcp/tool_schemas.dart с test/software/software_mcp_test.dart; history.add возвращает MutationValue(eventId,revision1), не выдаёт текст как проверенное состояние сервиса (FR-809/810; AC-810/811).
- [X] T020 [US3] Опубликовать только работающие27 tools с contractVersion3 в assets/mcp/tools.json и specs/003-ssh-mcp/contracts/mcp-tools.json; исходные21 tool и MCP2025-11-25 неизменны. Обновить registry/static unit expectations в test/mcp/ (FR-801/805/809; AC-801/805/810).
- [X] T021 [US3] Добавить журнал профиля/карточки и форму заметки в lib/software/software_view.dart: C20/C28/C18/C13/C03/C04/C02, автор/исход как сообщение автора, softwareName snapshot после delete, отметка предела10000, ссылка на обычную C26 консоль; functional cases test/software/software_view_test.dart (FR-809/810; AC-810/811).

## Phase 6 — US4: Анализ сервера (P2)

**Goal**: текст задания для внешнего ИИ, затем обычные карточки.
**Independent Test**: fake clipboard/console/owner, без запуска ИИ или сканирования.

- [X] T022 [P] [US4] Реализовать чистую подготовку задания в lib/software/software_analysis.dart с profileId/host/списком ПО, без credentials; задание предлагает обследование обычной консолью, обсуждение и software.save, не исполняет команды (FR-811; AC-812/813).
- [X] T023 [US4] Подключить C03/C02 действие анализа к lib/software/software_view.dart: явное копирование через injectable clipboard callback, не запускать внешний процесс или shell. Unit/functional tests в test/software/software_analysis_test.dart и software_view_test.dart (FR-811; AC-812/813).
- [X] T024 [US4] Проверить synthetic discovery→proposal→software.save в test/software/software_mcp_test.dart: несколько экземпляров, неизвестные version/service=null и пустые списки, те же console/CRUD routes без discovery RPC (FR-804/811; AC-813; SC-805).

## Phase 7 — Polish / Converge

- [X] T025 Выполнить speckit-converge по lib/, test/, specs/008-host-software/; добавить только найденные незавершённые требования новыми задачами в tasks.md, без стирания выполненных (FR-801–812).
- [X] T026 Выполнить root format/analyze/flutter test, tools/check-test-boundaries.ps1, schema/registry/import audit, полный lychee specs/**/*.md; записать реальные результаты и ограничения в specs/008-host-software/stages.md (FR-801–812; SC-801–805).
- [X] T027 Завершить независимые code/spec review/fix loops по AGENTS.md; после исправлений повторить обязательные checks и fresh review; финальный completion audit всех AC/FR/SC в specs/008-host-software/stages.md, без выдачи unit evidence за real integration (FR-801–812; SC-801–805).

## Dependencies and parallel opportunities

T001→T002→T003–T007. US1 затем проверяется независимо на существующей консоли.
US2 T010→T011→T012→T013→T014→T015→T016; зависит от foundation.
US3 опирается на атомарные CRUD events US2; T017→T018→T019→T020→T021.
US4 использует US1/US2: T022→T023→T024. T025→добавленные converge tasks→T026→T027.
Registry публикуется после всех шести работающих routes (T020), а не после четырёх.

Примеры независимой работы: для US1 проверка существующих console tests не меняет
storage; в US2 UI tests на fake могут готовиться отдельно от owner tests после API;
в US3 owner history cases и registry fixtures используют разные файлы, но общий router
меняется последовательно; в US4 T022 можно готовить отдельно от журналов после модели.

## Implementation strategy

Сначала foundation и проверка shell; затем полный CRUD с обязательными событиями,
потом сообщения/журнал и задание анализа. Каждый этап проверяется unit/fake, без
публикации/демо на реальном сервере. MVP-последовательность не уменьшает scope:
цель завершена только после всех историй, converge, checks и review loop.

## Review follow-up — Foundation

- [X] T028 Исправить safeJSON lower bound без abs overflow в lib/software/software_models.dart; unit boundary cases в test/software/software_models_test.dart (T003, FR-804; замечание independent foundation review).
- [X] T029 Применить Unicode/NUL invariant ко всем строкам public DTO, включая target/author/snapshot/CRUD summary в lib/software/software_models.dart; synthetic unit cases в test/software/software_models_test.dart (T003, FR-804/809; замечание independent foundation review).

- [X] T030 Исправить liveness MCP pagination: snapshotRevision курсора опирается на existing profilesListRevision, атомарно продвигаемый профильными и software mutation; auth-clock оставляет snapshot стабильным. lib/software/software_owner.dart, contracts/tools.md, plan.md, data-model.md; test/software/software_mcp_test.dart проверяет полный обход больших страниц без усечения/дубликатов (FR-805/808).
