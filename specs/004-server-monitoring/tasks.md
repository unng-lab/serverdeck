# Tasks: 004 — Базовый мониторинг серверов

**Input**: [spec](spec.md), [plan](plan.md), [model](data-model.md), [contract](contracts/monitoring.md)
**Tests**: unit-only, functional fake widgets. No real Isar/SSH/product launch/design gates.

## Phase 1 — Setup

- [X] T001 Подготовить lib/monitoring/ и test/monitoring/, прочитать контракты и existing unit fixtures; не добавлять зависимости (FR-414/415).

## Phase 2 — Foundational

- [X] T002 [P] Реализовать MetricKind(cpu,memory,disk), immutable readings (finite 0..100), CpuCounters (8 unsigned int≤2^63−1), session baseline и fixed reasons в lib/monitoring/monitoring_models.dart (FR-401/402/407/412).
- [X] T003 [P] Написать unit fixtures native marker missing/clean/running/malformed/oversized/reparse/I/O/retry в native/tests/monitoring_run_test.cpp и test/runtime/monitoring_run_test.dart, с fake native channel/temp files (FR-410).
- [X] T004 Реализовать native/include/monitoring_run.h и windows/runner/platform_channel.cpp monitoring.beginRun: fixed path, read≤128 bytes, AtomicFile running до admission, cached classification на owner epoch; finishExit clean только после validation; подключить lib/runtime/native_platform.dart и lib/main.dart без миграции Isar (FR-410/414).
- [X] T005 Написать in-memory protocol fixtures pending-open/exec ACK cancellation, late open success/failure, 65536 exact/overflow, early stdout/extended data, retired slot/no window grants в test/connections/monitoring_channel_test.dart (FR-406/409/412/414).
- [X] T006 Добавить bounded cancellable exec в third_party/dartssh2/lib/src/ssh_client.dart и ssh_channel.dart: synchronous handle, до buffering cumulative budget, 5s deadline, one unresolved monitoring channel/session, tombstone/retired close, без изменения обычных channel defaults; обновить patches/dartssh2-4.1.0-policy.patch, third_party/dartssh2/SERVERDECK.md и существующий provenance manifest (FR-406/409/412/414).
- [X] T007 Подключить typed MonitoringSshConnection в lib/connections/ssh_transport.dart и beginMonitoring port в lib/connections/connection_owner.dart; gate/session/generation/version/trust/current OwnerActor revalidation до dispatch/response, cancellation и existing admitWrite; unit denial/late-result/unchanged ordinary SSH behavior, revoke после promotion сохраняет UI metrics, revoke до promotion блокирует pending в test/connections/monitoring_admission_test.dart (FR-409/412/414).

## Phase 3 — US1: текущие нагрузки (P1)

**Independent test**: fake connected sessions / source / clock; AC-401–404,
first full set≤10s for 1–4 servers, no queue saturation.

- [X] T008 [P] [US1] Написать parser units CPU delta/guest/reset, RAM total/available missing/duplicates, df reserved blocks/zero/malformed, framing/UTF8/output limits в test/monitoring/linux_metrics_test.dart (FR-401/402/406, AC-402).
- [X] T009 [US1] Реализовать constant Linux collector и strict parser в lib/monitoring/linux_metrics.dart по contract v1, fixed safe reasons, no raw errors; первая CPU требует пары, session reset очищает baseline (FR-401/402/411/414).
- [X] T010 [US1] Написать fake-clock units auto all profiles/new MCP profile on return, prompt slots, admission response≠completed attempt, manual/MCP cancel/disconnect, complete MCP connect+disconnect при inactive/between ticks, generation>0 suppression после revision change и admission race, no retry, fair queues≤4/no backlog в test/monitoring/monitoring_owner_test.dart (FR-405/406/408/409, AC-401/403/404/412/414).
- [X] T011 [US1] Реализовать lib/monitoring/monitoring_owner.dart: coalesced 1s reconciliation, all profiles≤1000, separate queues≤4, 5s due/deadline, per-profile attempt marks/late epoch fences, canonical connections; FeatureRuntime capability в lib/runtime/feature_runtime.dart (FR-405/406/408/409/412).
- [X] T012 [US1] Подключить activation от section/window/runtime в lib/runtime/runtime_view.dart, observer manual actions в lib/profiles/profile_controller.dart, список C07/C09+C21/C18 в lib/profiles/profile_view.dart и lib/monitoring/monitoring_view.dart; preserve search/CRUD/trust (FR-401/405/408/415, AC-401–404).
- [X] T013 [US1] Добавить functional widget units text/data/select/connect/search/empty/live updates через fake dependencies в test/monitoring/monitoring_actions_test.dart (AC-401–404, SC-401, FR-415).

