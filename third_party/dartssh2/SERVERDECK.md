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
