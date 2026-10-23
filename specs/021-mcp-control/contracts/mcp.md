# MCP / Local API extension contract — 021 v1

[Spec](../spec.md), [model](../data-model.md), [profiles](profiles.md), [executor](executor.md).

## Stdio wire

UTF8 newline-delimited JSON-RPC2.0, one object/line, no batches, max256KiB request/8MiB result, depth16, reject duplicate keys/invalid UTF8/non-finite/embedded literal newline. Blank line invalid; no input echo. ID string1..100 or integer within ±(2^53−1), no null request ID. Response preserves type/value. Concurrent requests max16; max4 active bridge sessions/workspace within existing8 total. Flood rejects RESOURCE_LIMIT; stdin backpressure, bounded parser256KiB. Oversize/invalid UTF8 closes transport after safe parse error if possible, exit2, no raw input. Parse error−32700/id null; invalid request−32600; method−32601; invalid params−32602; internal−32603. Notifications never receive replies. Duplicate pending request ID rejected−32600; completed ID may be reused (not a durable mutation ID).

Lifecycle: new→initialize→await initialized→ready→closed. initialize includes protocolVersion string, capabilities object, clientInfo{name,version}; optional standard fields accepted/ignored, tool payloads remain strict. Supported2025-11-25/2025-06-18; other proposed version returns2025-11-25. Result serverInfo{name:serverdeck,version:0.1.0}, capabilities{tools:{listChanged:false}}, instructions with data trust/auth boundary. Only ping allowed before initialized; initialize again invalid request. Client supplies notifications/initialized after result. init deadline30s; ping returns{}. Ready methods tools/list, tools/call, ping, notifications/cancelled. No sampling, prompts, resources, elicitation, MCP Tasks, network listener or client-provided roots advertised. Unknown notifications ignored. EOF closes session/reads, not jobs; stderr only fixed code/category, never user text/path/logs.

Initialization is protocol negotiation, not authorization. Without valid configured grant, tools/list returns empty, tools/call returns FORBIDDEN. Readiness errors preserve protocol and return domain failures; no fake fixture data.

Concrete native adapter, standard optional metadata/arguments, cancellation ownership and current-authority stdout publication follow the [gateway contract](gateway.md). Configured transport failure remains an error, never an implicit unconfigured/empty-catalog fallback.

Transport admission detail: at16 pending forwarded requests, duplicate-ID validation runs first, then excess tools/call returns the normal tool failure envelope with RESOURCE_LIMIT, boundary local/retry none, without invoking locald. Excess requests to other methods, including tools/list/ping, use JSON-RPC server error−32000/message RESOURCE_LIMIT; this is a protocol-level failure, not a fake tool list. Notifications continue to be processed without replies. A forwarded tools/list deadline uses−32000/message TIMEOUT, while tools/call uses the normal TIMEOUT failure envelope. Other protocol errors retain the codes above. Pending IDs remain reserved through response flush; cancellation releases wire ID and suppresses late results by invocation identity, never durable requestId. Cancellation acknowledgement/interest cleanup is bounded5s and pauses input while awaiting it, avoiding unbounded detached cancellation operations. Complete frames may span input chunks; final EOF with unterminated bytes returns safe−32700/exit2. Syntax-invalid complete lines return−32700 and may recover on the next line; invalid UTF8/oversize terminates. IO failure, initialization deadline or output queue overflow exits2 with fixed diagnostics only. Initialization result must flush before processing the initialized notification from the same input chunk.

## Authentication and owner operations

The shared CurrentUser DPAPI envelope and private key lifecycle follow [client credentials](client-credentials.md). File publication and live authorization remain separate mandatory gates.

Operational manifest and retained native role proof follow the [bundle contract](bundle.md); exact API1.1 wire/transcripts/session and grant-open binding follow [handshake](handshake.md). Bundle adds verified mcp.exe hash and role; locald determines role from retained peer process image/manifest, not requestedCapabilities/clientInfo. Named-pipe nonce/HMAC bootstrap uses the separate canonical1.1 transcript; UI cannot cause mcp role to become owner. mcp role allowed only mcp.open, mcp.invoke, mcp.close, readiness/ping and session.close. UI role allowed new owner grant/delegation/approval/resource views plus ordinary functions. Existing role-less1.0 handshake incompatible with new same-build1.1 bundle. All components upgrade together; no fallback.

