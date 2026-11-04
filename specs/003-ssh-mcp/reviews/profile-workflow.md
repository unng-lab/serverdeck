# Журнал уточнения003/004 — 2026-11-04

Пользовательотменилотдельнуюупаковку иcompatibilityдоapp1.0. Current scope001/002/003/004. Прежнееreviewпрерваносменойscope,неclean. Ниже фактическаяисториядосменыscope; current-onlycleanup/checks/новоеreview обязательны.

# История уточнения профилей/мониторинга

## 2026-11-04 initial implementation
All product tasks T002–T008 completed BEFORE adding/running feature tests, as the user required. C21 compact is001scope; list uses one C07 with compact C21/status; timestamp/age rendering removed. Details/actions are live C12 modal. Successful save yields typed outcome and onboardingconnect, serialized trust/phrase prompts; changedpin remains warning in ordinary monitoring. Strict PKCS1 PEM/DER/AES128/192/256CBC/DES3 support preserves original privatefile bytes; nullablecanonicalpublicmetadata propagates throughimport/store/snapshot/identity and workerbinding beforeRSA256/512signatures. ExistingOpenSSHnullfallback preserved.

New unit evidence: synthetic staticPEM vectors generated offline from existingrepositoryRSAfixture; no user's.ssh used as fixture. Parser accepts plaintext/4cipher variants, missing/wrongphrase, malformedouter/DER/weak/inconsistentnumbers rejected. Signer verifies RSA256/512, wrongmetadata no signature. Owner/memoryrepo flow persistsoriginalbytes/publicmetadata, detachedcopies and missingmetadata failclosed. Widgetflow tests commit→trust→phrase, cancel/failedsave/networkfail/name-onlyupdate, deleted/stale/duplicate prompts and modalclose; sharedC21 testedon syntheticinputs only.

First test pass exposed used-after-dispose in passphrase dialog exit animation. AddedT061 instead of erasinghistory; controller nowowned byrouteState andclearedonsubmit/cancel/dispose. Focused005functional suite and lifecycle/metadata suite pass afterfix.

## Actual mandatory checks before code review
- tools/test-unit.ps1 exit0: exactformat252files/0changes, analyze0issues,634Fluttertests passed,2offlineMCPschemaunits passed; testboundary75files passed. output/profile-workflow-unit-1.log.
- SharedC21/C01–C30 syntheticcomponent suite:115passed,1explicitopt-incapture skipped; output/profile-workflow-components-1.log. Nofeaturelayout/golden/overflow checks.
- Nativeisolated units:10/10passed, output/profile-workflow-native-1.log. Onlynativeproductchange: keypickerSSHtitle.
- Spec links195total/189OK/6excluded/0errors, output/profile-workflow-links-1.log.
- Releasecandidatebuild/staticaudit inprogress output/profile-workflow-build-1.log, targetoutput/release-005/ServerDeck.exe. Runninguserapp not replaced yet.

No realSSH/Isar/VM/integration tests, screen-design acceptance or actualuser-save success claimed. Pending independentfullcodereview and finalanalyze/converge. Prior003bufferfix/diagnostic hooks remainunchanged except005parsemetadata propagation andhave separatecleanreview evidence.


## Independent review cycle1 — confirmed P2, T062
Reviewer /root/review_005_implementation_1 found close-during-edit/save connect/refresh could orphan onboarding because attempt ID arrived late and UI pending blocked cancel. Confirmed; appendedT062. Replaced widget-only attempt tracking with retired verification lease plus onStarted admission callback before refresh, and private cleanup controller method bypassing UI pending only. Canonical authorization/exact-attempt/established-session guards unchanged. Added4functional regressions: late pending admission, newer attempt, already established session, delayed refresh; all13workflow widget cases pass (output/profile-workflow-review-race-unit.log). Fullmandatorychecks/build/freshreview pending. No priorhistory removed.


## Independent review cycle2 — confirmed P2, T063
Reviewer /root/review_005_implementation_2 confirmed T061/T062 fixes but found late post-save A refresh could change onboarding flag of an already opened B details session. AppendedT063; _edit captures controller/navigation generation, rechecks before/afterrefresh and savedprofileid. Details open/close/rebind/dispose invalidate oldcontinuations. Two-profile regression keeps A committed, B selected with one ordinarymodal/noautomaticprompt/noextraconnect. All14workflow cases pass (output/profile-workflow-navigation-unit.log). Fullchecks/rebuild/freshreview pending.


