# Owner-confirmed executor enrollment

[Executor](executor.md), [connections](connections.md), [observations](observations.md),
[tasks](../tasks.md), [plan](../plan.md).

The native owner confirms the root helper's persistent hostUUID and the already
trusted SSH fingerprint. An MCP author/read/apply grant cannot enroll or replace
a helper. Inspecting a handshake is not confirmation. The application checks the
source-qualified bundled executor descriptor and actual helper response before
offering confirmation; matching self-reported hashes alone do not qualify code.

`ExecutorEnrollment` is exactly `{format:1,workspaceId,serverId,connection,hostId,
runtimeVersion,lockDigest,registryDigest,compilerDigest,bridgeDigest,createdAt}`.
UUIDs are canonical v4, connection is the existing exact ConnectionIdentity with
matching serverId, digests lowercase64hex, timestamp UTC milliseconds.
runtimeVersion includes the complete immutable program hash described in the
executor contract. A target connection/credential/trust change invalidates this
binding. Label changes do not confer authority. Owner confirmation cannot replace
the current native role/proof, target gate, SSH pin or per-step delegation check.

Metadata is stored in the existing protected workspace as
`executor-enrollments.json`, separately from the immutable Isar schema3 graph.
This file contains no credential or grant secret and grants no authority by its
presence. It is owner-only, read through retained protected Windows file APIs,
bound to workspaceId/receiptKeyId and HMAC authenticated by the existing receipt
key with purpose executor-enrollments-v1. Envelope is exactly `{document,mac}`;
document is exactly `{format:2,workspaceId,receiptKeyId,records,receipts}`. The old
format1 `{format:1,workspaceId,receiptKeyId,records}` remains readable with an empty
receipt set; the first new mutation publishes format2 atomically. Records are
unique by server, sorted on write, maximum250; receipts are unique by requestId,
sorted on write, maximum10000 and retained for the workspace lifetime. The whole
file is bounded64MiB; reaching either capacity refuses a new mutation before
publication and never evicts an old receipt. Corrupt, foreign,
wrong-key or unsafe file access refuses executor operations with STORAGE_BLOCKED.
Missing file means no executor enrolled. Stored old target facts are not silently
rebased to a new target. Workspace migration/backup must preserve this file and
its custody binding; copying it to another workspace never enrolls that workspace.

The production migrator keeps the active directory and replaces only registered
database/manifest files. Under its unchanged writer lease it captures protected
executor-enrollments.json bytes (or absence) before either upgrade step and
requires identical digest/absence after both, before ordinary store open.
Unsafe custody blocks migration. Sidecar HMAC/semantic validation remains the
executor store boundary; migration never recreates, drops or converts the file.

The existing original.isar migration copy is an internal DB recovery artifact,
not a standalone workspace backup. There is no user-facing backup/restore API.
An operator copying a workspace must retain its entire protected directory,
including receipt-key.dpapi, workspace identity, client credential custody and
this sidecar. Restoring only a DB is not a supported workspace restore. No new
arbitrary export path or credential tool is exposed by MCP.

StateStore queues protected read/write operations with its existing writer tail
and shared32 admission budget, verifies HMAC and exact readback after atomic
protected publication, and drains actual file work before release. This storage
primitive is not owner admission: the owner service still checks the exact
native method, current target, qualified release and confirmed host, performs the
required target/publication fence and retires affected executor operations before
ACK. An MCP caller cannot supply a fabricated parsed enrollment as a capability.

`RemoteExecutorService` loads only these protected records, compares the exact
connection tuple, opens the fixed helper over the existing interested transport,
and verifies host, runtime, lock, compiler, bridge and registry handshake fields.
The service owns pending protected-file/native/SSH work separately from logical
response lifetime. Target/session/service retirement and cancel cannot release
physical ownership early or start a late helper after cancellation. The shared
48-work connection budget includes these operations, and the transport's four
channel budget includes both observation and executor channels. Every request is
strict typed256KiB/depth16; responses8MiB, big-endian framing, no raw stderr,
no reconnect/retry, one outstanding request/stream with original5s IO deadline.
The same root stream binds status/authorize challenges. Root apply streams may
last at most2h, still requiring fresh current policy/native proof per request;
owner read/plan inspection remains bounded30s. Read contexts cannot submit,
cancel or authorize an effect. Job admission owns the additional exact plan,
approval/delegation and receipt checks before sending authority.