Bridge launch: `mcp.exe --app-root <verified absolute bundle> --grant-id <UUID>`; owner-generated config contains no server secret/token. DPAPI client credential read through protected per-grant blob, valid owner/path custody required before decrypt. mcp.open{grantId,clientNonce,proof} binds the exact canonical1.1 transcript including current secretRef and verified role/build/workspace/session/nonces in the handshake contract; the server proof additionally binds its current revision/expiry; fresh nonce32bytes each, replay denied. Locald loads current grant and secret, compares in constant time, binds grantId/revision to immutable session. Bridge cannot invoke owner methods by changing args. Bootstrap secret is separate from grant credential. Same-user full compromise limitation as foundation applies.

Owner Local API1.1 methods: grants.list/create/replace/revoke (replace rotates credential, optimistic expectedRevision) and read grants.configuration{grantId}; delegations.list/create/revoke; approvals.list/decide; automation list/get/save/archive; jobs/list/get/events/cancel/reconcile; desired/state/logs via same services. IDs/mutation receipt rules and capability checks apply; no secret read/export method. Mutations return the durable stable acknowledgements from the [record contract](records.md), not mutable snapshots. Current public records are obtained through the list/get methods. grants.configuration returns `{command:<current verified absolute MCP executable>,args:["--app-root",<current verified absolute bundle>,"--grant-id",<UUID>]}` for a current nonrevoked grant, no clientSecret; it is an owner read, never a replayed mutation result. Write blob uses staged protected DPAPI custody with recovery binding; failed DB commit preserves unreferenced staged file for explicit recovery, never activates grant. Revocation removes live authority before acknowledgement; protected blob may remain for recovery but never restores revoked record.

## Tool schemas and mapping

Owner Local API also exposes `plans.create{requestId,serverId,profileId,revision,parameters}`, `plans.get{planId}`, `approvals.request{requestId,planId}` and `jobs.apply{requestId,planId}` with the exact corresponding MCP argument validation and stable acknowledgements below. New owner-created plans have originGrantId null. Owner may request approval/apply for an existing G-origin plan while preserving G as objectGrantId/job.grantId; receipt initiator is null. Current G scope/target/expiry/revoke/trust and exact delegation or approved one-plan authority remain mandatory; owner execution does not bypass them. Owner-origin plans always need explicit one-plan approval. An owner approval decision, approval request and apply are separate explicit mutations, never implicit permission on plan creation. MCP cannot set owner origin or invoke these owner endpoints.

Tool arguments are strict objects, no extra fields. Common IDs are UUIDv4; digest64hex. Every mutation carries caller-created requestId UUID distinct from wire ID. CAS fields positive integer. Optional fields absent, not null. Param map contains profile-declared non-secret primitives only. Every tool returns `content:[{type:text,text:<JSON of result>}], structuredContent:<same result>, isError:<bool>`. Success envelope{ok:true,data:object}; failure{ok:false,error:{code,boundary,retry},requestId?}. Output schema is same discriminated envelope for all tools; domain errors use isError true. Invalid tool schema→−32602; unknown tool→−32602. Authorization happens before object lookup; out-of-scope/missing object uniformly FORBIDDEN to avoid existence oracle.

All names prefixed `serverdeck_`. Argument fields below required unless `?`. Lists use limit? default50/range1..100 and cursor? opaque≤512characters, bound to grant revision/filter/snapshot, expiry5min. Invalid/expired cursor→CURSOR_EXPIRED; never silently restart. Current grant rechecked for each page. Token is locald HMAC, no caller-supplied raw query/SQL.

