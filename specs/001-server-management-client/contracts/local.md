# Local contracts and authority

InventoryRepository.refresh(profile) -> partial timestamped observations.
ReadOnlyTransport.exec(ReadOperation) accepts typed detectors only, validated IDs
and POSIX-encoded arguments. No raw shell editor or sudo in this capability.
HostIdentity verifies enrolled fingerprint before auth: unknown requires enrollment,
mismatch denies. CredentialStore reads OS-custodied secret by local reference.
JournalRepository.history(limit)/follow(cursor,boot) -> record or explicit denied/
unsupported/transport/parse/truncation/gap. Failures never become successful empty.
MetricsRepository.sample -> nullable interval observations with timestamps.

JobRepository.submit(approved immutable plan, idempotencyKey) atomically returns
existing identical job or rejects conflicting key/input. Approval binds host key,
device, recipe digest and exact versions. Durable event transitions:
queued -> preflight -> awaiting-approval -> running -> succeeded/failed;
running -> cancel-requested -> cancelled/unknown;
in-flight crash -> unknown -> reconciling -> succeeded/failed/unknown.
Unknown/reconciling retain lock. Cancelled requires confirmed stopped execution and
reported partial effects. No rollback claim. Demo plans cannot grant approval.
Runner IPC is child-process pipes plus owner-local artifacts, no remote listener.
Raw events private, bounded and redacted before export.

## Local API v1 — implemented architecture increment

Flutter -> separate compiled Dart locald, IPv4 loopback ephemeral port; POST JSON,
Bearer session proof rotated at service restart, no browser Origin accepted.
Owner/SYSTEM-only Windows directory holds endpoint.json, exclusive process lock
and Isar database. No runtime Isar download. Request cap 1 MiB, client response
cap 2 MiB, request/client deadlines 5 seconds. Client bypasses HTTP proxy settings.
Health verifies API version and service identity; failed writes do not update UI.

Routes: /v1/health; profiles/{list,initialize,save,remove};
jobs/{list,get,submit,cancel,launch,events}. Profile init is one-time, deletion is
durable; last profile deletion refused. Profiles reject secret fields and require
.invalid in demo; cap250 profiles, each <=4096 UTF-8 bytes so listing fits the IPC
response budget. Job input is immutable and validated; submit does not authorize
execution. Launch always returns ExecutionDisabled; no caller-provided running
transition, probe result or executable approval route exists. Events accept
after>=0, limit1..1000; summaries have no stdout or credential fields.
The current client rediscovery is at startup; after service failure restart the
app, and never blindly retry a write. Automatic reconnect is future T005/T010.
The service remains alive when the UI closes. Actual executor survival and remote
recovery remain T010 acceptance gates. Historical Python SQLite files are not
automatically imported, modified or deleted.

Sync allowlists metadata only; no raw journal/credentials/known-host replacement/
executable approvals. Enrollment and execution remain local human actions.
