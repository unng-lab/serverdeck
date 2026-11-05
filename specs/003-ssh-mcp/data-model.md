# Data model — format2

Расширяет [storage002](../002-desktop-runtime/contracts/storage.md). Все domain записи
в одной Isar. AppSettings.logicalFormat=2; opens только полный schema set:
AppSettings, Profile, Credential, EndpointTrust, McpGrant, MutationReceipt, SecurityState.
UUID lowercase v4; revisions int64≥1; times UTC ms; byte arrays задают явные bounds.

| Entity | Поля / индексы / инварианты |
| --- | --- |
| Profile | internal IsarId; profileId unique UUID; profileRevision; connectionRevision; displayName≤100; normalizedHost; originalHost; port1..65535; username≤255; authKind=password/privateKey; credentialId; endpointId; createdAt; updatedAt |
| Credential | credentialId unique UUID; profileId unique; kind; protectedBytes DPAPI≤2MiB; publicKeyType?; publicKeyBits?; secretRevision; не отдаётся projection |
| EndpointTrust | endpointId unique; normalizedHost/port unique pair; trustRevision; observationRevision; acceptedKeyBytes?≤16KiB; acceptedType?; acceptedFingerprint?; acceptedAt?; changed bool; observedKeyBytes?; observedFingerprint?; detectedAt?; profileRefCount |
| McpGrant | clientId unique UUID; name1..100; grantVersion; authorizationEpoch; protectedSecret32; createdAt; expiresAt=createdAt+90days; revokedAt?; ownerUserSid; exportPending bool; no per-tool allowlist (все SSH tools без delete) |
| MutationReceipt | unique(clientId,mutationId); method; payloadHmac32; createdAt; expiresAt=+24h; resultCode; entityIds/revisions only; no plaintext payload/profile secret |
| SecurityState (id1) | DPAPI-protected receiptHmacKey32; authorizationEpoch>=1; lastAuthorizationUtc; minimumClockUtc; lastClockRollbackAt?; ownerEpoch ephemeral reference excluded from durability |

Isar indexes case-sensitive UUIDs after canonical validation. EndpointId — SHA256
UTF-8 canonical JSON `[normalizedHost,port]`, host not DNS-resolved. IP parsed canonical;
DNS input — ASCII labels (для international DNS пользователь вводит punycode),
lowercase and one trailing dot removed.
One outer bracket pair is removed only for a valid IPv6 literal (FR-308);
IPv6 zone identifiers, embedded ports, nested/unbalanced brackets and URI syntax reject. Unicode lengths for name
and username count scalar values; name alone trims outer whitespace. Username has
no whitespace/control/format characters. Ill-formed UTF-16 strings reject before
UTF-8 conversion, including password/passphrase (no replacement normalization).
Do not coalesce DNS aliases/IP. Unknown host record acceptedKey=null. Refcount is
transactionally maintained when profiles move endpoints/delete; zero refs deletes
trust/warning. Removing last profile never affects unrelated endpoints.

## Domain revisions

ProfileRevision увеличивается при любом изменении; connectionRevision — только
host/port/user/credentials. Credential revision отдельно для fenced callbacks.
TrustRevision увеличивается при принятии/замене/retain решения. ObservationRevision
увеличивается при любом новом отличающемся ключе, включая C после B; повтор B только
обновляет lastSeen без инвалидирования того же challenge. Warning survives matching A.
Смена endpoint при update удаляет старую запись только при refcount=0 и не переносит доверие.

## Atomic writes

Create: validated protected credential + profile + refcount + receipt одной txn.
Update: version check, close/invalidate relevant attempt, new protected credential,
profile revision/refcount update, старый credential удалить, receipt одной txn.
Delete UI-only: invalidate/close, profile+credential+refcount/last trust delete одной txn.
Trust decisions: exact captured revision/observation/key check, accepted/warning updates
и receipt одной txn; socket effects fenced тем же domain generation.
Grant rotate/revoke: canonical new version/state в txn, native closes old channels;
protected export reconciliation ниже. Ошибка закрытия deny-all на затронутом endpoint/grant.

## Attempt/session (только память)

Attempt: attemptId, profileId, captured revisions, endpointId, ownerEpoch, grant context,
state={connecting,needTrust,needPassphrase,authenticating,connected,failed,cancelled},
networkRemainingMs≤30000, promptExpiresAt≤5min, socket/client handles, failure code.
Session содержит endpoint/profile/connection fences и ping state; после успешной
аутентификации принадлежит приложению, не сохраняет grant authority initiating actor.
Revoke/expiry/clock epoch отменяют pending attempts, но не рвут уже общий SSH-сеанс. Connected projection только при живом
аутентифицированном socket; после restart все attempts/sessions отсутствуют.

TrustChallenge: nonce UUID, attemptId, endpointId, profileRevision, trustRevision,
observationRevision, exact offered key bytes/type/fingerprint, kind=first/replace/retain,
expiresAt, consumed bool. Не persist. Нет consent из старого запуска/другой revision.
PassphraseChallenge: nonce+attemptId+credentialRevision+deadline; bytes не persist.

