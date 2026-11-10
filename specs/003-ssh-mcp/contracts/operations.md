# AppOperations v1 — общие UI/MCP-действия


Это контракт будущей реализации, не реализация. Domain owner принадлежит основному
приложению002. Только типизированные UI adapters могут создать UiActor; MCP получает
McpActor(clientId,grantVersion,ownerEpoch), сформированный сервером после проверки
native peer/auth. Поле actor из JSON запрещено. Widgets/router не получают Isar handles.

## Общие types

Endpoint: normalizedHost,port,endpointId. Public ProfileView: profileId,revision,
connectionRevision,displayName,host,port,username,authKind,hasCredential,endpointId;
никаких password/key/passphrase/protectedBytes. ConnectionView: state,attemptId?,
sessionId?,failureCode?,challenge?,pendingInput?,reconnectAttempt? (integer 1..9007199254740991, saturating counter); TrustView: acceptedFingerprint?,observedKeyType?,
keyType?,trustRevision,observationRevision,changed,observedFingerprint?,detectedAt?.
В каждой projection dataRevision и ownerEpoch. Times int64 UTC ms, UUID lowercasev4.
Connection state: disconnected,connecting,needTrust,needPassphrase,authenticating,
connected,failed,cancelled. Wire не выводит «connected» из profile existence.

Result: `{ok:true,value,meta:{dataRevision,ownerEpoch}}` либо `{ok:false,error:{code,field?,retryable,messageKey}}`.
Коды: INVALID_ARGUMENT,PROFILE_NOT_FOUND,CONFLICT,AUTH_REQUIRED,ACCESS_REVOKED,
GRANT_EXPIRED,TRUST_REQUIRED,HOST_KEY_CHANGED,AUTH_FAILED,PASSPHRASE_REQUIRED,
PASSPHRASE_INVALID,UNSUPPORTED_KEY,UNSUPPORTED_SERVER,NETWORK_ERROR,TIMEOUT,
STORAGE_UNAVAILABLE,PROTECTION_UNAVAILABLE,SHUTTING_DOWN,RESOURCE_EXHAUSTED,CLEANUP_REQUIRED.
MessageKey не содержит сырых library exceptions/remote banners или secrets.

## Операции

| Operation | Вход | Исход / эффект |
| --- | --- | --- |
| listProfiles | limit1..100(default50),cursor? | items ProfileView; nextCursor?; snapshotRevision |
| getProfile | profileId | ProfileView+ConnectionView+TrustView либо NOT_FOUND |
| createProfile | mutationId,profile fields,auth input | profileId+revision; atomic profile/credential/refcount/receipt |
| updateProfile | profileId,expectedRevision,mutationId,patch≥1 field | new revision; stale CONFLICT; secrets unchanged unless auth provided |
| deleteProfile (UI only) | profileId,expectedRevision,explicitConfirmation | atomic profile/credential/refcount delete; close attempt/session first |
| connect | profileId,expectedRevision | current/new ConnectionView; repeated connect returns same attempt/session |
| getConnection | profileId | ConnectionView |
| providePassphrase | profileId,attemptId,nonce,passphrase | continue same current attempt; no secret echo |
| cancelConnection | profileId,attemptId | cancelled/noop; wrong current attempt CONFLICT |
| disconnect | profileId,sessionId | disconnected/noop; never disconnect a different new session |
| getTrust | profileId | TrustView + applicable current challenge? |
| acceptTrust | profileId,attemptId,nonce,expectedProfileRevision,expectedTrustRevision,expectedObservationRevision,fingerprint,mutationId,confirmed=true | commit first accepted key; allow same verified handshake to authenticate |
| replaceTrust | same exact challenge fields+oldFingerprint,newFingerprint | commit new key; invalidate endpoint sessions and end attempt; explicit reconnect required |
| retainTrust | same exact challenge fields+acceptedFingerprint | only a fresh observed accepted-key challenge clears warning; invalidate sessions/end attempt |

