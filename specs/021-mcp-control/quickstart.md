# Quickstart and acceptance — 021

## Current unit-widget commands

For PR3/source-only preview `0.2.0-preview.1+9`, follow
[Constitution4.0.0/VII and current-stage scope](../003-design-system/plan.md#unit-widget-stage-2026-10-27).
Only static and pure unit/widget checks run locally and in automatic CI.
This block takes precedence over native/integration/SSH/container/full-cold
commands below, which are retained as **future qualification procedures**;
they require a new user instruction before execution.

With the pinned Flutter3.47.7/Dart3.13.5 SDK and locked dependencies, from root:

```powershell
$env:SERVERDECK_NATIVE_CONTROL_RED = '0'
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --reporter expanded
Push-Location packages/serverdeck_protocol
try { dart analyze; dart test --reporter expanded } finally { Pop-Location }
Push-Location packages/serverdeck_windows
try { dart analyze } finally { Pop-Location }
Push-Location packages/serverdeck_locald
try {
  dart analyze
  dart test test/server_peer_coordination_test.dart --reporter expanded
} finally { Pop-Location }
lychee "specs/**/*.md"
```

Record every process exit separately; `try/finally` does not assert Dart
success. Root tests mean ordinary `test/` unit/contract/widget tests, no
`integration_test` or capture flags. Preserve the expected opt-in capture skip.
The full protocol suite and selected queue suite use pure fixtures; do not
run whole locald/Windows/MCP suites or `test-mcp.ps1` for this unit stage.
A filename or portable label alone does not make SSH/process/FFI tests pure.

After these checks, complete a fresh frozen-input independent policy/spec/
workflow review/fix loop. Automatic push/PR `unit-widget-checks` success is
a separate exact-source external gate under003; old native jobs remain
not-selected/skipped, without native acceptance. Default manual profile is
unit-widget; explicit `native-full` and Foundation workflows are future
qualification and are not dispatched now. Actual results are recorded in
[003 evidence](../003-design-system/evidence.md#current-unit-widget-evidence-2026-10-27).
Original T207 full-native acceptance and all complete product/native
qualification remain open.

This guide separates available source entry points from required acceptance.
For current build and client configuration commands, use the
[MCP setup guide](../../docs/development/mcp.md). Record actual commands/results
per task; source presence never counts as an executed fixture check.

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

Build the complete compatible format3 bundle with `pwsh -File tools/run-serverdeck.ps1 -Configuration Debug -BuildOnly` (not build-mcp.ps1 alone), start UI through the same entry without BuildOnly, create synthetic target/credentials and owner-confirm exact SSH fingerprint. Owner UI creates grant for A with read/logs/author/plan/apply and expiry; exports standard JSON entry command+args with no credentials. Standard client launches MCP executable with absolute app-root/grant-id. Initialize, initialized, tools/list and tools/call follow [wire contract](contracts/mcp.md). Second independent SDK client uses same standard transport with separately issued grant. No direct SSH/Local API/sdk-specific shortcut. Executable identity mismatch, invalid proof, revoked/expired grant and cross-workspace cases fail before data access. When a client Job Object refuses safe breakaway for a cold launch, start the normal UI/locald first; MCP must refuse the cold launch rather than inherit kill-on-close.

## US1 — common reads

Use MCP tools to list servers, connect A, state_get and logs_read with limit100, filters and cursor. UI must show same identity/time/source. Denied server B is absent and direct IDs return FORBIDDEN. Check unknown/changed host key, server unreachable, denied journald, malformed/oversize lines, source gap, cursor expiry, pause/disconnect and revision change while reply delayed. Two clients+UI share≤2SSH and8sessions, log ring500/server, record64KiB, aggregate64MiB. Revoke grant while delayed read in flight: no late data output. Close UI while MCP owns reading: session remains; close MCP: its interest released, durable jobs unaffected.

## US2 — author profiles

Before creating any server, owner issues author-only grant with serverIds=[]; client must author profiles while all server/read/apply tools remain forbidden. Then create format1 `system.motd` config_file profile with text parameter; get revision1/digest; update CAS to revision2; compare; failed competing CAS leaves both accepted history and no lost head. Validation rejects unknown fields, invalid refs/ranges, secret-shaped fields, Jinja, arbitrary paths/units/modules, NetBird references and oversized body. Archive blocks new plan, keeps historical revisions/jobs. Save/restart both clients: same profile IDs/body/digests, no Ansible prerequisite for authoring.

## US3 — real execution and recovery

```powershell
pwsh -File tools/test-mcp-vm.ps1 -Mode Create -FixtureRoot <owned-fixture-root>
pwsh -File tools/test-mcp-vm.ps1 -Mode Enroll -FixtureRoot <owned-fixture-root> -WorkspaceId <actual-owner-workspace-uuid>
pwsh -File tools/test-mcp-vm.ps1 -Mode Remove -FixtureRoot <owned-fixture-root>
```

These are implemented setup subcommands, not a complete acceptance command.
The owner/client core scenario has a source entry
`pwsh -File tools/run-mcp-scenario.ps1`; it builds the actual native integration
bundle, prepares two locked clients, creates a private fixture, takes the
workspace UUID from the real UI and coordinates enrollment. It has not yet run.
Its proof explicitly has fullAcceptance=false: the recipe/fault matrix and full
test-mcp.ps1 aggregation remain T189 work. FixtureRoot must be a
fresh protected direct child `.local/mcp-acceptance-<32-hex-ID>` with an
owner-only format1 `fixture.json` containing the matching fixtureId, prepared
using tools/mcp-fixture.ps1. Create requires a local otherwise idle disposable
Docker Linux engine, records exact nonce-labelled container/image identity in
docker.json and stores synthetic SSH credentials only in CurrentUser DPAPI
seed.dpapi. Enroll requires the UUID from the actual authenticated owner
workspace and records executor identity in enrolled.json. Remove revalidates
the exact owned container/image before removal. No saved server target or
remote Docker context is accepted. Never publish the private fixture or treat
setup completion as tested execution. The acceptance scenario must compare
actual deployed executor/runtime lock hashes and SSH fingerprint before use.

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

[MCP automatic checks](../../.github/workflows/mcp.yml) runs Windows source-built native/root/package checks and [Docker prerequisites](../../tools/test-executor-container.sh) on an isolated Ubuntu runner. The Docker job currently proves Python3.12/python3-apt, hash-locked Ansible, systemd PID1, SSH service and persistent state across container restart. It does not establish acceptance of the current privileged executor or installation recipes. No repository secrets, user profiles or stored server credentials are supplied. Full T026/T035 executor scenarios remain required beyond this prerequisite job.


First hosted prerequisite result: [run39555867561](https://github.com/unng-lab/serverdeck/actions/runs/39555867561), source ecf8d534efd2dbea85a0b5546cb450d4a6484066, job119075366238 succeeded in34seconds. The real Docker job reports ansible-core2.21.5, pip check clean, systemd=true, containerRestart=true, kernelReboot=false, executorAcceptance=false. Windows job was still running when this result was recorded. This result closes no executor/recipe/bridge acceptance gate.

## Shared format3 control composition qualification (T168)

Hosted test-failure proofs may include nullable `fixtureExitCode` with `failureKind: fixture-exit` for the fixed trusted-client native fixture when its hashed-source, exact-case-bound Dart assertion reports a nonzero process exit. Values retain the reporter's signed32 or unsigned32 representation. This is the server fixture's observed exit assertion, not a diagnosis of the inner client or evidence of a native crash. Other failures retain null. Raw reporter messages, process output and private paths stay local; these diagnostic fields never establish qualification or activation (T169).

This is the expected validation procedure for the [composition contract](contracts/trusted-services.md), not a claim that its implementation or startup is complete. Use only owned temporary same-build format3 native fixtures and the protected schema3 store; no saved server profiles. The existing loopback SSH fixture requires the hash-locked Python environment prepared by `tools/prepare-trust-probe-fixture.ps1`.

From `packages/serverdeck_locald`, run the new `dart test test/mcp/trusted_services_native_test.dart` and the existing production wire suite `dart test test/mcp/trusted_channel_native_test.dart`. The implementation adds the first command; absence of that test is incomplete T168. Verify shared owner/MCP catalog state, all25 owner routes, custody/role/attach refusals, no effect from stopped prepared grants, common foundation/trust receipts and real drain boundaries. Existing gate observation/owner-service probe builds must retain their explicit compile-time-only selection and ordinary-build refusal. Source-qualified DLL and full Windows/Linux startup/executor acceptance remain separate gates.

Run affected analyzers/component regressions, literal root `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`, `lychee "specs/**/*.md"` and independent review per AGENTS.md. A failed close must leave outer storage/key/mutex ownership retained; a successful component result does not qualify the full021 product.

## Native control correction validation

T204–T207 validate [accepted-peer control coordination](contracts/native-control.md).
Use the pinned Flutter3.47.7/Dart3.13.5 foundation SDK and existing isolated
Windows native fixtures; do not use an installed user's service or real servers.
From `packages/serverdeck_locald`, run the new pure
`dart test test/server_peer_coordination_test.dart`, then affected real
`test/mcp/operational_auth_native_test.dart`, `trusted_auth_native_test.dart`,
`gateway_native_test.dart`, channel and grant suites serially. Preserve original
gateway16/17/shared cancellation and channel17-reply oracles. From
`packages/serverdeck_windows`, run operational/trusted worker native regressions
serially; direct fourth ordinary native admission must still return RESOURCE_LIMIT.
The contract describes observation-control occupancy and all refusal/expiry/
physical-drain outcomes. Pure injected completions do not establish native proof.
Mandatory root format/analyze/test, affected package analysis, strict spec links,
fresh independent review and exact-source cold CI remain required. Actual CI8
causality and successful correction are not inferred from the planned scenarios.


T212 adds first-RPC failed-open terminal header/body drain cases for both formats
and epoch peer.write admission/throwing-observer retention cases to the existing
owned Windows actors. Run old-source RED and new-source GREEN only against
independently preserved source snapshots, with the same genuine fixtures; keep
normal17/16/native3 and original deadlines. Complete all affected channel modes,
the full Windows package suite (current168 plus the new cases), controlled
diagnostics (current18), root mandatory/package checks and strict links, then a
completed fresh independent code/spec review. The draft proposal has no runtime
evidence. The current frozen run must finish before applying the specification
amendment, and strict links plus a fresh independent readiness review precede
production implementation. An unrelated local resolver-host crash is separate
evidence, not a proved product fault or an accepted workaround.
