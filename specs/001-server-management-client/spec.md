# ServerDeck: server management desktop client

Created 2026-10-05. Status: refined for phased implementation; runtime evidence is separate.
Owner: ServerDeck. Scope authorized by user: new public project and separate task.
No installation on real hosts is authorized by this documentation.

## User goal

An ordinary user opens a local Flutter client, sees their servers, what software is
installed, its logs and basic hardware activity, and submits understandable jobs
to install PostgreSQL or ClickHouse using existing installation tooling. A backend
may synchronize data, but ordinary use must not require one or provider APIs.

## Requirements

| ID | Observable result | Origin |
| --- | --- | --- |
| BR-S01 | Add/edit/remove a server profile, SSH endpoint/port/user, tags and local credential reference; list online/offline/unknown and last observed time | Human; Logs |
| BR-I01 | Per-server software records show observed name/version/source, related units, state, last scan and uncertainty; global view answers which servers have PostgreSQL/ClickHouse | Human |
| BR-I02 | Distinguish OS packages, custom binaries, systemd units, Docker containers and Kubernetes workloads; unsupported scans are explicit, not an empty success | Proposed correctness |
| BR-L01 | Open logs from a server/software/service; bounded historical load and live follow over SSH for journald | Human; Logs |
| BR-L02 | Default100 history lines, configurable1..1000; per-server memory ring500 records; reveal truncation; no silent unlimited storage | Logs; proposed visibility |
| BR-L03 | Switch servers/screens without losing the bounded session buffer; pause display, resume and reconnect with explicit gap/duplicate handling | Logs; proposed extension |
| BR-L04 | Search message text, filter selected service/severity/time, show timestamp/timezone and structured details; copy/export only on explicit action | Logs; proposed extension |
| BR-L05 | Distinguish no logs, stopped service, permission denial, failed transport and malformed records; show stream freshness | Proposed correctness |
| BR-L06 | Select desktop journal text and display newest entries first; copying remains an explicit local action | Logs; source ID retained |
| BR-M01 | Host CPU/RAM/disk capacity+usage/uptime and basic network rates; service PID/CPU/RAM when available; timestamp/stale marker, unavailable is not zero | Human; Logs; proposed extension |
| BR-J01 | Choose host, catalog application, supported exact version and parameters; inspect planned actions, submit installation job and follow status/output | Human |
| BR-J02 | First recipes PostgreSQL and ClickHouse; fresh install and adoption are explicit; preserve existing data/config and deny implicit reset/downgrade | Human; proposed safety |
| BR-J03 | Persist queued/preflight/awaiting-approval/running/succeeded/failed/cancel-requested/cancelled/unknown/reconciling; success requires post-install version/unit/probe verification | Proposed job semantics |
| BR-J04 | Repeated clicks/sync retries do not repeat writes; per-host exclusive writer, restart/network-loss reconciliation, bounded retries and cancellation without claiming rollback | Proposed job semantics |
| BR-S02 | Status/start/stop/restart selected systemd service with permissions, action result and subsequent status/log refresh | Logs; retained scope |
| BR-C01 | Desktop works directly over SSH with optional server synchronization; unavailable backend must not prevent local inventory/logs/jobs | Human |
| BR-C02 | Synchronize profiles/tags/settings/non-secret inventory/job summaries with revisions/conflict handling; no credential or raw-log upload by default | Proposed sync boundary |
| BR-A01 | Native Flutter desktop, Windows first; remote Linux Ubuntu baseline first; other desktops/OS are later adapters | Human; proposed first target |
| BR-T01 | Use ready-made host-install tooling; do not implement another package manager or require cloud APIs | Human |
| BR-P01 | Pin host keys, keep secrets in OS custody, escape commands, separate read and write capabilities, immutable job inputs+recipe hash; do not modify NetBird | Existing user constraints; proposed design |

## User stories and success criteria

- US1 (P1): inspect profiles, software, unit states and hardware freshness without
  a backend. BR-S01/I01/I02/M01/C01/A01; AC01/AC02. M0 uses fixtures only.
- US2 (P1): read bounded journal history and follow/search/filter without losing
  session state during navigation. BR-L01..L06; AC03.
- US3 (P2): review exact-version plans and durable jobs on disposable hosts.
  BR-J01..J04/T01/P01; AC04/AC05/AC07. M0 previews cannot execute.
- US4 (P2): explicitly authorized service operations with verified results.
  BR-S02/P01; AC07 plus stopped/failed/instance service walkthrough.
- US5 (P3): opt into non-secret metadata sync. BR-C01/C02; AC06.

SC01: M0 opens on Windows at 1100x760 and 800x600 without layout exceptions;
all five views are reachable, demo labels persist, and no network/write operation
is reachable. Fixture widgets verify navigation, filtering and stale data.
SC02: journals retain at most 500 records/server (each record <=64 KiB); history
requests accept only 1..1000 (default 100). At most two transports are open; excess
requests are explicitly refused. Overflow/parse/gap/duplicate counts are visible.
SC03: metrics expire after 15 seconds and inventory after 5 minutes. Failed refresh
keeps prior observations and marks them stale; unavailable values are null.
SC04: unknown/changed host keys and untrusted identifiers deny execution; secrets
remain in OS custody and never enter sync or non-secret persistence.
SC05: real jobs need tested duplicate/crash/cancel/host-lock paths and post-install
probes before AC04 passes. M2 gates must not be claimed by fixture tests.

## Acceptance scenarios (stable IDs)

- AC01: add two fixture servers; after refresh each has identity, freshness and
  observations; losing one connection marks it offline/unknown without erasing
  previously observed software. No host mutation during inventory.
- AC02: discover installed/stopped/failed and instance units; recognized packages
  have version/source; an unrecognized custom binary remains unknown until scanned.
- AC03: select a fixture service, read100 lines, follow a new log event, search,
  inspect severity/timestamp, pause display and reconnect; bounded memory and
  visible gaps/drop counters. Denied journals do not appear as successful empty logs.
- AC04: on disposable Ubuntu host submit exact PostgreSQL recipe, verify installed
  version+unit+probe, repeat no-op; repeat for ClickHouse. No production host test.
- AC05: duplicate submission, disconnect, runner/client restart and cancellation
  retain honest job outcomes; unknown writes are reconciled before retry.
- AC06: client opens cached profiles without backend; sync conflict is explicit;
  backend never contains private SSH keys or queued jobs executable by another
  device without a separate execution authorization.
- AC07: host-key mismatch, malicious unit/parameter, unsupported version/OS,
  unavailable runner and protected NetBird modification are denied.

## Milestones / exclusions

M0: requirements, design, runnable Windows UI against fixtures; no real writes.
M1: read-only server/software/log/metrics adapters and local credential custody.
M2: existing-tool job executor + two recipes on disposable fixtures.
M3: optional synchronization service with conflict/authorization tests.
No HA/SLO/backup rollout, cloud provisioning, central log platform or full Kubernetes
management is part of the initial product. Inventory is not continuous monitoring.
Initial budgets and release gates are in plan.md; these are design limits until
measured. Catalog execution remains disabled until provenance, limited privileges
and disposable installation compatibility are verified.