List sort: createdAt ascending then profileId. Cursor opaque base64url of last tuple+
listRevision. Concurrent list mutation invalidates cursor → CONFLICT; start list again.
Empty list is successful only after store read success. Unsupported patch keys rejected;
profileId/credentialId/endpointId cannot be overwritten directly. Port omitted on create22.
Auth input: password exact UTF-8 string (1..65536 bytes); or original supported SSH private-key bytes per key-input.md
base64 (decoded≤1MiB), optional ephemeral passphrase (≤65536 UTF-8 bytes). Input bounds
check before decoding/protect. UI file picker yields the same key bytes; MCP cannot
read arbitrary local filenames. No secret getters, token-management or generic command.

## Fences, persistence and conflicts

One writer FIFO queue, max64 queued commands, overflow RESOURCE_EXHAUSTED. No network
wait under gate. Every admission captures coordinator epoch/actor grant version;
before commit/send auth packet checks runtime running, grant current, profile/trust
versions and attemptGeneration. Irreversible network effect linearizes at socket write
admission, not at wall-clock delivery after bytes entered OS. Revoke ordered before
admission prevents effect; completed-before-revoke effects are not rolled back.

Credential parsing/protection performed before gate; at gate revisions checked again.
Connection-affecting mutation invalidates generation and closes socket first; if close
cannot be confirmed, affected endpoint stays quarantined/denied, storage mutation
is not reported successful. Rename does not close session. Delete of last endpoint
profile deletes trust+warning atomically; moves to new endpoint update both refcounts.

Admission order: runtime/current actor authorization → existing receipt lookup by
clientId/mutationId and constant-time payloadHmac match → replay result OR new
expected-version/challenge validation → transaction/effect. Replay does not re-validate
consumed nonce/current entity revision and never resumes authentication or repeats
socket effects. It returns only the already committed outcome IDs; changed current
state is read separately. Different payload still conflicts.

All mutation receipts are written with effect in same txn; HMAC store key from
[data model](../data-model.md). Replays pass current auth first, return commit IDs/
revision with replayed=true, not a resurrected entity; caller re-reads current state.
Expired receipt≥24h no longer deduplicates; client must not blindly retry creates.
Different payload with same mutationId conflicts even if operation name differs.
UI mutations may use generated local IDs but are not addressable as MCP actor receipts.

For trust, warning and observation persisted before exposing challenge; storage error
blocks auth and returns storage error with runtime warning retained. Unknown key grant
record version starts1; no accepted key until explicit acceptance. Nonce consumed once,
5min deadline monotonic in memory. A newer offered key increments observationRevision
and invalidates old nonce. Rejected/closed dialog stores no acceptance. Matching A
while warning from B exists permits authentication but does not silently clear warning.
Retain requires explicit nonce from fresh handshake proving accepted A, not cached data.

DeleteProfile cannot be invoked by MCP even by guessed tool name, unknown JSON keys,
bulk import, shutdown, reset or admin tool. Internal delete requires UiActor, not
`source='ui'` from a caller-controlled payload. Updating host/credentials retains ID
and normal UI edit semantics; cleanup of replaced secret is not deletion of the host.

## Resource limits

До1000 profiles, 64 live attempts/sessions total (one per profile), 64 command queue.
Limits give explicit RESOURCE_EXHAUSTED and do not evict existing profiles/secrets or
sessions. Secret buffers bounded as above. Retained receipts≤100000 unexpired records;
when full, new receipt-bearing mutation rejects before effect rather than weakening24h.
Limits are release defaults, not user-editable settings in these packages.

Public TrustChallenge additionally includes host,port,keyType for the exact observed
endpoint/key, so first-trust UI/MCP never needs to infer key type from authKind.


## Quarantine and cleanup recovery

ConnectionOwner owns in-memory endpoint quarantine and exact attempt/session handles
whose close is unconfirmed. Invalidate generation before requesting close. A cleanup
attempt waits at most5s (within runtime10s shutdown deadline); exception/deadline
retains those handles, never reports closed/success. Quarantined handles count toward
64 live-resource limit. State is failed, failureCode CLEANUP_REQUIRED; mutations
return that code, retryable:true, messageKey connection.cleanupRequired. Public reads
remain available. No new connect/auth or profile connection-affecting update/delete/
trust decision may pass for that endpoint while pending; trust observations/warnings
still persist before exposing an error, no credential mutation is partially committed.
Rename/non-effect reads and replay of already committed IDs do not perform network
work. Other endpoints remain usable.

