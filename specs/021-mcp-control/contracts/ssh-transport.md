# SSH transport qualification — 021

[Plan](../plan.md), [tasks](../tasks.md), [MCP](mcp.md), [target fence](target-fence.md).

## Responsibility and staged boundary

T144 supplies the real portable dartssh2 4.1.0 connection primitive in
`packages/serverdeck_locald/lib/remote/ssh_transport.dart`. Only trusted locald
composition calls it. Neither owner nor MCP wire exposes its arguments or a
socket/client/channel handle. It has no execution, forwarding, file transfer,
agent, interactive prompt or trust-writing API. Later typed adapters extend
this component without giving callers command strings.

This increment qualifies pinning, authentication and transport lifetime. T011
remains open for persisted owner-only trust, native actor/target fence,
revision invalidation, shared service composition and UI. T012 owns remote
reads. A low-level connection is not service authorization, state evidence or
permission to activate startup. Schema2 rows/bundles are not reinterpreted to
store trust. No change to wire versions or durable storage is needed for T144.

## Inputs and trust

Connection/read implementation extension (pending final checks): an opaque
`SshTransportReservation` charges this same two-slot pool before scoped custody
work and atomically transfers its charge into the actual authenticated attempt.
It accepts no wire credentials or authority. Failed/cancelled custody retains
the reservation until actual completion. `SshLease.read` accepts only typed
`SshReadRequest` operations (system, metrics, dpkg inventory, systemd inventory,
journald); no arbitrary command/script/path input. At most four read channels
per transport include late cleanup, each with a maximum 30-second logical
budget and explicit cancel/physical settlement. Stdout caps are 256KiB for
system/metrics, 4MiB packages, 2MiB units, 8MiB journal; stderr is drained without
publication. Truncated stdout is marked rather than silently interpreted as a
complete source. Transport teardown cancels and waits owned read channels.
These extensions do not establish source/SSH/runtime qualification merely
because their code compiles; full checks are deferred by the user's sequencing.

One locald-owned pool admits at most two transports, including pending TCP,
rejected handshakes and cleanup. There is no waiting queue: a third admission
fails RESOURCE_LIMIT synchronously. Production composition shares one pool.
Pool close prevents admission, aborts owned attempts/connections and awaits
actual settlement. A logical timeout does not free a physical slot before a
late TCP attempt and socket/client cleanup settle.

Endpoint is immutable: host1..253 ASCII letters/digits/dot/hyphen/colon,
port1..65535, username1..64 ASCII letters/digits/underscore/dot/hyphen starting
with a letter or underscore. IPv6 is unbracketed. No URI, path, whitespace,
control, embedded port inference, DNS during validation or target authority.

Host pin is a supported public-key format plus canonical OpenSSH SHA256
fingerprint. Formats exactly ssh-ed25519, ssh-rsa,
ecdsa-sha2-nistp256/384/521. Fingerprint is `SHA256:` plus43 base64 characters
without padding; decode32 bytes and re-encode identically. dartssh2 callback
bytes are UTF-8 of that entire string, not32 raw digest bytes. Strictly decode
and validate both fields, then compare the complete pair. Callback names
rsa-sha2-256 and rsa-sha2-512 map to canonical pin format ssh-rsa before
comparison; ssh-ed25519 and ecdsa-sha2-nistp256/384/521 map identically. Reject
all other callback names, including legacy ssh-rsa SHA1 signature negotiation.
The pin constructor accepts canonical key formats only, not rsa-sha2 names.
Authenticated connect always
requires a pin. Mismatch or malformed callback fails TRUST_CHANGED before any
SSH user authentication or data channel.

Explicit probe has endpoint only and never receives a credential. Capture the
validated advertised pin, deliberately reject host verification, close/drain
and return that pin. It never authenticates or persists trust. MCP has no probe
or confirmation route through this increment. No observed key means fixed
CONNECTION_FAILED, rather than an invented empty pin.

Credentials are immutable ephemeral password or PEM private key with nullable
passphrase, validated by the existing foundation CredentialAction rules in
[profile validation](../../../packages/serverdeck_protocol/lib/profile_validation.dart):
password nonempty<=4096 UTF8 bytes, PEM<=65536, passphrase<=4096, preserved
Unicode/bytes, forbidden controls rejected. Crypto PEM parsing is additional
and fails VALIDATION_ERROR before opening a socket. No fallback credential.
The credential constructor performs only bounded foundation validation, not
synchronous cryptography. After admission, parse/decrypt PEM in one owned
worker isolate before TCP. Its5second monotonic sub-budget starts before
worker spawn and is included in the original15seconds. Timeout/malformed key
yields VALIDATION_ERROR without a socket; cancel/pool close retains its
corresponding first logical code. On timeout/cancel/close kill only that owned
worker (including one whose spawn returns late), observe its real onExit and
close its private ports before releasing the transport slot. Never run key
decryption in the locald event loop. At most two workers total, accounted in
the same two physical transport slots; no detached parsing queue or retry.
Before decrypting OpenSSH keys, reject bcrypt work factors outside1..64 and
salt lengths outside16..64 bytes; other unsupported KDFs fail validation.
Unencrypted OpenSSH requires cipher/kdf none. Supported traditional RSA/EC
PEM uses the locked library parser under the same isolated5second bound.
Do not serialize worker exceptions/stacks or log credential messages. The
parent receives only parsed in-memory key objects or a fixed validation code.
Eventual service loads custody only after fresh native authorization. Key
parsing may occur locally before key exchange because dartssh2 copies the
identity list at construction. No private-key authentication/signature,
password callback or user authentication starts before exact host verification.
No raw secret/exception is included in errors, toString, logs or artifacts.
Dart strings cannot promise memory zeroization; drop retained references at
completion/close. No agent or keyboard-interactive fallback.

