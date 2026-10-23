# Shared trusted connections — 021

[Plan](../plan.md), [MCP](mcp.md), [trust](host-trust.md),
[transport](ssh-transport.md), [composition](trusted-services.md),
[foundation acceptance](../../001-service-foundation/spec.md).

## Responsibility and identity

Implement `TrustedConnectionService` in
`packages/serverdeck_locald/lib/remote/connections.dart`, constructed only by
`TrustedControlServices` with its identical schema3 store, custody, registry
and existing transport pool. Owner and MCP adapters call this same service.
No UI/bridge SSH dependency, second pool, credential store, mutable profile
copy, durable connection row or automatic reconnect. This stage completes
connection orchestration; typed remote reads remain T012.

One entry is keyed by actual profile UUID and the captured tuple
`{connectionRevision,credentialRevision,trustRevision}`. Its public identity
also includes `profileId` and exact confirmed `key:{format,fingerprint}`.
These counters use existing decimal-string foundation encodings. A profile
name/tag/settings edit does not change this identity. A captured profile
revision is not the transport key. Connected means authenticated pinned SSH,
not an observation of Linux host UUID, installed executor or healthy software.

Entry states are `connecting|connected|closing`; absence is `disconnected`.
No persisted or retained disconnected entries. Keep a closing entry charged
until its actual attempt/lease and native/credential work settle. Connecting
or connected entries for an identical tuple share one physical attempt/lease;
new callers join without another credential decrypt or authentication.
There are at most two entries including physical cleanup, sharing the existing
pool's two slots with trust probes. No connection queue or eviction of another
client's target; a new distinct target over capacity fails RESOURCE_LIMIT.

## Principals and authorization

Owner operations require the same-registry live native owner and exact admitted
method, with initial proof completed before any service effect. Add an opaque
`TrustedOwnerConnectionContext` in the existing operational auth library, issued
only by that admitted `servers.connect` request. It retains the actual registry,
channel/session identity and original admission time, not the completed RPC.
It cannot confirm trust, change credentials or admit another method. Like the
owner probe context it observes actual native proof completion separately from
logical waits. Its connection budget is 15 seconds from original RPC admission.
Existing probe context and its 30-second budget remain unchanged.

MCP operations require the existing actual `TrustedMcpContext` for this registry,
current `read` scope and explicit server access. Author-only grants cannot
connect, inspect connection state or detach a target. Check authorization before
target lookup; missing/out-of-scope MCP targets uniformly fail FORBIDDEN. Owner
missing target is NOT_FOUND. Recheck native identity/current policy and captured
tuple after every asynchronous authorization, custody or transport wait, and
immediately before publishing a result or transferring a connection interest.
Do not accept session strings, callbacks, caller revisions, pins, credentials
or boolean proof substitutes as connection authority.

Load the ready schema3 snapshot after initial proof. Absence/revoked/noncurrent
trust is TRUST_REQUIRED; only an observed pin mismatch is TRUST_CHANGED. Missing
saved access is NOT_READY. Retained unsupported username is UNSUPPORTED before
TCP. Use existing `KeyCustody.openCredential` with actual workspace/profile/
credential IDs; credential corruption is STORAGE_BLOCKED, never a new password
prompt or fallback credential. Construct the existing ephemeral SshCredential
only after successful custody validation. Drop plaintext references after use;
retain existing cleartext-byte zeroization and honest Dart string limitation.

One monotonic 15-second connect budget includes native authorization, custody,
joining/starting transport, authentication and final authorization. Extend the
internal transport connect entry to accept a positive remaining duration capped
at its existing 15 seconds; default remains 15 and probes remain unchanged.
No wire budget field. Waiting for an existing connecting entry uses that
caller's own remaining budget and never renews the shared attempt's deadline.
No native publication lease is held across SSH authentication. A concurrent
target change retires the old operation under the invalidation rules below.

## Shared interests and operation lifetime

An attached interest belongs to an actual session object and target identity,
not a caller-supplied label. At most one interest per session/entry; at most
eight per entry from the existing eight-session bound. Successful connect
retains the interest until explicit disconnect or actual session detach.
Joining the same connected entry is idempotent and returns that identity.
Pending connects from the same session/target share that one interest; each
caller still has its own bounded operation/result lifetime. Cancelling one
pending caller removes only that caller; remove a not-yet-established session
interest if no pending caller or successful connect remains for it.

Session disconnect/expiry, MCP grant replacement/revoke or authority retirement
removes only that session's interests. Last interest departure synchronously
prevents publication, cancels its pending attempt or closes its lease, and
retains physical charges through actual settlement. Later explicit connect
while this entry is closing fails RESOURCE_LIMIT; it does not join dead work
or enqueue a reconnect. A spontaneous SSH disconnect retires every interest
of that entry, invalidates its observations and closes/drains it; no automatic
retry. Future job interests must be opaque service-owned attachments backed by
admitted jobs; no job-interest wire field or fabricated job is added here.

