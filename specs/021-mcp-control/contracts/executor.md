# Executor protocol and Linux runtime v1

[Plan](../plan.md), [profiles](profiles.md), [model](../data-model.md), [MCP](mcp.md).

## Packaging and ownership

Separate owner-provisioned Ubuntu24.04 amd64/systemd package: `/usr/libexec/serverdeck-executor-bridge`, supervisor code and fixed compiler/probes under `/usr/lib/serverdeck-executor`, root-owned venv `/opt/serverdeck-executor/venv`, root config `/etc/serverdeck-executor`, durable spool `/var/lib/serverdeck-executor`, runtime socket `/run/serverdeck-executor/control.sock`. Directories root0700 except executable ancestors0755, files0600/executable0755; no writable symlink/reparse parents. One canonical namespace per host OS; container/chroot duplicate state unsupported. Root install host UUIDv4 generated once, preserved upgrade/uninstall does not silently delete active/unknown receipts. Registry controller public IDs/admin-approved SSH Unix users; no public TCP listener.

Ansible-core==2.21.5, Python3.12 venv with fully hash-locked wheel closure, `/usr/bin/python3` and python3-apt supplied by administrator. systemd, sudo, dpkg/apt tools, journald available. Pin and lock hash part of runtime handshake. No runtime downloads/apt preparation on read/apply. Package includes systemd service `serverdeck-executor.service`: restart only supervisor receipt-recovery, never re-execute uncertain steps. Supervisor startup marks any nonterminal launch with ambiguous process state unknown and retains writer occupancy. Job children in tracked systemd cgroup; new supervisor must prove old children stopped before final state/slot release. Changing host UUID while receipt exists blocks.

Bridge is fixed allowlisted sudo command (no args) for explicitly enrolled Unix account. It validates protocol and forwards to local root Unix socket; sudo -n, no password prompt/TTY, no arbitrary executable/path from payload. Locald SSH opens literal `sudo -n /usr/libexec/serverdeck-executor-bridge` with request in stdin. Regular read-only adapters do not need this helper. Operator with unconstrained root/sudo remains outside confinement model; ServerDeck never hands this session to AI.

## Framing, session and methods

Length-prefixed uint32 big-endian UTF8 strict JSON, request≤256KiB, response≤8MiB, depth16, duplicate/unknown fields invalid, no secret echo. Version1, request{v:1,id:UUID,method,params}; response{id,result} or{id,error:{code,retry}}. Entire bridge request deadline5s except preflight≤30s via stable handle; result status polls≤5s. Same version/digest errors fail before admission; no legacy fallback.

Methods:

