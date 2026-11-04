# Implementation evidence: 004

## Foundation checkpoint — 2026-11-04

T001–T004 implemented: runtime-only metric/counter/snapshot model and durable
native run marker with Dart/native boundary units. Remaining T005–T021 are
unchecked: collector transport, scheduling, UI and full feature acceptance
are NOT implemented. This checkpoint does not claim full 004 readiness/completion.

Changed application scope:
- lib/monitoring/monitoring_models.dart
- lib/runtime/native_platform.dart (beginMonitoringRun method)
- lib/main.dart (publish marker before store/feature admission and pass flag)
- lib/runtime/feature_runtime.dart (monitoringAutoAllowed constructor field)
- windows/runner/platform_channel.h/.cpp (monitoring.beginRun / validated finish)
- native/include/monitoring_run.h (fixed-path bounded read/atomic write/cache)
- native/CMakeLists.txt and native/tests/monitoring_run_test.cpp
- native/tests/platform_channel_test.cpp (synthetic method boundary cases)
- test/monitoring/monitoring_models_test.dart, test/runtime/monitoring_run_test.dart

Initial targeted Flutter tests failed as expected because model/method absent.
After implementation targeted tests: 8 passed. Native adapter builds successful;
ctest selected monitoring_run/platform_channel: 2/2 passed (unit fixtures only).
Native tests build has SERVERDECK_BUILD_HISTORICAL_INTEGRATION=OFF.

Mandatory current-worktree checks actually executed:
- dart format --output=none --set-exit-if-changed .: exit0,226 files,0 changed.
- flutter analyze: exit0, no issues (25.1s).
- flutter test --reporter expanded: exit0,495 passed; log build/monitoring-unit.log.
- tools/check-test-boundaries.ps1: passed,56 Dart test files.
- flutter build windows --release: exit0,27.2s; build only, app not launched.
- git diff --check: exit0.
- lychee specs/**/*.md: first attempt failed only GNU df HTTP429; retry with --host-concurrency 1 --host-request-interval 2s --retry-wait-time 10
  passed exit0:174total,168OK,0errors,6excluded,2redirects.

Parallel external edits appeared during this checkpoint: local diagnostics in
lib/domain/app_operations.dart, lib/profiles/profile_owner.dart,
lib/runtime/local_diagnostics.dart, test/runtime/local_diagnostics_test.dart,
extra diagnostic hunks in feature_runtime.dart, specs/003-ssh-mcp/tasks.md.
Preserved without reverting; formatting touched app_operations/local_diagnostics
when mandatory whole-tree formatter initially reported them. No behavior changes
in these diagnostic files belong to 004. Whole-tree checks include their current
state. Independent review must focus on listed monitoring changes and assess
interactions, without attributing external diagnostics to this implementation.

No commits/publishing; no real Isar/SSH/integration/e2e/product launch/VM/design tests.
Review pending after links complete. Full goal remains active.

## Foundation independent review — 2026-11-04

Fresh reviewer review_004_foundation completed read-only inspection of T001–T004,
package004, related002/003 and native security/startup/shutdown boundaries.
Result: замечаний не найдено. Foundation acceptable as intermediate result;
package ready for continued implementation. Full feature remains incomplete
with T005–T021 unchecked. Reviewer did not rerun checks and did not modify files.
No confirmed findings remain in this checkpoint. Next: T005/T006 bounded SSH
collection protocol units and vendor implementation, then T007 owner admission.

Post-review metadata-only link retry: the same GNU df URL again returned HTTP429
(exit1,174total167OK1error6excluded2redirects). Earlier successful throttled run
remains recorded above, but the latest link run is NOT green. No source changes
after the successful foundation review. Retry external link validation in next
checkpoint; do not suppress429 or claim latest links passed. Web probe of the
alternative official /s/ GNU URL timed out; no source link changed speculatively.

## Bounded SSH protocol checkpoint T005–T006 — 2026-11-04

