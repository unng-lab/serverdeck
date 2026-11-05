# Installer adapter corrections — 2026-11-05

## Scope and observed cause

User-authorized local maintenance exposed two native adapter defects. The HKCU
size probe allocated49 UTF-16 code units while the subsequent read returned96
bytes; old code retained a spare NUL and rejected its own registration. The read
adapter now uses the actual returned byte count and retains malformed-value checks.

First removal failed before ACK at ValidateLeaseHandle's path-string comparison.
Local diagnosis resolved the fixed logical LocalAppData lock to the packaged
caller's physical LocalCache path. Retry without transfer succeeded. Lease proof
now compares volume and full128-bit file ID against an attribute-only handle to
the fixed expected path in the same namespace. All rights, regular-file,
reparse, zero-size, exclusive-sharing, ancestry/logon and permission checks remain.
Temporary diagnosis instrumentation was removed from application sources.

## Verification

- Targeted native build and ctest maintenance_handoff/install_executor/uninstall:
  exit0,3/3 passed. New synthetic units cover same-object alias/different locks
  and HKCU probe-vs-actual length, malformed count/NUL/error inputs.
- Global lychee: exit0,281total275OK0errors6excluded2redirects before this report.
- Full native build and `ctest --test-dir build/native-tests -C Release -L unit --output-on-failure`: exit0,19/19 passed (tmp/installer-native-unit.log).
- `tools/build-release.ps1`: exit0; full Flutter/native/setup resource/import/font build checks completed (tmp/installer-fixed-build.log). No Flutter sources changed.
- Independent read-only installer_fixes_final_review (fresh fork_turns=none): no findings; ready within T070–T072 correction scope. Reviewer inspected source/package chain and actual build/unit/link logs; no unresolved confirmed findings. Application sources unchanged after review.

Tests use synthetic inputs/ports and temporary files; no integration/e2e/process
launch or product/Explorer launch is part of the unit gate. User-requested local
installation diagnosis is separate operational evidence, not clean-OS coverage.
No Flutter code or shared design components changed.

## User-authorized local maintenance

The final rebuilt installer was installed locally, then the ordinary initial
`--uninstall` completed successfully without retry. The UI reported successful
removal; application and uninstall registration were absent. All six previously
snapshotted user-data files retained their hashes. The same final installer was
then used to restore the app. This is operational evidence in this packaged
caller environment, not an integration test or a clean-OS acceptance gate.
