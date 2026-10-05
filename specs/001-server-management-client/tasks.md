# Tasks

- [ ] T001 Review Logs research/source attribution and clarify bounded product
  requirements; configure Spec Kit in this independent repository, preserving IDs.
- [ ] T002 Validate proposed architecture/tool/runtime choices and pin versions;
  choose scan/log/job budgets and lifecycle semantics; generate technical artifacts.
- [ ] T003 Cross-artifact consistency analysis and requirement/test mapping before code.
- [ ] T004 Build Windows Flutter navigation and fixture server/software/log/metric/job
  views; distinguish fixtures from connected hosts (BR-A01,S01,I01,L01,M01,J01).
- [ ] T005 Local non-secret storage, OS secret custody, pinned SSH and safe adapters;
  fault/host-key/command-injection negatives (BR-C01,P01; AC07).
- [ ] T006 Read-only host/package/unit-instance inventory and version mapping,
  stopped/failed/unknown/stale cases (BR-I01/I02; AC01/02).
- [ ] T007 Journald history/live/search/severity/time/details/copy, bounded buffers,
  cursor/gap/reconnect/permission/drop tests (BR-L01..L05; AC03).
- [ ] T008 Timestamped CPU/RAM/disk/uptime/network and service metrics; stale and
  unsupported behavior (BR-M01).
- [ ] T009 Explicit systemd operations and result verification on fixtures (BR-S02).
- [ ] T010 Local containerized Ansible Runner, durable jobs/locks/idempotency/events,
  restart/cancel/reconciliation and authenticated IPC (BR-J01/J03/J04,T01; AC05/07).
- [ ] T011 Versioned PostgreSQL and ClickHouse recipes: upstream provenance,
  preflight, check-mode limitations, install/adopt/data preservation/version+probe,
  duplicate no-op; only disposable Ubuntu targets (BR-J02; AC04).
- [ ] T012 Optional sync contract/user scoping/revisions/conflicts/secret exclusion,
  then backend adapter and offline tests (BR-C01/C02; AC06).
- [ ] T013 Windows build/user walkthrough and actual acceptance evidence; no
  successful checkboxes before execution. Public docs must contain no live hosts.

Order:T001→T002→T003→T004→T005→T006/T007/T008→T009→T010→T011;
T012 after local persistence and authorization design; T013 at each milestone.