Existing cancelConnection(attemptId)/disconnect(sessionId) accept the retained current
ID as a cleanup retry, including state failed; controller shows «Повторить отключение».
Retry closes only retained handles. Confirm closure via socket/client done, not just
return from close request; then clear quarantine and show disconnected/cancelled.
No automatic reconnect or replay of failed profile/trust mutation: user submits a
fresh version/challenge after cleanup. Repeated failure retains quarantine and same
retry. Restart removes memory handles/attempts and starts disconnected; native OS
process teardown closes its sockets, no quarantine persistence or auto-connect.

GrantOwner separately retains in-memory grant quarantine when affected channel close
is unconfirmed, deadline5s; no auth/frame/commit/output for that grant. Current
canonical revoke/version/epoch fencing remains effective even if physical close fails.
UI displays CLEANUP_REQUIRED with grant.cleanupRequired and «Повторить закрытие
каналов». Retry is cleanup-only, not another rotation. Revoke already durably committed
stays revoked; repeated revoke resumes cleanup without increasing version again.
Rotation already committed new version/secret keeps exportPending until closure and
export reconciliation complete; retry uses same canonical version/secret. While that
recovery is pending another rotation does not generate another secret/version.
After all exact old channel handles confirm closed, clear memory quarantine and
reconcile export before admission/configuration. Restart has no old handles and
reconciles canonical pending export; revoked grants remain denied. Other grants are
unaffected, except clock rollback intentionally fences all previous epochs. No new
MCP tool/admin action is introduced: grant recovery remains UI-only.


## Typed command kernel (T003)

AppOperations — типизированный публичный interface: Actor только UiActor/McpActor,
deleteProfile принимает именно UiActor. Ни generic-command, actor-from-JSON, raw DB
или произвольного Map результата нет. PublicValue — sealed набор DTO; metadata
(dataRevision/ownerEpoch) находится в envelope OperationResult согласно registry.
Ошибки используют enum code/field/reason и фиксированные message keys; raw exceptions
не копируются в ответ. Ephemeral password/key inputs не являются PublicValue,
не сериализуются, key bytes копируются/read-only и очищаются при dispose.

DomainCommandGate — общий concrete FIFO kernel,64 waiting slots plus active command,
без собственного persistent состояния. ActorAuthority удерживается composition root
и grant owner; identities привязаны к уникальному issuer object и ownerEpoch.
Router получает только уже проверенный McpActor/typed AppOperations, не issuer.
Внутренний OwnerActor не является публичным Actor: нужен только queue-командам
app-owned observations/liveness, не может передаваться в публичные UI/MCP operations
или UI delete. После успешного SSH auth session callbacks используют OwnerActor,
а pending attempts сохраняют исходный grant context. Revoke не рвёт общий SSH session.

OperationState читает canonical owners/store, не дублирует grants/entities в gate.
Async authorize(admission/response) задаёт durable auth/clock guard; sync
boolean isAuthorizedNow повторяет current grant/version/expiry/epoch/runtime проверку
непосредственно на границе эффекта. Реальная persistence/check implementation —
T006/T016/T025, не fake state из unit tests. Проверка ответа выполняется также для
ошибки body; права, потерянные после commit, не откатывают эффект и не выдают данные.
Контекст истекает сразу после body, ДО await response authorization.

Receipt lookup через context.read авторизован до чтения и не проверяет consumed
nonce/entity fence: committed replay возвращает только IDs/revisions. Новый эффект
идёт через context.linearize с актуальным VersionFence. Callback linearize имеет
синхронный PublicValue result, Future не подходит по типу. При записи вызывать
linearize ВНУТРИ фактической writeTxnSync до mutation/receipt, а не оборачивать
WorkspaceStore.write Future. Для SSH — непосредственно перед socket.write admission.
Captured profile/connection/credential/endpoint/trust/observation/generation проверяются
в этой синхронной границе. Rename/session fences могут опускать profileRevision;
consent обязан её включать. Quarantine блокирует новые connection effects, но не
публичные reads и exact cleanup retry; requiresUsableEndpoint=false разрешён лишь
для предусмотренных cleanup/non-connection operations.

