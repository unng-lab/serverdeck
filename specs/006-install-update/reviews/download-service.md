# Download service and cancellation outcome — T017 / T052–T054

Date: 2026-11-04. Service orchestration milestone; actual channel/runtime binding,
bootstrap consumption/handoff, uninstall and final acceptance remain open.

## Implemented behavior

UpdateService now accepts the validated PendingPersistence and ArtifactTransport ports.
Startup restores pending on a worker without a network request, and never exposes a
target≤installed as ready. Explicit Download admits only the currently verified offered
version. The worker rechecks cached catalog signature/expiry at consent time, delegates
bounded streaming/resource/persistence checks, reports observed progress/verifying and
publishes ready at the actual consent-pointer linearization point under its cancellation
mutex. There are no automatic downloads or partial-transfer retries.

The service keeps preparedVersion/preparedCode independently of a newer offer. New checks,
cancelled replacements, revocation or network failure retain previous consent/bytes and
show their last known validation result. Same-version changed file identities are refused
against the previous catalog and supplied bootstrap-verified installed identity. Failed
checks preserve lastSuccess. TryDrain polls the owned native worker handle and joins only
an already terminated thread; blocking final Drain remains available to teardown.

Dart decode, local projections and UpdateView preserve/display the prepared version and
reason. This is not a claim that the C++ channel map or actual FeatureRuntime is wired.

## Independent review/fix loop

Reviewers used fresh fork_turns=none, read AGENTS/package/source directly and made no edits.

1. `review_download_service`: P1 publication could rename consent successfully then fail
   deleting the staging marker before committed/ready was set. Store reconciliation could
   return success while UI stayed verifying, with a false-cancel gap. T053 records closure.
   Files now notifies immediately after successful durable rename, before cleanup. The
   service marks committed/ready at that notification under the same cancellation mutex.
2. `review_download_service_fresh`: native fix confirmed; P1 Dart optimistically displayed
   CANCELLED after a void ack even if native publication had already won. T054 removes
   that projection: only an authoritative snapshot establishes cancelled/ready/failure.
   Delayed/failed reads retain the last phase and expose read failure, never false cancel.
3. `review_download_service_ui_final`: «Замечаний не найдено»; no unresolved confirmed
   findings in T052–T054. Entire function readiness was explicitly not inferred.

## Actual checks

- Native unit gate exit0:16/16,15.78s. New synthetic service ports test restore without
  requests/downloads, exact admission/BUSY, progress, cancel before commit with a backend
  ignoring cancellation, late cancel after commit, no-cancel and concurrent write→notify→
  throw→reconcile, prior ready preservation, revoke/offline, success timestamps, cancelled
  late restore, expiry before backend entry, changed identities, local IO classification/
  retry and live/completed TryDrain.
- Pending adapter fixture opens the synthetic staging marker GENERIC_READ without share-
  delete at publication, forcing the real post-rename DeleteFile failure. It verifies
  notification, ready pointer and later safe reclaim. The initial attrs-only blocker did
  not deny deletion and the fixture failed; corrected before the successful gate.
- Exact Dart formatting:385files0changes; analyze:no issues,4.1s; full Flutter suite:
  757passed, exit0, including26 update tests. New cases cover separate prepared metadata,
  malformed orphan metadata and late cancel with delayed/error authoritative status.
- Boundary audit:93Dartfilespassed. No design/layout/golden or integration acceptance.
- Windows host release compilation:exit0,16.7s for current C++ source. Subsequent changes
  were test fault injection and Dart prepared/cancel projection, verified by unit gates.
- Latest lychee:259total253OK0errors6excluded2redirects.

No real network/server, application, Explorer, registry, VM/e2e/smoke/process-kill test,
publication or deployment occurred. Unit/static/build scope does not prove clean-OS
installation/update integration. T013/T015/T016/T018–019/T021/T023–029 retain their
unfinished mapping, startup, removal and final verification requirements.
