# Quickstart and acceptance — 021

This guide describes the intended implemented entry points. They do not exist merely because this file is written. Record actual commands/results per task, never label planned fixture checks executed.

## Prerequisites

For T170–T173 shared connection qualification, follow the [connection contract](contracts/connections.md). After those tasks exist, run `dart test test/mcp/connections_native_test.dart` from packages/serverdeck_locald with the existing actual DPAPI/native fixture and hash-locked loopback SSH fixture. Require two owner windows plus scoped MCP to share one authentication, cross-client disconnect isolation, all owner handle/TTL/quota boundaries and confirmed target/credential/trust/delete changes to drain old transport before ACK. Run existing trusted-services, strict-channel, recovery and portable/actual SSH suites serially. These are planned acceptance commands; missing tests or a passed low-level transport suite alone do not close this stage.

Pinned Windows SDK/build tools and existing foundation native bundle requirements; current-user protected disposable workspace, no real stored profiles. Ubuntu24.04 amd64/systemd disposable Docker fixture on a GitHub Ubuntu runner (or an explicitly owned VM) with owned SSH identity, Python3.12/python3-apt/systemd/sudo/journald and prepared signed apt repositories/packages. Executor owner provisioning is explicit; MCP read/author tools never install it. See [runtime](contracts/executor.md), [profiles](contracts/profiles.md).

## Local checks after implementation

