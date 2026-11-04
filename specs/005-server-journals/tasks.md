# Tasks: Журналы сервера005

**Input**: [spec](spec.md), [plan](plan.md), [data](data-model.md), [contract](contracts/journals.md), [research](research.md).
Только unit/fake проверки по FR-514; обязательные checks не заменяются интеграционными. Выполненные задачи не удалять.

## Phase 1: Setup

- [x] T001 Проверить существующие зависимости/ignore и создать каталог lib/journals согласно plan.md, без новых runtime dependencies.
- [x] T002 Выполнить link check и независимое readiness review пакета specs/005-server-journals, закрыть подтверждённые замечания перед кодом.

## Phase 2: Foundation

- [x] T003 Реализовать immutable модели, validation, safe text и payload version1 в lib/journals/journal_models.dart (FR-503/506/508/510/511/513).
- [x] T004 Добавить JournalSource в lib/storage/records.dart, сгенерировать records.g.dart, добавить CRUD/atomic cascade и очистку connection revision в lib/storage/domain_repository.dart; обновить test/fixtures/domain_repository.dart (FR-506/512/513).
- [x] T005 Реализовать opt-in bounded stderr/nonzero result в third_party/dartssh2/lib/src/ssh_client.dart, сохранить deadlines/slots/caps/default004; synthetic тесты test/connections/journal_channel_test.dart (FR-504/509/510).
- [x] T006 Реализовать закрытые requests/job/port в lib/journals/journal_port.dart, typed transport в lib/connections/ssh_transport.dart, admitted owner jobs в lib/connections/connection_owner.dart; test/connections/journal_owner_test.dart проверяет UiActor/OwnerActor/trust/revision/late cancel/shared slot (FR-504/513,SC-501).
- [x] T007 Реализовать базовый durable owner, конфигурационные операции и atomic batch/checkpoint в lib/journals/journal_owner.dart, synthetic validation/repository тесты test/journals/journal_owner_test.dart (FR-503/508/512).

## Phase 3: US1 — Journal (P1, MVP)

Goal: выбрать службу и видеть реальные записи. Independent test: fake service discovery+JSON batch, actions/state без remote server.

- [x] T008 [US1] Реализовать bounded discovery/journal commands и parsers/recovery в lib/journals/journal_protocol.dart; test/journals/journal_protocol_test.dart покрывает JSON types/cursor/repeats/permissions/caps (FR-502/507/508/509,SC-504).
- [x] T009 [US1] Подключить discovery/journal collection в lib/journals/journal_owner.dart с состояниями и fair polling (FR-502/505/509,SC-502/505).
- [x] T010 [US1] Создать lib/journals/journal_view.dart с C02/C03/C04/C06/C07/C08/C10/C11/C12/C13/C14/C20/C28, выбором источника/службы, временем/важностью/текстом, состояниями и pagination200 (FR-501/502/509/511).
- [x] T011 [US1] Заменить только Journals заглушку в lib/profiles/profile_view.dart; inject через lib/runtime/runtime_view.dart; functional test/journals/journal_view_test.dart проверяет A/B/discovery/add/content/empty/retry без layout (FR-501/514,SC-501).

## Phase 4: US2 — Files (P2)

Goal: чтение новых строк из произвольного явного файла. Independent test: synthetic header/bytes и form actions.

- [x] T012 [US2] Реализовать безопасный file script и bounded byte/line parser в lib/journals/journal_protocol.dart; test/journals/file_protocol_test.dart покрывает quoting/offset/rotation/long/incomplete/invalidUTF8 (FR-503/507/508/510/511).
- [x] T013 [US2] Подключить file checkpoints/reset/gaps в lib/journals/journal_owner.dart; тесты test/journals/file_owner_test.dart проверяют first EOF/reconnect/ошибки одного источника (FR-507/508/509,SC-504/505).
- [x] T014 [US2] Добавить file form, rename/toggle/delete confirmation в lib/journals/journal_view.dart; functional test/journals/journal_view_test.dart для validation/actions/draft сохранения при storage failure (FR-503/511/512/514).

## Phase 5: US3 — Retention / runtime (P2)

Goal: локальный последний час после restart. Independent test: fake clock/repository и lifecycle.

- [x] T015 [US3] Реализовать startup/tick/projection TTL, clock high-water и count/bytes pruning в lib/journals/journal_owner.dart; test/journals/journal_retention_test.dart для границы60мин, rollback/restart/caps/atomic failure (FR-506/510,SC-503).
- [x] T016 [US3] Включить durable collection/lifecycle в lib/runtime/feature_runtime.dart; teardown/drain в lib/journals/journal_owner.dart; test/journals/journal_lifecycle_test.dart для tray/tab/offline/revision/delete/late writes/выхода (FR-505/512/513,SC-501/505).
- [x] T017 [US3] Проверить restart history/paused/disconnected/partial UI в test/journals/journal_view_test.dart на fake owner/store (FR-506/509/514,SC-503/504).

## Phase 6: Cross-cutting completion

- [x] T018 Выполнить format/analyze/flutter test и tools/check-test-boundaries.ps1, lychee по quickstart.md; сохранить реальные результаты в specs/005-server-journals/reviews/implementation.md (FR-514).
- [x] T019 Выполнить speckit-converge относительно полного пакета005, append обнаруженную работу в tasks.md, реализовать её и повторить checks (FR-501–514,SC-501–505).
- [x] T020 Выполнить fresh независимое code/spec review по AGENTS.md, устранить подтверждённые замечания с повтором checks/review; сохранить отчёт specs/005-server-journals/reviews/implementation.md.

## Dependencies / Strategy

