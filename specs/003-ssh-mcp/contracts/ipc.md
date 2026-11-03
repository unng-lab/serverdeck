# Native IPC and stdio bridge v1

Normative security boundary: [access model](../mcp-access.md). One main owner; helper
sameEXE has only stdin/stdout+pipe handles. Native bridge does not load Flutter/Isar.

## Discovery and peer checks

Main publishes `mcp/owner.json` only after pipe listener ready and canonical store
available: protocolVersion1,ownerEpoch,pid,processCreationTime,userSid,logonSid,pipeName.
File ACL current user, atomic replace, reparse/path traversal denied. MCP descriptor
separate from activation descriptor002. Disabled/unavailable MCP removes descriptor;
stale file never grants access. Native GetNamedPipeServerProcessId + process token and
creationTime must match before DPAPI read/auth. Process creationTime uses exact FILETIME,
not PID alone. Main actual client Windows token supplies user+logon SID; JSON claims
cannot supply authority. Impersonation failure fails closed, always RevertToSelf.

Pipe name `\\.\pipe\ServerDeck.Mcp.<ownerEpoch>.<random128hex>`; local only,
PIPE_REJECT_REMOTE_CLIENTS; first handle FIRST_PIPE_INSTANCE; explicit DACL current
logon SID, not default/Everyone/Anonymous. All subsequent instance handles belong
same verified server PID. Name collision selects new random name before publication;
not a fallback to another process. ACL/protection failures disable MCP, not UI/SSH.

## Frames

UTF-8 JSON per line, literal newlines in strings escaped; max2MiB including newline.
Invalid UTF8/oversized/invalid envelope closes channel; no partial domain action.
First frame, within5s:
`{kind:"auth",version:1,clientId,grantVersion,ownerEpoch,secret:<base64url32>}`.
Owner canonical Isar validates enabled/runtime state/user/grantVersion/expiry/secret;
constant-time secret compare; exportPending fails closed. Reply
`{kind:"authorized",version:1,grantVersion,expiresAt}` or generic AUTH_REQUIRED thenclose.
No fallback/rawMCP before auth. Duplicate auth after success closes channel.

After auth frames:
`{kind:"mcp",payload:<JSON-RPC object>}` both directions. Native channel metadata
clientId/grantVersion/user/logon/ownerEpoch is transport-owned, not fields client sets.
UTF8 frame decoder limits buffering before newline, not after allocating unbounded line.
Stdout has ONLY unwrapped MCP payload lines, no internal authorization frames/banner.
Before initialize errors: sanitized stderr + exit code; never synthetic non-MCP stdout.

Limits main8channels,2pergrant; native main queued frames≤16/channel, overflow closes
violator, no effect from dropped command. Already admitted mutation preserves atomicity.
Idle channels expiry timer closes at grant deadline; every frame/commit/data response
checks current grant anyway. Shutdown/disable closes pipe and helper; stdio EOF only
ends helper, no app exit. Main cancels explicit CancelledNotification only for pending
noncommitted request, not durable effect already committed.

## Main native ↔ Dart extension

Channel `serverdeck/platform.v1` adds `mcp.publishOwner`, `mcp.removeOwner`,
`mcp.sendFrame(channelId,frame)`, `mcp.closeChannel`, `mcp.writeGrantBlob(clientId,
grantVersion,protectedSecret)`, `mcp.deleteGrantBlob(clientId)` and events
mcpChannelOpened/mcpFrame/mcpChannelClosed. Args validated canonicalUUID and boundedbytes;
paths always derived internally, not caller-provided. All UI/main native RPCs carry
epoch; bootstrap bridge cannot call this Flutter channel.

Native verifies peer+frame bounds and delivers handshake to Dart grant owner; it
never reads canonical Isar or decides permanent domain permissions. Dart verifies
authorization before sending authorized frame. Native holds channel state only.
Grant blob write happens through atomic native metadata API; main store determines
whether version permitted. Event channelId cannot be reused within ownerEpoch.

## Helper exit codes

0 clean EOF/client close;2 invalid args;20 APP_UNAVAILABLE/MCP disabled;21 PEER_REJECTED;
22 credential/DPAPI/auth failure;23 protocol/resource failure. No auth-error details
that disclose secret/grant existence on unauthenticated channel. Clean EOF while owner
is live does not stop it. Root argument parser dispatches stdio before payload load.


## Concrete native ownership and metadata representation

The implementation shares `native/bootstrap/mcp_pipe.cpp` and
`native/include/mcp_pipe.h` between the bootstrap and Windows host. The private,
UTF-8 strict, duplicate-key rejecting JSON codec is `native/include/mcp_json.h`.
No helper library, Flutter dependency or database access is introduced in bridge
mode. Bootstrap dispatch remains before payload loading.

`processCreationTime` in owner.json is a canonical unsigned decimal string of the
exact FILETIME; pid is an integer. Grant metadata is JSON version1, clientId,
grantVersion and canonical standard-base64 protectedSecret. DPAPI entropy/purpose
is UTF-8 `mcp-grant.v1:<client UUID>`. Protected grant ciphertext is limited to8192
bytes; descriptor/grant metadata files are limited to16384 bytes. The plaintext
secret is exactly32 bytes, auth proof is unpadded canonical base64url43 characters.
No metadata path is supplied by clients or Dart callers.

Broker owns listener and reader/writer threads, overlapped operation handles and
stop events. Close acknowledges termination of those exact native workers; no
thread is detached. Queued frames are bounded to16 per channel in each direction,
with a bounded256 event queue across8 channels. Event-queue exhaustion disables the
listener, closes channels and reports unavailability; it does not dispatch dropped
frames. Native channel UUIDs combine the current owner epoch prefix and an increasing
48-bit sequence, retained across listener restarts in that epoch. Closed-ID history
is therefore unnecessary and no ID is reused. Counter exhaustion fails closed.

The helper validates private metadata ACLs (current user, SYSTEM and administrators
only, matching foundation002 file policy), rejects reparse files and verifies the
actual server PID/creation/token before reading or decrypting grant data. The server
checks client process identity and, after the first bounded read, its impersonated
thread token; it always reverts before delivering any Dart event. External malformed
JSON produces a bounded MCP parse error after authenticated bridge setup; internal
malformed envelopes close the native channel. These are implementation bindings,
not evidence of an executed IPC or integration test.


## Native unit boundaries and final close/queue acknowledgments

`native/include/mcp_boundary.h` contains the production handshake, verified-client
policy, private metadata policy, frame/stdio pumps and owned-worker closure used by
native mcp_pipe.cpp. The synthetic ipc_boundary unit supplies read/write, Windows
peer-result, metadata and unprotect functions; this is not a launched bridge or an
application integration. Native Win32 bindings remain subject to static review and
isolated underlying adapter tests.

The internal platform extension additionally accepts `mcp.ackFrame(channelId)`.
Native retains each incoming reservation across InvokeMethod delivery, until Dart
finishes that frame and acknowledges it. The16 limit therefore includes delivered
but unfinished frames; it does not merely limit the transient native event deque.
Acknowledgment grants no authority and is inaccessible through external MCP tools.
Stop disconnects the native peer immediately; mcpChannelClosed is emitted only after
exact workers join and the accepted pipe handle is released. Explicit Close and
accept-side retirement share the same idempotent worker/handle acknowledgment.
