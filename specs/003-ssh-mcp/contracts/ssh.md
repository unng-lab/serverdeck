# SSH transport policy v1

## Dependency and patch

Vendored upstream dartssh2 4.1.0 archive SHA256
`39359aceafcf5940b868249e3c9c6d86e4e0f989eec7417d033c943157c84c51`.
License и pristine source provenance сохраняются, diff фиксируется отдельно.
Patch: onVerifyHostKey callback получает третий Uint8List exactHostKeyBlob после
проверки KEX signature и до NEWKEYS/auth; application всегда устанавливает callback.
Удалить начальное добавление none-auth, разрешать только configured password/publickey,
partial/MFA response → UNSUPPORTED_SERVER без fallback. Upstream не обязательно
использует none после обычного auth failure; patch обеспечивает строгую политику
во всех путях, включая null/cancel credentials.

## Host identity

Identity — exact public key wire blob. Canonical key type читается из blob;
negotiated `rsa-sha2-512/256` не становится новым `ssh-rsa` public key.
Fingerprint = `SHA256:` + unpadded base64 SHA256(blob). Upstream4.1.0 fingerprint
уже UTF-8 такой строки, не raw digest; вычислить из blob и сверить, не хешировать строку.
Store accepted bytes+type+fingerprint, equality по bytes. Не доверять одному callback
fingerprint без blob. Rekey signature verification остаётся включённой; несовпадение
на rekey закрывает соединение и через patched changed-key notification передаёт
новый verified blob владельцу для persistent warning; silent library error недостаточен.
Этот notification — дополнительная часть patch; не допускает continuation/rekey acceptance.

Host callback awaits domain decision. Unknown → needTrust/challenge, no userauth.
Accepted matching → allow, even retained changed-warning until explicit retain.
Mismatch → persist warning, invalidate endpoint generations/close other sessions,
end attempt; replaceTrust commits only matching current challenge, ends attempt.
Rekey changed key handled как mismatch without offering in-place approval.
Callback absent / disableHostkeyVerification=true / success on storage failure запрещены.

## Explicit supported algorithms

Host signature: ssh-ed25519, rsa-sha2-512, rsa-sha2-256 (в этом порядке).
User private keys: OpenSSH Ed25519/RSA≥2048, encrypted bcrypt/unencrypted OpenSSH only,
one key per input. KEX: curve25519-sha256, curve25519-sha256@libssh.org,
ecdh-sha2-nistp521/384/256, diffie-hellman-group-exchange-sha256,
diffie-hellman-group14-sha256. Cipher: aes256-gcm@openssh.com,
aes128-gcm@openssh.com,chacha20-poly1305@openssh.com,aes256-ctr,aes128-ctr.
MAC: hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,
hmac-sha2-256,hmac-sha2-512. No SHA1 signatures/KEX/MAC, MD5, CBC, group1;
no automatic weaker fallback. Unsupported overlap → UNSUPPORTED_SERVER.

## Credentials and authentication

Original bounded UTF-8 OpenSSH file bytes validate with passphrase if encrypted,
require exactly one Ed25519/RSA≥2048 key, protect ORIGINAL bytes via DPAPI and store;
never serialize parsed key via unencrypted toPem. Invalid/cancel leaves old data.
Synchronous bcrypt parsing runs cancellable worker isolate; cancel kills worker,
late results fenced. Protection/parse/log errors redacted.

Private-file encryption supports bcrypt with AES128/192/256 CTR or CBC; this does
not enable CBC in SSH transport. Other private-file cipher/KDF combinations reject
UNSUPPORTED_KEY. At most4 workers (including pending spawn and unconfirmed exit),
30s monotonic parse deadline, clamped by caller remaining network budget on connect.
Only explicit passphrase/trust prompt pauses the connection budget; parsing after
a supplied passphrase counts toward it. Deadline/cancel returns a fixed error and
stops the owned Dart isolate. Slot releases only after confirmed exit; failed stop
retains slot for cleanup retry. Late spawn/result cannot publish or allocate beyond
capacity. Runtime stops admission, cancels and drains these owned workers. A Dart
isolate is an in-process parser unit, not an external process-kill scenario.

Preparation protects original bytes with DPAPI CurrentUser and purpose
`credential.v1:<canonicalCredentialUUID>`; the same purpose is required to decrypt.
Password UTF-8 bytes remain exact. Parser returns only metadata to import preparation;
parsed signing material stays private to the attempt/parser. Prepared ciphertext
is copied into the record in the later fenced transaction and disposed afterward.
No passphrase is stored; owned temporary byte buffers are cleared on success/error/
cancel. Immutable strings/BigInts/library copies have no GC-wide wipe guarantee.
Native protect input<=1MiB/output<=2MiB; unprotect input<=2MiB/output<=1MiB. Bound or
OS protection failure never returns partial plaintext/ciphertext or persists data.