Implemented synchronous SSHClient.startBoundedExec, fixed failures, max5s timer,
65536 cumulative stdout+all extended-data before buffering, one unresolved channel
per SSH connection (pending-open tombstone or retired channel until peer close).
Cancellation before allocation/open/exec ACK, late success without exec, no retired
window/reply queue growth, duplicate ACK rejection. Ordinary execute keeps2MiB
receive window and upstream stream buffering. This is vendor functionality only:
T007 application-only fixed collector/admission is not yet implemented.

Changed scope of this checkpoint:
- third_party/dartssh2/lib/src/ssh_client.dart
- third_party/dartssh2/lib/src/ssh_channel.dart
- third_party/dartssh2/SERVERDECK.md, UPSTREAM.json
- patches/dartssh2-4.1.0-policy.patch, tools/check-ssh-vendor.py (4-source allowlist)
- test/fixtures/ssh_auth_peer.dart (opt-in synthetic protocol packet callback)
- test/connections/monitoring_channel_test.dart (14 unit cases)
- specs/004-server-monitoring/research.md (same manual's source reference instead
  of repeatedly rate-limited rendered GNU URL), tasks.md, this log.

Actual checks after final code/test changes:
- targeted protocol tests:14 passed, memory byte streams only.
- dart format --output=none --set-exit-if-changed .:exit0,227files,0changed.
- flutter analyze:exit0,no issues,2.8s.
- flutter test --reporter expanded:exit0,509passed,build/monitoring-unit.log.
- tools/check-test-boundaries.ps1:passed,57files.
- python tools/check-ssh-vendor.py:passed,98files,4policy sources; reverse patch
  applies and pristine/changed hashes retain pinned4.1.0 identity.
- flutter build windows --release:exit0,20.4s,no application launch.
- lychee specs/**/*.md:exit0,174total,168OK,0errors,6excluded,2redirects.
- git diff --check:exit0 (after blank patch context normalization).

Initial T005 test compilation failed because bounded API absent; fixed implementation
then passed. During development a fixture confirmation lacked required data field;
corrected. An ACK sent in a later input event can legally be observed after exec,
so that test was replaced by a duplicate-ACK queue regression. Vendor SDK3.0 lint
required returning byte copies instead of newer asUnmodifiableView API.

Pristine vendor scratch reconstructed by reversing the prior patch, hash-verified,
then moved outside repository to TEMP/serverdeck-monitoring-vendor-pristine-004
so whole-tree Dart formatter cannot traverse pristine upstream sources. Temporary
patch regeneration helper lives only in ignored build/. No dependencies changed.
T005–T006 marked done; independent review pending. Full004 remains incomplete.

## Bounded review round1 and correction T022 — 2026-11-04

Reviewer review_004_bounded found one confirmed P2: after ACK/stdout/status0,
local destroy from duplicate ACK or packet-size violation completed channel.done
without sticky failure, allowing bounded success. Reproducing units failed with
actual failure:null for both variants (build/monitoring-channel-review-red.log).
T022 appended; completed task history preserved. Added optional channel onAbort
notification after local teardown, mapped to bounded invalidResponse; normal peer
CLOSE still succeeds, cancelled/outputLimit reasons remain first-wins. Protocol ID
retained until peer CLOSE; regressions assert empty failed stdout, cleanupPending,
no new window grants, successful next collection after retired ID releases.

Final post-fix checks actually run:
- targeted protocol16passed; full fluttertest511passed, log build/monitoring-unit.log.
- format227files0changed exit0; flutter analyze no issues2.8s exit0.
- boundaries57files passed; vendor98files4sources hashes+reversepatch passed.
- Windows release build20.2s exit0, no launch.
- lychee174total168OK0errors6excluded2redirects exit0.
- git diff --check exit0.
New independent read-only review pending; T022 remains unchecked until clean report.
T007+ still unimplemented, no full-feature completion claim.


## Bounded review round2 — 2026-11-04

Fresh reviewer review_004_bounded2: замечаний не найдено; T005/T006/T022 accepted
as intermediate result, package ready to continue implementation. Reviewer
independently ran16protocol tests and98file/4source provenance/reversepatch check,
both successful; inspected saved full511test/analyze results. No files modified.
Confirmed first-wins local-abort failure, ordinary CLOSE/execute preservation,
pending-open tombstones, retired guards and resource bounds. No unresolved
confirmed findings remain in this checkpoint. T022 marked complete by author.
Next task T007: canonical owner admission and fixed collector-only transport port.
Full004 incomplete; no commits or publishing. Existing unrelated diagnostics kept.