Run from repository root:

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
lychee "specs/**/*.md"
pwsh -File tools/test-mcp.ps1
```

`test-mcp.ps1` must run root/affected package analyze/tests, Python unit/compiler/protocol tests, MCP stdio transcripts against actual bridge, migration1→2 crash fixtures and secret-marker scans. Use approved protected local fixtures; output safe proof with source/build/runtime lock digests. It must fail if a mandatory scenario is omitted, not count generated fixture transcript as real bridge proof.

## Owner setup and independent clients

Build same compatible bundle with tools/build-mcp.ps1, start UI through existing entry, create synthetic target/credentials and owner-confirm exact SSH fingerprint. Owner UI creates grant for A with read/logs/author/plan/apply and expiry; exports standard JSON entry command+args with no credentials. Standard client launches MCP executable with absolute app-root/grant-id. Initialize, initialized, tools/list and tools/call follow [wire contract](contracts/mcp.md). Second independent SDK client uses same standard transport with separately issued grant. No direct SSH/Local API/sdk-specific shortcut. Executable identity mismatch, invalid proof, revoked/expired grant and cross-workspace cases fail before data access.

## US1 — common reads

Use MCP tools to list servers, connect A, state_get and logs_read with limit100, filters and cursor. UI must show same identity/time/source. Denied server B is absent and direct IDs return FORBIDDEN. Check unknown/changed host key, server unreachable, denied journald, malformed/oversize lines, source gap, cursor expiry, pause/disconnect and revision change while reply delayed. Two clients+UI share≤2SSH and8sessions, log ring500/server, record64KiB, aggregate64MiB. Revoke grant while delayed read in flight: no late data output. Close UI while MCP owns reading: session remains; close MCP: its interest released, durable jobs unaffected.

## US2 — author profiles

Before creating any server, owner issues author-only grant with serverIds=[]; client must author profiles while all server/read/apply tools remain forbidden. Then create format1 `system.motd` config_file profile with text parameter; get revision1/digest; update CAS to revision2; compare; failed competing CAS leaves both accepted history and no lost head. Validation rejects unknown fields, invalid refs/ranges, secret-shaped fields, Jinja, arbitrary paths/units/modules, NetBird references and oversized body. Archive blocks new plan, keeps historical revisions/jobs. Save/restart both clients: same profile IDs/body/digests, no Ansible prerequisite for authoring.

## US3 — real execution and recovery

```powershell
pwsh -File tools/test-mcp-vm.ps1 -FixtureManifest <owned-disposable-vm.private.json>
```

Harness must reject non-owned/non-disposable fixture and any target loaded from user's profiles, provision only this explicitly selected disposable systemd Docker fixture (or owned VM), retain process/container/VM ownership and synthetic credentials, never publish private fixture. Fixture manifest requires format1, disposable true, unique fixture ID, host/port/user/key reference, expected host fingerprint, owned container ID plus Docker context (or owned VM identity), approved cleanup scope; no ambient target discovery. Test actual deployed executor/runtime lock hash.

Through actual MCP bridge/UI:

1. Create profile, immutable plan, owner delegation to exact digest/A/parameter enum. Apply twice with same requestId and again new ID for same plan: same job, one file change. Read drift, externally modify fixture file as harness, observe drift; no automatic repair.
2. Test identical-content A/r1→A/r2 (including metadata-only edit) and A/r1→B/r1: tuple-based delegation rejects both while already-admitted A/r1 remains bound. Test forged tuple mismatch and out-of-scope server/parameter/revision/expired grant/delegation; owner approval request and deny/approve. AI cannot call grant/trust/approve management.
3. Qualified clean PostgreSQL16 and ClickHouse recipes each install exact package/dependency pins, preserve unrelated sentinel/NetBird fixture and have local-only listener/active unit/SELECT1. Existing config/data/package, missing SSE4.2, unsigned/missing package, apt drift/downgrade/unrelated transaction block without effect.
4. Exercise settings file/service profiles after qualification, source/unit dependency conflicts, parser/post-check failure. UI and MCP show exact plan/job/events and desired vs observed.
5. Crash locald/bridge/supervisor before and after durable admission/step launch/result; drop acknowledgement, restart fixture container/init (or reboot owned VM); record any host kernel reboot separately, second-controller race/alias SSH profile, revoke/cancel at step barriers, unavailable runtime/disk quota. Receipt/unknown retain occupancy; reconciliation never reruns playbook. Current committed step can finish, no next effect after revoke.
6. Disconnect active MCP and close UI; job state survives. Reopen/recover explicitly, no automatic replay. Seeded passwords/private keys/client secret markers absent from stdout/errors/progress/profile bodies/ordinary files and generated Ansible args.

Capture separate evidence for Windows/native bridge, wire client1/client2, migration, each real recipe/systemd Docker or VM, denial/cancel/recovery and UI sizes/themes (1100×760,800×600,360×800,390×800). The user authorized Docker on GitHub runners for disposable execution acceptance. A real systemd Docker fixture may qualify application, installation, service and durable recovery scenarios; mocks cannot. Record container init restart separately from host kernel reboot and never report one as the other. Host-kernel-specific cases require separate evidence if exercised. Preserve failed evidence and exact missing prerequisite instead of passing a reduced suite.


## Hosted automation

Windows native owner trust probe tests additionally use a disposable loopback SSH server with an ephemeral in-memory RSA key. Prepare Python3.12.10 x64 with [the fixture setup script](../../tools/prepare-trust-probe-fixture.ps1), which installs only the exact hash-locked Windows wheels from [the fixture requirements](../../tools/trust-probe-fixture-requirements.txt) into `.local/trust-probe-python`. Set `SERVERDECK_TRUST_FIXTURE_PYTHON` to the returned absolute executable before native tests. Both Windows workflows perform this setup. This test-only dependency is absent from the product bundle: the fixture accepts only loopback connections, rejects every authentication method and exposes only its generated public fingerprint and counters. Successful owner probes must match that actual SSH fingerprint, drain the physical transport before challenge publication and show zero authentication attempts. These cases do not establish trust confirmation, remote execution or full release acceptance.

[MCP automatic checks](../../.github/workflows/mcp.yml) runs Windows source-built native/root/package checks and [Docker prerequisites](../../tools/test-executor-container.sh) on an isolated Ubuntu runner. The Docker job currently proves Python3.12/python3-apt, hash-locked Ansible, systemd PID1, SSH service and persistent state across container restart. It does not yet prove the unimplemented privileged executor or installation recipes. No repository secrets, user profiles or stored server credentials are supplied. Extend this same disposable fixture for T026/T035 acceptance as the executor is implemented.


First hosted prerequisite result: [run39555867561](https://github.com/unng-lab/serverdeck/actions/runs/39555867561), source ecf8d534efd2dbea85a0b5546cb450d4a6484066, job119075366238 succeeded in34seconds. The real Docker job reports ansible-core2.21.5, pip check clean, systemd=true, containerRestart=true, kernelReboot=false, executorAcceptance=false. Windows job was still running when this result was recorded. This result closes no executor/recipe/bridge acceptance gate.

## Shared format3 control composition qualification (T168)

Hosted test-failure proofs may include nullable `fixtureExitCode` with `failureKind: fixture-exit` for the fixed trusted-client native fixture when its hashed-source, exact-case-bound Dart assertion reports a nonzero process exit. Values retain the reporter's signed32 or unsigned32 representation. This is the server fixture's observed exit assertion, not a diagnosis of the inner client or evidence of a native crash. Other failures retain null. Raw reporter messages, process output and private paths stay local; these diagnostic fields never establish qualification or activation (T169).

This is the expected validation procedure for the [composition contract](contracts/trusted-services.md), not a claim that its implementation or startup is complete. Use only owned temporary same-build format3 native fixtures and the protected schema3 store; no saved server profiles. The existing loopback SSH fixture requires the hash-locked Python environment prepared by `tools/prepare-trust-probe-fixture.ps1`.

From `packages/serverdeck_locald`, run the new `dart test test/mcp/trusted_services_native_test.dart` and the existing production wire suite `dart test test/mcp/trusted_channel_native_test.dart`. The implementation adds the first command; absence of that test is incomplete T168. Verify shared owner/MCP catalog state, all25 owner routes, custody/role/attach refusals, no effect from stopped prepared grants, common foundation/trust receipts and real drain boundaries. Existing gate observation/owner-service probe builds must retain their explicit compile-time-only selection and ordinary-build refusal. Source-qualified DLL and full Windows/Linux startup/executor acceptance remain separate gates.

Run affected analyzers/component regressions, literal root `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`, `lychee "specs/**/*.md"` and independent review per AGENTS.md. A failed close must leave outer storage/key/mutex ownership retained; a successful component result does not qualify the full021 product.