Network/crypto/prompt и ожидание close acknowledgments выполняются вне command gate:
короткие fenced фазы invalidate→close outside→recheck/commit. Не сохранять context
через такое ожидание между submit-командами; передавать immutable VersionFence и
повторно проверять actor. Queue stop блокирует новые/queued/uncommitted effects,
drain ожидает активные/ожидающие команды; уже committed эффект не отменяется.
nextRevision проверяет JSON-safe ceiling перед изменением счётчика, без wrap.

Kernel не reentrant: facade делегирует конкретному owner, submit выполняется один
раз на фазу. OperationState проверяет canonical store внутри уже занятого gate,
не делает рекурсивный submit/await на том же kernel. Между фазами close/prompt
сначала завершается submit, затем выполняется ожидание вне gate и новое submit.
Synchronous authorization возвращает bool (false всегда deny) или typed failure;
Future/async-void implementation не подходит по типу для этой границы.

OperationState.running привязывается к RuntimeCoordinator.acceptsOperations, не к
видимости окна или факту включения MCP. dataRevision — из canonical AppSettings;
versions — из canonical Profile/Credential/EndpointTrust и текущих generation/
quarantine ConnectionOwner. Gate не хранит их копии. ActorAuthority.mcp не является
аутентификацией: выдаётся grant owner только после native peer+canonical secret
проверки, затем channel-owned context не принимается из request arguments.


## Internal split-phase preparation

DomainCommandGate.prepare<T> uses the same bounded queue and current admission/
response authorization as submit, but yields private owner intent with no JSON
projection. Intent is not an effect permit: CommandContext expires before response
authorization in either path. Outside-gate preparation is followed by a new submit;
current auth/receipt/fences are checked again inside actual write/socket admission.
Never retain a context for use after prepare returns. Nullable/void private intent
is allowed; public submit remains PublicValue-only. Preparation failure throws only
the fixed OperationFailure contract, and does not poison the queue.

DomainRepository is root/owner-only over the single WorkspaceStore. Consistent reads
reuse the active synchronous transaction when canonical auth/version checks occur
inside write; do not start nested Isar read transactions or use cached profile/grant
snapshots for current authorization. Unit fake snapshots model rollback only, not
native DB durability. ReceiptSigner is private key material, never PublicValue.


## Profile mutation payload and persistence binding (T006)

ProfileOperations is the typed profile subset of AppOperations; ProfileOwner
implements it. ProfileDraft preserves omitted port as null internally; validator
resolves22 for persistence. Receipt HMAC includes original profile/patch values,
profileId/expectedRevision for update, excludes lookup mutationId, includes method.
Omitted port and explicit22 remain distinct payloads. Name/host normalization occurs
after receipt lookup and never rewrites signed input. Input name is bounded1..100
Unicode scalars AFTER trim; schema raw name does not impose100 before trim, while
output remains100 and the transport frame still bounds raw input. Private key wire
base64 must use canonical standard alphabet/padding (roundtrip encode(decode)==input)
before typed PrivateKeyInput; no hidden normalization of a signed string. Passphrase
absence and empty supplied value remain distinct. UI uses original file bytes with
canonical base64 for the same internal identity; no local filename enters payload.

ReceiptBook validates printable ASCII mutationId1..128, namespaces MCP by canonical
clientId and UI by ui:<ownerEpoch>. Current auth precedes lookup; expiry<=now permits
new mutation, expired records prune within transaction. Lookup replay returns IDs/
commit profile revision only without validation against current entity or socket
resumption. The final actual write repeats lookup before fences, so concurrent
same requests have one effect. Receipt insertion, profile/credential/refcounts and
data/list revisions commit or roll back together; limits1000profiles/100000unexpired
receipts reject without partial writes. Indexed expiresAt count/prune avoids loading
all retained records per mutation. Startup/hourly retention cleanup is still T016.