- hello{controllerId:UUID,workspaceId:UUID}: hostId,runtimeVersion,lockDigest,registryDigest,compilerDigest,bridgeDigest,bootIdHash,capabilities. SSH trust plus root-installed expected bridge/registry hashes checked against release descriptor; enrollment owner confirms hostId+fingerprint binding. Different fingerprint/hostId requires owner trust review. One persistent workspace is one controller: controllerId equals its existing workspaceId across UI/MCP clients and process generations, never a fresh process or AI-client UUID. runtimeVersion is the base semantic version plus `+` and the SHA256 canonical `{baseVersion,lockDigest,bridgeDigest,files}` where files contains the complete fixed thirteen-module executor source inventory (including qualification.py, apt.py and apt_gate.py). This makes an altered supervisor/probe/runner build invalidate a captured plan even when compiler/lock bytes alone did not change. Root validates all actual source/bridge/lock bytes before handshake; the owner application compares the matching qualified bundled descriptor before confirming enrollment. A generated digest alone is not source/runtime qualification.
- observe{resourceId,target,expectedHostId}: fixed read-only registered managed resource probe. target has the same exact binding as preflight, workspace is enrolled, expectedHostId must match root install identity. Returns exactly `{observation}` with the full schema3 [ManagedResourceObservation](plans.md); known facts come from actual fixed probes, no path/command/SQL argument. Unsupported/denied/unqualified facts return a fixed error, never guessed values. At most128KiB for an observation. Locald verifies the complete captured target, host/registry/resource and current native authorization before publication.
- preflight{operationId,profileBody,profileDigest,parameters,expectedHostId,target}: pure probes only; returns operationId immediately, followed by preflight_get{operationId}. `target` is exactly `{workspaceId,serverId,targetRevision,connectionRevision,accessRevision,trustRevision}`, captured from the current locald target before dispatch. UUIDs/counters and schema3 inequalities follow [plans](plans.md); workspaceId must match the enrolled controller workspace. Root uses this metadata with its actual observed values/host/registry to compute the same full resource fingerprints as locald. These caller-supplied identity fields are bindings, never proof of SSH trust, current permission or factual observations. Result immutable planFacts/digest/reasons/derived effect list/checks. Reused operationId different inputs conflict; read ops expire5min. Submit must retain the exact target from this cached evidence; locald checks it against its current captured target before admission.
- submit{jobId,attemptId,planDigest,profileId,profileRevision,profileBody,profileDigest,parameters,preflightDigest,expectedHostId,controllerId,workspaceId}: durable queued receipt only; no effect until step authority. Accepted input includes exact recipe descriptor digest/resolved packages when needed. Request controller/workspace bound to actual enrolled SSH caller; other controller status denied. Receipt before acknowledgement.
- status{attemptId,afterSequence?:int,limit?:1..100 default50}: exact result `{attemptId,state,stepIndex,authorizationEpoch,sequence,events,checks,needsAuthorization,failureCode,droppedEvents}`. authorizationEpoch is the persisted last accepted step epoch, initially0; a fresh unused challenge uses exactly the next epoch. Checks are exact `{checkId,passed}`; events are `{sequence,at,kind,stepId,code}`. Owner recovery uses same enrolled controller identity; foreign controller sees HOST_BUSY only, not private plan/logs. Locald validates every referenced effect/check/challenge against its immutable program and rejects backwards sequence/step/epoch.
- authorize_step{attemptId,stepId,planDigest,challenge32bytes,authorizationEpoch:int,expiresAt}: one-step authority. Challenge generated/persisted supervisor for next effect; unused challenge only, expires≤5s after issuance, server monotonic clock bounds and wall clock sanity. Locald checks live grant/delegation/target/trust, CAS challenge then sends. Supervisor verifies same enrolled controller/workspace/current socket stream, target/plan/step and expiry. Durable launch commitment linearizes step beginning; grant revoke after it stops subsequent effects, not current atomic operation. Each invocation at most one Ansible effect, no unbounded playbook continuation. No grant secret/SSH credential in message.
- cancel{attemptId,requestId}: mark stop requested. Before commitment→cancelled/no effects; active step finishes safe boundary; no kill apt/dpkg, rollback promise or deletion. Repeated request id same result.
- reconcile{attemptId}: read-only receipt/process/cgroup/boot and factual probes, never Ansible run. Exact result `{attemptId,state,childrenStopped,sequence}`. A queued/waiting receipt with no committed child is journalled cancelled or cancelled-partial and releases root occupancy; it cannot resume a next step. An actual active child remains unproved, with childrenStopped false. If effect happened but required health failed→failed with effects, not succeeded; ambiguous ongoing process stays unknown/occupied.

Controller polling1s while active, sends authorize only for challenge and current policy; no automatic permission resurrection after owner restart. Session loss: current admitted step may complete, next step remains waiting max60s then cancelled-partial if prior outcome proven; uncertain current result→unknown. Reconnect may continue only same durable job and unused current step after policy checks, never automatically run an already committed step. Explicit owner/job recovery is required after locald generation change. Host receipt maps immutable planDigest to one job permanently while retained, so new attempt/request IDs cannot replay that plan. Requests with mismatched IDs/digest conflict.

## Canonical cgroup identity in disposable systemd containers

The same systemd manager resolves system.slice ControlGroup before matching
executor child, native gate peer or canonical database membership. Exact
membership is that slice path plus the fixed generated/canonical unit name.
On a normal host it remains /system.slice/unit; a delegated container can add
its real manager prefix. This is not a caller-selected namespace/path flag and
does not accept substring or basename-only membership. The kernel /proc peer
membership, manager service ControlGroup, receipt unit and filesystem cgroup
stop proof must still agree exactly. Failed resolution refuses qualification or
gate admission. Source support is not container/runtime acceptance evidence.

## NetBird preservation fence

