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

Sync allowlists metadata only; no raw journal/credentials/known-host replacement/
executable approvals. Enrollment and execution remain local human actions.
