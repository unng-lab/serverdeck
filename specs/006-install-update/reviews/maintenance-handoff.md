# Typed maintenance handoff adapters — T060/T061

Implemented native strict four-HANDLE argv parser, inherited lease adoption,
type/access/path/exclusive-share validation, parent process identity/ancestry and
readiness Event checks. Parent uses four inheritable duplicates in an explicit
STARTUPINFOEX HANDLE_LIST; original leases remain held. Child clears inheritance,
acknowledges readiness and waits for parent exit before the future entry-point
mutation. Ready deadline3s/parent deadline10s; no process termination fallback.
Canonical launch has a fixed path, no arguments and no inherited handles.

## Review / fix loop

Initial read-only `review_006_maintenance_handoff` found one P1: combined RW-denial
did not prove no DELETE/read sharing. Replaced it with independent READ/WRITE/DELETE
ReOpenFile probes against the original file object, with fully permissive probe
sharing; only sharing violation counts as proof. T061 tests all7 nonzero sharing
masks and partial-sharing AcceptTransfer refusal before ACK, preserving parent lease.

After fix, fresh read-only `review_006_maintenance_handoff_fresh`, fork_turns=none:
no findings, ready for the bounded adapter scope and subsequent T018 wiring.
Source, Lease::Adopt, fixtures, compilation and installation contract were reviewed.

## Checks actually run after fix

- `tools/test-release.ps1`: exit0, 18/18 native units, 12.13s.
- `tools/build-release.ps1`: exit0, full DEVELOPER app/setup build and static
  resource/import/identity audits.
- `lychee "specs/**/*.md"`: exit0, 276 total, 270 OK, 0 errors,
  6 excluded, 2 redirects.

Tests use synthetic temp files/kernel objects, internal parent/wait seams and
fake Spawn/Wait ports. They do not launch any product or test child process,
kill processes, open a real database or exercise live network. Positive full
real-parent validation and production CreateProcess remain static/build-reviewed;
this evidence does not prove clean-OS integration.

## Remaining work

Bootstrap/installer entrypoints remain unmodified by this step. T018–024/T028
still cover pending decision, fresh revalidation/apply, durable consumption,
deferOnce fallback, cleanup and uninstall. T060/T061 completion does not establish
working update application or completion of the full feature/active goal.