Owner connect reservations/operations are bounded at 16 total, including
reserved/running/retained-completed and late physical/native/custody cleanup.
Reserve before asynchronous work; refuse excess RESOURCE_LIMIT. Completed
records expire after 60 seconds of monotonic time. Detach discards publication
and completion retention immediately, but physical work stays charged until
settled. Owner status/cancel uses exact same session/generation and fresh native
proof; status of foreign/expired/absent handles is NOT_FOUND. Cancel of foreign,
expired, absent or completed handles uniformly returns cancelled:false, never
reveals foreign ownership and never restores an operation. MCP uses its existing router
32-workspace/16-session/60-second operation retention, not owner handles. Neither
operation cache is durable or restorable after locald restart.

## Owner and MCP contracts

Add only these format3 owner routes; old format2/001.1 parsers remain closed.
All params are exact objects, IDs UUIDv4. Connection status results never contain
address, username, credential reference or secret. UI still gets profile
metadata through the existing authorized profiles APIs.

| Method | Params | Result |
| --- | --- | --- |
| servers.connect | `{profileId}` | `{operationId,state:"running"}`; operationId is this envelope's request UUID |
| servers.connectStatus | `{operationId}` | `{operationId,state:"running"}` or `{operationId,state:"succeeded",connection}` or `{operationId,state:"failed",code}` |
| servers.connectCancel | `{operationId}` | `{operationId,cancelled:boolean}`; removes this pending operation only |
| servers.connection | `{profileId}` | `connection` snapshot below, no TCP/credential access |
| servers.disconnect | `{profileId}` | `connection` after removal of this session's interest; physical close may still be pending |

`connection` is exactly `{profileId,state,interested,identity}`: state
`disconnected|connecting|connected|closing`, interested boolean for the current
session; identity null only when disconnected, otherwise the immutable public
identity above. Reporting another authorized client's shared connected state
does not attach the reader. `connectStatus` succeeded requires that caller's
interest still exists and identity/policy remain current; otherwise retire the
old completion and return NOT_FOUND. A cancelled pending operation cannot be
reported succeeded. Cancel returns false for absent/completed operations and
never removes an already successful session interest; use disconnect for that.

Different owner request UUIDs are separate bounded operations; repeated UUID
in the same live session and retained operation with identical profile joins
that operation, different profile fails IDEMPOTENCY_CONFLICT. A foreign session
cannot claim its UUID. After retention expiry the old UUID may start a new pure
connect; it has no durable receipt. No mutation retry or trust acceptance.

MCP `server_connect` returns the same `connection` as its operation result after
successful attachment. `server_disconnect` returns the same snapshot after
detaching only its session. When T012 implements `server_get`, it must use this
same connection snapshot in its authorized profile result; it remains outside
this connection-only increment. Pure state inspection never attaches. Existing
MCP tool arguments, scopes and asynchronous envelope remain unchanged. Define
strict shared result capture in protocol `connections.dart` and its verified
format3 method-result switch; owner and MCP serializers use that capture.

Compose a closed tool-service group of the existing catalog backend and this
connection backend: exactly the existing seven author tools plus connect and
disconnect are implemented at this stage. Unknown/unfinished domains remain
UNSUPPORTED; discovery still describes the full existing tool contract and
does not claim remote feature readiness. Router cancellation/timeout requests
cleanup of a pending connect caller. The synchronous final authorized transfer
of the session interest and service-result completion is its linearization
point: cancellation first prevents transfer, transfer first leaves an established
session interest. Like owner connectCancel, cancellation of an already-completed
connect does not implicitly disconnect; explicit disconnect or session retirement
removes established interests. Router completion/retention expiry releases only
its operation reference. No new router lifecycle callback is needed.

Fixed transport failure mapping: VALIDATION_ERROR→VALIDATION,
AUTHENTICATION_FAILED→FORBIDDEN, CONNECTION_FAILED→SERVICE_UNAVAILABLE; other
existing codes retain spelling. MCP transport failures have boundary remote,
retry reconnect for SERVICE_UNAVAILABLE/TIMEOUT and none otherwise. Owner
operation failure stores only its fixed code; ordinary owner RPC errors retain
the existing closed local error envelope. No raw transport exception or reason.

## Confirmed target changes and shutdown

The older `beginTargetChange` eagerly detaches every MCP session before every
profile mutation, even metadata/failed CAS/replay. It cannot implement this
stage's unchanged/unrelated transport preservation and remains unchanged for
existing format2 and standalone format3 adapters. Add a separate native-backed
`TrustedSessions.beginReconciledTargetChange` entry for the composition with
this connection service. It synchronously reserves the same bounded open-fence
interest and acquires the identical generation publication gate, with unchanged
16-interest/5-second/physical-release/poison rules, but does not detach established
MCP sessions before its lease is returned. No wire flag selects this path.
Acquisition/deadline failure before effect retains its open-fence charge through
actual native cleanup but does not detach established MCP sessions merely for
that no-effect failure. A poisoned gate/failed release still stops the generation
under the existing fail-closed rules; no successful preservation is claimed
when physical ownership is uncertain.