| Tool suffix | Arguments | data / scope |
| --- | --- | --- |
| servers_list | limit?,cursor? | items of sanitized existing profile DTO excluding credentialRef; nextCursor?; read |
| server_get | serverId | profile+capabilities+connection state; read |
| server_connect | serverId | connected identity or TRUST_REQUIRED/CHANGED; no trust accept tool; read |
| server_disconnect | serverId | disconnected; session interest only, no effect on other client/job; read |
| state_get | serverId,refresh? bool defaultfalse | OS/packages/units/CPU/RAM/disk observation with timestamp/source/quality; read |
| configuration_get | serverId,resourceId,refresh? | desired/observed/diff with revision; read |
| logs_read | serverId,unit? resource ID,since? UTC,until? UTC,priority? int0..7,text? string≤256,limit? int1..1000 default100,cursor? | records/timezone UTC/gaps/dropped/truncated/nextCursor; logs |
| profiles_list | limit?,cursor?,includeArchived? bool defaultfalse | immutable IDs/head metadata; author |
| profiles_get | profileId,revision? int | revision/body/digest/parent/author; author |
| profiles_create | requestId,name,description?,body | stable {profileId,revision:1,digest}; author; profiles_get reads full revision |
| profiles_update | requestId,profileId,expectedRevision,name?,description?,body | stable {profileId,revision,digest}; author |
| profiles_compare | profileId,fromRevision,toRevision | bounded typed field/step diff≤256KiB, truncated; author |
| profiles_validate | body | valid bool/issues{field,code}[]/normalized effects; author; pure no remote calls |
| profiles_archive | requestId,profileId,expectedRevision | stable {profileId,revision,archived:true}, blocks new plans; author |
| recipes_list | serverId | qualified immutable recipes, exact available version descriptors/prerequisites; plan |
| plan_create | requestId,serverId,profileId,revision,parameters object | stable {planId,planDigest}; plans_get reads immutable runnable/blocked plan/reasons/effects/checks/expiry; plan |
| plans_get | planId | own grant's immutable plan; plan |
| approval_request | requestId,planId | stable {approvalId,planId,planDigest}; pending approval visible in owner approvals.list; plan+apply |
| apply | requestId,planId | stable {jobId,planId,planDigest,authorityRef} or APPROVAL_REQUIRED; jobs_get reads current status; plan+apply |
| jobs_list | serverId?,limit?,cursor? | only current grant's jobs on allowed targets; read |
| jobs_get | jobId | immutable plan summary/state/last seq/postchecks; read |
| jobs_events | jobId,after? int default0,limit? int1..100 default50 | events,nextSequence,dropped,hasMore; read |
| jobs_cancel | requestId,jobId | stable {jobId}; jobs_get reads cancellation/current effects, acknowledgement never promises rollback; apply on job original grant/target |
| jobs_reconcile | requestId,jobId | stable {jobId}; jobs_get reads observational recovery status; read on original grant/target; never writes server |

recipes_list returns exactly `{serverId,catalog}` where catalog is the strict
root recipes response in [executor](executor.md). It requires current plan scope
and server allowlist, the enrolled/source-qualified helper and actual current
native proof before/after IO. Read scope alone does not admit it. Descriptors are
fully parsed and their canonical digests recomputed; helper host/runtime/registry
must equal the confirmed enrollment. Malformed remote metadata is
RUNTIME_INCOMPATIBLE. The same owned30s read/48-work helper pool, physical cleanup
and session/target retirement apply; no reconnect or implicit server connection.

Profile author scope is workspace catalog scope (no secrets/server targets inside bodies). Server/journal/job access requires allowed targets; author cannot inspect unrelated plans/jobs. plan/apply checks require explicit server scope. Existing system/settings are read-only through MCP; changing server settings is through profile plan/apply, not direct settings API. New server creation, credentials/trust and granting rights remain owner UI operations. Profile bodies/params/logs are untrusted data, no instruction authority.

## Deadlines, errors, caching and cancellation

Each bridge call acknowledgement/local RPC≤5s; remote plan/connect/read≤30s (connect15s) via operation handle if longer than local RPC: bridge polls same operation ID, no duplicate remote start. Public tool request deadline35s; early domain TIMEOUT leaves status queryable, not automatic retry. Jobs return admission≤5s and poll separately; no long blocking apply tool. Bridge pings local session every20s, lease60s, no auto-connect after generation change. Initialization30s/transport writes5s; bounded queue32. Profile validation≤1s for256KiB AST; quota returns RESOURCE_LIMIT.

