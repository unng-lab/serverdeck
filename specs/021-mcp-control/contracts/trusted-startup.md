# Production format3 startup

The production locald entry uses `TrustedLocaldEnvironment` and
`TrustedLocaldBootstrap`. It verifies the installed format3 bundle, retained
locald image and native runtime before touching workspace files. It owns the
canonical mutex, eight trusted pipe slots, protected discovery and
[trusted workspace](trusted-workspace.md) for the whole generation.

Discovery is published before workspace initialization so authenticated clients
can observe starting/recovering/blocked readiness. Its format1 container is not
an API-version negotiation: the actual native bootstrap requires same-build
API1.1, format3 role proof and schema3 typed responses. No old bootstrap fallback
is permitted. After storage opens, discovery gains the actual workspace ID.

The first eligible native peer binds the actual locald publication gate and
`TrustedSessions`. A locald contender is permitted only the ownership probe; it
cannot initialize owner/MCP services or poison an eligible connection's binding.
The format3 native worker can identify another verified same-bundle locald for
this probe only; native2 keeps its existing refusal. Before any service/session
binding, the winner sends the exact framed object
`{"serverdeckOwnerProbeV1":"<verified-build-id>"}` and drains that output within
five seconds. The contender independently verifies the native locald peer and
reads this exact single-field object within both its original 30-second startup
budget and a five-second probe budget. Only an exact same-build value succeeds.
No bootstrap token, workspace contents, role grant or RPC session is issued.
Drain keeps the pipe alive until the contender has read the response; the
normal physical disconnect/reuse barrier follows. Failed, silent or malformed
probes never count as a live owner or extend either deadline.
The deferred API admits readiness/session lifecycle while storage starts; domain
routes activate only after actual shared-service composition and job recovery.
Only the activated composition can publish ready features. The verified bundle
and its optional verified executor descriptor are passed directly to that
composition; absence of the descriptor never implies executable job support.

The original process startup deadline is 30 seconds. First authentication and
bootstrap completion are both required within it. Session expiry and the
existing two-second empty-session grace use actual registry state; no keeper
session is fabricated. Shutdown stops admission, waits for actual startup,
binding, activation and mutation drains, then closes storage, pipes, discovery,
keys and finally the mutex. Unconfirmed storage close or reservation prevents
early mutex release. A constructed channel owns its physical disconnect barrier;
the serving loop must not disconnect its slot twice.
If workspace startup fails after discovery publication, authenticated diagnostic
readiness remains available. The first startup failure is retained through
normal last-session shutdown and all physical cleanup. After cleanup the
production entry reports its fixed failure code and exits1; closing a diagnostic
session must not turn an unsuccessful workspace open into a successful exit0.
The unauthenticated startup watchdog still closes the service within its original
budget, but its later TIMEOUT does not replace an already known startup failure.
An actual physical-cleanup failure takes precedence and remains STORAGE_BLOCKED;
the first startup code is reported only after cleanup has succeeded.

The normal Flutter entry uses `TrustedNativeBootstrapHost` and the explicit
`LocalApiClient.trusted` constructor. This constructor accepts only a genuine
`TrustedApiClient` plus its authenticated generation; it does not route native
traffic through the old handshake or turn schema3 results into legacy DTOs.
Snapshot consistency, ordered trust counters, immutable mutation IDs, receipt
recovery, polling epochs and stale-generation rejection remain enforced. The
same actual client is borrowed by server and automation panels. Disposing these
panels does not close the shared session.

The MCP entry accepts exactly `--app-root <absolute path> --grant-id <UUID>` or
no arguments. A configured bridge verifies its own fixed MCP image, uses the
same protected discovery and may launch one verified matching locald contender.
Startup has one 30-second budget; unavailable pipe slots may be tried, but an
authenticated-session/grant failure is terminal. The narrow
`readinessBeforeGrant` API serializes typed readiness before ordinary RPC claim;
it cannot overlap grant proof or ordinary RPC. It supplies the authenticated
workspace ID for protected per-grant DPAPI custody. The bridge proves the grant
before `LocalMcpGateway.connectTrusted` claims the actual RPC session and native
publication gate. The gateway retains the existing cancellation, current-grant
publication and physical drain rules. No arguments exposes only unconfigured
protocol negotiation; configured failure never selects that mode.

An optional MCP cold launch uses CREATE_BREAKAWAY_FROM_JOB with the existing
hidden/Unicode process flags. It may not inherit a host Job Object that can kill
the shared daemon when one client closes. If host policy refuses breakaway,
startup reports the fixed PREREQUISITE_UNAVAILABLE code; the owner starts the
normal UI/locald independently before connecting that host. There is no retry
without the flag and no unrequested broker/task/shell workaround. Existing
independently started locald connections require no breakaway operation.

`tools/run-serverdeck.ps1` assembles the normal Flutter binary, locald, MCP,
selected native DLL/notices and generated executor descriptor. It publishes a
format3/API1.1/schema3 manifest binding all five artifact hashes and all five
dependency lockfiles. `run-foundation.ps1` delegates ordinary builds to it;
historical acceptance targets remain explicit and must be updated/qualified in
the deferred final checks. Neither source activation nor selected analysis
establishes installed-runtime, native-release or full-feature acceptance.
