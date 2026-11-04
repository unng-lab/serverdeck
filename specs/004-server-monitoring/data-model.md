# Data Model: 004

Публикуемые snapshots immutable; owner владеет baseline/queues.

| Entity | Fields / constraints |
| --- | --- |
| MetricKind | cpu, memory, disk, ровно три |
| MetricReading | nullable percent finite 0..100; monotonic receivedAt; UTC displayAt; fixed nullable reason |
| CpuCounters | восемь неотрицательных int ≤2^63−1; baseline на sessionId |
| MonitoringSnapshot | profileId, sessionId?, connectionRevision, generation, три readings, computed flags |
| PerProfileState | attemptedAuto, manualStop, unsupportedSession?, dueAt, handle?, baseline?, readings |
| OwnerState | active, epoch, startupBlocked, stopped, fair queues; ≤4 collects и ≤4 auto attempts |
| MonitoringConnectResult | operation receipt, immutable cancelledBeforeAdmission set only by canonical admission guard |
| CollectionHandle | result Future, synchronous idempotent cancel; cancelled result не публикуется |

States: inactive → queued/connecting → trust/passphrase wait → collecting →
fresh/partial/unavailable; age≥15s → stale. Hide/leave invalidates active epoch,
retains readings as stale and clears CPU baseline to require a new pair on resume. Disconnect clears baseline, blocks auto retry. Canonical ConnectionOwner generation>0
(or retained attemptId/sessionId) records a prior attempt even while disconnected;
this history survives profile connection/credential revisions in the current run.
It does not survive profile deletion/new runtime, and explicit connect remains allowed. New
session clears baseline/unsupported. Deletion removes state and cancels work.
Rename preserves session/baseline. Invalid metric immediately loses freshness;
old value retained only as stale with reason. Invalid CPU resets baseline;
next valid establishes it, following valid computes delta. First pair spans two cycles.

Only fresh percent≥90 contributes critical. Partial and critical independent.
UTC display-only, monotonic controls age/deadlines. Keys profile UUID, не endpoint.
At most 1000 states under existing profile limit; deleted states pruned.

Persistence: data/monitoring-run-v1.json, exactly ASCII
`{"version":1,"state":"running"}` or `{"version":1,"state":"clean"}`.
Read≤128 bytes; invalid/oversized/reparse/I/O is blocked, not missing.
No metric/credentials/config persistence, no Isar migration.