## Phase 4 — US2: превышенные пороги (P1)

**Independent test**: synthetic 0/89.9/89.95/90/100, freshness и per-metric severity,
без проверки цветов/расположения.

- [X] T014 [P] [US2] Добавить numeric boundary/rounding/aggregate critical regression units в test/monitoring/monitoring_threshold_test.dart (FR-403/404, AC-405–407, SC-402).
- [X] T015 [US2] Реализовать threshold 90 по unrounded value, '<90,0' formatting и independent critical flags в lib/monitoring/monitoring_models.dart; C21 error semantics/text и C10 summary в lib/monitoring/monitoring_view.dart (FR-403/404/415).

## Phase 5 — US3: отсутствие данных и восстановление (P2)

**Independent test**: fake clock/source/state, stale at 15s, partial invalid result,
trust/passphrase waits, tray/hide/return, crash gate и shutdown.

- [X] T016 [P] [US3] Добавить isolated lifecycle units stale/partial/timeout/outputLimit/cleanupPending/session replacement/deletion/rename/clock rollback/deactivation/late reconcile/shutdown в test/monitoring/monitoring_lifecycle_test.dart (FR-406/407/410–414, AC-408–414, SC-403/404).
- [X] T017 [US3] Завершить lib/monitoring/monitoring_owner.dart cancellation/drain/unsupported per session/stale independent readings, startup explicit gate, deletion pruning и no auto retry после session loss; lib/runtime/feature_runtime.dart shutdown (FR-407/409–414).
- [X] T018 [US3] Добавить C11 fixed reasons/next actions, C02 «Начать мониторинг», C10 waiting/partial/paused и C18 per-metric time в lib/monitoring/monitoring_view.dart; preserve selectable trust prompts и UI actions; fake widget assertions в test/monitoring/monitoring_recovery_actions_test.dart (FR-410/413/415, AC-408–414).

## Phase 6 — Validation and converge

- [X] T019 Выполнить dart format --output=none --set-exit-if-changed ., flutter analyze, flutter test, tools/check-test-boundaries.ps1, lychee specs/**/*.md; applicable vendor/native unit targets и static Windows build, результаты записать в specs/004-server-monitoring/reviews/implementation.md (FR-401–415/SC-401–404).
- [X] T020 Провести speckit-converge по specs/004-server-monitoring, дописать оставшиеся задачи без удаления истории; после checks независимое review/fix loop по AGENTS.md, записать evidence в reviews/implementation.md. Не коммитить/публиковать.

## Dependencies and execution strategy

T001 → T002–T007 → US1(T008–T013) → US2(T014–T015) → US3(T016–T018) → T019–T020.
T003 до T004; T005 до T006; T007 после T006. Tests перед соответствующей реализацией.
[P] означает разные файлы без зависимости в своей фазе, не автоматическое разрешение
на implementation subagents. Примеры независимой работы: T002 и T003, T008 parser
fixtures и подготовка fake clock в T010; T014 threshold fixtures и T016 lifecycle
fixtures после US1. Общие owner/view меняются последовательно.
MVP — US1; полная цель требует все US1–US3 и clean checks/review. US2/US3 тестируются
на synthetic model без реальных SSH. Публикация/commit в scope не входят.

## Phase 7 — Pre-implementation review corrections

- [X] T021 Закрепить regression-сценарии R1/R2 из reviews/planning.md в test/connections/monitoring_admission_test.dart, test/connections/monitoring_auto_admission_test.dart и test/monitoring/monitoring_owner_test.dart: current OwnerActor after promotion, canonical generation history для inactive MCP disconnect и concurrent admission (FR-409/412, AC-412/414). Выполнить совместно с T007/T010 до проверки T019.

## Phase 8 — Bounded channel review correction

- [X] T022 Передать sticky local-abort cause из third_party/dartssh2/lib/src/ssh_channel.dart в bounded operation ssh_client.dart; regression units ACK→stdout→status0→duplicateACK/oversized packet в test/connections/monitoring_channel_test.dart. Partial stdout MUST NOT публиковаться успешно; сохранить retired slot, обновить patch/provenance, rerun checks/fresh review (FR-406/414, review_004_bounded P2).


## Phase 9 — Scheduler review corrections

- [X] T023 Различить cancelled-before-admission и completed failure в lib/monitoring/monitoring_port.dart, monitoring_owner.dart, lib/connections/connection_owner.dart; regression controlled failure delivery across hide в test/monitoring/monitoring_owner_test.dart, сохранить canonical no-retry после resource exhaustion и resume только действительно не начатого запроса (FR-408/409, review_004_scheduler R1).
- [X] T024 Отделить временную pause-причину от состояния сервера в lib/monitoring/monitoring_owner.dart; regression manual disconnect/terminal failure → hide → return в test/monitoring/monitoring_lifecycle_test.dart, active snapshot MUST NOT сохранять paused; checks и fresh independent review (FR-413, review_004_scheduler R2).

