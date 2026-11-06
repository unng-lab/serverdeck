# ServerDeck policy variant

Upstream source and MIT license are preserved. UPSTREAM.json records archive and
per-file pristine hashes; patches/dartssh2-4.1.0-policy.patch records the three
changed library files. Upstream README examples describe upstream defaults, not
this stricter application variant.

SSHClient requires onVerifyHostKey(type,fingerprint,exactBlob) and
onHostKeyChanged(type,fingerprint,exactBlob), signature verification enabled, and
exactly one password callback OR one identity. No keyboard-interactive, hostbased,
agent or password-change callbacks. No initial none auth; partial success fails
with SSHUnsupportedAuthError. Changed rekey closes and notifies, never asks to
continue; key identity compares exact bytes, not negotiated RSA signature type.
Callbacks receive copies. Missing raw transport verifier rejects the first key.

Upstream already supports nullable handshakeTimeout/authTimeout; application
adapter supplies null timers and keepAliveInterval:null, using its own budget.
The application algorithm allowlist and key parser policy are implemented by003
transport adapter tasks, not implied complete by vendoring this library.

Only lib/, package metadata, README/CHANGELOG and license were extracted from the
verified archive; upstream runnable/integration tests were not added to this repo.
Local analyzer options retain upstream lint style while keeping errors/warnings
checked. Unit tests use memory transport; no SSH/network process is started.

RSA host signatures must match negotiated rsa-sha2-256/512 exactly; embedded SHA1
or a different RSA digest rejects before host acceptance and NEWKEYS/auth. Public
key identity still uses the unchanged ssh-rsa wire blob. T028 tests feed complete
synthetic pre-NEWKEYS KEX bytes in memory, never a listening SSH service.


The application supplies onVerifyHostSignature backed by an owned4slot worker pool.
Transport checks bounded canonical encoding/algorithm first, then awaits the CPU
verifier before host acceptance. verifyHostSignature is the shared pure function;
low-level tests may use the synchronous fallback, never the strict app adapter.
Closure during signature/trust waits prevents late NEWKEYS/auth. Pending incoming
bytes are capped at1MiB; overflow closes with fixed SSHResourceLimitError. Worker
scheduling failures use fixed SSHSignatureVerificationError reasons. No host key
size-security floor is added; numeric/format sanity and bounded CPU are enforced.

## 004 bounded monitoring execution

SSHClient.startBoundedExec returns a synchronous cancellable handle, one unresolved
opening/open/retired monitoring channel per connection. Deadline at most5s begins
before open. A65536-byte cumulative stdout+all extended-data budget is enforced
inside channel admission before asynchronous buffering; only stdout retained.
Ordinary channels retain upstream window/stream behavior. Cancelled pending opens
retain their waiter/ID; late success closes without exec. Retired channels drop
messages until peer CLOSE, never refill windows or queue replies. New monitoring
calls receive cleanupPending until the protocol slot retires. Duplicate ACKs cannot
accumulate as reply queue entries. All public bounded results use fixed failures,
not remote exception text. Application adapter must supply only its fixed collector
and must enforce canonical session/trust/cancellation admission.


## 007 guarded interactive PTY

startOwnedPty supplies synchronous receive callbacks before buffering, explicit
15s opening cancellation, PTY acknowledgment before shell/quoted exec, bounded
protocol slots including retired opens, late success cleanup and positive remote
packet size validation. SSHOwnedPtySession accepts whole bounded input actions
with removable remote-window/cancel listeners, positive per-fragment progress,
15s deadline and a final guard for every packet. Device replies use the same app
FIFO. trySendPacket returns false before encryption/sequence mutation during rekey;
it never queues that payload. The strict application adapter reserves capacity
before encryption and admits guard/encrypt/raw socket.add atomically, then flushes
outside the command gate. It never drops or retries encrypted packets. Synthetic
units cover cancellation/rekey/late-open/malformed packet size boundaries.

Packet send callbacks also receive one SSHOwnedPacketWait deadline/cancellation
control. Input checks the same monotonic deadline across fragments; setup uses
its opening deadline. The strict adapter subscribes to removable rekey/drain/cancel
signals, and a completed/expired wait removes timers/listeners. Synthetic clock
injection exists only on the owned PTY options for adapter units. A timed-out
queued gate callback is latched inactive; up to64 such active/retired admissions
are retained until their original callbacks settle. Committed ciphertext keeps
its flush/FIFO reservation independently from an action's returned unknown outcome.
