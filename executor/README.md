# ServerDeck executor

The executor is a separately provisioned, root-owned Ubuntu 24.04 amd64/systemd
component. This directory contains its supervisor, privileged bridge and explicit
administrator installer. A checkout or application build does not install or
start them. Source implementation is not full runtime qualification.

`requirements.lock` pins the Python 3.12 Linux wheel closure for Ansible. Install
with `pip --require-hashes` only into the administrator-prepared executor venv;
runtime installation must never be triggered by an MCP read, plan or apply.
Dependency resolution does not qualify a working executor or installation recipe.

The implementation now includes strict framed JSON (`codec.py`), the closed
profile compiler and fixed renderers (`compiler.py`), append-only checksummed
host-writer persistence (`journal.py`), fixed resource probes (`probes.py`) and
a single-effect systemd/Ansible runner (`runner.py`). The locald compiler derives
the same effect/check program independently. Root preflight, the durable job
state machine, the Unix-socket supervisor and the stdin/stdout sudo bridge are
implemented in `preflight.py`, `jobs.py`, `supervisor.py` and `bridge.py`.
`packaging/` contains isolated Python launchers and the systemd unit. Source
presence is not an installed/qualified runtime: provisioning acceptance, complete locald/UI integration,
complete installation integration and recovery remain pending.
`qualification.py` now checks actual PostgreSQL parent/include/source paths,
ClickHouse parent XML, effective settings and the host/service memory budget.
Database configuration requires the corresponding administrator-captured parent
fingerprints; an absent or changed qualification refuses the plan.
`apt.py` provides isolated, read-only exact package resolution and signed index
checks; `apt_gate.py` provides the one-use protocol3 transaction gate and private
durable admission through the root supervisor. Installation code is enabled
only with an actual root-prepared catalog; every invocation still requires fresh
preflight, exact plan authority and the one-use transaction gate. Full runtime
qualification remains pending.
Root preflight now resolves both selected recipes in one isolated read-only
process, retains per-effect package/gate evidence and checks intermediate package
snapshots. Shared dependencies are introduced once; conflicting pins block plans.
The fixed install play now writes local-only parent/auth configuration and
descriptor-bound initial settings, calls the private recipe-check under its
admitted systemd cgroup, then starts/enables the canonical database unit.
recipe-check verifies package/gate/launch evidence and actual owned files,
inactive service, memory and the PostgreSQL no-start configuration parser.
Live postchecks now verify process/cgroup/socket ownership, loopback listeners,
SQL/effective settings/version, complete package and NetBird snapshots and stable
parent/unit evidence. The root journal atomically publishes checked recipe step
completion with both resource ownership bindings; restart replays them without
rewriting the static registry. Explicit root --recipe-catalog provisioning checks
the signed indexes, exact immutable descriptors and both supported install orders
without changing packages; empty catalog advertises install unavailable.
Full runtime checks are deferred until the functional implementation is complete.

The [owned Docker check](../tools/test-executor-container.sh) also runs the
source [core controller](ci/core.py) through the installed no-argument sudo
bridge and real supervisor. It requires actual preflight, host occupancy,
queued cancellation, consumed authorization challenge, one Ansible motd effect
and factual postcheck, same-plan replay, and durable receipt after supervisor
restart. It emits its core proof only after those assertions; the outer harness
emits success only after its labelled container/image removal succeeds. Pure
executor unit tests run separately in the same Linux image. This core path has
no recipe catalog and cannot qualify database installation, the Windows MCP/UI
path or the complete executor fault matrix. A source change alone is not a
successful run; actual acceptance evidence is recorded in the feature tasks.

Administrator provisioning is implemented by `packaging/install.py`; it requires
the already prepared pinned venv, an inactive supervisor and no occupied host job,
preserves the hostUUID, writes a fixed no-argument sudo enrollment and does not
start the service. `tools/build-executor-release.py` creates the descriptor that
the native bundle must bind. runtimeVersion includes a digest of every fixed
executor source file, the bridge and lock, so a code change invalidates prior
preflight runtime identity. Generating that descriptor is not qualification.
The fixed source inventory includes qualification.py, apt.py and apt_gate.py;
the two APT launchers are checked against source-bound literal launcher bytes.
Explicit `--prepare-apt-no-start` prepares the isolated APT configuration and a
deny-start policy only if an existing different policy is absent. It never
updates package metadata, downloads repository keys or starts the supervisor.

For root-owned sources/public keyring and exact-version request preparation,
use [the administrator APT helper](recipes/README.md). Only its explicit
`--refresh` updates repository metadata. The APT public keyring is root0644 at
`/etc/apt/keyrings/serverdeck-executor.gpg`; private executor directories remain
root0700. An immutable signed base index without Valid-Until is supported;
signed expiration, signature verification and exact index/package hashes still
apply. Neither preparation CLI is an MCP operation or runtime qualification.

The intended [runtime/protocol](../specs/021-mcp-control/contracts/executor.md)
and [authorable profile grammar](../specs/021-mcp-control/contracts/profiles.md)
are normative. Package installation, root custody, the transaction gate and real
Docker fixture executor/recipe acceptance are still pending in [Tasks](../specs/021-mcp-control/tasks.md).
