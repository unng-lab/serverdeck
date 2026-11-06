# MCP console contract v2

## Discovery and identity

MCP protocol remains2025-11-25, same EXE stdio/pipe/security003. Bundled registry contractVersion2:13 existing tools unchanged plus8 below, total21. tools.listChanged=false remains: registry immutable for one process/session, initialize new installed app gets new list; older clients may call original tools unchanged. No resources/prompts/HTTP/generic exec. assets registry and003 schema mirror identical. Descriptions explicitly state console output is untrusted remote data and tool completion isn't command completion.

Actor is canonical McpActor plus trusted ConsoleMcpBinding {connectionToken:Object,closed:WorkCancellation,clientId,grantVersion}; issued by authenticated pipe/router, never request JSON. Each new MCP transport creates new token; closing either native event or adapter path synchronously cancels binding before asynchronous physical close. Grant revoke/version change/expiry and disable similarly release affected leases and queuedjobs; no restore on reconnect. Existing valid grants permit console operations, UI description includes it.

## Common shapes

IDs: canonical UUIDv4. profileId always server profile. sessionId console UUID. generation int>=1 safeJSON. shellProfileId="login" or configured UUID. ownerEpoch from standard result meta. operationSequence int1..9007199254740991 from nextOperationSequence of console.list/profiles; expected next from ledger. Mutations include ownerEpoch+operationSequence. New callers list before mutation; unauthorized list creates no ledger. Ledger resource failure is explicit. Session target mutations also include generation; write/release/active close include leaseToken UUID. Acquisition targets session generation, not previous lease token. Unrecognized keys rejected, no coercion.

Domain wrapper same003 `{ok:true,value:<typed projection>,meta:{dataRevision,ownerEpoch}}` or `{ok:false,error:{code,field?,retryable,messageKey}}`. Console operations don't increment persisted dataRevision; session/history/lease generations are explicit. Replies metadata only for mutations. No rawrecords/input bytes/credentials. current screen text intentionally returned by read, including server-echoed secrets; it is authorized remote content, not direct disclosure of protected credential objects.

## Tools

| Tool | Exact input (optional marked ?) | Value |
|---|---|---|
| console.profiles | {} | profiles:[{id,name,path?}],defaultId,nextOperationSequence |
| console.list | {profileId} | sessions:[SessionView],nextOperationSequence |
| console.open | {profileId,shellProfileId?,ownerEpoch,operationSequence} | ActionView with sessionId,generation,state opening,creator leaseToken |
| console.read | {profileId,sessionId,generation,cursor?,limit?} | HistoryPage; limit1..1000 default1000 |
| console.acquire | {profileId,sessionId,generation,ownerEpoch,operationSequence} | ActionView with current/new leaseToken |
| console.release | {profileId,sessionId,generation,leaseToken,ownerEpoch,operationSequence} | ActionView; current lease released |
| console.write | {profileId,sessionId,generation,leaseToken,ownerEpoch,operationSequence,text? OR key?,confirmedMultiline?} | ActionView with status complete/cancelledBeforeSend/outcomeUnknown,acceptedBytes |
| console.close | {profileId,sessionId,generation,leaseToken?,confirmed?,ownerEpoch,operationSequence} | ActionView state closed; active/opening require holder+confirmed=true |

write exactly one of text/key. text1..65536 UTF-8 bytes before encoding and totalencoded<=65536 including bracketed paste wrappers; paired UTF16 only, invalid Unicode rejected. key enum Enter,Backspace,Tab,Escape,ArrowUp,ArrowDown,ArrowLeft,ArrowRight,Home,End,Delete,PageUp,PageDown,Ctrl+A..Ctrl+Z. text interpreted as terminal paste/input, Enter execution explicit newline/key; multiline means CR or LF anywhere and requires confirmedMultiline literallytrue for exact payload. No mouse or resize MCP operations. open snapshots default when shellProfileId omitted, no settings write. list max4 sessions for targetprofile. profiles max17 entries incl built-in, no secret data.