Create starts revisions1 and empty trust for a new normalized endpoint. Successful
nonempty patch increments profileRevision once; connectionRevision advances only if
normalized endpoint/username changes or authentication is explicitly replaced. Raw
host spelling/name changes alone do not close SSH. New credential import gets a new
UUID/purpose and secretRevision+1; old credential removed atomically. A same-value
patch still records the explicit save and profile/list revision, without unnecessary
connection invalidation. Moving endpoint adjusts both refcounts, never copies trust;
last profile deletion removes accepted key/warning with profile and credential. UI
delete returns the last deleted profile revision, has no MCP receipt/addressability.

Connection-affecting update/delete first requires a usable endpoint, then asks the
canonical connection port to invalidate under the shared gate and close outside it.
Only confirmed closure yields a fresh VersionFence; final commit rechecks it/current
authority. Failure leaves original records and endpoint quarantine. Rename is allowed
through quarantine. Production binds real ConnectionOwner atT010, never a permissive
placeholder. ProfileOwner is a RuntimeCapability: stop admission, cancel preparation,
drain in-flight operations; protected temporary bytes and input clear in finally.
No automatic retry of a failed effect; client submits current versions after recovery.

CanonicalOperationState reads current profile/credential/trust directly through
DomainRepository plus required ConnectionVersionState and CanonicalGrantAuthorization
ports. Missing/inconsistent canonical records fail closed. No cached grant snapshot
or default permissive authorizer exists; GrantOwner implements durable clock and grant
checks inT016/T025, UI/Owner callbacks do not depend on an initiating MCP grant.
loadReceiptSigner unprotects the existing32byte store key once before domain admission
with receipt-hmac.v1, clears owned buffers and refuses failure/invalid length without
regeneration. Composition root owns signer disposal after accepted work drains;
startup/UI wiring remainsT007/T020, not claimed by the isolated owner implementation.


ProfileConnectionPort.closeForMutation receives an optional synchronous findReplay
callback for receipt-bearing update. ConnectionOwner invokes it INSIDE its current
authorized common-gate phase before expected revision/generation/quarantine checks
and before invalidation/handle capture/close admission. Matching receipt yields
ProfileCloseOutcome.replayed immediately with no new socket work. After a close
already admitted before another commit, the post-close gate checks receipt again
before stale/deleted-entity fences and may return the same replay. Otherwise it
returns ProfileCloseOutcome.closed only on confirmed exact-handle closure and a
fresh fence. A lookup outside this gate phase cannot replace the callback: another
request can commit between that lookup and close admission. UI delete has no callback.
Preparation/close exceptions also trigger current authorized receipt resolution
before reporting the error, so a late failed duplicate does not mask an already
committed result. No receipt means the original fixed failure; revoked/expired actor
still cannot read a replay. ConnectionOwnerT010 must implement this port ordering.


## Connection owner control and lifecycle denial latch (T010)

ConnectionOwner provides the five typed ConnectionOperations, ProfileConnectionPort
and RuntimeCapability; it uses the same DomainCommandGate/CanonicalOperationState
as profiles and trust. Product connect/cancel/disconnect/passphrase/mutation-close
phases authorize in that gate. Initial native dial starts inside actual linearize
with slot reservation; DPAPI await/parse/native readiness/SSH/close wait run outside.
Every actual byte write reacquires the gate with current entry actor and checks its
current connection/credential/endpoint/trust/observation/generation fence immediately
inside linearize. On guarded promotion, tryComplete must succeed; actor switches
from initiating Ui/Mcp to OwnerActor, session ID is new, watchdog starts. Void private
write completion may migrate to OwnerActor if the initiating actor became irrelevant
after promotion; it never repeats an already sent packet or discloses an MCP result.

Private runtime-owned timeout/liveness/terminal/stop signals synchronously latch
cancelled and invalidate the generation BEFORE requesting physical close, even when
another gate command awaits persistence. This latch can only deny/close/invalidate;
it cannot authorize a connection, persist data or issue consent. All pending product
transactions/writes check current versions/latch at their actual effect. Visible
resource status and quarantine also follow exact handle completion; ordinary caller
commands still authorize under the FIFO gate. This prevents an indefinitely busy
gate from delaying the30s network deadline. Generation overflow never wraps: denial
still latches and resources close; further attempts return RESOURCE_EXHAUSTED.

