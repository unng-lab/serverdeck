# Research decisions — 2026-10-05

## Tooling

Decision: official specify-cli==1.1.0 initialized with Codex skills and PowerShell.
Rationale: real installed workflow/scripts, version repeatability; existing BR/AC/T
IDs authoritative. Alternative: hand-written lookalike scaffolding rejected.
Source: https://github.github.com/spec-kit/installation.html

## Local storage architecture amendment

Decision: follow the local Docs project's Flutter -> Local API -> Dart locald ->
Isar ownership pattern, with an independently written ServerDeck implementation.
Isar Community and generator 3.3.2, pinned bundled Core from flutter_libs 3.3.2;
runtime download:false, inspector:false, relaxedDurability:false. No Python
desktop coordinator or SQLite job database remains in the active architecture.
Rationale: one owner for non-secret data and job state, Dart domain/API, UI lifecycle
separated from durable coordination. Alternatives: Python sqlite3 coordinator
replaced by user instruction; direct UI Isar ownership would couple storage to
window lifetime. Existing prototype SQLite files require a separately validated
explicit importer, not automatic reset/import. Upgrade migrations, inventory cache,
settings and real job executor are still future work.
Research comparison checked Docs locald/discovery/store locally; no Docs source
was copied. Windows DACL must replace explicit non-owner grants too. Test actual
compiled-process death/restart and stale endpoint discovery separately from orderly
reopen. Packaged service and Core are required; plain Flutter build is insufficient.
Generator succeeded but warned analyzer language3.12 vs SDK3.13; no SDK changes or
dependency overrides. Runtime compilation and analyzer checks remain required.
Sources: https://pub.dev/packages/isar_community
https://pub.dev/packages/isar_community_generator

## Windows executor

Decision: Docker Desktop Linux container, Ansible Core 2.21.4 + Runner 2.4.3,
Python 3.12. PyPI declared Python support verified; initial assessment preceded
runtime smoke, whose subsequent result is recorded below.
Runner wheel SHA256 cdac6daa151a50084ffda710e769db23fa975fc0507796191d7708831b286e37.
Follow-up evidence: pinned image built and Core/Runner localhost assertion smoke
passed (8 events). Actual remote recipes remain gated; see docs/verification.md.
Rationale: Windows not a native Ansible control node. Runner provides structured
events, not durable job reconciliation. No Docker socket or nested runtime.
Alternatives: WSL adapter later; AWX unnecessary; Terraform not package management.
Sources: https://docs.ansible.com/projects/ansible-core/devel/os_guide/intro_windows.html
https://docs.ansible.com/projects/runner/en/stable/execution_environments/
https://pypi.org/project/ansible-core/2.21.4/
https://pypi.org/project/ansible-runner/2.4.3/

## Least privilege gate

Decision: stock become disabled for future strict recipe execution. Require
admin-preprovisioned root-owned helper accepting only signed/allowlisted recipes
and exact parameters, with remote lock and preservation checks.
Rationale: sudo command allowlists do not constrain elevated generated modules.
An app catalog allowlist alone is not server least privilege. No helper deployed.
Source: https://docs.ansible.com/projects/ansible-core/devel/playbook_guide/playbooks_privilege_escalation.html

## Windows secret custody and SSH foundation

Decision: dartssh2 4.1.0 with mandatory endpoint/key-type/SHA256 enrollment and
bounded read-only typed operations. Native localhost SSH tests passed; no connected UI.
Windows Credential Manager via win32 6.4.0/ffi 2.2.0, current-user local-machine
persistence. Native synthetic read/write/overwrite/delete tested. Max generic
blob 2560 bytes; large PEMs explicitly rejected until protected-envelope support.
Alternative evaluated: flutter_secure_storage 11.2.0 needs absent Visual Studio ATL;
removed dependency without changing the shared toolchain or using plaintext.
Sources: https://pub.dev/packages/dartssh2
https://learn.microsoft.com/en-us/windows/win32/api/wincred/ns-wincred-credentialw
https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credwritew

## Candidate catalogs, NOT enabled execution

Ubuntu 24.04 amd64/systemd first. PostgreSQL 18 candidate apt version
18.6-3.pgdg24.04+1 (postgresql-18/client-18) observed in official pool. Must check
signed current apt index, availability/dependency resolution and actual install.
ClickHouse LTS candidate 26.8.17.4 server/client/common-static matched in official
apt index. Keep all three exact pins. Dedicated Signed-By keyrings. Fresh install
and adoption differ; unknown data never overwritten. No automatic fallback.
Sources: https://www.postgresql.org/download/linux/ubuntu/
https://apt.postgresql.org/pub/repos/apt/pool/main/p/postgresql-18/
https://clickhouse.com/docs/get-started/setup/self-managed/debian-ubuntu
https://packages.clickhouse.com/deb/dists/lts/main/binary-amd64/Packages

## Durable job boundaries

Decision: SQLite journal + unique active host lock + detached container identity.
Cancel is best effort; restart means unknown until postcondition reconciliation.
Runner run_async is process-local thread, not a daemon/rollback. Full recipes,
SSH executor image/client dependencies, helper and disposable VM tests remain
T010/T011 gates; dependency-smoke image digest/transitive locks are implemented.
Sources: https://docs.ansible.com/projects/runner/en/stable/intro/
https://docs.ansible.com/projects/runner/en/stable/python_interface/

## Logs provenance

Only behavioral requirements from docs/logs-research.md commit
a7bf7f8f0c4d5d37be6a54119eaf70a1248520b9. No source copied; license pending.
New app fixture records are synthetic. No source-runtime validation claimed.
