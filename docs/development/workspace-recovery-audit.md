# 001.1 workspace recovery audit

Date: 2026-10-11. Scope: native workspace coordinator and repository initialization, not full service acceptance. Completed independent review: workspace_recovery_acceptance_review, no findings.

This audit evaluates the original T084 alternative: reproduce/fix a confirmed cause **or** collect sufficient independent evidence about the limits of the check. It does not change deadlines, expected outcomes or any product requirement. A passing repeat alone is insufficient. The historical verifier timeout is retained as unexplained evidence; it is not a system rejection.

## Requirement and observable result

The [runtime contract](../../specs/001-service-foundation/contracts/runtime-storage.md) requires protected native files before open, durable initial rows, validation before promotion, preservation of ambiguous/partial state and no readiness before successful reopen. [T082/T084](../../specs/001-service-foundation/tasks.md) require actual process death and fresh-process verification, not simulated recovery. Full Q06/Q08 and compiled-service acceptance remain future gates.

`packages/serverdeck_locald/test/workspace_crash_test.dart` stops the real coordinator at a verified script/line through the Dart VM debugger, kills only its own creator PID, and starts a separate verifier. The verifier must exit naturally with code0 within the existing30second deadline while its debugger remains connected. The tests also require the appropriate ready/blocked marker, every shutdown marker, active/staging state, file counts for partial state and unchanged manifest/key bytes. Debugger source locations and owned process cleanup remain bounded. Normal entrypoints contain no production failpoints.

| Actual creator boundary | Files at pause | Fresh verifier outcome |
| --- | --- | --- |
| staging-created | 0 | blocked; staging preserved |
| key-flushed | 1 | blocked; key/staging preserved |
| manifest-flushed | 2 | blocked; key/manifest/staging preserved |
| native-files-created | 4 | blocked; partial native files preserved |
| uncommitted-initial-rows | 4 | blocked; incomplete transaction preserved |
| initial-transaction-durable | 4 | ready; complete empty staging promoted |
| before-promotion | 4 | ready; validated staging promoted |
| after-promotion | 4 | ready; active reopened |
| active-opened | 4 | ready; active reopened |

Files are receipt-key.dpapi, workspace.manifest.json, workspace.isar and workspace.isar-lck. The actual lock DACL is checked at each boundary where it exists. `workspace_init_test.dart` additionally checks complete staging, active+staging, missing components, damaged DPAPI, unsupported manifest schema, non-default settings staging, concurrent open and invalid prerequisites. Existing repository tests cover readonly schema rejection, invalid records/blobs, durable commit/crash, native capacity rollback and unknown native failure blocking. Credential lifecycle tests separately cover eight committed snapshots with reopen.

## Retained negative evidence

- Original T084 timeout occurred at manifest-flushed after the native path correction. A later run reproduced a verifier30second timeout at native-files-created: `.local/audits/t091-diagnostic-failure-full.txt` ends33passed/1failed in126seconds.
- The latter diagnostic preserved all lifecycle markers through VERIFIER_MAIN_RETURNING and showed main Resume/livePorts1/receivePorts1/pauseOnExitfalse, without a reported worker. It established that application cleanup returned; it did not establish the remaining port's owner. `_lookupOpenPorts` was the diagnostic enumeration itself.
- An independent reviewer reproduced a separate isolated stdin-first/open-parent protocol failure with a Socket Event Handler port after main return. T093 corrected that fixture protocol to start→flush→EOF and single-through-EOF; T094 preserved the former criterion as historical. This is a confirmed fixture correction, not proof of causality for the historical workspace timeout.
- Earlier TLS-related native path, mutex ownership and pending-I/O defects were reproduced independently and corrected in T083/T085/T086. Their regression results do not identify the historical timeout's port owner.

## Current evidence and its limits

Verified existing logs, all terminal:

| Log in .local/audits | Actual result | Scope |
| --- | --- | --- |
| t084-allocation-full.txt | 35passed,110seconds | all then-current locald tests, before EOF correction |
| t084-allocation-targeted.txt | 3passed,36seconds | staging/key/manifest boundaries, before EOF correction |
| t093-full-locald.txt | 35passed,110seconds | all then-current locald tests after EOF correction |
| t093-eof-repeat-1.txt | 4passed,37seconds | stdin probe plus staging/key/manifest boundaries |
| t093-eof-repeat-2.txt | 4passed,31seconds | same corrected protocol/boundaries |
| t093-eof-repeat-3.txt | 4passed,31seconds | same corrected protocol/boundaries |
| t095-full-locald.txt | 36passed,106seconds | full current locald suite including credential snapshots |
| t096-windows.txt | 23passed,61seconds | full current Windows adapter suite, concurrent with locald |
| t096-locald.txt | 36passed,122seconds | full current locald suite, concurrent with Windows |

Fresh `stdin_protocol_allocation_fixed_review` independently passed corrected EOF/RPC/staging/key/manifest5tests in32seconds; fresh `stdin_gate_criteria_final_review` independently passed EOF/RPC2tests in20seconds and inspected the repeat/full logs. Fresh `credential_snapshots_review` independently passed lifecycle1test in5seconds and inspected the current36-pass full log. These are completed scoped reviews, not independent full initialization acceptance.

The allocation diagnostic has a controlled regression for partial/failed RPCs, nullable unavailable fields and preserving the original timeout. It reads only source StackTrace references, with fixed per-call limits, without port handlers/messages/locals or secret objects. A real paused staging-created main snapshot identifies the two held mutex ports; that does not prove a shutdown leak. Every current verifier timeout still fails the test and collects bounded source/lifecycle diagnostics. No automatic success retry, deadline extension or forced verifier exit was introduced.

Fresh concurrent full Windows/locald suites completed exit0:23passed61seconds and36passed122seconds respectively; all owned processes/check jobs terminal. No application/test code changed in this audit. Mandatory links check passed515OK52unique0errors and git diff --check exit0 with CRLF warnings.

Fresh read-only workspace_recovery_acceptance_review completed with no findings and independently passed all nine hard-kill boundaries plus initialization scenarios:10tests107seconds exit0, with natural verifier exits and unchanged deadlines. It inspected the actual source and current full-suite logs and supported closure of T084 by its original evidence-limits alternative, T082 for all nine boundaries, T017 for repository/storage/initialization tests, T021 for coordinator implementation, and T096 for this audit. These tasks are now closed in precisely that scope. Historical timeout cause remains unestablished. Any new failure remains a failure to diagnose; passing trials do not prove absence of an intermittent defect or identify its historical cause. The audit does not establish compiled UI/locald auth/readiness, other-user, reboot, release composition or full001.1 acceptance. Rejected cleanup operations remain deferred and are not retried.