## Смена scope по пользователю —2026-11-04
Все текущие требования перенесены в существующие001/002/003/004. Конституция1.4.0/VI добавлена отдельным governanceэтапом; template resolved, hooks отсутствуют. Старый отдельныйкаталог вынесен изspecs вignored.local, активныйFeature003. Current APIs требуютpublicmetadata/hint, alias/oldrecordfallback иformat1migration подлежатудалению. Реальныеuserdataнеудаляются/непереносятся. Предыдущее незавершённоеreviewнеclean; обязательны новоеpackage-review, codecleanup, checks иfullfreshreview.


Current-package planningreview cycle1: /root/review_existing_packages_current_policy found two P2 docconflicts (002manifesttableformat1 vs current2;001R014 ghostpackage dependency). Both corrected directly; freshreview required beforecleanup. No new product decisions, no codechanged inthisreviewcycle.

Current-package planningreview cycle2 /root/review_existing_packages_current_policy_2: nofindings, readyforcurrent-onlycleanup. Requirementchecklists0039/9,0044/4,0023/3PASS. Lychee188/0errors. Clarify0questions; noextensionhooks. Current-onlyimplementation nowstarts; earlier passbeforepolicychangeisnotcurrentacceptance.

## Current-only implementation and review cycle1
Current APIs require explicit public metadata and PublicKeyHint. Removed parseOpenSshKey alias, format1 migration/copyStore, optional identity inference and obsolete migration units. Renamed the current manifest module to store_manifest.dart. Invalid CURRENT versions are rejected before backend initialization/open/writes, preserving source bytes; no user-data reset or migration was performed.

Current checks before review: output/current-policy-unit-1.log exit0 (253 files/0 format changes, analyze0, boundary76 files,632 Flutter units,2 offline schema units); output/current-policy-components.log exit0 (115 shared tests,1 opt-in capture skip); output/current-policy-native.log10/10 unit passed; output/current-policy-links.log188 total/0 errors. Release build/static packaging passed, current-policy-build.log. This candidate was not launched.

Independent reviewer /root/review_current_packages_implementation completed with two confirmed P2 findings: terminal connected/failed guard hid current replace/retain challenges during onboarding; three old parser cancellation/scheduler aliases remained. Added T067/T068 without removing history. Code now considers challenge before terminal completion (including already connected verification), and callers use WorkCancellation/WorkCancelled/ScheduleOwnedDeadline directly. Three functional regressions cover failed+replace, connected+retain, and retain already connected before save returns; consent remains explicit and established sessions survive closing. Focused current-review-fix-unit.log32 passed. Full repeated checks and fresh independent review required; this first review is not clean.

## Current-only final checks, review and Spec Kit closure
Repeated mandatory checks after T067/T068: tools/test-unit.ps1 exit0, output/current-policy-unit-3.log: format253/0changes, analyze0issues, boundary76files,635 Flutter units and2 offline MCP schema units passed. Shared C21 suite remains output/current-policy-components.log115passed/1explicit opt-in capture skip; native output/current-policy-native.log10/10passed. Final release build/static packaging output/current-policy-build-3.log exit0; output/release/ServerDeck.exe SHA256 3cf3ce140461477c8e014c5132ac8544854ced840b76df1d106761de119a0544.

Fresh independent reviewer /root/review_current_packages_implementation_2 completed: no findings, ready; both prior findings checked independently, no unresolved confirmed defects or mandatory decisions. Read-only review covered current tracked/untracked changes across001/002/003/004 and all affected contracts/tests, with actual unit/static/build evidence. No real SSH/Isar/DPAPI/VM/integration, feature layout or user-key success claimed.

Final speckit-analyze:003 inventory41FR/30AC/12SC/68tasks;004 inventory18FR/16AC/5SC/28tasks. Current refinement traceability is complete:003 FR335–341→P35–41→T053–068 and002T044;004 FR416–418→compact presentation decision→T026–028 and001R014. Six constitution principles checked. No current ambiguity, unmapped refinement task, coverage gap or constitution conflict found. Historical completed tasks remain explicitly superseded where current corrections apply.

Final speckit-converge inspected current implementation against spec/plan/tasks (including completed tasks and corrective chains), not checkbox claims. No missing/partial/contradicts/unrequested work found in this scope. Tasks files unchanged by convergence:003 SHA2566751a674c727981e5b2b04595d0ef9e5980b02613142962e85f859aaeefd1701;004 SHA25616b3bca869d8358485994f8f3109a006dc7bea4d89a0cc21b5919f942a6fc8f9. No empty phase appended; no extension hooks. Active package remains003. Existing001R014/002T044/003T052–068/004T026–028 completed; no separate new package, commit or push.
