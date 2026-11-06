# Verification evidence — 2026-11-07

Implemented scope: embedded UI console, shared C26 terminal engine, bounded guarded SSH PTY, shell settings/storage migration, eight MCP console tools, input leases/binding lifecycle, in-memory replay receipts and paged shared history. Final independent review is clean and convergence found zero remaining gaps; all tracked tasks are complete.

Actual latest checks:

- `dart format --output=none --set-exit-if-changed .`: exit 0, 496 files, 0 changes.
- `flutter analyze`: exit 0, no issues found.
- `flutter test --reporter expanded`: exit 0, 865 passed; `.local/console-unit-check.log`.
- `flutter test test_design/components --reporter expanded`: exit 0, 134 passed, one explicit opt-in capture skipped; `.local/console-shared-check.log`.
- `tools/check-test-boundaries.ps1 -TestRoot H:/projects/unng/serverdeck/test`: exit 0, 111 Dart files.
- `lychee "specs/**/*.md"`: exit 0, 348 total / 342 OK / 0 errors / 6 excluded / 2 redirects.
- `python test/mcp/official_schema_test.py`: exit 0, two tests; all 21 definitions and tools/list validate against the pinned offline official MCP schema; runtime/specification registries byte-identical.
- Earlier code generation: exit 0, two generated outputs; nullable reader regenerated and audited. Current runner ignores removed delete-conflicting-outputs option. No Isar engine loaded by tests.

Coverage uses synthetic packets, fake ports/repositories, clocks and functional widget callbacks. Tests cover shared UI/MCP output/input, key correction sequences, exact multiline consent/lease races, history gap and UTF8 pagination, grant revoke/rotation/expiry/disable/EOF, retry eviction and unknown outcome, input/raw/session caps, late opening, normal end/disconnect versus trust clearing, rename/endpoint/delete/shutdown and C26 component behavior. These are unit checks, not real SSH/Isar/process/OS integration. No release or clean-OS installation claim.

Design review was clean after fixes (reviews/design.md). Increment reviews identified and drove R701–R704 (reviews/increment.md); final independent review follows the current full checks. No user changes to the pre-existing storage/002 monitoring work were included in this feature's review scope.


After the full review, converge appended T040–T043. They now implement creator guard at every setup packet/ready, one deadline/cancellation control through all packet waits with removable subscriptions and bounded retired admissions, exact named-object cursors, and typed distinct opening failures. All checks above were rerun successfully after these fixes (864 ordinary tests). Targeted native units also cancel before raw admission, during rekey and after a committed fragment with stalled flush, repeat cancellation to check listener/retired-admission bounds, then continue with a valid cipher stream. Fresh independent review pending.


T044 now routes platform/IME CR/LF edits and internal PasteTextIntent through C26's onPaste delegate before terminal input. Shared synthetic tests preserve plain text/physical Enter and intercept both paste paths; feature tests exercise actual platform editing, no sends before consent, Cancel, server changes and lease loss. Rechecks after this fix: format496files0changes, analyze noissues, ordinary865passed, shared134passed/one opt-in skip, boundaries111files, lychee348total342OK0errors6excluded2redirects, official MCP schema2tests passed. All exited0. Fresh independent review pending.


## Final closure

Fresh independent reviewer review_console_ime_fixed completed read-only: no findings, package ready and no confirmed unresolved implementation defects/mandatory gaps. Closure report is reviews/final.md. Final converge checked26 FR,7 SC,22 acceptance scenarios,8 grouped plan decisions and6 constitution principles, including all44 T tasks and4 review-fix items. No missing/partial/contradicting/unrequested work remains in the authorized scope. No convergence tasks appended in the final audit. tasks.md SHA256 stayed92B9B16C8C8FB55CDF9BFD458AFBB5CD7BF84DB29EB78DA675914717F6B33B98 byte-for-byte during that read-only audit; T039 was marked complete afterward as workflow bookkeeping. No extension hooks exist. Scope001 R020 and all007 tasks completed. No commit/release/publication was requested or performed.

Final check scope remains865 ordinary unit tests,134 shared tests/one opt-in capture skip, format/analyze, test-boundaries, offline official MCP schemas and all specification links. No application code changed after these successful checks and the clean final review; subsequent edits only record completion/status/evidence.