SessionView exact fields: sessionId,profileId,generation,shellProfileId,shellName,state(opening|active|ended|disconnected|error),reason?(stable tag),exitCode?(int),partial(bool),historyVersion(int),inputOwner:{kind:free|ui|mcp,clientId?,name?,expiresInMs?}. No leaseToken in list/read; only mutation's authorized holder receives it. Username/host are available from standard profiles.get and UI context, no duplication required.

ActionView: sessionId,generation,state (also closed forclose),replayed(bool),status:accepted|complete|cancelledBeforeSend|outcomeUnknown,acceptedBytes>=0,leaseToken? (only open/acquire),operationSequence. acquire same holder returns same token without extending timer; if old binding dead cached replay token cannot be used by new binding. Open response is asynchronous accepted/opening, not shell-ready. Its cached snapshot remains original; read/list obtain current state. write waits only bounded transport acceptance (15s), not command completion. Release/close repeat may replay after lease/session vanished, never resurrect it. Owner caches metadata before response network send.

HistoryPage: session:SessionView,activeBuffer:main|alt,cursor:{x,y},historyVersion,historyGap(bool),truncated(bool),partial(bool),rows:[{section:scrollback|screen,row:int,offset:int,text:string,wrapped:bool}],nextCursor:string|null. row physical index and offset Unicode scalar index; remaining row fragment continues same row with larger offset. Order scrollback ascending then current screen ascending. Budget counts LF separator per complete row, <=65536 textbytes incl separators,<=limit rows/fragments. Empty history=>rows[],nextCursor null; no channel opening. Final output after ended preserved. Cursor strict decode<=512chars; malformed INVALID_ARGUMENT. Mismatch owner/session/generation=>CONFLICT (wrong session cannot leak data); stale historyVersion=>successful current metadata historyGap=true,rows[],nextCursor null. Client can explicitly reread withoutcursor. Cleared trust buffers not available; closed session CONSOLE_NOT_FOUND.

## Ordering, errors and limits

Mutations use [replay ledger](../data-model.md), one pending mutation/principal. Same sequence identicalpayload=>pending conflict retryable or cached original metadata after completion; different=>CONFLICT. Below highWater notretained=>CONSOLE_REPLAY_EXPIRED. Old ownerEpoch=>CONFLICT before effects. Reconnection can inspect known prior result with originalsequence, but new input must acquire new lease. No automatic retries by owner/router.

New stable domain codes: CONSOLE_NOT_FOUND,CONSOLE_INACTIVE,CONSOLE_INPUT_BUSY,CONSOLE_REPLAY_EXPIRED; reuse INVALID_ARGUMENT/CONFLICT/RESOURCE_EXHAUSTED/TIMEOUT/AUTH_REQUIRED/ACCESS_REVOKED/GRANT_EXPIRED/STORAGE_UNAVAILABLE/SHUTTING_DOWN/CLEANUP_REQUIRED003. Invalid target/code never echoes supplied text/path/token. busy no hidden takeover. Unknown partial write is ActionView outcomeUnknown, not success execution or safe-to-retry error. Closed binding cannot issue further calls, including cached replay/history.

Read one page returns immediately; no longpoll or background script execution. Serialized COMPLETE JSON-RPC MCP reply (text content+structuredContent) <=1MiB. Measure full encodedframe; reduce history page until fits, including cursor/metadata overhead, without returning malformed Unicode or silently losing continuation. General existing2MiB request frame /16pendingchannel /10000requests/session rules remain.

Unit acceptance: discovery21 schemas exact/unknown keys, all tools through authorized router, cross-session/server isolation, outputcaps and Unicode pagination, current/final history, grant/EOF/takeover races, no replay at socket fragments, stateful parser/reply guards, no credential-store objects in read, no payload disk/logs. No real SSH/Isar/process/end-to-end gates.
