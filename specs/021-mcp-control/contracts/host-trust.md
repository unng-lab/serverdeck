# Persisted owner host trust — 021

[Transport](ssh-transport.md), [loading](loading.md), [migration1→2](migration.md),
[owner foundation](owner-foundation.md), [target fence](target-fence.md),
[model](../data-model.md), [tasks](../tasks.md).

The internal [shared control composition](trusted-services.md) binds the
schema3 owner/trust/grant/catalog instances and their shutdown ownership.
It does not activate installed startup or unfinished remote services.

## Components and compatibility

Extend the existing single workspace to schema3 before activating remote
services. Schema1/2 retain their exact closed definitions/readers; neither
gains an optional JSON field or hidden trust file. Schema3 contains all15
schema2 collections unchanged plus StoredHostTrust (auto native id,
unique indexed String entityId, String payload), entityId=server profile UUID.
Generate its ordinary Isar3.3.2 schema with the pinned generator. Native
preflight recognizes exactly5/15/16 collections as1/2/3; mixed/unknown/partial
registries refuse before writable open. Old schema2 openers still refuse3.

Implement storage/models and trust records in locald; public pin/trust DTOs
and strict method validation in protocol/host_trust.dart. Move the transport's
canonical SshHostPin validation there, re-export it from the existing remote
module together with the existing SshTransportCode/SshTransportFailure types,
preserving their API/algorithm mappings and all accepted T144 tests. These
remain private transport codes, not a new MCP error enum or wire capability.
No protocol dependency on locald/dartssh2 or UI access to storage/SSH.

Explicit schema3 loader/store/coordinator entries use the same mutex, DPAPI,
single durable queue and total32 mutation admissions as schema2; no second
writer or fallback snapshot. Full retained15+trust graph validation precedes
readiness. Existing grant/catalog/foundation services must explicitly support
this retained schema3 snapshot before composition; migration success alone
never activates services. Preserve schema2 component fixtures/readers.

Remote product bundle has a separate strict format3 manifest with the exact
format2 field set/four filenames, values format3/workspaceSchema3/API1.1;
workspace manifest exactly `{product:"serverdeck-next",format:3,schema:3,
workspaceId,receiptKeyId,ownerSid}`. Add explicit format3 verifier/native runtime
entry, reuse actual hash/root/retained peer/role checks without caller-selected
roles. Format1/2 verifier/loader/runtime entries remain closed to3. All four
executables/DLL belong to the same verified format3 build for remote startup;
no format2 proof authorizes a schema3 service or vice versa. Common native
initialization reservation binds format/schema as well as existing build/root/
DLL identity; a process cannot switch formats after initialization. MCP wire
versions/tools stay unchanged; owner-only additions below are Local API1.1
same-build methods, unsupported by older component bundles. No startup flag
becomes true until full T011/T012 and the existing activation gates pass.

Format3 uses a separate strict readiness DTO with the same operational fields,
generation/feature semantics and base readiness-reason vocabulary, but
storageSchema exactly3. Its verified native client rejects schema2 readiness;
existing format2 DTO still requires2. During migration/failure the service is
not ready and remote features remain false; HOST_BUSY from migration is a
startup/owner failure, not a claim that a partially migrated store is ready.
Readiness/ping never probe a server. Qualify reciprocal readiness decoding
with the format3 native fixture, alongside bundle/runtime mode refusal.

## Exact record and foundation transitions

StoredHostTrust.payload is strict JSON<=4096 UTF8 bytes with exactly:
`{workspaceId,profileId,revision,connectionRevision,status,key,createdAt,updatedAt}`.
IDs lowercase UUIDv4; revisions decimal strings uint63>=1; key exactly
`{format,fingerprint}` canonical SshHostPin; status trusted|revoked; times UTC
milliseconds and createdAt<=updatedAt<=current profile.updatedAt. One row per
existing profile, maximum250; no orphan or cross-workspace row. No secret,
address, credential reference, historical key list or unbounded extension map.