Password attempt: exactly one non-null saved password callback, no identities,
userinfo/agent/hostbased. Key attempt: exactly one selected identity (async owned signer), no
password or keyboard-interactive callback. Auth failure ends attempt; no fallback.
Passphrase request bound to attempt/credentialRevision; 5min deadline. For a supported encrypted container, absent passphrase returns PASSPHRASE_REQUIRED;
a provided empty/wrong value returns PASSPHRASE_INVALID (field passphrase). Successful
import does not save passphrase; next connect asks again. No interactive shell,
exec, subsystem, PTY or remote install command opens as proof of connection:
authenticated SSH transport suffices for connected status.

## Time, cancellation and liveness

Own monotonic budget30s for DNS/socket/KEX/auth waits; pause only during explicit
trust/passphrase wait. Prompt5min includes no automatic affirmative action. Built-in
handshake timer must not count user wait; adapter config disables/replaces it and
actively closes socket/client on own deadline. Vendor patch may expose constructor
null network timer if upstream cannot disable it; patch tests prove paused budget.
No raw Future timeout while leaked socket continues authenticating.

Disable library keepAliveInterval. Owner sends one ping every15s after last completed
ping; single ping timeout10s. First missed reply closes session, gives NETWORK_ERROR;
upper bound half-open≤25s after last successful interval start, within spec90s.
No automatic connect/reconnect. Cancel/disconnect/shutdown/credential/endpoint changes
advance generation before closing and before stale callback can publish success.

## Unit verification scenarios

In-memory byte-stream fixtures проверяют policy/codec/auth order и wire method
allowlist, signature failure, raw blob/type/fingerprint и rekey notification.
Fake monotonic clock/timer проверяют30s budget pause,5min prompt,15+10 liveness и
late callbacks. Synthetic encrypted/unencrypted Ed25519/RSA vectors проверяют
pure-Dart key parser, wrong passphrase и unsupported algorithms. Нет TCP listener,
OpenSSH process, actual server, real credentials, VM или end-to-end прогона.
Парсинг/криптография проверяются как отдельные units; domain owners используют fake
transport/parser. Продуктовые требования SSH сохраняются, unit pass не доказывает
реальную сетевую совместимость всего приложения.


## Exact RSA signature binding (T028)