## Grant export (производное состояние)

`mcp/clients/<uuid>.grant` содержит JSON{version:1,clientId,grantVersion,protectedSecret}.
Native atomic write, file+parent DACL CurrentUser; DPAPI CurrentUser. Canonical secret
в Isar. Create/rotate ставит exportPending=true и блокирует admission grant; записать
blob из canonical, затем txn clear exportPending. До этого UI не выдаёт конфигурацию.
После crash main reconciles pending exports до grant admission; stale blob не проходит
canonical secret/version check. Revoke сначала durable canonical revoked/version++,
потом закрытие каналов/удаление blob best effort; остаток blob не возвращает доступ.

## Bounded retention

Receipts expire24h; cleanup hourly и на startup, транзакционно, не влияет на profile IDs.
MutationId1..128 ASCII; одно и то же id+client+method+canonicalpayload даёт прежний
result IDs/revisions; разное содержимое CONFLICT. Digest — HMAC-SHA256 с защищённым
store key, не plaintext password hash. Canonical JSON: объект keys ordinal sorted,
arrays preserve order, no floating numbers, exact string values без trim/NFC секретов.
UI deletion removes any cached profile projection; receipt содержит только ID и
commit revision, replay не восстанавливает сущность. После24h ключ повтора может быть
переиспользован; client обязан читать актуальное состояние, не считать это exactly-once forever.


## Clock rollback epochs

SecurityState.authorizationEpoch starts1 and increases monotonically on detected
rollback; McpGrant.authorizationEpoch captured on create/rotate. Both are canonical
and durable. Epoch mismatch always denies admission/replay/commit/output, regardless
of corrected current time or remaining90days. No automatic epoch migration of grants.
minimumClockUtc is durable high-water within current epoch; lastAuthorizationUtc
records last successful guarded check. Before any MCP auth/admission/commit/output,
and before UI grant create/rotate, the serialized gate samples UTC. If now>=floor,
update floor=max(floor,now) and lastAuthorizationUtc before allowing check. Equal time
is valid. If now<floor, one transaction increments epoch, records lastClockRollbackAt,
and sets new epoch floor/lastAuthorizationUtc=now; all older grant epochs stay old.
After commit cancel their pending attempts and close old MCP channels; already
established app-owned SSH sessions remain. Failed transaction denies all MCP in
memory until successful guard persistence; no permissive fallback/new secret export.
After restart durable floor/epoch are checked again before any grant is admitted.

UI rotation of A commits new secret/version/current epoch and expiresAt=now+90days;
B stays in old epoch and denied even after clock catches up/restart. Grant creation
can issue current epoch, never makes old clients current. ACCESS_REVOKED with
messageKey grant.clockRollbackRequiresRotation identifies old epoch; UI shows reason
and rotate/revoke actions. Integer/epoch overflow or unreadable SecurityState gives
STORAGE_UNAVAILABLE, not reset. A repeated rollback creates a further epoch, not
multiple increments for requests at the same already-recorded floor.


## Current format2 initialization

Текущий manifest/appsettings используют толькоlogicalFormat2. Format1 и его copy/publication migration не поддерживаются. Fresh store создаёт receipt HMAC key; существующий current store читается без app-version adapters/backfill. Неизвестный формат отклоняется до DB open без подмены пустым состоянием.


## Текущие private credentials и модальная сессия
Credential.publicKeyBytes — nullable byteList толькодляpassword; privateKey требует canonical SSH public bytes≤262144, type/bits соответствуют им. Worker import даёт metadata одновременно с proof, DPAPI защищает original file bytes. Нет чтения старых записей через envelope fallback. Constructor/API текущие, без aliases.
ProfileSaveOutcome(profileId,requiresConnection) содержит только публичную identity save. DetailsSession хранит profileId/controller/navigationgeneration, onepromptledger≤64 и route refs только пока смонтирован. VerificationLease хранит controller/profile/admittedview/closed/cancel latch безroute refs, отменяет late pending admission exactly once через backendfences. Новая navigation/controller инвалидирует старый post-save intent.


## Server workspace (runtime only)
ProfileController.connections: immutable Map<profileId,ConnectionView>, successful
current public reads only. Missing entry means unknown. Workspace selection uses
existing selected/details with selection fence, current section enum PO/logs/jobs/
settings and navigation generation. No navigation persistence or schema change.
Global MCP route owns temporary activation flag; no server credential data in it.
Workspace lease replaces details-modal lease ownership, retaining exact-attempt cleanup.


OwnedSettingsRoute is runtime-only: exact DialogRoute/NavigatorState, retired latch,
open state. Retired route cannot be reused; RuntimeView replaces the session on owner
retirement. Prompt route handles are captured while mounted, not derived during
workspace disposal. No new persisted record or compatibility branch.

The format2 schema adds MonitoringHistoryRecord(profileId unique,connectionRevision,payload) defined by [004](../004-server-monitoring/data-model.md#history). Unsupported versions are rejected before DB open without modification.