Schema3 Profile retains the existing exact JSON fields. In schema1/2 keep
connectionRevision==trustRevision; schema3 requires
1<=connectionRevision<=trustRevision<=profile.revision. Credential counters
retain their existing separate rules. A trust row's revision equals current
profile.trustRevision. Its connectionRevision identifies the connection at
which its key was confirmed: trusted requires equality with current profile;
revoked permits an older value1..current connectionRevision. Absence means
never confirmed, requires trustRevision==connectionRevision, and never implies
permission to connect. Initial/migrated profiles have no trust row.

The same schema3 rule applies to every captured target in Plan,
ManagedResourceObservation and their nested preflight/baseline DTOs:
1<=connectionRevision<=trustRevision<=captured serverRevision/targetRevision;
accessRevision remains independently1..that captured revision. Keep the exact
existing JSON fields, decimal encodings, plan format and canonical digest
inputs. Add explicit schema3 parsing/construction paths; old schema2 DTO
constructors/loaders retain equality. Schema3 full-graph loading, compiler,
read adapters, plan services and format3 UI/bridge clients select the new
paths from verified composition, never a caller-supplied JSON schema flag.
An old equal-counter plan remains byte-identical/readable as history. A later
trust increment makes its live admission stale, not structurally corrupt;
current-policy checks remain separate from historical decoding. New plans
and even unknown observations after confirm must represent conn1/trust2
without coercing either counter. No old profile or observation is relabelled.

Every successful mutation below is one real transaction: profile, optional
trust row, all existing affected foundation records, foundation storeRevision
and immutable foundation receipt. Preserve every automation row/native ID.

| Mutation | Required transition |
| --- | --- |
| Confirm | CAS profile revision; increment profile/trust revisions by1, preserve connection/credential revisions; insert/replace row trusted with new trust revision/current connection revision and exact challenged key. Keep original row.createdAt; updatedAt=commit timestamp. |
| Revoke | Require existing row; CAS profile revision; increment profile/trust revisions even if already revoked; preserve key, original confirmed connection revision and createdAt; set revoked/updatedAt. Unknown row fails TRUST_REQUIRED without write. |
| Connection fields change | Existing profile/connection/trust increments apply; existing trust row becomes revoked with new trust revision, retaining old confirmed connection revision/key/createdAt. Absent row stays absent. |
| Credential change | Existing credential/profile increments and transport invalidation apply; trust row/key/revision remain unchanged. |
| Name/tags/settings | Existing rules; no trust change or transport invalidation. |
| Profile delete | Existing guards/credential/settings effects; atomically remove current trust row, retain historical receipts/plans. |

No wraparound/native-ID overflow; quota/capacity/failed CAS leaves all16 rows
and IDs unchanged. A new native row allocates only after admission; existing
row updates preserve its native ID. Full readback before cache publication;
uncertain commit/readback failure blocks, never clears data or retries effect.
The common native target fence covers confirm/revoke/connection/credential/
delete through actual commit/rollback and old-reader physical drain; active/
unknown target jobs retain HOST_BUSY guards. Metadata changes remain allowed.
Late old-epoch values cannot publish, observations keep old identity/stale.