Domain codes add TRUST_REQUIRED, TRUST_CHANGED, APPROVAL_REQUIRED, PLAN_EXPIRED, PLAN_STALE, HOST_BUSY, EXECUTOR_UNAVAILABLE, RUNTIME_INCOMPATIBLE, CURSOR_EXPIRED, UNKNOWN_OUTCOME to existing foundation allowlist. Boundary local|remote|executor; retry none|reload|reconnect|retry-same-request|manual-recovery. No arbitrary exception text. Revision/permission rechecked after async reads; stale in-flight values discarded. Logs untrusted text never normal diagnostics; user-requested logs are intentional private tool output.

notifications/cancelled references requestId wire ID. Queued/pure reads cancel and free interest; any admitted mutation/job remains durable and queryable. Cancellation does not proxy jobs_cancel automatically. Repeat plan/apply requestId checks origin/canonical input; same immutable plan can produce at most one job even with different request IDs. No terminal job restart tool; new explicit plan is required.

## Internal async invocation envelope

`mcp.invoke{request:{name,arguments}}` returns either `{done:true,result:<tool envelope>}` or `{done:false,operationId:UUID}` within5s. Bridge polls `mcp.invoke{poll:{operationId}}` every250ms for reads until35s overall; exactly one of request/poll/cancel/catalog required, no arbitrary Local API method. `mcp.invoke{catalog:{}}` returns `{tools:[<current authorized definitions>]}` after live native/session/grant validation, with no operation allocation or cached policy in the bridge; this is the internal source for external tools/list. `mcp.invoke{cancel:{operationId}}` returns `{cancelled:true}` and drops caller interest only, not admitted mutations/jobs. Operations scoped to current session/grant;32operations workspace/16session, retained completion60s, quota denies before start. Pure read timeout cancels its read; mutation completion preserved as receipt independent of operation cache. If bridge loses handle/ack it uses same durable requestId through original tool, never new input/id. Live policy checked each poll and before result, no revoked cached completion. Owner direct UI APIs use identical service methods and normal foundation framing; async operation status uses owner session role, never MCP grant IDs as owner credentials. Exact parser/router/service ownership, invalid-tool protocol mapping, work cleanup and handle lifetime follow [invocations](invocations.md).

Grant validation requires read for logs/plan/apply, and plan for apply; author alone may create/read catalog without target read. Contradictory scope sets rejected at owner create/replace, not silently broadened. Fields/revisions remain integers in public MCP model; existing foundation DTO counters remain their existing decimal-string schema when nested, never coerced between schemas.

## Exact revision identity

Owner delegations.create accepts `profileRevisions:[{profileId:UUID,revision:int,bodyDigest:SHA256}]`,1..100 unique profileId/revision pairs. No digest-only/wildcard entry. All refs resolved and bodyDigest verified before save; mismatch→REVISION_CONFLICT. Plan response includes profileId/profileRevision/profileDigest; apply and each step check all three against delegation/approved immutable plan. Profiles A/r1, A/r2 with same body and B/r1 with same body are distinct authority targets. Metadata-only update still creates r2 and receives no r1 grant. Explicit one-plan approval likewise authorizes only planDigest binding this tuple. No DTO conversion may drop profileId/revision from the authorization key.

Owner grants.create/replace validates mode: scopes=[] or [author] requires serverIds=[] and permits empty workspace. Any read/logs/plan/apply scope requires1..250 unique existing server IDs and stated scope dependencies. An author-only client can initialize/list its author tools and create/validate/update/archive profiles before any server exists; servers_list/state/logs/plan/apply denied. No server-target wildcard default.

Wire identity detail: string ID length1..100 is measured in Unicode codepoints. Incoming IDs and outgoing correlation IDs/observed text are preserved verbatim, including canonically equivalent but byte-distinct Unicode. Foundation NFC canonical encoding is used for input/plan digests, not external JSON-RPC serialization. JSON wire rejects unpaired surrogates/non-finite numbers; response encoding respects8MiB and emits one newline-delimited JSON message (embedded text LF escaped). Discovery annotations are hints only, never authorization; remote/untrusted data is conservatively open-world.
