# Tasks: ServerDeck

Stable T001..T013 IDs retained. Expanded descriptions replace initial umbrella
tasks without pretending they were executed. Subchecks live in verification.md.
Input: spec.md, plan.md, research.md, data-model.md, contracts/local.md.

## Phase 1 — setup
- [x] T001 Configure official Spec Kit and refine stable BR/AC IDs in .specify/ and specs/001-server-management-client/spec.md; preserve Logs provenance.
- [x] T002 Generate pinned design decisions, budgets and privilege gates in specs/001-server-management-client/{plan,research,data-model,quickstart}.md and contracts/local.md.

## Phase 2 — foundation
- [x] T003 Analyze cross-artifact consistency and requirement/test mapping in specs/001-server-management-client/{analysis,traceability}.md before implementation.

## Phase 3 — US1/US2/US3 fixture MVP
Independent test: five Windows views, per-server retained journal, filter/pause,
unknown/stale distinction; demo preview cannot execute or reach network.
- [x] T004 [US1] Build fixture server/software/journal/metric/job shell in lib/domain/, lib/data/fixtures.dart, lib/ui/app.dart; bounded journal 500 and record <=64 KiB, profile port 1..65535, unknown values nullable; test in test/ and integration_test/ (BR-A01/S01/I01/I02/L01..L06/M01/J01/C01; SC01..SC03).

## Phase 4 — US1/US2 read-only
Independent test: disposable SSH host only, enrollment/mismatch, denied/unsupported
results; credentials survive Windows restart in OS custody, never JSON.
- [ ] T005 [US1] Add non-secret SQLite storage, native OS secret store, mandatory pinned SSH and typed read capability in lib/data/{storage,credentials,ssh}.dart; negative tests test/security_test.dart (BR-C01/P01; AC07/SC04).
- [ ] T006 [US1] Implement bounded package/all-unit-instance inventory and version evidence in lib/data/inventory.dart; stopped/failed/unknown/stale tests test/inventory_test.dart (BR-I01/I02/S01; AC01/AC02).
- [ ] T007 [US2] Implement journal history/live/cursor/boot/search/severity/time/details/copy, reconnect and fault counters in lib/data/journal.dart; history 1..1000/default100, ring500/64KiB, max two streams; tests test/journal_test.dart (BR-L01..L06; AC03/SC02).
- [ ] T008 [US1] Implement nullable sampled CPU/RAM/disk/uptime/network/service metrics in lib/data/metrics.dart; 15-second stale tests test/metrics_test.dart (BR-M01; SC03).

## Phase 5 — US3/US4 durable operations
Independent test: real disposable systemd VM, no-op duplicate, crash/cancel/
network-loss reconciliation and preserved data/config; production never targeted.
- [ ] T009 [US4] Add explicitly authorized selected service operations and post-verification in lib/data/service_actions.dart and test/service_actions_test.dart after T010 authority gates (BR-S02/P01; AC07).
- [ ] T010 [US3] Implement containerized Runner, SQLite job events/locks/idempotency, helper privilege gate and restart/cancel/reconciliation in runner/ and runner/tests/; immutable recipe digest, no automatic write retries (BR-J01/J03/J04/T01/P01; AC05/AC07/SC05).
- [ ] T011 [US3] Add exact-version PostgreSQL/ClickHouse recipes/provenance/preflight/adoption preservation/probes in runner/recipes/; disposable Ubuntu systemd integration tests runner/tests/ (BR-J02; AC04).

## Phase 6 — US5 optional sync
Independent test: local works offline, revisions conflict, credential/log exclusion.
- [ ] T012 [US5] Define sync revisions/scoping/allowlists, adapter and offline tests in specs/001-server-management-client/contracts/sync.md, lib/data/sync.dart, test/sync_test.dart (BR-C01/C02; AC06).

## Phase 7 — cross-cutting validation
- [ ] T013 Record Windows build/walkthrough and actual per-milestone evidence in docs/verification.md; no successful checkbox for unexecuted ACs (BR-A01/P01; SC01..SC05).

## Dependencies and parallel opportunities

T001 -> T002 -> T003 -> T004 -> T005 -> T006/T007/T008 -> T010 -> T009/T011.
T012 after T005 and authority design. T013 at every milestone, final completion only
when all applicable acceptance checks pass. T006/T007/T008 use distinct adapters
and may be tested independently after shared transport. T009/T011 share executor
gate, not order-dependent. IDs retain original meaning even where order changed.

MVP strategy: validate complete M0 fixture navigation first; fixture checks never
close connected AC01..AC03 or installation AC04/AC05. Incremental M1/M2 gates follow.