When the connection-aware format3 composition is implemented, use the explicit
[reconciled target lease](connections.md#confirmed-target-changes-and-shutdown)
for foundation and trust adapters: same native gate/open fence, actual stable
pre/post identity delta, affected-grant retirement and physical connection
drain before ACK. This avoids eager retirement closing MCP-only transports
on metadata/no-effect/replayed or disjoint-target mutations. Standalone legacy
target leases retain their existing eager retirement behavior.

Add exactly foundation receipt operations servers.trust.confirm/revoke,
validated as profile updates (nondeleted entityId=profileId, entityRevision>=2,
entityRevision<=receipt storeRevision). Existing foundation10000 receipts,
gapless storeRevision, cross-origin automation ID conflicts, HMAC key and
permanent replay rules apply. Existing schema1/2 receipt readers do not accept
these operations. Receipt digest covers validated operation/body, including
challengeId/key for confirm, not the envelope request ID. Stable replay uses
this body even after challenge expiry/restart/profile deletion, after fresh
native owner authorization; never reactivates trust or performs another write.

## Owner-only protocol and challenge lifetime

All methods below require an actual same-registry native owner request;
MCP/wrong-role/method/session fails before parsing or target/receipt lookup.
Foundation mutations use the existing envelope UUID as durable request ID.
No additional wire origin/token/owner flag or credential field.

| Method | Exact params and result |
| --- | --- |
| servers.trust.get | `{profileId}` → `{profileId,profileRevision,connectionRevision,credentialRevision,trustRevision,trust:null|record}`; public record omits workspaceId only. |
| servers.trust.probe | `{profileId,expectedRevision}` → `{operationId,state:"running"}` after bounded native admission; operationId=envelope UUID. No credential load. |
| servers.trust.probeStatus | `{operationId}` → `{operationId,state:"running"}` or `{operationId,state:"succeeded",challenge}` or `{operationId,state:"failed",code}`. |
| servers.trust.probeCancel | `{operationId}` → `{operationId,cancelled:boolean}`; no transport/credential handle. |
| servers.trust.confirm | `{profileId,expectedRevision,challengeId,key}` → unchanged foundation MutationResult. |
| servers.trust.revoke | `{profileId,expectedRevision}` → unchanged foundation MutationResult. |

Revision fields are decimal strings. UUIDs/keys strict, unknown fields fail.
Probe operation belongs only to its exact live native owner session/generation;
other owner session gets NOT_FOUND, not a bearer capability. Total16 live/
retained probe interests/challenges per workspace, including active probes.
Reserve synchronously before awaits; excess RESOURCE_LIMIT. No implicit
duplicate probe: live duplicate envelope gets existing operation if exact
same immutable body, otherwise IDEMPOTENCY_CONFLICT. Terminal result retained
60seconds; after expiry NOT_FOUND and explicit new probe required. Probe has
one30second monotonic service budget including fresh proof; the underlying
transport keeps its own15second budget. Ordinary owner call/poll keeps5seconds;
never wait for SSH inside a synchronous owner response or reset deadlines.

Actual transport probe rejects the key before authentication and physically
settles before producing a challenge. After fresh native proof and unchanged
captured profile revision/all three access counters, issue exactly
`{challengeId,profileId,expectedRevision,connectionRevision,credentialRevision,
trustRevision,key,expiresAt}`. Challenge UUIDv4, expiresAt UTC display timestamp,
actual TTL300seconds monotonic from issuance, bound to session/generation and
exact captured target. Removing the terminal probe result after60seconds does
not erase its still-live challenge; it occupies the same one admission slot
until TTL/consume/detach. A cancelled probe never publishes a late challenge;
physical transport/worker ownership drains before slot release. Disconnect,
generation change, explicit cancel or shutdown invalidates that session's
challenges; restart creates none. Current closed failure codes only; no raw
SSH text or fingerprint from another target in an error.

Keep the request ID/immutable body binding for the whole admission-slot
lifetime, even after its60second status-result window. A duplicate after that
window returns NOT_FOUND without starting another probe while a challenge is
still retained. Once the slot retires, the ID is reusable for a new read-only
probe. Cancel returns true only when it cancels pending work or invalidates an
unconsumed live challenge; repeated cancel returns false while the status
entry exists, otherwise NOT_FOUND. An already published success remains its
historical result and never proves that its challenge is still usable. After
consume/cancel/expiry, retain the terminal result only until the original
60second deadline; release the slot once no result/challenge/physical work
remains. Cancellation cannot revoke an already committed trusted pin.

Confirm admission after stable replay requires matching unexpired challenge,
same owner session/generation, exact key/profile/expected revision/counters.
Missing/expired/mismatched challenge fails TRUST_REQUIRED; failed CAS remains
REVISION_CONFLICT. Serialize consume with the actual store queue/native gate;
only the successful committed confirm consumes, quota/rollback leaves the
challenge usable until expiry. An uncertain commit blocks service until
reopen and exact receipt lookup, not another blind confirmation. Multiple
requests cannot consume one challenge for two commits. CAS checks precede
challenge use, and current owner proof precedes both. Revoke needs no probe.

No trust mutation comes from MCP or a read. Mismatching SSH key blocks that
attempt with TRUST_CHANGED, leaves the stored pin unchanged and exposes no
remote data. New-key acceptance requires owner probe/confirm; every future
connection still verifies the stored exact pin, including after restart. An
old trusted key restored on the host can satisfy that same pin; no unseen key
is accepted. Owner UI uses these same methods, displays canonical fingerprint
and target before confirmation, and cancellation preserves profile/credentials.
Existing valid profiles with usernames unsupported by the qualified transport
are retained; connection reports UNSUPPORTED without TCP rather than treating
stored data as corrupt or rewriting it.

## Exact owner errors and async failure codes

Format1/2 ErrorCode/LocalError and their clients remain unchanged. Format3
uses a separate immutable TrustedLocalError with exactly the existing
`{code,boundary:"local",retry}` shape (plus the existing optional bounded
foundation validation field only). Its closed code set is the existing15
ErrorCode wire values plus TRUST_REQUIRED, TRUST_CHANGED, HOST_BUSY,
AUTHENTICATION_FAILED, CONNECTION_FAILED, CANCELLED. No arbitrary strings,
provider messages, raw exceptions or new MCP error enum. probeStatus.failed.code
is exactly this same21-value closed set; it carries no retry/message/field.
Use the same centralized retry mapping for rendering async outcomes.

Existing15 codes retain LocalError retry rules. New TRUST_REQUIRED,
TRUST_CHANGED, HOST_BUSY, AUTHENTICATION_FAILED and CANCELLED have retry none;
CONNECTION_FAILED has reconnect (explicit action, never automatic mutation).
Trust-required/changed UI action is fresh owner probe/confirmation; host-busy
requires existing job reconciliation; failed auth requires owner access repair.
Format3 server/client/channel select this codec only from the actual verified
format3 native composition. No request option selects it; format2 stays strict.
Unknown code or wrong retry/field rejects as malformed, never INTERNAL success.
Extended domain errors are emitted only on owner routes, not substituted for
MCP tool-domain results or the standard native authentication close behavior.

Transport private code mapping is exhaustive: VALIDATION_ERROR→VALIDATION;
all other seven transport codes map to the identical wire spelling. Unknown
internal failures map INTERNAL without exception text. Service mapping:
malformed params→VALIDATION; wrong owner/method→FORBIDDEN before target lookup;
failed native peer→UNAUTHORIZED with existing native session retirement;
missing target→NOT_FOUND; changed expected revision/captured counters→
REVISION_CONFLICT; unsupported username→UNSUPPORTED; unavailable workspace→
its actual NOT_READY/STORAGE_BLOCKED; quota/native capacity→RESOURCE_LIMIT;
expired budget→TIMEOUT; explicit probe cancel→CANCELLED; stopped service→
SERVICE_UNAVAILABLE; missing/expired/consumed/mismatched challenge→
TRUST_REQUIRED; occupied active/unknown target mutation→HOST_BUSY;
request ID changed-input→IDEMPOTENCY_CONFLICT. Existing proof/queue/CAS ordering
still applies. Confirm/revoke use this error envelope, keeping their successful
MutationResult unchanged. Native wire tests check exact codes/retry, malformed
extended responses, retained unauthorized-session close, and a subsequent
valid call after ordinary domain refusal.

## Schema2→3 migration

Apply the complete7-step protected-copy/publication/recovery protocol from
[migration1→2](migration.md), with these exact substitutions/extensions:

| Item | Schema2→3 value |
| --- | --- |
| Source/target | strict schema2/format2 → strict schema3/format3 |
| Stage directory | default.upgrading-2-3/ |
| Allowed stage files | migration.json, migration.json.new, workspace.isar, workspace.isar-lck, original.isar, manifest3.json |
| Journal | same exact format1 fields/phases/hashes, fromSchema2/toSchema3; target fields required only for prepared |
| New collection | StoredHostTrust, required empty after migration |
| Old preserved rows | all15 existing collections, not only foundation |

Preservation digest is SHA256 of foundation canonical JSON
`{workspace,collections}`. workspace is the existing nativeId/validated payload
excluding only schemaVersion. collections maps each of the other14 exact
schema2 collection names to rows sorted by nativeId, each
`{nativeId,entityId:null|string,payloadBase64}`; StoredSettings entityId=null,
all other rows retain their exact entityId. Payload bytes use padded base64
without normalization. No old timestamp/revision/key/ID/blob is changed;
workspace schemaVersion is the only semantic change. Full historical graph
and all credential DPAPI checks still run on protected copies.

Under the same sole-writer lease, refuse any nonterminal job (anything other
than succeeded/failed/cancelled), including unknown/reconciling, with HOST_BUSY
before staging; preserve source rows. This requires an initial owned schema2
preflight before freezing any migration hashes. Only when the2→3 stage is
absent or an empty protected directory (and no creating/1→2 stage exists),
verify the format3 actual-locald runtime, exact schema2 manifest/key wrapper,
fixed active path/ACL/lock and exact15 native registry, then open active with
exact schema2 definitions under the same global open reservation and writer
lease. Perform no application transaction or native schema change. Capture and
validate the entire15-collection graph, all server/client DPAPI bindings and
existing credential lookups, without publishing or repairing any lookup. Close
and confirm every native handle before returning HOST_BUSY or freezing hashes.
An unconfirmed close retains the shared reservation and lease and returns
STORAGE_BLOCKED. No stage/journal/backup or service readiness is created by this
preflight. A normal same-schema native open may change physical housekeeping
bytes; those preflight bytes are not migration source hashes. Existing row
payloads/native IDs and manifest/key bytes remain unchanged. Once closed and
job-free, capture source hashes and start the original7-step protocol; no
subsequent active native open is allowed while a journal/hash binding exists.
On recovery with a nonempty stage, never repeat active preflight: validate only
the protected source/target copy selected by the recovery table. Its complete
graph must also be job-free before candidate change or resumed publication;
nonterminal jobs in a journal-bound copy mean STORAGE_BLOCKED, not permission
to reopen or mutate active with a schema2 build. The same immutable capture
and preservation digest are used for source2 and target3 copies; target trust
must be empty, and migration validation never publishes credential lookups.
Use distinct internal source-preflight/source-copy/target-copy entries with
fixed active or default.upgrading-2-3 paths, not a caller-selected directory or
JSON schema switch. Keep existing normal schema2/3 loader publication behavior.
Retained plans/approvals are unchanged but
cannot execute with absent trust or after a later trust-revision change.
64MiB map,144MiB free staging/16MiB reserve, atomic retained-handle rename,
hash-bound no-active-open recovery and process-kill failure model remain exact.
No power-loss qualification, extra DB, plaintext fallback or rollback after
DB publication. Recovery table substitutes2/3 for1/2 literally; malformed or
cross-step stage/journal/hash/identity blocks without reset. Schema1 startup
runs1→2 then2→3 sequentially under one writer lease; no remote readiness or
mutations between steps. An interrupted fully valid2 resumes3; active/unknown
jobs require reconciliation using a compatible schema2 build before upgrade,
while no2→3 journal/hash binding exists.

## Acceptance and implementation order

T150: pure exact pin/trust/schema3 foundation records, historical receipt and
cross-reference tests; unchanged schema1/2 strict refusal, immutable DTOs and
Unicode/uint63/bounds. T151: actual native16-collection loader/writer and
2→3/1→2→3 migration, real DPAPI/payload/native-ID preservation, all recovery
kill boundaries/quota/capacity/CAS/fault/blocking cases from migration contract;
format3 reciprocal proof/runtime refusal and same-build native fixture.
T152: actual native owner API/challenge/coordinator, real loopback SSH fixture,
cancel/expiry/replay/queued race/revoke and physical target invalidation before
ack, two owner windows and denied actual MCP/foreign-registry clients. T153:
owner UI guided trust and actual Windows→Linux lifecycle evidence, retaining
MCP privacy and no direct UI SSH. Existing T011/T109/T110 remain open until
full service composition; T012 observations are separate. Root/package checks,
link checks and fresh independent design/code reviews precede each handoff.