T001→T002→T003/T004→T005→T006→T007. US1 T008→T009→T010→T011; US2 T012→T013→T014; US3 T015→T016→T017; затем T018→T019→T020. MVP=foundation+US1, затем файлы/retention завершить до финала. Core retention входит в foundation, US3 дополняет границы/lifecycle.

Параллельные независимые проверки после реализации: US1 protocol и view tests; US2 file protocol и view tests; US3 retention и lifecycle tests на отдельных fake owners. Реализация owner/protocol/view в разных story последовательна из-за общих файлов. Не создавать дополнительных агентов кроме research/review, требуемых workflow.

## Phase 7: Specification review closure

- [x] T021 [US1] Реализовать cursor reset/fallback из contracts/journals.md в lib/journals/journal_owner.dart; test/journals/journal_owner_test.dart проверяет nonzero cursor→no-cursor recovery, empty success, failed fallback, restart и sticky partial, возобновление новых событий без бесконечного старого cursor (FR-508,SC-504). Выполнять вместе с T009 до T010.
- [x] T022 Реализовать атомарный independent global source cap1024 в lib/journals/journal_owner.dart; test/journals/journal_owner_test.dart проверяет1024/1025, disabled count и concurrent admissions; test/journals/journal_view_test.dart проверяет error+draft retention (FR-503). Выполнять вместе с T007 до US1.
- [x] T023 Проверить и реализовать в lib/storage/domain_repository.dart сохранение sourceId/kind/target/name/enabled при endpoint/auth save с обновлением connectionRevision и empty payload+partial в той же транзакции; test/journals/journal_lifecycle_test.dart проверяет точный config, cleared history/checkpoint и запрет late old-revision batch (FR-512). Выполнить вместе с T004/T016.

## Phase 8: Convergence

- [x] T024 Исправить lifecycle/error подтверждения удаления и stale owner/profile callbacks в lib/journals/journal_view.dart, functional tests test/journals/journal_view_test.dart per FR-501/509/512 (partial, HIGH).
- [x] T025 Дополнить functional tests test/journals/journal_view_test.dart для discovery/add/content/rename/delete/offline/partial/pagination и отказа cap с сохранением draft per FR-514 и T011/T014/T017/T022 (missing, MEDIUM).
- [x] T026 Очищать source/profile runtime maps в lib/journals/journal_owner.dart после удаления и shutdown; test/journals/journal_lifecycle_test.dart проверяет bounded lifecycle per FR-510/512 (partial, MEDIUM).
- [x] T027 Ограничить хранение pending file fragment теми же60мин через fragmentAt, удалить expired prefix с partial/discard-until-LF; закрепить текущий checkpoint в data-model.md/contracts/journals.md и test/journals/file_owner_test.dart per FR-506 (partial, MEDIUM).

## Phase 9: Independent implementation review fixes

- [x] T028 Ввести общую bounded FIFO admission очередь collectors004/005 в lib/connections/connection_owner.dart с прежним5s deadline и cancellation; test/connections/journal_owner_test.dart проверяет несколько deterministic contention циклов и отмену ожидающего запроса per FR-505/513 (partial,P1).
- [x] T029 Связать cached discovery и его state с connectionRevision в lib/journals/journal_owner.dart, скрывать stale projection сразу и очищать при prune; owner/widget A→B tests в test/journals/journal_lifecycle_test.dart и journal_view_test.dart per FR-501/512 (partial,P2).
- [x] T030 Разделить полный unit target и initial display name≤80runes в lib/journals/journal_view.dart; functional long-unit test в test/journals/journal_view_test.dart per FR-502/503 (partial,P2).
- [x] T031 Показывать waiting для due-but-not-admitted sources независимо от предыдущего ready/partial; test/journals/journal_owner_test.dart с fake clock и16источниками per SC-502/FR-509 (partial,P2).
- [x] T032 Привязать все callback controls/selection/dialogs в lib/journals/journal_view.dart к captured owner/profile контексту; functional test сохранённого старого Add callback после A→B в test/journals/journal_view_test.dart per FR-501/SC-501 (partial,P2, дополнительная self-review находка).

## Phase 10: Independent review regression closure

- [x] T033 Очистить rows/state старого discovery до присвоения stamp новой revision в lib/journals/journal_owner.dart; test/journals/journal_lifecycle_test.dart и journal_view_test.dart проверяют Refresh после revision save до prune: offline/loading/error не возвращают старые units per FR-501/512 и T029 (partial,P2).
- [x] T034 Сбрасывать loading отменённого чтения в waiting при rename/invalidate в lib/journals/journal_owner.dart; test/journals/journal_lifecycle_test.dart проверяет отсутствие ложного active loading и late data per FR-509/512 (partial,P3,self-review).
- [x] T035 Согласовать validation opaque cursor на remote parse/render/storage границах в lib/journals/journal_models.dart и journal_protocol.dart; control/bidi cursor не должен сохранять checkpoint, который затем отвергает storage decoder; regression test test/journals/journal_protocol_test.dart per FR-508/509 (partial,P2,self-review).

## Phase 11: Reactive retention review closure

- [x] T036 Связать opened record detail с текущей owner/profile/source/event/receipt/revision проекцией в lib/journals/journal_view.dart; не держать snapshot payload; functional tests test/journals/journal_view_test.dart покрывают TTL/source delete/revision reset, контракт005 per FR-506/512/SC-503 (partial,P2).
- [x] T037 Добавить точный expiry-notify timer и advancing monotonic UTC high-water в lib/journals/journal_owner.dart, освобождать timer при shutdown и повторно читать current projection на deadline; test/journals/journal_retention_test.dart и journal_view_test.dart проверяют границу между5s ticks и rollback per FR-506/SC-503 (partial,P2,self-review).