The descriptor builder is `tools/build-executor-release.py`; generating it does
not qualify a runtime. The native release manifest must bind that actual artifact.
Owner inspection/confirmation/revoke UI and service admission, preservation in
workspace operations, source-qualified descriptor delivery and actual native/
SSH negative/cleanup checks are required before enrollment is accepted as ready.

## Owner routes and native descriptor delivery

Format3 manifests may include the one additional fixed hash entry
executor-release.json. The four existing binary entries remain required; unknown
entries reject, and format2 still accepts exactly its original four entries.
An older four-entry format3 bundle provides no executor release. The Windows
bundle verifier alone constructs VerifiedExecutorRelease after bounded strict
descriptor parsing and before/after manifest/artifact hash checks. Pure
ExecutorRelease parsing does not produce this opaque verified type. Each use
revalidates the artifact binding. Native startup must obtain it from its own
verified bundle and pass it to the shared control composition.

`servers.executorInspect{profileId}` uses the existing native owner asynchronous
read handles/status/cancel path with its original30s budget and16-handle quota.
Result kind is executorInspect; payload exactly
`{serverId,challengeId,expiresAt,enrollment}`. The enrollment is a proposed public
binding, not an active registration. Locald reads actual helper hello, verifies
the complete qualified release, captures current SSH tuple/host/registry and
retains a random UUID challenge bound to the actual owner session. At most16
challenges,60s monotonic TTL; owner session detach removes them. The UI displays
hostUUID and the complete SSH fingerprint for confirmation.

`executor.enrollment{profileId}` returns `{profileId,enrollment}` with nullable
stored metadata. `executor.confirm{profileId,challengeId,hostId}` returns
`{profileId,enrollment}` only for that owner session's unexpired observation,
matching host and current SSH identity. `executor.revoke{profileId}` returns
`{profileId,revoked}`. These three are exact owner-only native routes with dedicated
strict format3 client result capture; MCP cannot call them. Initial owner proof
precedes prepared effects. Confirmation/revoke holds the existing native
reconciled target fence around metadata reads/publication, fresh owner proof and
physical executor-channel drain. Changed bindings retire affected/unbound MCP
sessions before ACK; exact same binding retains its original createdAt and does
not retire sessions. Cache observations become stale when a binding changes.
This closes next-step authorization; it never kills an already committed apt step.
Each confirmation/revoke stores its original result in the SAME protected
replacement as the changed registration, including no-change confirmation and
revocation of a missing binding. Receipt shape is exactly
`{requestId,method,requestDigest,result}`; requestDigest is the receipt-key HMAC
over `{purpose:executor-enrollment-mutation-v1,workspaceId,method,input}`. Input
is the exact validated route parameters, including the confirmation challenge
and host. Changing method or input under the same requestId gives
IDEMPOTENCY_CONFLICT. A freshly admitted owner may replay after reconnect/restart
even when the original challenge expired: lookup precedes challenge validation,
and returns the historical ACK without restoring its enrollment, changing
createdAt, reopening SSH, retiring sessions or renewing authority. A new request
still needs its own current challenge. Replay never exempts the current native
owner proof; the common target fence also serializes receipt lookup with new
mutations. Fresh mutations revalidate owner/identity/challenge again at queued
storage entry and immediately before publication. An ambiguous replacement or
failed authenticated readback blocks the store; no stale in-memory fallback is
used. Sidecar preservation and runtime/native/UI qualification remain explicit
T178 work before acceptance.

The native owner may inspect the same catalog with `servers.recipes{profileId}`
through the existing owner read start/status/cancel envelopes. Success kind is
recipes and result exactly `{serverId,catalog}` with the same strict complete
catalog capture. Original30s budget,16 retained handles,60s completion retention
and actual physical drain are unchanged. This read context may issue the
metadata-only root recipes request; it still cannot issue preflight, submit,
authorize, cancel or reconcile. MCP catalog access separately requires plan
scope. No JSON role flag or owner-to-MCP invocation is introduced.

The Flutter ServerController/ServerPanel uses the genuine TrustedApiClient,
tracks original async handles/cancel and retired epochs, and presents SSH trust,
connection, state/history, managed observations, logs and executor confirmation.
It owns no SSH credential/channel. State sampling is limited to an open panel
with its own connected interest; closing the panel stops sampling and cancels
pending read interest. Root UI/startup still must provide the verified format3
owner client; constructing this widget does not enable it in the legacy runtime.