## Canonical admission and Linux parser T007–T009 — 2026-11-04

Added typed optional MonitoringSshConnection (no arbitrary command parameter),
StrictSshTransport fixed POSIX-sh collector and normalized LinuxSample, plus
MonitoringJob(result,cancel) from ConnectionOwner. Owner authorizes its UiActor,
current promoted OwnerActor, exact session/revision and existing version/trust
fences before dispatch and response. Parent entry cancellation cancels child.
A5s owner deadline starts before gate admission, remaining budget passed to vendor.
Four unresolved jobs globally/one per profile; cancelled gate/adapter continuations
retain slots until underlying work finishes. Runtime stop cancels/drains jobs.
AppOperations/MCP wire/tool schemas unchanged; no raw output reaches owner clients.

Parser returns CPU counters (first8, no guest duplication), RAM percent via
MemAvailable, disk used/(used+available) with BigInt denominator, separate reasons.
Strict framing/UTF8/line/byte bounds; partial malformed source doesn't erase other
valid sources. Empty uname is sourceUnavailable (retry), not permanent unsupported
OS; nonempty non-Linux stays unsupported. Contract clarifies this and concrete API.
CPU session baseline still belongs to upcoming MonitoringOwner T011/T017; parser
has no cross-session state. T008/T009 were executed with T007 because the typed
transport must return parsed values; no deferred requirement was dropped.

Changed application/test scope of this checkpoint:
- lib/connections/connection_owner.dart, lib/connections/ssh_transport.dart
- lib/monitoring/linux_metrics.dart, lib/monitoring/monitoring_job.dart
- test/connections/connection_owner_test.dart (opt-in collection state in existing
  synthetic Session fixture; existing lifecycle tests retained)
- test/connections/monitoring_admission_test.dart (13 isolated owner cases)
- test/connections/monitoring_transport_test.dart (1 isolated strict adapter with
  synthetic encrypted in-memory peer and fake write admission, no real server)
- test/monitoring/linux_metrics_test.dart (10 parser cases)
- specs004 plan/contract/tasks and this evidence log.

Actual final checks:
- Targeted admission/parser23 passed; strict transport1 passed.
- dart format --output=none --set-exit-if-changed .:exit0,232files,0changed.
- flutter analyze:exit0,no issues3.2s.
- flutter test --reporter expanded:exit0,535passed,build/monitoring-unit.log.
- boundaries60files passed; vendor provenance98files/4sources passed unchanged.
- Windows release build:exit0,19.8s; no app launch.
- lychee specs/**/*.md:exit0,174total168OK0errors6excluded2redirects.
- git diff --check:exit0.

Red tests initially failed for absent parser/admission APIs. A Dart intersection
promotion required explicit capability cast; targeted tests then passed. Units
cover foreign UI/session/revision, revocation before/after promotion, stale
connection/credential/trust/deletion, disconnect/deadline/shutdown, queued cancel,
global4cap, source corruption/partial results and ordinary ping preservation.
No real Isar/SSH/integration/VM/layout tests, no commits/publication. T007–T009
marked implemented; fresh independent review pending. Remaining T010+ unbuilt;
T021 still unchecked because scheduler generation-history regression is pending.

## Admission/parser independent review — 2026-11-04

Fresh read-only reviewer review_004_admission_parser completed scope T007–T009
and related package/code boundaries: замечаний не найдено. Checkpoint acceptable;
package ready for further implementation. Reviewer independently executed24tests
(admission13/parser10/stricttransport1), exit0, allpassed. Other checks accepted as
provided evidence, not rerun by reviewer. No source files modified during review.
No unresolved confirmed findings remain in current checkpoint. Remaining T010–20
and scheduler half ofT021 explicitly incomplete; CPU baseline across sessions,
queues, activation/freshness/UI and final converge/review are still required.
Next: T010 fake-clock scheduler units and T011 canonical auto-admission/owner.