## Phase 10: Convergence

- [X] T025 Показывать C11 safe reason/next action с названием каждой отказавшей метрики в lib/monitoring/monitoring_view.dart, сохранив общие причины всего сбора/SSH; regression CPU valid + RAM invalidResponse + disk sourceUnavailable в test/monitoring/monitoring_recovery_actions_test.dart; обновить presentation contract, rerun mandatory checks и fresh independent review per AC-410/FR-407/FR-413 (partial; review_004_complete P2).


## Компактное представление — 2026-11-04
- [X] T026 Обновить lib/monitoring/monitoring_view.dart и C07 composition lib/profiles/profile_view.dart: compactC21 из001/R014, общаясвежесть, безtimestamp/age/log; internalfreshness/critical/partialсохранить, detailedpersourcerecovery вmodal003/T056 (FR-416–418,AC-415/416,SC-405).
- [X] T027 Functional synthetic widgetunits в test/monitoring/ иfixtures/monitoring_widgets.dart: data/freshness/threshold/sources/actions/modalnavigation, отсутствиеtime-text; nofeaturelayout/golden/overflow (FR-416–418,AC-415/416).
- [X] T028 Mandatorychecks/shared001units/links иполноеindependentreview current003/004/002; analyze/converge004, actualresults вreviews/implementation.md, singleEXE вместе003 безновогопакета (FR-416–418,SC-405).


## Server workspace monitoring presentation
- [X] T029 Обновить lib/monitoring/monitoring_view.dart до C21 icon-only compact и
  C10 разных connection/freshness icons с C14 tooltip, detailed source notices
  вworkspace003. Unit data/freshness/threshold/reasons/semantics/activation,
  checks/review/converge совместно003 (FR-419–421,AC-417/418,SC-406).

## Phase 11 — US4: persisted hour history

- [X] T030 [US4] Update current format3 storage guards in lib/storage/{records.dart,records.g.dart,store_manifest.dart,workspace_store.dart}; add MonitoringHistoryRecord schema, required MonitoringHistoryStore in lib/monitoring/monitoring_history.dart and lib/storage/domain_repository.dart; atomic profile revision/delete cleanup; fake repository and unit codec/store fences in test/monitoring/monitoring_history_test.dart, test/storage/current_store_format_test.dart (FR-423–426,AC-420–422).
- [X] T031 [US4] Add bounded owner history load/save/retry,720 rows/192KiB/1h TTL,UTC+monotonic pruning and segment/lifecycle fences in lib/monitoring/monitoring_owner.dart; wire required store in lib/runtime/feature_runtime.dart; fake-clock owner units test/monitoring/monitoring_history_owner_test.dart (FR-423–426,AC-420–422).
- [X] T032 [US4] Extend shared C22 lib/ui/deck_history.dart maxPoints1..720(default120),periodLabel,finite fractional percent,breakBefore; document001 and synthetic component tests test_design/components/history_hour_test.dart (FR-422,SC-407). No feature design acceptance.
- [X] T033 [US4] Add C16 Monitoring tab/icon and C22/C11/C02 composition lib/profiles/profile_view.dart,lib/monitoring/monitoring_view.dart; functional fake tests test/monitoring/monitoring_history_actions_test.dart for selected profile,points,empty,retry,no extra collection (FR-422,FR-426,AC-419,AC-422).
- [X] T034 Run mandatory format/analyze/flutter test,boundary,shared component units and lychee specs/**/*.md; analyze/converge004 and independent review/fix loop; record actual evidence specs/004-server-monitoring/reviews/hour-history.md. No commit/publish (FR-422–426,SC-407).

Dependencies:T030→T031;T032 after001 contract;T031+T032→T033→T034.
MVP US4 includes persistence and all failure/recovery semantics. Existing completed
history remains intact. Readiness requires clean independent package review first.


## Phase 12: Convergence

- [X] T035 Fence history,historyError,retryHistory by selected profile connectionRevision in lib/monitoring/monitoring_owner.dart,lib/monitoring/monitoring_view.dart,lib/profiles/profile_view.dart; add delayed/failed reconciliation after profile edit fake functional regression test/monitoring/monitoring_history_actions_test.dart; retain rename/reconnect history. FR-425,AC-419/421 (partial; independent review P2). Rerun mandatory/shared/link checks and fresh review.