Cleanup cancels known dial/client immediately, including while unprotect is pending,
then drains preparation and any precise handles constructed before cancellation.
It never awaits its own auth pipeline. Same pending close Future is reused; only a
failed completed close is retried explicitly. Its5s observer does not abandon that
Future. Late confirmed completion releases the original slot/quarantine without
starting a connection. If closure is uncertain, all live resources of that endpoint
are denied/closed and retained; other endpoints remain usable. Every profile of the
quarantined endpoint projects CLEANUP_REQUIRED, including already closed or never
connected profiles. Explicit retained-ID cleanup retry can retarget to cancelled/
disconnected and invalidate any remaining consent, with no generation/secret renewal.
Quarantine clears only after all retained exact handles confirm closure.

ConnectionProof is an internal opaque owner binding, never JSON/actor issuance.
Real TrustOwner must use the same authorized context, validate current full consent
revisions/nonce, persist accepted/warning/receipt data, then call guarded owner
controls. Owner refuses allowAuthentication unless canonical accepted key bytes,
type and fingerprint match the verified observation. HostObservation's verified-blob
data factory grants no authority and does not replace cryptographic verification:
Strict verifies proof first; unit transports can construct synthetic projections.
A mismatch invalidates endpoint resources and then binds a fresh terminal proof for
replacement; cleanup failure cancels old consent and requires fresh verification.
Matching accepted A with warning B may authenticate and expose a separately expiring
retain challenge; it must not pause the network budget. These policy decisions and
real challenge persistence remain T013, not the fake policy used in owner units.

GrantOwner calls cancelPendingClient after durable revocation/expiry/clock changes.
It must not await resource acknowledgments inside an authorization/transaction gate
phase; immediate denial may initiate the cleanup Future and the owning lifecycle
tracks/drains it outside. Established OwnerActor sessions are not selected. Runtime
stop/cleanup works after global product admission is false and drains owned work
before canonical store closes. Connected projections additionally check the live
transport flag, so delayed terminal notification cannot keep a closed session live.


**T040 terminal and canonical binding:** pending authentication failure projects
failed with its reason; loss of an established session projects disconnected with
its reason (including ended/watchdog cleanup completion). Unconfirmed cleanup still
overrides either with failed/CLEANUP_REQUIRED. A retained terminal entry is not a
canonical endpoint cache: projection compares current endpoint, connection revision
and credential revision, and drops obsolete attempt/session IDs after a semantic
profile change. Current canonical endpoint alone determines quarantine. Old IDs
cannot retry cleanup of unrelated old endpoint after profile move; return CONFLICT.
Rename preserves the binding and live session. Exact live handles are never evicted
by projection/pruning; confirmed terminal bindings for deleted/moved profiles may be
pruned at next guarded connect admission to bound metadata history.


## Final owner graph and trust mutation result binding

`FeatureRuntime` constructs the real ProfileOwner, ConnectionOwner, TrustOwner,
GrantOwner, common CanonicalOperationState/DomainCommandGate and OwnedAppOperations
before runtime admission. Shared parsing, host verification and signing pools are
root capabilities. UI controllers and the MCP router receive typed operations, not
repository handles. Native MCP failure disables MCP and exposes retry in settings;
it does not replace trust policy or grant authorization with permissive defaults.

Trust mutations return entityId equal to the addressed profile UUID and revision
equal to the committed endpoint trustRevision. The actual trust record remains
endpoint-scoped and updates all referring profiles; entityId does not create a
second profile-scoped trust model. This keeps the MutationValue/receipt UUID contract.
Canonical receipt replay precedes nonce, revision and cleanup checks and performs
no additional network/authentication effect.

MCP CancelledNotification attenuates only its authenticated request actor with a
private cancellation predicate. The common gate checks it again at actual effect
admission. It cannot issue identity or roll back a committed mutation. EOF does not
implicitly cancel an admitted domain operation. Receipt cleanup is scheduled hourly
and at startup; shutdown cancels scheduling and drains any already owned write.

UI key selection reads the original bounded file bytes via the native picker; no
path or passphrase is saved as a credential. Cancelling an attempt passphrase or
first-trust confirmation explicitly cancels that attempt. C03 secret controls deny
copy/cut through keyboard and selection menus even while revealed; paste remains
available. This is functional privacy behavior, not a feature-screen design gate.