## Scheduler/lifecycle T010–T011/T016–T017/T021 — 2026-11-04

Implemented MonitoringOwner as single FeatureRuntime capability with Listenable
projections; MonitoringConnectionPort is the canonical ConnectionOwner. Separate
bounded auto-admission and collection queues; prompts retain auto slots, collections
rotate FIFO, one request/profile, no backlog. Initial/return/MCP-added profiles
reconciled through bounded pagination. Atomic connectForMonitoring reuses canonical
connect and checks generation==0 plus activation cancellation at gate effect;
manual003 connect remains unchanged. Per-runtime attempt marks preserve failed or
manual history; an unstarted cancelled admission resumes when the screen returns.

Owner remains inactive until upcoming UI activation wiring T012. Startup gate
blocks auto-connect and scheduled collect until explicit start; manual SSH remains
available.1s coalesced epoch-fenced reconciliation drives5s due times; new session
or connection revision resets readings/baseline, rename preserves it. Local age
is monotonic; UTC is display-only. Partial source failures retain only stale old
values; timeout/outputLimit/cleanupPending/sourceUnavailable/invalidResponse clear
freshness and CPU baseline, then recover on new pair. Unsupported OS stays sticky
for that session, including pause/resume, until reconnect. Synchronous snapshot
checks canonical session before async reconciliation, preventing old fresh values
from flashing onto a new session. Hide cancels collections, stops timer, preserves
SSH and clears CPU baseline; shutdown cancels/drains owned work.

Changed scope:
- new lib/monitoring/monitoring_port.dart and monitoring_owner.dart
- lib/monitoring/monitoring_models.dart snapshot connection/status/collecting fields
- lib/connections/connection_owner.dart canonical auto-admission wrapper/checks
- lib/runtime/feature_runtime.dart monitoring construction/capability registration
- new test/fixtures/monitoring_harness.dart (fake ops/port/clock)
- new test/monitoring/monitoring_owner_test.dart12cases
- new test/monitoring/monitoring_lifecycle_test.dart15cases
- new test/connections/monitoring_auto_admission_test.dart3canonical owner cases
-004 plan/model/contract/tasks/evidence updated. No UI changed yet.

Initial tests failed for absent owner/port API. Analyzer identified protected
ChangeNotifier.notifyListeners delegation; fixed with private notifier subclass,
without suppressing diagnostics. Self-checks added synchronous new-session guard
and preservation of unsupported status on resume; regression units cover both.
T021 now covers both original OwnerActor and scheduler/canonical generation history.

Actual checks on final source/test state:
- Targeted scheduler/lifecycle/canonical auto admission30passed.
- format --output=none --set-exit-if-changed .:exit0,238files0changed.
- flutter analyze:exit0,no issues2.8s.
- full flutter test --reporter expanded:exit0,565passed,build/monitoring-unit.log.
- boundaries64files pass; vendor provenance98files4sources pass unchanged.
- Windows release build:exit0,21.8s,no app launch.
- lychee specs/**/*.md:exit0,174total168OK0errors6excluded2redirects.
- git diff --check:exit0.

Fresh independent review pending; full004 still incomplete (UI, thresholds,
functional widgets, final converge and acceptance). Parallel diagnostics preserved;
no realSSH/Isar/integration/VM/design tests, no commits/publishing.

## Scheduler review round1 and fixes T023–T024 — 2026-11-04

review_004_scheduler found2 confirmed P2 issues (no missing mandatory decisions):
R1: late cancellation with generation0 erased a completed auto-admission failure.
R2: _cancelWork stored paused as server reason, surviving active return for
manually disconnected or failed profiles. Three reproducing regressions failed
before fixes (build/monitoring-scheduler-review-red.log).

T023 introduces immutable internal MonitoringConnectResult(operation,
cancelledBeforeAdmission), set only when canonical admission's cancellation guard
actually denies the lease. Later cancellation cannot relabel capacity/version/
queue failure. Only that receipt plus generation0 permits queue restoration.
Canonical unit verifies cancelled queued guard receipt and immutable non-cancel
failure. T024 separates transient pause from stored server reason while still
staling readings/clearing CPU baseline; active snapshot restores disconnected.
Existing true unstarted-cancel/resume, sticky unsupported and canonical history
regressions remain green. Contract/model updated, no public MCP wire changes.

