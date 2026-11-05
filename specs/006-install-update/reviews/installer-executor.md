# Installer executor, composition and catalog signer

Date: 2026-11-04. Partial implementation milestone; remaining updater/handoff/uninstall
and final convergence tasks stay open. No release was published or deployed.

Implemented source scope: native install executor, Windows registration ports, setup
resource reader and entry point, their native units/CMake wiring, Python static setup
audit, full build script/workflow, PowerShell catalog signer and synthetic-key unit.
Executor requires matching maintenance/owner leases; verifies app/setup identities;
stages candidates/backups, journals before mutation, commits registration/metadata/proof
before cleanup. Explicit repair operates on verified installed identities, retains
an intact preceding recovery image and rejects missing/corrupt recovery assets.
It never applies the embedded older recovery release. Same-version conflicting bytes
are rejected before recovery/registration mutation.

## Independent review loop

All reviewers used fresh `fork_turns=none`, read source/AGENTS/package directly and
did not modify files. Earlier clean catalog/foundation/generator milestones remain
recorded separately; this milestone reviewed their interactions too.

1. `review_install_executor`: two findings, explicit repair bypassed registration
   journal and equal-version conflicting bytes were accepted. Tracked T037/T038;
   journaled `Repair()` and separate app/setup conflict units added.
2. `review_install_executor_fresh`: one finding, explicit repair could succeed with
   broken recovery assets. Tracked T039; SID/full image hash/embedded resource checks
   before repair journal plus missing/corrupt image/marker units. Its initial capacity
   failure was retried and is not counted as a clean result.
3. `review_catalog_signer`: case-insensitive/nonabsolute keyId validation accepted
   uppercase/trailing LF. Tracked T040; case-sensitive absolute boundaries and unchanged
   output negative fixtures added.
4. `review_install_and_signer_final`: broad installer/build/sign scope; previous
   T037–040 fixes closed, one remaining signer payload bound rejected allowed catalogs
   near128KiB. Tracked T041; bounded stream read and independent envelope limit, near-limit
   success/envelope overflow atomic-refusal units added. No other confirmed findings.
5. `review_signer_bound_final`: fresh affected-scope review, «Замечаний не найдено»;
   reviewer independently ran signer unit successfully. Broad installer code unchanged
   since step4. No unresolved confirmed findings in this milestone.

## Actual verification

- Native unit gate: 13/13 passed, including executor fault checkpoints, fake registry/
  shortcut partial writes, repeated repair, identity conflicts and recovery failures.
  Real inproc shortcut codec tested only inside synthetic temp tree with fake registry;
  no Explorer/application/session launch or real uninstall registry mutation.
- Python tooling discovery: 14/14 passed. Signer unit generates temporary P256 keys,
  checks exact bytes/raw64 P1363 verification/tamper/invalid PEM/keyId/bounds; no actual
  operator key was required or used.
- Flutter format:380 files0changes; analyze:no issues; ordinary suite:731passed.
  Boundary audit:90 Dart files, no forbidden integration/layout coupling. Subsequent
  milestone changes were native/build tooling only; Windows release compilation passed.
- `tools/build-release.ps1`: exit0, developer profile, current Flutter payload and
  current `/MT` bootstrap embedded into full `/MT` `ServerDeckSetup.exe` version0.1.0+1.
  Final setup57044992bytes SHA256
  `7850c1295df4ef83ed9d0658f38b51984cf919ea29b3613b0ded1a36e629ae16`;
  embedded app56529920bytes SHA256
  `b6ddb65816471379e09cf7e515c6f5ce1bcf311fe481e0e549028fc2343bb6ac`.
  Static audits passed exact embedded app hash/size/version, matching absent developer
  policy, x64 PE, asInvoker/uiAccess=false and OS-only bootstrap/setup imports.
  No binary was launched. Generated identities/audits are under ignored output paths.
- Link gate after fixes: lychee258total252OK0errors6excluded2redirects.

These are unit/static/build results. They do not prove actual installation/update/
uninstall integration on a clean OS. Network worker/platform/UI, startup handoff,
pending consumption and removal remain open tasks. Full-feature readiness and final
Spec Kit converge/completion have not been declared.