Catalog pins and native APT protocol actions reject netbird and all netbird-*
client packages; the public protected-package digest covers the same family.
For an install plan, root preflight additionally captures a private preservation
digest and rechecks it before returning evidence. It binds canonical
netbird.service load/active/start identity, root-owned fragment/drop-ins,
resolved unit environment/file inputs, and the standard /etc/netbird and
/var/lib/netbird configuration/state trees plus /etc/sysconfig/netbird.
Trees are bounded512 entries/eight levels,16MiB per file/128MiB total; unsafe
custody, unsupported inode types or inconsistent reads fail qualification.
Adding/removing a root is a change. Only private digests are retained/compared;
no NetBird configuration, environment values, keys or state is returned to AI.

For an active root daemon, bounded actual process environment/cmdline and the
unit inputs are checked for config/state selectors. Explicit selected paths
must remain normalized beneath the two captured standard trees; external
overrides require operator qualification instead of an unobserved success.
Unit start identity is stable across the snapshot. Legitimate concurrent daemon
changes may cause CONFLICT; they do not authorize clearing or repairing NetBird.

The immutable root execution document carries netbirdPreservationDigest into
the source-bound private APT context. Revalidation checks it before each step;
the native-lock gate checks it before admitting dpkg; private recipe-check
compares it after APT and before database startup; factual installation
postchecks compare it again before ownership/success publication. A changed or
missing fence never becomes success, and no path to NetBird mutation is added.
This source path still requires actual deferred runtime/failure qualification.

## Terminal private-work cleanup

The root supervisor schedules at most one cleanup owner after a durable job is
succeeded/failed/cancelled/cancelled-partial, has finishedAt, has released its
host occupancy and has no running task/reconciliation or physical output drain.
It never cleans active/unknown work, orphan directories without a receipt,
journal/snapshots, immutable execution facts, outcomes or owned-resource bindings.
No AI-facing deletion/path/retention override is added.

Only work-directory names derived from the retained attempt UUID and immutable
effect IDs are eligible. Each existing target requires actual systemd/cgroup
stop proof before inspection and again immediately before deletion. The parent
is pinned by a directory descriptor; target inode/device must remain unchanged.
Validation accepts only root-owned directories/regular files/symlinks, rejects
hardlinked files and other inode types, bounds traversal at4096 entries,
128MiB and16 levels, and requires every opened directory to retain the same
Linux mount ID as the parent (including protection against same-device bind
mounts). Walk errors abort inspection. The fd-based symlink-resistant Python
rmtree implementation removes only the generated name relative to this pinned
parent, then fsyncs it; symlink targets are never traversed. Unsupported platform
support, unproved stop, unusual custody or partial failure retains remaining
evidence and retries after60s without changing job outcome. Logical cancellation
joins the actual filesystem worker. Cleanup may run again after restart; absent
already-cleaned targets are harmless and permanent receipts still deny replay.

## Environment custody