Final post-fix checks actually run:
- targeted scheduler/lifecycle/canonical auto34passed.
- format238files0changed exit0; analyze noissues25.3s exit0.
- fullFlutter569passed exit0; boundaries64files pass.
- vendor98files4sources hashes/reversepatch pass unchanged; diffcheckexit0.
- Windows release build25.6s exit0, no product launch.
- lychee174total168OK0errors6excluded2redirects exit0.
New read-only independent review pending. T023/T024 remain unchecked until clean
report; UI/final gates still incomplete. No commits/publication or integration tests.


## Scheduler review round2 — 2026-11-04

Fresh read-only reviewer review_004_scheduler2: замечаний не найдено; backend
checkpoint accepted, package ready for remaining implementation. Independently
ran34scheduler/lifecycle/canonical auto-admission units: exit0,allpassed. Inspected
saved analyze/noissues and full569test results; other checks accepted as provided.
Confirmed T023 immutable receipt and T024 pause/server-reason separation, plus
queue/resource/epoch/freshness/ownership/runtime invariants. No files modified
by reviewer and no reviewed source changed while it ran. T023/T024 now complete.
Remaining T012–15/T018–20 explicitly unbuilt (UI, thresholds, widgets, final
converge/acceptance). Fullgoal stays active; no unresolved confirmed findings in
implemented backend scope. Next: UI activation and C21 metric projection.

## UI implementation and final mandatory checks — 2026-11-04

Implemented T012–T015/T018: RuntimeView activation by section/runtime/tray;
ProfileController action reconciliation; C07/C09 server cards with C21 individual
metrics, C10 critical/partial/fresh states, C18 local update times and monotonic
age, C11 safe recovery and C02 explicit start. Search/selection/CRUD/trust actions
reuse the existing profile feature. Threshold uses unrounded value, >=90;
89.95 displays <90,0 and stale values never keep current critical semantics.

Added 22 unit cases: thresholds7, functional actions4, recovery8, activation3.
Widget fixtures use fake dependencies only and assert data/actions/lifecycle.
The initial analyze found one unused test import; removed and reran all Flutter
checks successfully. Final actual evidence:
- format244files0changed exit0 (build/monitoring-final-format.log).
- analyze noissues2.8s exit0 (build/monitoring-final-analyze.log).
- full Flutter591passed exit0 (build/monitoring-final-tests.log).
- boundaries69files passed; vendor98files4sources provenance/reversepatch passed.
- native build + CTest unit10/10 passed (build/monitoring-final-native.log).
- Windows release static build19.4s exit0 (build/monitoring-final-build.log).
- lychee174total168OK0errors6excluded2redirects exit0; diffcheck exit0.

T019 complete. T020 full independent implementation review and converge pending.
No product/real SSH/Isar launch, integration, e2e, design checks, commits or
publication. Parallel diagnostics changes excluded from 004 ownership.

## Full implementation review round1 and convergence — 2026-11-04

Read-only review_004_complete found1 P2: per-source causes/actions lost by choosing
only first error and not naming the metric. Package ready for implementation;
implementation not complete until correction/review. Reviewer independently ran
104 targeted unit/widget tests and vendor provenance; all passed. Other evidence
reviewed from logs. No other confirmed defects/mandatory decisions in full004 scope.

speckit-converge initialized via check-prerequisites -Json -RequireSpec
-RequireTasks -IncludeTasks; no extensions.yml. Intent inventory:15FR,4SC,14AC,
24existing tasks,10 plan decisions and5 constitution principles. One partial/HIGH
remaining-work item (review severity P2): AC-410/FR-407/FR-413 presentation loss.
Appended only Phase10/T025; prior task history preserved. Outcome tasks_appended.