The signature's embedded RSA type must equal the negotiated rsa-sha2-256/512;
ssh-rsa/SHA1 and mismatched SHA2 digests reject before the host callback, NEWKEYS
or authentication. The public-key wire blob still begins ssh-rsa; it is not
rewritten to the negotiated signature name. This matches the separation of key
format and signature algorithm in [RFC8332 §3.1](https://www.rfc-editor.org/rfc/rfc8332.html#section-3.1).
Memory byte fixtures exercise complete version/KEXINIT/Curve25519/KEX-reply with
synthetic host signatures; false trust callback stops before authenticated session.
These are protocol component units, not a listening SSH service or TCP integration.

## Bounded host-signature crypto (T034, required for adapter T009)

Untrusted RSA public numbers can make synchronous verify outlive a UI budget timer.
The production adapter therefore supplies an asynchronous signature verifier hook
before public host acceptance. Extract one pure vendor signature verifier (same
exact-algorithm policy), used by owned worker isolates, with the library awaiting
that hook and never bypassing verification. Preserve a fallback for low-level vendor
component tests; the strict application adapter always installs the bounded hook.
No product host-key minimum/maximum algorithm is invented by this scheduling change.

A separate root-owned host-signature worker pool allows4 reserved jobs total,
including pending spawn and unconfirmed exit; overflow RESOURCE_EXHAUSTED retryable,
no unbounded queue. Deadline<=30s clamped by remaining connection budget; cancellation
stops the owned isolate, retains reservation until confirmed exit and disposes late
results. Host blob/signature each<=16KiB and exchangeHash length32/48/64 are checked
before dispatch. The pure verifier checks complete canonical key/signature encoding
(no trailing fields) before expensive math. Invalid bounds/crypto/signature policy give UNSUPPORTED_SERVER;
crypto deadline TIMEOUT, no host callback/auth on false/error/late success. Exact
verified host-key mismatch still goes through domain HOST_KEY_CHANGED warning, not
this cryptographic-failure path. Runtime capability stops admission/cancels/drains
workers and keeps uncertain stops for retry. Fake workers/deadlines and synthetic
memory KEX verify cancellation/capacity/late callback/no-auth, no TCP/process tests.
This is separate from the4private-key parser slots; neither pool may allocate past
its own confirmed-exit reservation limit. T034 is required before T009 acceptance.


## Buffered wire bytes during asynchronous waits (T035)

SSHTransport pending incoming backlog is limited to1MiB, checked on the sum of
existing bytes plus the incoming chunk before append. Overflow closes the owned
transport with fixed SSHResourceLimitError; adapterT009 maps RESOURCE_EXHAUSTED.
No late data grows a closed buffer; late signature/trust success cannot emit
NEWKEYS/auth or re-enter host acceptance. This bounds memory while a verifier or
5min prompt is pending, even if a peer keeps sending individually small chunks.
Memory fixtures exercise both one oversized chunk and cumulative sub-limit chunks.
No new host-algorithm key-size policy or real network test is implied.

Shared ownership core lives in lib/runtime/owned_work.dart: private key parser and
HostSignatureVerifier each own a separate4slot pool with the same confirmed-exit
reservation/retry rules. Cancellation aliases retain existing parser caller types;
all prior parser units continue to apply. Fixed scheduler/spawn/getter/result errors
are sanitized by each adapter, never copied from worker stderr or exception text.
Vendor helper checks canonical full key/signature bytes, positive odd RSA e>=3 and
odd n>e, supported digest binding and hash lengths before expensive verification.
The application's host pool accepts only its3allowed host types; low-level vendor
fallback retains ECDSA format support but is not selected by the strict adapter.


## Bounded private-key authentication signing (T036)

Passing a parsed in-memory RSA key directly to SSHClient would execute its synchronous
sign on the main owner, defeating cancel/network timers. Use one SSHIdentity wrapper:
public-only hint from the bounded original file, no private math on main; actual
private parse/validation/sign occurs in a separate root-owned4slot pool using shared
confirmed-exit ownership. Original file<=1MiB, ephemeral passphrase<=64KiB UTF-8,
challenge<=2MiB, <=remaining30s deadline; cancellation/late outputs/uncertain exit
follow the existing parser rules. Result contains signature only, never private key
or passphrase; owned byte buffers clear, library immutable copies have no global
wipe guarantee. Root disposes wrapper/file material after auth/end, not between
connections by retaining passphrase. Private signing is distinct from the4import
parser and4host verifier slots, with no unbounded queue in any pool.

Hint metadata must match the canonical credential's type/bits/revision. Ask ephemeral
passphrase only after verified host acceptance; supplied input resumes the same
current attempt after its fences, with budget resumed during parse/sign. Selected
signature scheme is frozen for that attempt: Ed25519; RSA prefers rsa-sha2-512 when
advertised by server-sig-algs, otherwise rsa-sha2-256 when advertised, and defaults256
when no discovery exists. An advertised list without overlap gives UNSUPPORTED_SERVER.
No method/key/signature-scheme fallback after rejection. The shared pure file parser
still validates the same supported key formats and private/public consistency.
T036 and its strict adapter binding are required beforeT009 acceptance. These are
CPU scheduling/identity implementation decisions, not a new SSH tool or key policy.


**T036 component contract:** `profiles/key_envelope.dart` is the shared bounded
OpenSSH envelope reader for import and public hints. Hints retain a canonical
public blob and keyType/bits/encrypted only, validate keyCount=1 before allocation,
and never evaluate private-key math or bcrypt. Decoded private storage is owned
and cleared even on parse failure. Public data is copied before that clearing.
Passphrase size checks count UTF-8 bytes without allocating another secret buffer.
`connections/private_signer.dart` owns a separate four-slot pool and the
`OwnedPrivateIdentity` attempt wrapper. Signer workers receive original bytes,
one frozen scheme, challenge and optional ephemeral phrase; return encoded
signature only. Import parser and signing workers share the same envelope and
private validation policy. Required/invalid phrase and unsupported-key errors are
fixed; capacity, timeout, stop and cancellation retain existing owner semantics.
Identity is single-use for signing; its public algorithm remains available after
successful sign because SSHClient reads it again when sending userauth. Private
file and challenge are cleared on success/failure; owner disposes the public
wrapper after auth/end. External cancellation also ends a pending prompt wait;
late prompt errors/results are consumed without starting signing.
The strict adapter must provide the mandatory admission callback (accepted verified
host, current credentialRevision and all attempt/authority fences), bounded prompt,
server discovery and monotonic remaining-budget callbacks. It must dispose every
identity on auth/end, register/drain the shared signer, and bind actual socket write
authority. Components and fake callback units alone do not satisfy these T009/T010
production bindings. T036 remains open until those bindings are implemented.


**T008/T010 timer component:** `connections/network_budget.dart` supplies one
NetworkBudget per attempt and ConnectionWatchdog per connected session. Both use
Stopwatch-based monotonic time, with injected clock/scheduler only for units.
Budget starts on attempt creation; only explicit trust/passphrase prompt leases
pause it. Duplicate observations of the same prompt do not renew five minutes;
foreign/stale leases cannot resume the current wait. Resume/query checks current
time before accepting a late response, independently of timer delivery. At timeout
its callback must invalidate the owning generation and close exact resources.
Before publishing connected inside the final authorized/fenced owner transition,
NetworkBudget.tryComplete MUST succeed. It refreshes monotonic time, rejects an
expired attempt or any still-active prompt, and accepts success at most once.
A late success before an undelivered timer cannot suppress timeout. isEnded also
refreshes time. finish is cleanup for cancel/error only; it deliberately emits no
new timeout and cannot authorize success. Either termination fences/cancels all
captured late timers.
Watchdog sends first ping fifteen seconds after creation, waits at most ten seconds,
and schedules the next interval after successful completion. One ping in flight,
first failure/late response stops the watchdog and calls owner failure once; no
reconnect. Timer rearming and ping result generations are separate so an early
timer delivery cannot discard a still-valid ping result. Owner maps failure to
NETWORK_ERROR and closes the session; both obligations remain T010. These helpers
do not by themselves implement attempt/session ownership or socket cleanup.


## Strict application adapter and actual write admission (T009)

`connections/ssh_transport.dart` exposes StrictSshTransport.authenticated, ended,
ping and retryable close only, never SSHClient/channel/exec/shell/agent access.
Its exact algorithm lists implement the allowlist above. It always installs the
provided shared HostSignatureVerifier hook, async PrivateSigner identity for keys,
raw verified host and changed-host callbacks; all vendor timeout/keepalive timers
are null. Root must register/drain the two shared pools before startup completes.
Root owns initial dial/socket reservation; if adapter construction throws, root
still closes the known socket. AttemptCredential takes its own bounded input copy;
owned credential/identity bytes clear after auth or every terminal/cancel path.

AdmitSshWrite is mandatory and has no allow-all default. OwnerT010 implements it by
enqueueing DomainCommandGate with CURRENT pending actor (OwnerActor after connected
promotion), then invokes actualWrite synchronously INSIDE CommandContext.linearize
with current connection/credential/endpoint/generation fences. The effect returns
its current ConnectionValue; no network Future is awaited under the gate. Gate
admission/response authorization remains canonical. A queued write never captures
an authorization decision made before a wait. Adapter owns FIFO encoded byte copies
(max64 reserved packets, total1MiB including active admission), invokes one admission
at a time, clears completed/dropped wrapper-owned copies and rejects late/duplicate actualWrite
callbacks. Overflow fails RESOURCE_EXHAUSTED and closes; no unbounded wire queue.
The actual synchronous raw sink.add is the write linearization point.

Root checkAuthentication is mandatory current synchronous authority/fence/trust
validation before credential access/sign and before the authenticated result.
Auth success additionally requires accepted verified host and a prepared selected
credential; unsolicited success without a selected credential fails
UNSUPPORTED_SERVER. Auth result awaits queued actual writes/flush and current
checks, but owner STILL must use NetworkBudget.tryComplete inside its final guarded
connected publication. Remaining-budget callback returns current initial attempt
budget for auth/crypto; after successful ownership promotion, rekey verification
uses an independent <=30s crypto deadline while the session watchdog remains active.
Explicit user trust decline is TRUST_REQUIRED at adapter level; owner maps its own
cancelled attempt state. Invalid crypto/protocol/negotiation is UNSUPPORTED_SERVER,
partialMFA UNSUPPORTED_SERVER, selected-method refusal AUTH_FAILED, resource overflow
RESOURCE_EXHAUSTED, timeout TIMEOUT; structured private-sign/authority failures retain
fixed domain codes. Untrusted exception strings never become operation messages.

Changed-host owner callback is invoked synchronously before library done microtasks
can invalidate the attempt; adapter waits its completion before ended notification.
This preserves the verified observation for persistent warning. Failed persistence
is STORAGE_UNAVAILABLE rather than being replaced by the earlier library close.
Physical close always calls and awaits the OWNED socket close/done even if vendor
already reports closed after destroy. Failed close stays retryable; queued write
admissions must also drain before close completes. Owner retains quota/quarantine
until this Future confirms cleanup. done/ended/isClosed alone never release a slot.
Root bounds uncertain cleanup at5s and tracks retries per existing T010/T013/T026.

Adapter allows only one outstanding ping, rejecting another with RESOURCE_EXHAUSTED
without queuing a second vendor request or closing the healthy first one. Watchdog
owns normal ping cadence/deadline; root handles missed reply as NETWORK_ERROR and
closes, without reconnect. The adapter itself does not create timers, trust records,
credentials exports, Isar or domain actors. All mandatory production bindings above
remain T010/T013/T020, explicitly absent from the isolated adapter units.


**T038 wire ownership and terminal arbitration:** actualWrite transfers a separate
immutable encoded-byte copy to raw.sink.add and NEVER mutates that sink-owned list.
The wrapper-owned packet can be cleared only independently of that list. Reservation
(packet count and logical byte count) remains held through raw.flush outside the
gate, including backpressure; no admission/cleanup can silently release an active
unconfirmed consumer. Cancel stops later write admission, closes the physical socket
and also drains these retained writes. Delayed-consumer units verify byte identity
before/after flush and cancellation, without a real Socket or process.
An outstanding ping aborted by changed-host rekey is subordinate to changed-host
persistence. It waits the adapter ended result; it cannot set an earlier
UNSUPPORTED_SERVER or overwrite HOST_KEY_CHANGED/STORAGE_UNAVAILABLE. Both outcomes
have explicit outstanding-blackhole-ping + rekey unit cases. Native raw socket
closure/owner quarantine semantics remain as above.

All subordinate async errors, including a pending KEX raw.flush aborted by destroy,
follow the same arbitration: after changed-host observation is detected, _fail may
continue resource cleanup but cannot select terminal code or complete auth before
changed persistence. _onEnded alone determines that outcome after changedWork.
Units combine pending KEX write acknowledgement, blackholed ping and changed host
for both persistence success/failure. This extends T038; ping-only arbitration was
insufficient and its previous clean expectation was not treated as completion.


## Owned native dial admission (T010)

connections/owned_dial.dart uses Socket.startConnect/ConnectionTask, not a detached
Socket.connect Future.timeout. Root reserves its64-live-resource slot and constructs
OwnedSshDial synchronously INSIDE the current authorized/fenced gate effect. The
factory begins there; awaits/DNS/socket readiness happen outside the gate. Initial
30s attempt budget starts before this admission and keeps running through DNS,
connect and preparation. BeginSshDial returns an owned task, and a factory failure
must leave no live resource. A pending factory remains owned even after cancel.
Cancellation rejects its public socket result promptly but close waits the factory,
cancel acknowledgment (task.socket completion) and any exact late socket close/done.
No timer/future observation abandons it or releases the root quota. A5s owner cleanup
deadline can quarantine that same retained dial; retry never starts another dial.

Known socket is delivered once; takeSocket transfers ownership synchronously only
if the dial was not cancelled, succeeded and not previously transferred. Caller must
record the exact returned raw handle before constructing the strict adapter, and
close it on EVERY constructor/error path. After transfer, dial.close never closes
that now separately owned socket. Root closes raw/adapter resources before releasing
the single logical connection slot. Before transfer, failed cancellation/getter/
close retains the task/socket and allows cleanup retry; late success never becomes
an authorized socket result after cancel. Error strings are dropped, using fixed
NETWORK_ERROR or retryable CLEANUP_REQUIRED/connectionCleanup. A failed destroy does
not prevent trying a close which can still confirm the same physical handle.

NativeSshSocket is a thin Dart Socket adapter; its close waits the Socket consumer
completion. An errored completed consumer (for example reset) still confirms closure
and is not converted to permanent cleanup quarantine; library done/stream still
reports the network failure independently. Default native factory is not invoked
by units: fake tasks, SSHSocket and Socket objects cover pending/late/error/transfer,
physical confirmation and retry. No TCP/listener/real socket or OS process tests.


**T039 acknowledgment acquisition:** acquire socket.done Future outside the catch
which interprets its errored completion as physical-close acknowledgment. A sync
throwing getter means no acknowledgment was obtained: retain the exact resource,
return retryable CLEANUP_REQUIRED and retry that same handle. This applies to dial
cleanup, NativeSshSocket's errored-close fallback and strict admitted socket close.
An actually obtained done Future that completes with an error still confirms the
consumer's exit. Units distinguish all three getter failures from completed errors.