Unit qualification binds resolved Environment, PassEnvironment, UnsetEnvironment
and every EnvironmentFiles entry, including optional absence. The systemd255
printer emits one line per file; repeated names are not collapsed into a map.
At most16 literal normalized /etc paths are accepted, each root-owned with
nonwritable/no-symlink ancestry and64KiB content bound. Unsupported escaped,
glob or unprintable paths require operator qualification. Environment contents
remain private: only the resulting baseline digest crosses the RPC boundary.
PostgreSQL additionally binds optional /etc/postgresql/16/main/environment,
which cluster startup can read independently of systemd. A changed environment
input invalidates the old qualification and plan. The repeated-line format is
defined by the [systemd255 source](https://github.com/systemd/systemd/blob/v255/src/systemctl/systemctl-show.c).

## Administrator catalog provisioning

The explicit root installer accepts --recipe-catalog with a root-owned JSON
file containing the closed digest-keyed map of0..2 complete pinned descriptors.
This is not a bridge/MCP method and grants no shell or repository preparation
operation to the AI. Existing registry qualifications are preserved.

With supervisor inactive and the actual root journal writer lock held, it
validates the candidate and stages fixed protected catalog-candidate.json in
/etc/serverdeck-executor. Source-bound apt-probe --qualify-catalog accepts only
the expected SHA256 and reads that fixed file. In system Python it checks each
singleton and both possible two-recipe orders through the read-only cumulative
resolver, requires unchanged complete packages and rechecks the candidate digest.
It returns only candidate/package-snapshot digests. The parent independently
compares these and its before/after package snapshots before selecting the map
for resources.json and the matching release registry digest. Provisioning has
a120-second helper budget and performs no update, download, installation or
service start. All preflight and native-lock gate checks remain mandatory on
each later apply.

This is explicit stopped-service maintenance. Failure does not authorize the
candidate. An interrupted installer may leave source/registry/release mismatch,
which prevents startup; protected pending files remain evidence for operator
recovery. Host UUID and journal receipts are preserved. Current source still
enables the install code only with a prepared nonempty catalog; each later call
still requires fresh preflight/authority/native-lock gate and factual postchecks.
This CLI alone establishes no runtime acceptance.

## Recipe catalog metadata

Explicit administrator preparation is `executor/packaging/prepare-apt.py`
with protected --sources, --keyring, --request and --output files. Only an
explicit --refresh runs isolated apt-get update (Error-Mode=any, bounded120s/
1MiB output); no package commit, version selection, key download, enrollment
or service start. Existing different protected input files fail unchanged.
This source CLI is not installed or exposed through the bridge/MCP. The
read-only catalog.py path still requires already prepared metadata and never
refreshes it. Both produce exact root-owned digest-keyed descriptors, which
require the existing stopped-service installer publication and runtime gates.

APT public trust anchor is the fixed root0644 file
`/etc/apt/keyrings/serverdeck-executor.gpg` under a root0755 parent. This is the
only additional public configuration artifact: it contains public signing keys,
no credentials. Private executor config/enrollment remain root0700/0600.
The fixed APT config, each sources.list signed-by, root gpgv verifier and native
transaction gate all bind this same path/bytes/metadata. The gate whitelist
accepts only this exact keyring path; no caller-selected key file or directory.
Retain APT's _apt sandbox and normal signature checks. Qualification must prove
actual _apt readability and refusal after key/path/permissions are changed.

For each verified signed InRelease, require exactly one timezone-aware Date,
not over300seconds in the future, and at most one Valid-Until. When present,
Valid-Until must be timezone-aware, later than Date and strictly later than
the current UTC time. Reject malformed/empty/duplicate fields, case-insensitively.
Without Valid-Until, do not invent a maximum age: Ubuntu's immutable noble base
release is dated2024-04-25. Its exact signed/index bytes still belong to the
approved descriptor and every preflight/gate checks them. No expiry field is
not a promise of up-to-date security fixes; no implicit latest/update is added.
These semantics follow [APT](https://manpages.debian.org/apt/apt.conf.5.en.html)
and its [keyring access requirement](https://manpages.debian.org/testing/apt/sources.list.5.en.html).

The additional read-only method `recipes{target,expectedHostId}` uses the same
workspace/server/counter tuple as observe and is bound to the enrolled caller.
Its result is exactly `{hostId,runtimeVersion,registryDigest,environment,
installEnabled,recipes,unavailable,prerequisites}`. recipes contains0..2 complete
immutable descriptors with initialSettings, unique product IDs and recomputed
descriptor digests. unavailable contains each unavailable product exactly once
as `{id:postgresql16|clickhouse,code:QUALIFICATION_REQUIRED}`; if installation is
disabled, both products are unavailable even when metadata exists. prerequisites
is exactly `{requiresFreshInstall:true,requiresPreflight:true,metadataRefresh:false}`
and describes required admission, never a passed host check. No APT cache
operation, update, download, package snapshot or simulation runs for this read.
Fresh target-specific installation evidence is obtained by plan preflight. No
runnable permission follows catalog membership alone.

## Writer and persistence

Root install UUID identifies physical host in executor, one spool/one writer table for all SSH accounts/controllers/profiles. `flock` prevents concurrent supervisors, durable occupied receipt prevents crash/reboot unlocking. Admission atomically fsyncs job input, plan mapping, writer occupied, event seq before returning. Each launch writes launch_committed and fsyncs before subprocess; a crash in gap is unknown, never auto-retry. Append-only journal records JSON length/checksum plus fsync; partial tail retained and fail-closed unknown, no skip/resume writes. Atomic snapshot tmp+fsync+rename+directory fsync, checksums/version required. Spool disk full→no new launch, state blocked; original files retained. Files cannot be written from caller paths.

Before any new effect revalidate preconditions, authority and registered scope. Locald also holds matching hostId writer admission in Isar; host prevents other controllers after stale local admission. Two device race→one accepted, other HOST_BUSY; no queues waiting for unknown host. Active runtime max1job/host, 32steps/job; each effect max30min, job max2h. Exceed limit does not kill unsafe package operation: mark timeout/unknown, retain cgroup/lock and forbid next step. Manual owner can inspect/recover via same status/reconcile, no force-unlock API. Terminal proven receipt releases occupied writer transaction only after checks and proven no continuing child; retain receipt30days, up to1000 terminal; limit blocks new jobs if safe GC unavailable. Active/unknown never TTL-unlocked/GCed. Events10000/job≤4KiB; overflow drops progress only, persists outcome/seq and count. Disk budget256MiB excluding installed runtime/packages; refuse before launch below16MiB free or quota, no deleting active evidence.

## Trusted execution

Supervisor prepares root0700 single-use per-attempt workdir; clean environment fixed PATH/system locale/HOME/ANSIBLE_CONFIG/plugin paths, no PYTHONPATH/PYTHONHOME/LD_PRELOAD/user config. Only bundled builtin modules and fixed callback that emits allowlisted bounded step events, no raw module stdout into public response. Process stdout/stderr bounded1MiB discard excess with flag; diagnostics fixed code, not captured raw output. Generated JSON inputs are nonsecret; remove terminal temp artifacts only after outcome persisted. Configuration renderer paths/root modes are fixed resource registry values. Reject changed unit/dependencies/parent config digests before effect. Ansible and known maintainer scripts are trusted package code, not code supplied by MCP author.

Apt flags fixed: auto_install_module_deps=false, update_cache=false, cache_valid_time=0, force_apt_get=true, allow_downgrade=false, allow_unauthenticated=false, allow_change_held_packages=false, fail_on_autoremove=true, autoremove/autoclean/clean=false, lock_timeout=1, state=present, no upgrade/default_release/arbitrary dpkg_options. Existing apt lists and python3-apt prechecked. Apt owns native locks; never retain an outer dpkg/frontend lock across Ansible launch. A fixed root-owned Pre-Install-Pkgs protocol3 gate compares approved complete snapshot and exact transaction before dpkg while apt retains frontend lock; never accept unrelated installed package changes, repository updates, downgrade or NetBird effects. Trusted probes enforce initial local-only listeners, exact versions, resource-owned service state and SQL.

When one profile installs both products, the root read-only resolver processes
recipes in source-step order in one isolated python-apt process. All shared pins
must agree in name, architecture, exact version and archive digest; conflicting
pins block the plan. Each cumulative resolver transaction must equal exactly the
declared pin union so far, with no existing installed-package changes. Shared
additions belong to their first recipe only. Every install effect retains a
private `{recipeDigest,packages,expectedPackages,pins,files,transactionDigest}`
entry keyed by compiled effect ID: packages is the full expected state before
that effect, expectedPackages is its full state after, pins contains only new
additions for that effect, and transactionDigest binds those additions plus
configure-new actions. The second gate therefore validates the first recipe's
completed package additions as part of its baseline, rather than incorrectly
requiring the original pre-install snapshot. Read-only resolution performs no
metadata refresh, download or dpkg write. Public capsule binds original and
final package snapshots and the complete selected immutable recipe descriptors.
Pre-step revalidation advances its expected snapshot only across earlier
completed install effects; a partial/unknown effect never advances it.

PostgreSQL probe: fixed runuser postgres psql -X -w -A -t -d postgres -c SELECT1 via local peer, fixed safe args, no AI SQL; ClickHouse: bundled read-only local HTTP SELECT1 probe to127.0.0.1:8123 with no URL/query from caller, default account only during fresh local-only qualification. Existing auth/custom config blocks fresh install; secret-bearing auth changes not profile format1. Probe timeout5s, stdout≤4KiB, parsed expected scalar1, version/resource settings checks separate. Unknown/failure/unsupported never succeeded. No raw SQL results or password to MCP.

The trusted install effect's literal task sequence is: fixed isolated APT task
with noninteractive environment and the pre-existing deny-start policy; protect
the fixed configuration directories; write fixed initial parent/auth files and
the fragment rendered from descriptor.initialSettings; run the source-bound
private recipe-check; start and enable the canonical unit. No AI command/path,
handler, loop or arbitrary task is introduced. PostgreSQL is local peer only,
TCP bound127.0.0.1:5432 with host authentication rejected; ClickHouse binds
127.0.0.1:8123/9000 and the initial default user is local/read-only. Existing
product/config/data and administrator/runtime unit overrides block fresh install.
The private recipe-check launcher is root0755 with literal bytes bound through
qualification.py in the release inventory; it is not a sudo/MCP entry point.
It accepts only selected recipe SHA and registry SHA, derives its attempt/step
from the actual systemd cgroup, and checks launch/program/gate evidence, complete
post-APT package digest, boot, actual catalog, exact owned file bytes/modes,
inactive service, no NetBird unit dependencies and host/canonical-unit memory
budget. PostgreSQL also runs its fixed postgres -C parser without starting a
server. Refusal stops the play before explicit service start. These checks do
not replace the mandatory live post-start SQL/listener/version checks.

Installation postchecks require the authoritative journal's matching APT gate
proof, original boot/runtime/registry and exact expected complete package state.
They verify exact initial files/ownership, active+enabled canonical service,
actual process UID/executable/config argument and systemd cgroup, owned kernel
TCP socket inodes on the declared loopback ports, local SQL health, effective
settings, PostgreSQL16 source paths or matching ClickHouse runtime version,
memory limits and unchanged NetBird package snapshot. Listener inspection is
bounded5s, proc tables8MiB each,4096 cgroup processes/16384 descriptors per
process; missing required ownership or main-PID/start instability refuses success.
Package/parent/unit evidence is checked again at the end. A successful process
exit alone never creates ownership.

Root journal state includes a closed four-resource `resources` map. Each binding
is exactly `{format:1,hostId,resourceId,recipeDigest,registryDigest,runtimeVersion,
sourceAttemptId,sourceEffectId,baselineDigest,confirmedAt}`. Both resources of a
successful recipe effect are published in the SAME fsynced journal transaction
as its checked step completion/outcome. The journal requires the source install
effect, matching owned pair, gate proof, passed recipe check and advanced step
index. Failed or unknown effects cannot publish bindings; a proved successful
recipe remains owned if cancellation or a later unrelated effect stops the job.
This root ownership is distinct from locald's success-only desired configuration.
The static resources.json and registryDigest are never rewritten by apply.
On restart root replays bindings from the journal; only matching host, current
runtime and static registry contribute baselines beside explicit administrator
qualifications. Actual observe/preflight still recompute unit/parent fingerprints
against those baselines. A runtime/catalog upgrade does not silently adopt old
bindings; it requires new supported qualification.

## APT transaction gate

Bundled `/usr/libexec/serverdeck-apt-transaction-gate` is the sole Pre-Install-Pkgs hook via fixed root-owned APT_CONFIG; disable unqualified Pre-Invoke/extra config fragments, preserve only qualified prepared sources/index paths. Protocol3/InfoFD0; unknown/malformed/empty protocol fails closed. Gate validates root/cgroup/current receipt/one-use launch context, approved baseline/index/config digests, exact addition+configure-new actions including package architecture/version/archive SHA256; remove/upgrade/downgrade/reinstall/configure-existing forbidden. Fsync successful transaction digest into receipt before returning0. Missing gate proof forbids success. Hook timeout5s/crash aborts apt; uncertainty retains job lock, never retries. External cooperating package-manager races either HOST_BUSY or gate abort before effects; root deliberately bypassing native locks outside threat model. Test actual supported Ubuntu apt hook/lock ordering and archive/architecture/snapshot race, not only simulated gate input. Maintainer scripts/triggers allowed only as declared qualified recipe effects without unrelated package versions/membership/config/NetBird change.

Execution receipt preserves exact `(profileId,profileRevision,profileDigest)` and verifies its binding to planDigest at submit. Authorization challenge/status bind the immutable receipt, not current catalog head or bodyDigest alone. Same-body new revisions/profiles cannot substitute the approved tuple; existing job receipt never follows profile head updates.