Implement pass for T025 replaces first-error reduction with metric-titled C11
notices, one for every failed source, each retaining its safe cause/next action.
Global whole-collection/SSH failures retain global notices. Contract clarified.
New regression combines successful CPU, invalid RAM and unavailable disk, checks
both attributed causes and actions. Targeted recovery9passed. Full mandatory
checks and fresh independent review pending; T025/T020 remain open.

## T025 post-fix checks — 2026-11-04

Full Flutter592passed, format244files0changed, analyze noissues2.8s: exit0.
Boundary69files pass; vendor98files4sources hashes/reversepatch pass; diffcheck0.
No native source changed since successful native unit10/10. Static Windows build
and links rerun; fresh read-only review follows. No app/integration/design tests.

## Full implementation review round2 and final acceptance — 2026-11-04

Fresh independent read-only review_004_complete2: замечаний не найдено;
готовность к реализации: готов; реализация завершена в проверенном scope.
T025 accepted: every failed source retains its own metric-titled cause/action;
whole-collection and SSH failures remain global. Reviewer independently ran105
monitoring/admission/auto/channel/transport/marker unit-widget cases, vendor98/4
and diffcheck: all exit0. Viewed saved full592, analyze, format, native10/10,
Windows release and link evidence. No reviewed source changed during either
review; no files changed by reviewers. No unresolved confirmed findings.

Final speckit-converge: converged, zero missing/partial/contradicts/unrequested
findings. Prerequisites read current004; no extension hooks. Assessed15FR+4SC+
14AC,10 plan decisions,5 constitution principles and all25tasks against current
source/test evidence (not checkbox claims). tasks.md SHA256 stayed
4143E46881C21EB0FEAAC06A591F78901752E21DA39A3D8B1799F39FAF2E8127 during
convergence; no empty phase or new task appended. Completion markers below are
implementation bookkeeping after the clean outcome, not converge edits.

Final traceability assessment:

| Intent | Implementation and actual unit evidence |
| --- | --- |
| FR-401/402/411; AC-402; SC-401 | Linux constant collector, strict parser, CPU delta/RAM/df formulas; linux_metrics_test, monitoring_models_test, owner first-pair case |
| FR-403/404; AC-405–407; SC-402 | Unrounded >=90, formatting and independent C21/C10 projection; threshold7 cases and live widget recovery |
| FR-405/406; AC-401/403; SC-401 | Owner 5s due, fair4workers, no backlog; bounded channel/deadline/budget and admission units |
| FR-407/412; AC-409/410/413; SC-403 | Independent freshness, cancellation, revision/session/actor fences; lifecycle/admission and multi-source widget regression |
| FR-408/409; AC-401/411/412/414; SC-404 | Canonical history, auto4slots, no retry, trust/promotion rules; owner/auto-admission/revocation units |
| FR-410; AC-408/412/414 | Startup durable marker, runtime section/tray activation, explicit start, capability drain; native marker and fake activation/lifecycle tests |
| FR-413/415; AC-403/404/408/410/411 | Existing C02/C04/C07/C09/C10/C11/C18/C21, preserve actions/trust, attributed recovery; functional action/recovery units |
| FR-414 | Memory-only metrics, private capability, fixed command/reasons, bounded source bytes; parser/transport/vendor tests and source/API inspection |

Plan obligations checked: existing Flutter/Dart/C++17/vendor stack; no Isar schema
change; single monitoring/SSH graph; canonical actor/session authorization;
private non-MCP capability; separate bounded queues; constant Linux parsing;
activation/coalesced1s epoch fences; fixed native marker; reuse shared C IDs.
Constitution I–V satisfied within004 changes: shared components, no feature design
tests, unit-only validation, no new services/dependencies/release assets, tray and
shutdown/crash semantics. No shared component/theme changes require design tests.

Final mandatory results after T025: format244files0changed; analyze noissues;
Flutter592passed; boundaries69files; vendor98files/4sources; native10/10unit
(unchanged native code); Windows release static build19.4s; lychee176total170OK
0errors6excluded2redirects; diffcheck0. Actual logs build/monitoring-final-*.log.
Full goal is complete after T020/T025 bookkeeping and final link check.
No commits/publication. No product launch, realSSH/Isar, integration/e2e/VM or
screen-design tests; these results do not prove clean-OS integration.