## Protocol and lifetime

Use SSH2 and exact locked dartssh2 4.1.0 defaults except remove hmac-sha1.
Retain its modern key exchanges, host signatures, AEAD/CTR ciphers and
SHA256/SHA512 MACs. Never set disableHostkeyVerification, omit verification,
enable debug/trace, or retry another connection. Unsupported algorithms fail
with fixed CONNECTION_FAILED.

Each admitted probe/connect has one monotonic15second deadline beginning
before TCP connect, including DNS, key exchange and authentication. Phase
timeouts use remaining budget, never a fresh15seconds. Pool close or explicit
cancel wins over an unpublished connection. Late success is closed, never
published. Publish one opaque lease only after authentication and final
live-pool/deadline check. Lease exposes only close/done in T144; close is
idempotent, spontaneous disconnect drains ownership and frees its slot.
No reconnect, credential retry, transport reuse or keepalive-driven retry.

Attempt exposes result, cancel and settled separately. result has the logical
deadline; settled tracks actual pending TCP and cleanup. An admitted lease
keeps settled pending until close/disconnect. Attach handlers immediately to
all library futures, including failed authentication and a probe's deliberate
key rejection. Destroy owned socket on cancellation/terminal failure and await
actual client/socket completion before slot release. Pool close drains even
when callers stopped waiting. No unrelated process/socket is touched.

Internal failure codes are exactly VALIDATION_ERROR, RESOURCE_LIMIT,
TRUST_CHANGED, AUTHENTICATION_FAILED, CONNECTION_FAILED, TIMEOUT, CANCELLED,
SERVICE_UNAVAILABLE. No underlying text/endpoint is attached. These private
codes do not expand the MCP enum. Only library authentication rejection maps
AUTHENTICATION_FAILED; other protocol/network errors map CONNECTION_FAILED.
Recorded pin mismatch takes precedence over its resulting library exception.
Expired budget yields TIMEOUT, explicit cancel CANCELLED, pool close
SERVICE_UNAVAILABLE for unpublished attempts. Closing a published lease does
not rewrite its successful result. The first logical terminal decision wins.

## Acceptance

Pure tests: strict canonical pins, key-format distinction, endpoint/credential
boundaries, safe formatting and malformed callback bytes. Real SSH tests run
disposable Ubuntu24.04/OpenSSH Docker on GitHub Ubuntu runners, ephemeral
fixture-only password, generated ed25519 client key and ed25519/RSA host keys, loopback publish,
cleanup on exit. Never upload keys or private authentication logs.

Cover correct password and PEM key, wrong password/key, changed pin,
unauthenticated probe, two pending sockets and third refusal, actual15second
stalled-peer timeout, explicit cancel, pool close during connect and after
authentication, peer disconnect and capacity reuse after actual settlement.
Wrong pin with correct password and correct key must not reach authentication:
assert using private fixture auth evidence without publishing it. Check fixed
errors do not contain fixture secret/host values. No synthetic success socket,
reduced timeout or local pure pass replaces actual SSH/deadline acceptance.

Pure cases must cover both RSA callback mappings, rejection of callback
ssh-rsa/SHA1 and rejection of rsa-sha2 names as canonical pin formats. Real
RSA-only host fixtures force rsa-sha2-256 and rsa-sha2-512 separately and
exercise probe, correct pin connect and incorrect pin pre-auth refusal for
each negotiated signature algorithm.

Include valid encrypted OpenSSH (default16 rounds) authentication, wrong
passphrase, rounds65 and uint32max rejection, and actual worker lifecycle
after immediate cancel/pool close. Excessive rounds must be rejected before
KDF, with no TCP listener acceptance or lingering worker. Verify concurrent
stalled-peer cancel/deadline remains responsive while a key worker runs. Use
an actual owned worker and key parser; no test callback may replace success
or physical worker-exit evidence.

Root format/analyze/test, locald analyze, links and fresh independent review
precede closure. Hosted failure remains failure. Native actor/service wiring
and Windows-to-Linux end-to-end product acceptance remain T011 obligations.