The returned opaque lease exposes `retireAffected(profileIds)` to its trusted
owner adapter. After stable commit/readback comparison, detach every MCP session
whose bound current grant allows any changed profile ID; also detach unbound
MCP sessions when the set is nonempty. Empty set detaches none. Attempt every
matching detach despite a notification error; failure poisons/stops this
generation and fails SERVICE_UNAVAILABLE after all cleanup attempts. Never
restore a detached session. The service compares all pre/post profile identity
tuples plus existence (at most250), not request field guesses; settings/name/
tags, exact replay and failed CAS produce an empty set. A disjoint grant and
its connected target survive a mutation of another target. A grant containing
the changed target is retired as a whole, even if it also allowed other targets;
the usual session-interest detach rules apply. This is authority retirement,
not selective resurrection of its other interests.

Capture the pre-effect immutable ready snapshot after acquiring the lease and
fresh owner proof, then run the actual coordinator effect. Capture its stable
post-effect snapshot even on a known no-effect failure. Invoke retirement and
reconciliation before releasing the lease. The native gate prevents old queued
MCP target output from publication throughout this interval; the shared open
fence blocks protected opens at every existing check. Old already-bound work
still requires its final gate/current-policy/tuple check, and cannot admit a
new durable job effect past this gate. Running/unknown target jobs retain the
existing HOST_BUSY mutation guard. On storage uncertainty use all-session
retirement and all-entry drain, never an assumed empty set. No asynchronous
publication callback waits inside the store queue.

Extend both trusted foundation and trust owner adapters with a typed internal
connection reconciliation dependency owned by the composition. After the common
coordinator's actual effect/readback settles and before owner acknowledgement,
while the existing target-change native lease remains held, reconcile against
the now-stable schema3 snapshot. This is outside the store queue; never await
session authorization/store-stability from inside a store publication callback.
Receipt replay also reconciles current state, without replaying a remote effect.

For changed connection/access/trust tuple or profile deletion, synchronously
advance the entry epoch, stop publication, retire all owner/MCP interests and
cancel reads/subscriptions; then await actual old attempt/lease, issued native
proof and custody work cleanup before releasing the target fence/ACK. Reconcile
unchanged tuples without disconnecting metadata/settings edits or failed CAS.
If storage is blocked/uncertain, fail closed by stopping/draining every entry;
do not infer rollback or revive an old interest. Run reconciliation even when
the effect throws, preserve the effect's safe failure unless cleanup fails,
then return SERVICE_UNAVAILABLE. No forced drain deadline or early slot release.

`TrustedControlServices` must construct explicit connection-aware foundation
and trust adapters using this new lease path. Existing constructors without
the connection service retain eager retirement and their existing tests; they
are not installed in the connected composition. Prove that identical store,
registry and connection service are required. Update production-composition
test expectations for metadata preservation only on this reviewed path, while
retaining all earlier eager-fence primitive/standalone regressions.

Reads publish only after current tuple/entry epoch/current session authorization
checks. An in-flight response between store publication and reconciliation is
rejected by the tuple check; there is no stale publication window. Retained
observations keep their old identity and become stale; deletion removes its
local observations. New identity needs explicit connect, never relabelling old
values. This service exposes an internal retirement notification for T012; it
cannot be overridden by a wire client or implement a second observation cache.

Composition close stops connections and logical interests synchronously, starts
their drain alongside the existing component drains, and closes the shared
pool only after all owned service/native/custody work settles. Observe each
cleanup failure and attempt every cleanup path. Failed drain retains existing
composition claims and fixed SERVICE_UNAVAILABLE; borrowed store/key/mutex
and raw native channel teardown remain outer-runtime owned.

## Acceptance and staging

T170 records/reviews this design. T171 implements shared protocol captures and
native opaque owner context; T172 implements service/owner+MCP adapters and
composition/reconciliation; T173 qualifies real native protected schema3 and
disposable SSH integration. Keep existing completed task history. Full read,
executor, UI, installed startup and source-qualified release gates stay open.

Qualify two owner windows plus scoped MCP sharing one authentication/physical
entry; third distinct transport/probe refusal; cancellation of one joiner;
last-interest cleanup including late credential/native/TCP completion; actual
session/grant expiry/revoke; credential/connection/trust/delete mutation during
authentication and after connection; unchanged settings/name/tags; replay and
failed CAS; exact profile/operation scope and all quota/TTL boundaries. Include
MCP-only connected A with no owner interest: name/tag edits of A, failed CAS,
exact replay and mutation of B under a disjoint grant must preserve A's same
actual SSH authentication/lease. A grant that includes changed B must retire;
test that distinction and queued actual target stdout before/after the native
gate, plus in-flight protected open and overlapping new reconciliation leases.
Use the
same actual gate/store/coordinator, real CurrentUser DPAPI and loopback SSH.
Prove fresh native proof before decrypt/start/publication, zero authentication
on pin mismatch, no secret outputs, no late success/observations after target
ACK and close retaining physical ownership. Actual transport loss requires
explicit reconnect. No callback, fake session/proof or saved user server fixture.
