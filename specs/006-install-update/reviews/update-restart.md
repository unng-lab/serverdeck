# Direct updates / restart — Spec Kit evidence

## Specification readiness

2026-11-06: specify amendment FR-621–623, clarify user choice (no tray restart),
constitution4.0.0 narrow confirmed-update exception, plan/research/model/platform,
US5 tasks T082–087. Setup scripts succeeded; no extensions.yml hooks configured.
Analyze: each FR maps to contract/plan/task and AC-619/620/SC-607, no unresolved markers.
First independent review found R1 ambiguous global vs prepared error and R2 duplicate
US4. Both confirmed and corrected before implementation: retained A allowed after
failed/cancelled replacement B if A preparedCode absent; current story US5.
No prior completed task history removed. Fresh independent readiness review: no findings, ready; CHK001–008 PASS.

## Implementation candidate

RuntimeView direct C02 update button and independent owned route; current version retained.
UpdateView exact prepared-version C14 and runtime callback; atomic native acceptance and
transient intent, snapshot recovery for lost events, shared safe shutdown/retry. Host8
unloads once, Resume preserves owner across maintenance failure, existing pending helper
performs readiness/permission/parent-exit/fresh-release checks. Plain tray/OS exit revoke
restart; no extra tray item. Package002 historical tray-only text explicitly superseded.

Isolated candidate at H:/projects/unng/serverdeck-update-restart-check, base abd63c1d;
unrelated root storage WIP excluded. Actual candidate checks:
- dart format --output=none --set-exit-if-changed .: 285 files,0changed;
- flutter analyze: no issues,5.3s;
- flutter test:775passed,16s;
- test boundaries:96Dart files PASS;
- native19unit tests PASS,19.89s; synthetic ports/temp files, no product launches;
- Python22unit tests PASS,6.246s;
- lychee289total283OK0errors6excluded.
Publishable setup build/audits in progress; final independent implementation review,
converge and public release remain T087. Unit results do not establish full application
integration on a clean OS. No integration/e2e/VM/process-kill/design screen checks run.

## Implementation review R1

Independent review found a second WM_QUIT after explicit pump quit8: scoped window
teardown would post quit0, aborting subsequent native retry modal UI. Confirmed from
Win32Window::WM_DESTROY. T088 adds a shared host-pump completion adapter that disables
normal quit before restart teardown, with real thread queue + synthetic window unit.
No product/window/modal dialog is launched by this unit. Fresh checks/review pending.
Initial publishable build completed successfully with embedded policy, import/resource
checks; candidate setup cde0661f5548145bdebbed57f2ed94ed6a494c6f7d4c48148037964ad98ea7db
is superseded by the corrected rebuild and will not be published.

## Corrected candidate: final independent review

Fresh review_update_restart_code_fresh completed read-only: no findings, requirements
ready and implementation consistent; R1 confirmed closed against real Win32Window and
new queue unit. Post-fix checks actually rerun: format285files0changed, analyze clean4.1s,
Flutter775PASS16s, boundaries96PASS, native19PASS19.91s, lychee289total0errors.
Python22PASS from unchanged tooling. Corrected full publishable build/resources/import
closure PASS; setup SHA256482a40e881ae2da8d92ba9eb47f5a2024cc189c7cb7a7331a6642e827ad19596.
Final catalog SHA256d9c4dae1e1337555bfd6f71062f5a44597c576ac439567b8e1b7fb77c7a042c6;
prepare-release validated previous signature/key and retained prior immutable records.
Public release is still pending; these are local artifact facts, not installation proof.

## Publication and convergence

[Stable v0.1.0+4](https://github.com/unng-lab/serverdeck/releases/tag/v0.1.0%2B4)
ID436385247, source commit51259999a9dc5128142297a28b0283918f2c4300. Draft had exactly
two uploaded public assets; sizes/digests matched local audited setup and signed catalog
before publishing. Setup57,778,688bytes; catalog3,703bytes, protocol2/3 immutable records.
Anonymous latest with real client headers returns this stable release; downloaded public
catalog matches exact local bytes. Previous +2/+3 asset digests remained unchanged.
Private signing key never uploaded. These are publication metadata observations,
not product/OS integration tests or proof this version is installed on the user's PC.

Converge assessed current code against spec/plan/tasks/constitution after implementation;
no unbuilt work.88tasks complete,0open. tasks.md byte-identical during converge
SHA256da75c0f388ffdaf19ddb025e0af146af510e8d1504e1a55bba302122ce06630a.
Specify/clarify/constitution/plan/checklist/tasks/analyze/implement/review-fix/converge
finished; no hooks configured. T087/T088 closed only after completed clean review,
corrected build, successful public release and anonymous metadata verification.
