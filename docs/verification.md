# Verification record — 2026-10-05 (Europe/Moscow)

Repository H:\projects\unng\serverdeck; initial HEAD
5900f905677886a5147238cf065187097de64309 was confirmed clean before work.
Only repository code changed; no Infrastructure/Logs/live server modifications.

## Completed scope

M0 fixture Windows UI complete: navigation, session profile add/edit/remove,
software sources/versions/stopped/failed/instance states, bounded journal/search/
unit/priority/time/details/copy/pause/demo-flow, nullable/stale fixture metrics,
nonexecuting install preview. No actual SSH connection from UI.
T001/T002/T003/T004 complete. T013 milestone evidence recorded, overall task pending.

M1 foundation partial: typed final-class read commands, host enrollment policy,
bounded/deadlined SSH snapshot transport, Windows Credential Manager FFI,
package/unit/CPU/memory parsers. Tested only disposable localhost SSH, not real hosts.
M2 foundation partial: SQLite intent/event transactions, immutable input hash,
idempotency, durable exclusive host lock, cancellation/unknown/reconciliation;
public executor always denies. Linux Core+Runner pinned image smoke successful.
M3 optional sync not implemented.

## Actual successful checks

| Check | Actual result | Scope |
|---|---|---|
| specify version/init/check | 1.1.0; Codex available; real scaffolding | Official PyPI CLI, PowerShell scripts |
| Spec Kit setup-plan/setup-tasks/check-prerequisites | Exit 0, expected feature/docs | Existing stable BR/AC/T IDs retained |
| Cross-artifact analysis | 20/20 BR requirements mapped; 0 critical contradictions | Planning coverage, not AC completion |
| dart format | formatted source/tests/tools | Final no-change verification: 14 files, 0 changed |
| flutter analyze | No issues | Final source |
| flutter test | 20 tests passed | domain, parser, identity, CRUD, widget navigation/search/pause/gates |
| Windows native smoke | 2 tests passed | navigation + synthetic OS custody roundtrip/overwrite/UTF8/large-blob rejection/delete |
| Disposable SSH Windows integration | 3 tests passed | actual TCP/auth, mismatched pin denial, package/proc read, absent journal unsupported, byte cap |
| Python job unit/fault tests | 11 tests passed | duplicate/lock/reopen/probe/cancel/reconcile/atomic rollback/concurrent claims |
| Linux image build | succeeded with hash-locked Python dependencies | Python 3.12.12 base digest pinned |
| Linux Runner smoke | status successful, rc 0, 8 structured events | localhost assert only, no network/SSH/package changes |
| flutter build windows --release | produced release exe/DLL/data | final fixture app |
| Fixture preview render | successful; visually inspected server/journal previews | Flutter test renderer with Windows fonts, not a native screenshot |
| Fixture cleanup | no serverdeck.disposable containers remained | Each uniquely named local test container removed |

## Environment and pins

Flutter 3.47.0 revision 4cf24164269a5ebf0c16a028a00727d0e77bbb05, Dart 3.13.0.
Flutter doctor reports nonstandard user-branch (warning); shared SDK not changed.
Visual Studio Community 2022 17.14.16; Windows SDK 10.0.26100.0.
Docker Desktop 4.89.0; client/engine 29.7.2 Linux. Python test host 3.12.
dartssh2 4.1.0, win32 6.4.0, ffi 2.2.0, flutter_lints 6.0.0.
Runner Python 3.12.12, ansible-core 2.21.4, ansible-runner 2.4.3; image base
sha256:593bd06efe90efa80dc4eee3948be7c0fde4134606dd40d8dd8dbcade98e669c.
Python transitive pins/hashes in runner/requirements.lock.
OpenSSH fixture resolved 1:9.2p1-2+deb12u10 from Debian bookworm apt; fixture apt
dependencies are not snapshot locked. This fixture is not the installation runner.

## Failures found and corrected

Initial tests failed before implementation as expected. Subsequent tests exposed
layout overflow and premature dialog-controller disposal; both corrected and
covered by passing navigation/CRUD tests. Preview font-loading fake-async hang
corrected. Host-key rejection raised package Error; normalized to explicit
HostIdentityRejected and native mismatch test passed.
flutter_secure_storage 11.2.0 native build failed on missing ATL headers. Removed
that dependency and implemented direct Credential Manager APIs; native build and
custody tests then passed. No plaintext fallback or shared Visual Studio install.

## NOT performed / remaining gates

AC01..AC03 not complete: no cached SQLite profiles, enrollment UI, read-only
connected repositories, real journald history/follow/cursor/boot/denied tests,
periodic disk/network/service sampling, load limits or reconnect transport.
Fixture stale values are computed on rendering, not proof of periodic monitoring.
Native custody tested with new adapter instance, not across a Windows reboot;
large PEM envelopes and cross-platform stores pending.

AC04/AC05 not complete: no actual PostgreSQL/ClickHouse install/adopt/no-op on
Ubuntu 24.04 systemd VM; no privilege helper/remote lock, detached actual executor,
OS file ACL deployment, SSH credential handoff, event redaction/retention under
load, process-kill/network-loss container tests or real post-install probes.
Job tests inject historical running fixture state and caller-supplied probe
evidence, not real remote outcomes. Local job journal is separate from Flutter UI.
Candidate version availability does not prove signed apt index/current installability.

AC06 optional sync absent. AC07 has partial pin/injection/catalog/gate coverage;
full privileges/protected-scope acceptance remains pending.
NetBird not touched; production hosts not contacted; no real credentials, host
inventory or private logs entered the repository or distribution. No source copied
from Logs and no Logs runtime tests claimed.
