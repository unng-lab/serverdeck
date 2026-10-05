# Data model

ServerProfile: stable ID, display name, endpoint, port 1..65535, user, tags,
credential reference, enrolled fingerprint. No credential material.
Observation<T>: nullable value, UTC observedAt, source, status available/unknown/
unsupported/denied/failed, evidence. Age computes stale. Failure retains last value.
Software: server ID, name, nullable version, package/binary/unit/container/workload
source, related units, confidence, observedAt. Unit: full @instance name, load/
active/sub state, nullable MainPID. Unit or running process does not imply package.
JournalRecord: cursor, boot ID, UTC instant, unit, priority 0..7, message, raw fields.
BoundedJournal: ring of 500, max 64 KiB record, duplicate/parse/drop/gap counters.
Pause freezes display while transport may continue. Session survives navigation.
Job: immutable identity/version/recipe/parameters/preflight/approval/idempotency;
phase and sequenced events committed atomically. One active writer/host. Success
requires version/unit/probe. Uncertain cancellation never claims rollback.
SyncEnvelope: owner/device/revision/baseRevision/allowlisted non-secret payload;
conflict retains both revisions. Remote metadata cannot grant execution approval.
